"""
Goal Executor - StepExecutor, GoalEvaluator, FinalEvaluator, GoalExecutionLoop
Implements the goal-based execution orchestration with step execution and evaluation
"""

import logging
import asyncio
import json
from typing import Dict, Any, List, Optional, Callable
from datetime import datetime

from app.models.agent_schemas import (
    GoalModel,
    GoalPlanModel,
    GoalStatus,
    PlanStepModel,
    ContextArtifactModel,
    ContextValueModel,
    AuthEntryModel,
    ObservationResult,
    GoalEvaluationResult,
    FinalEvaluationResult,
    GoalEvent,
    Skill,
    DataPacket,
    RowSet,
    RowResult,
    RowStatus
)
from app.services.ai_agent import get_ai_agent
from app.services.skill_registry import get_registry
from app.utils.param_utils import normalize_param_value
from app.services.execution_engine import FanOutEngine, FanInEngine
from app.services.agent_service import StepPlannerAgent, ContextAgent

logger = logging.getLogger(__name__)

# Constants
MAX_GOAL_RETRIES = 3
MAX_PLAN_EXTENSIONS = 2
GOAL_TIMEOUT_SECONDS = 120
SESSION_TIMEOUT_SECONDS = 600


# =============================================================================
# Step Executor
# =============================================================================

class StepExecutor:
    """
    StepExecutor: Executes individual steps with fan-out/fan-in support.
    Reuses existing execution patterns from ReactAgentLoop.
    """
    
    def __init__(self, goal_id: str):
        self.goal_id = goal_id
        self.registry = get_registry()
        self.fan_out_engine = FanOutEngine()
        self.fan_in_engine = FanInEngine()
        self._row_sets: Dict[str, RowSet] = {}  # Store RowSets for fanin
    
    async def execute_step(
        self,
        step: PlanStepModel,
        context: ContextArtifactModel
    ) -> ObservationResult:
        """
        Execute a single step and return observation.
        Handles standard, fan-out, and fan-in execution patterns.
        
        Args:
            step: The step to execute
            context: Current context artifact
        
        Returns:
            ObservationResult with execution results
        """
        try:
            # Get skill from registry
            skill_id = f"{step.plugin_id}.{step.skill_id}"
            skill = self.registry.get_skill(skill_id)
            if not skill:
                return ObservationResult(
                    success=False,
                    view="error",
                    data=DataPacket.error(f"Skill not found: {skill_id}", code="SKILL_NOT_FOUND"),
                    error=f"Skill not found: {skill_id}",
                    summary=f"Failed to find skill {skill_id}"
                )
            
            # Extract auth
            auth_dict = self._extract_auth(context)
            
            # Create skill executor function for FanOut/FanIn engines
            async def skill_executor_fn(skill_obj: Skill, task_context: ContextArtifactModel):
                """Execute skill with given context, returns DataPacket"""
                resolved_params = self._resolve_params(skill_obj, {}, step.input_mappings, task_context)
                return await skill_obj.execute(resolved_params, auth_dict)
            
            # Check for FanOut (foreach) pattern
            if step.foreach:
                return await self._execute_fan_out(step, skill, context, skill_executor_fn)
            
            # Check for FanIn pattern
            if step.fanin:
                return await self._execute_fan_in(step, skill, context, skill_executor_fn)
            
            # Standard single execution
            resolved_params = self._resolve_params(skill, {}, step.input_mappings, context)
            
            logger.info(f"Executing skill {skill_id} with params {resolved_params}")
            data_packet = await skill.execute(resolved_params, auth_dict)
            
            # Create observation from DataPacket
            return self._create_observation(skill_id, skill, data_packet, step)
            
        except Exception as e:
            logger.error(f"Skill execution failed: {e}", exc_info=True)
            return ObservationResult(
                success=False,
                view="error",
                data=DataPacket.error(str(e), code="EXECUTION_ERROR"),
                error=str(e),
                summary=f"Failed to execute {step.skill_id}: {str(e)}"
            )
    
    async def _execute_fan_out(
        self,
        step: PlanStepModel,
        skill: Skill,
        context: ContextArtifactModel,
        skill_executor_fn
    ) -> ObservationResult:
        """Execute a foreach (FanOut) step"""
        foreach = step.foreach
        
        # Parse source format: 
        # - "Step-N" or "Step-N.field" (within-goal)
        # - "G-M.Step-N" or "G-M.Step-N.field" (cross-goal wildcard)
        # - "G-M.Step-N-R.field" (cross-goal specific row)
        import re
        goal_prefix_pattern = r'^G-\d+\.'
        
        if re.match(goal_prefix_pattern, foreach.source):
            # Has goal prefix: "G-M.Step-N...", "G-M.Step-N.field", or "G-M.Step-N-R.field"
            parts = foreach.source.split(".")
            
            if len(parts) == 2:
                # Format: "G-M.Step-N" (wildcard, no field specified)
                # Use entire source as key, default field to "items"
                full_source_key = foreach.source
                source_field = "items"
            elif len(parts) == 3:
                # Format: "G-M.Step-N.field" or "G-M.Step-N-R.field"
                # parts[0] = "G-M", parts[1] = "Step-N" or "Step-N-R", parts[2] = field
                full_source_key = f"{parts[0]}.{parts[1]}"
                source_field = parts[2]
            else:
                # Unexpected format, use as-is with default field
                full_source_key = foreach.source
                source_field = "items"
        else:
            # No goal prefix: "Step-N" or "Step-N.field"
            source_parts = foreach.source.split(".", 1)
            full_source_key = source_parts[0]
            source_field = source_parts[1] if len(source_parts) > 1 else "items"
        
        # Resolve source RowSet
        source_row_set = self._resolve_source_row_set(full_source_key, source_field, context)
        if not source_row_set:
            return ObservationResult(
                success=False,
                view="error",
                data=DataPacket.error(f"Source RowSet not found: {foreach.source}", code="FANOUT_ERROR"),
                error=f"Source RowSet not found: {foreach.source}",
                summary=f"Failed to resolve source for foreach"
            )
        
        logger.info(f"FanOut: executing {step.skill_id} on {source_row_set.count} items")
        
        # Execute fan-out
        result_row_set = await self.fan_out_engine.execute_fan_out(
            step, source_row_set, skill, context, skill_executor_fn
        )
        
        # Extract step number from step_id (e.g., "Step-1-0" -> 1)
        step_num = int(step.step_id.split("-")[1])
        
        # Store result RowSet for downstream steps
        self._row_sets[f"Step-{step_num}"] = result_row_set
        
        # Count successes/failures
        ok_count = sum(1 for r in result_row_set.rows if r.status == RowStatus.OK)
        failed_count = sum(1 for r in result_row_set.rows if r.status == RowStatus.FAILED)
        
        # Create context updates with goal-scoped namespacing
        context_updates = {
            f"{self.goal_id}.Step-{step_num}.row_set": json.dumps({
                "step_id": result_row_set.step_id,
                "field": result_row_set.field,
                "count": result_row_set.count,
                "ok_count": ok_count,
                "failed_count": failed_count
            }),
            f"{self.goal_id}.Step-{step_num}.count": str(result_row_set.count)
        }
        
        # Store individual results with goal-scoped namespacing
        for row in result_row_set.rows:
            if row.status == RowStatus.OK and row.value:
                if isinstance(row.value, DataPacket) and row.value.rows:
                    for field_name, value in row.value.rows[0].items():
                        key = f"{self.goal_id}.Step-{step_num}-{row.index}.{field_name}"
                        context_updates[key] = str(value) if not isinstance(value, str) else value
        
        # Create table DataPacket from RowSet results
        table_rows = []
        table_schema = {"index": {"type": "integer"}, "status": {"type": "string"}}
        
        # Collect field names
        field_names = set()
        for row in result_row_set.rows:
            if row.status == RowStatus.OK and row.value and isinstance(row.value, DataPacket) and row.value.rows:
                field_names.update(row.value.rows[0].keys())
        
        for field_name in sorted(field_names):
            table_schema[field_name] = {"type": "string"}
        
        # Build table rows
        for row in result_row_set.rows:
            table_row = {"index": row.index, "status": row.status.value}
            
            if row.status == RowStatus.OK and row.value and isinstance(row.value, DataPacket) and row.value.rows:
                for field_name, value in row.value.rows[0].items():
                    table_row[field_name] = str(value) if not isinstance(value, str) else value
            elif row.status == RowStatus.FAILED:
                table_row["error"] = row.error or "Unknown error"
                if "error" not in table_schema:
                    table_schema["error"] = {"type": "string"}
            
            table_rows.append(table_row)
        
        table_packet = DataPacket(
            schema_def={"type": "object", "properties": table_schema},
            rows=table_rows
        )
        
        return ObservationResult(
            success=ok_count > 0,
            view="table",
            data=table_packet,
            context_updates=context_updates,
            summary=f"FanOut: {ok_count}/{result_row_set.count} items processed successfully"
        )
    
    async def _execute_fan_in(
        self,
        step: PlanStepModel,
        skill: Skill,
        context: ContextArtifactModel,
        skill_executor_fn
    ) -> ObservationResult:
        """Execute a fanin step"""
        fanin = step.fanin
        
        # Parse source format: 
        # - "Step-N" (within-goal wildcard)
        # - "G-M.Step-N" (cross-goal wildcard)
        # - "G-M.Step-N-R.field" (cross-goal specific row)
        import re
        goal_prefix_pattern = r'^G-\d+\.'
        
        if re.match(goal_prefix_pattern, fanin.source):
            # Has goal prefix: "G-M.Step-N" or "G-M.Step-N-R.field"
            parts = fanin.source.split(".")
            
            if len(parts) == 2:
                # Format: "G-M.Step-N" (wildcard, no field specified)
                # Use entire source as key, use combine_field for the field
                full_source_key = fanin.source
                source_field = fanin.combine_field
            elif len(parts) == 3:
                # Format: "G-M.Step-N.field" or "G-M.Step-N-R.field"
                full_source_key = f"{parts[0]}.{parts[1]}"
                source_field = parts[2]
            else:
                # Unexpected format, use as-is with combine_field
                full_source_key = fanin.source
                source_field = fanin.combine_field
        else:
            # No goal prefix: "Step-N" or "Step-N.field"
            source_parts = fanin.source.split(".", 1)
            full_source_key = source_parts[0]
            source_field = source_parts[1] if len(source_parts) > 1 else fanin.combine_field
        
        # Resolve source RowSet
        source_row_set = self._resolve_source_row_set(full_source_key, source_field, context)
        if not source_row_set:
            return ObservationResult(
                success=False,
                view="error",
                data=DataPacket.error(f"Source RowSet not found: {fanin.source}", code="FANIN_ERROR"),
                error=f"Source RowSet not found: {fanin.source}",
                summary=f"Failed to resolve source for fanin"
            )
        
        logger.info(f"FanIn: combining {source_row_set.count} items for {step.skill_id}")
        
        # Execute fan-in
        data_packet, _ = await self.fan_in_engine.execute_fan_in(
            step, source_row_set, skill, context, skill_executor_fn
        )
        
        # Create observation from DataPacket
        return self._create_observation(f"{step.plugin_id}.{step.skill_id}", skill, data_packet, step)
    
    def _resolve_source_row_set(
        self,
        source: str,
        field: str,
        context: ContextArtifactModel
    ) -> Optional[RowSet]:
        """Resolve a source RowSet from stored results or context
        
        Args:
            source: Either "Step-M-R" or "G-N.Step-M-R" (with goal prefix)
            field: The field name to extract
            context: The context containing step outputs
        """
        import re
        logger.info(f"Attempting to resolve source RowSet: source='{source}', field='{field}'")
        
        # Check if source already contains a goal prefix
        goal_prefix_pattern = r'^G-\d+\.'
        has_goal_prefix = re.match(goal_prefix_pattern, source)
        
        # Extract the step part (with or without goal prefix)
        # Examples: "Step-0" or "G-1.Step-0" -> "Step-0"
        step_part = source.split(".")[-1] if has_goal_prefix else source
        
        # Check if source is a wildcard pattern (e.g., "Step-1" or "G-1.Step-1" without row index)
        if step_part.startswith("Step-") and step_part.count("-") == 1:
            # Extract goal ID from source if present, otherwise use current goal
            if has_goal_prefix:
                goal_id = source.split(".")[0]  # e.g., "G-1" from "G-1.Step-0"
            else:
                goal_id = self.goal_id
            
            step_num = int(step_part.split("-")[1])
            pattern = f"{goal_id}.Step-{step_num}-"
            
            logger.info(f"Wildcard pattern detected: collecting all rows matching '{pattern}*'")
            
            # Find all matching keys in step_outputs
            # First, try to find keys matching the specific field
            matching_keys = [k for k in context.step_outputs.keys() 
                            if k.startswith(pattern) and k.endswith(f".{field}")]
            
            if matching_keys:
                # Sort by row index
                matching_keys.sort(key=lambda k: int(k.split("-")[2].split(".")[0]))
                
                logger.info(f"Found {len(matching_keys)} matching keys for field '{field}'")
                
                # Build RowSet from collected values
                rows = []
                for key in matching_keys:
                    row_index = int(key.split("-")[2].split(".")[0])
                    value = context.step_outputs[key].value
                    
                    # Check if value is an array
                    try:
                        parsed_value = json.loads(value) if isinstance(value, str) else value
                        if isinstance(parsed_value, list):
                            for item in parsed_value:
                                rows.append(RowResult(
                                    index=len(rows),
                                    value=DataPacket(rows=[{field: item}]),
                                    error=None,
                                    status=RowStatus.OK
                                ))
                        else:
                            rows.append(RowResult(
                                index=row_index,
                                value=DataPacket(rows=[{field: value}]),
                                error=None,
                                status=RowStatus.OK
                            ))
                    except (json.JSONDecodeError, TypeError):
                        rows.append(RowResult(
                            index=row_index,
                            value=DataPacket(rows=[{field: value}]),
                            error=None,
                            status=RowStatus.OK
                        ))
                
                return RowSet(step_id=source, field=field, count=len(rows), rows=rows)
            
            # If no specific field match, collect ALL fields for each row
            # This handles the case where source is "G-0.Step-1" without a field
            all_keys = [k for k in context.step_outputs.keys() if k.startswith(pattern)]
            
            if not all_keys:
                logger.warning(f"No matching keys found for pattern '{pattern}*'")
                # Fallback: check stored RowSets
                if source in self._row_sets:
                    logger.info(f"Found stored RowSet for '{source}'")
                    return self._row_sets[source]
                return None
            
            # Group keys by row index and collect all fields
            row_data = {}  # row_index -> {field: value, ...}
            for key in all_keys:
                # Extract row index and field name from key like "G-0.Step-1-0.diff_text"
                parts = key.split(".")
                if len(parts) >= 3:
                    # parts = ["G-0", "Step-1-0", "diff_text"]
                    step_with_row = parts[1]  # "Step-1-0"
                    field_name = parts[2]      # "diff_text"
                    row_index = int(step_with_row.split("-")[2])
                    
                    if row_index not in row_data:
                        row_data[row_index] = {}
                    row_data[row_index][field_name] = context.step_outputs[key].value
            
            # Build RowSet with all fields per row
            rows = []
            for row_index in sorted(row_data.keys()):
                rows.append(RowResult(
                    index=row_index,
                    value=DataPacket(rows=[row_data[row_index]]),
                    error=None,
                    status=RowStatus.OK
                ))
            
            logger.info(f"Built RowSet with {len(rows)} rows, each containing fields: {list(row_data.get(0, {}).keys()) if row_data else []}")
            return RowSet(step_id=source, field="*", count=len(rows), rows=rows)
        
        # Check stored RowSets
        if source in self._row_sets:
            return self._row_sets[source]
        
        # Check context for array field
        # If source already has goal prefix (G-N.Step-M-R), use it directly
        # Otherwise, prepend current goal_id
        if has_goal_prefix:
            namespaced_key = f"{source}.{field}"
        else:
            namespaced_key = f"{self.goal_id}.{source}.{field}"
        
        logger.info(f"Looking for key: {namespaced_key}")
        
        if namespaced_key in context.step_outputs:
            logger.info(f"Found key in context: {namespaced_key}")
            value = context.step_outputs[namespaced_key].value
            try:
                items = json.loads(value) if isinstance(value, str) else value
                if isinstance(items, list):
                    rows = []
                    for idx, item in enumerate(items):
                        rows.append(RowResult(
                            index=idx,
                            value=DataPacket(rows=[{field: item}]),
                            error=None,
                            status=RowStatus.OK
                        ))
                    return RowSet(step_id=source, field=field, count=len(rows), rows=rows)
                else:
                    # Scalar value - wrap in single-row RowSet
                    logger.info(f"Wrapping scalar value in single-row RowSet")
                    return RowSet(
                        step_id=source,
                        field=field,
                        count=1,
                        rows=[RowResult(
                            index=0,
                            value=DataPacket(rows=[{field: items}]),
                            error=None,
                            status=RowStatus.OK
                        )]
                    )
            except (json.JSONDecodeError, TypeError):
                # If JSON parsing fails, treat as scalar string
                logger.info(f"Treating as scalar string value")
                return RowSet(
                    step_id=source,
                    field=field,
                    count=1,
                    rows=[RowResult(
                        index=0,
                        value=DataPacket(rows=[{field: value}]),
                        error=None,
                        status=RowStatus.OK
                    )]
                )
        
        logger.warning(f"Could not resolve source RowSet: {source}.{field}")
        logger.warning(f"Tried key: {namespaced_key}")
        logger.warning(f"Available keys in context.step_outputs: {list(context.step_outputs.keys())}")
        return None
    
    def _resolve_params(
        self,
        skill: Skill,
        params: Dict[str, Any],
        input_sources: Dict[str, str],
        context: ContextArtifactModel
    ) -> Dict[str, Any]:
        """Resolve parameters from literal values and context, enriching context with new literals"""
        import re
        resolved_params = {}
        
        # Get all params from skill schema
        all_params = skill.input_schema.get("properties", {}).keys()
        unfilled_keys = set(all_params)
        
        # Template pattern for detecting {{ variable }} syntax
        template_pattern = re.compile(r'\{\{\s*(\w+)(?:\.(\w+))?\s*\}\}')
        
        # Step 1: Process input_sources (input_mappings from LLM)
        for param_name in list(unfilled_keys):
            if param_name in input_sources:
                value = input_sources[param_name]
                
                # Check if it's a template pattern ({{ variable }})
                if isinstance(value, str) and template_pattern.fullmatch(value.strip()):
                    # It's a template - skip processing here, let it be resolved from iteration context
                    # The _create_task_context in execution_engine.py will inject _iter.{param_name}
                    # which will be picked up in Step 2 below via context.resolve_param()
                    logger.info(f"Detected template for {param_name}: {value}, will resolve from iteration context")
                    continue
                # Check if it's a reference (contains dot or starts with Step-)
                elif isinstance(value, str) and ('.' in value or value.startswith('Step-')):
                    # It's a reference - resolve from context
                    resolved_value = context.resolve_param(param_name, {param_name: value})
                    if resolved_value:
                        resolved_params[param_name] = normalize_param_value(resolved_value)
                        unfilled_keys.remove(param_name)
                elif param_name in context.user_values:
                    resolved_params[param_name] = context.user_values[param_name].value
                else:
                    # It's a literal - use directly (normalize to strip LLM-added quotes)
                    normalized_value = normalize_param_value(value)
                    resolved_params[param_name] = normalized_value
                    unfilled_keys.remove(param_name)
                    
                    # Enrich context with this literal value if not already present
                    if param_name not in context.user_values:
                        context.user_values[param_name] = ContextValueModel(
                            name=param_name,
                            description=f"Extracted from input_mappings",
                            value=str(normalized_value),
                            required=False,
                            field_type="string"
                        )
                        logger.info(f"Enriched context with literal parameter: {param_name}={normalized_value}")
        
        # Step 2: Fill remaining keys from context (including iteration context _iter.{param_name})
        for param_name in list(unfilled_keys):
            resolved_value = context.resolve_param(param_name)
            if resolved_value:
                resolved_params[param_name] = normalize_param_value(resolved_value)
                unfilled_keys.remove(param_name)
        
        return resolved_params
    
    def _extract_auth(self, context: ContextArtifactModel) -> Dict[str, str]:
        """Extract auth tokens from context"""
        auth_dict = {}
        for auth_id, auth_entry in context.auth.items():
            if auth_entry.value:
                if auth_entry.strategy_used == "oauth":
                    context_key = auth_id.replace("_auth", "_access_token")
                elif auth_id.endswith("_auth"):
                    context_key = auth_id.replace("_auth", "_token")
                else:
                    context_key = auth_id + "_token"
                auth_dict[context_key] = auth_entry.value
        return auth_dict
    
    def _create_observation(
        self,
        skill_id: str,
        skill: Skill,
        data_packet: DataPacket,
        step: Optional[PlanStepModel] = None
    ) -> ObservationResult:
        """Create ObservationResult from DataPacket with goal-scoped namespacing"""
        # Check if error
        if data_packet.is_error():
            return ObservationResult(
                success=False,
                view="error",
                data=data_packet,
                error=data_packet.first("error") or "Unknown error",
                summary=f"Skill {skill_id} failed: {data_packet.first('error')}"
            )
        
        # Extract context updates with goal-scoped namespacing
        namespaced_updates = {}
        
        if step and step.step_id.startswith("Step-"):
            step_num = int(step.step_id.split("-")[1])
            namespace_prefix = f"{self.goal_id}.Step-{step_num}-0"
        else:
            namespace_prefix = f"{self.goal_id}.{skill_id.split('.')[-1]}"
        
        # Extract fields from output_schema
        if skill.output_schema and "properties" in skill.output_schema:
            if data_packet.rows:
                first_row = data_packet.rows[0]
                for field_name in skill.output_schema["properties"].keys():
                    if field_name in first_row:
                        namespaced_key = f"{namespace_prefix}.{field_name}"
                        namespaced_updates[namespaced_key] = first_row[field_name]
        
        return ObservationResult(
            success=True,
            view=skill.output_type,
            data=data_packet,
            context_updates=namespaced_updates,
            summary=f"Successfully executed {skill_id}"
        )


# =============================================================================
# Goal Evaluator
# =============================================================================

class GoalEvaluator:
    """LLM-based evaluator for individual goals"""
    
    async def evaluate(
        self,
        goal: GoalModel,
        context: ContextArtifactModel
    ) -> GoalEvaluationResult:
        """
        Evaluate if a goal's objective has been met.
        
        Args:
            goal: The goal to evaluate
            context: Current context with step outputs
        
        Returns:
            GoalEvaluationResult with completion status and strategy
        """
        prompt = self._build_evaluation_prompt(goal, context)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "Evaluation failed"))
            
            output = result.get("output", "").strip()
            eval_data = json.loads(output)
            
            return GoalEvaluationResult(**eval_data)
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse goal evaluation output: {e}")
            return GoalEvaluationResult(
                completed=False,
                reasoning="Failed to parse evaluation output",
                strategy="abort_goal"
            )
        except Exception as e:
            logger.error(f"Goal evaluation failed: {e}")
            raise
    
    def _build_evaluation_prompt(self, goal: GoalModel, context: ContextArtifactModel) -> str:
        """Build evaluation prompt for goal"""
        
        # Format step outputs
        outputs_text = []
        for key, value in context.step_outputs.items():
            if key.startswith(f"{goal.goal_id}."):
                outputs_text.append(f"  {key}: {value.value[:200]}...")
        outputs_str = "\n".join(outputs_text) if outputs_text else "No outputs yet"
        
        return f"""You are evaluating whether a goal has been completed.

GOAL: {goal.description}
PLUGIN: {goal.plugin_id}

STEP OUTPUTS:
{outputs_str}

Your task: Determine if the goal's objective has been met based on the step outputs.

Return ONLY a valid JSON object with this structure:
{{
  "completed": true | false,
  "reasoning": "Explanation of your evaluation",
  "strategy": "complete" | "retry_steps" | "abort_goal",
  "suggested_next_steps": "Suggestion if incomplete, null otherwise"
}}

Guidelines:
- completed: true if the goal objective is fully accomplished
- strategy: "complete" if done, "retry_steps" if more steps might help, "abort_goal" if impossible
- suggested_next_steps: hint for what additional steps might help (if retry_steps)

Return ONLY the JSON object, no markdown formatting, no explanations."""


# =============================================================================
# Final Evaluator
# =============================================================================

class FinalEvaluator:
    """LLM-based evaluator for overall query resolution"""
    
    async def evaluate(
        self,
        query: str,
        goals: List[GoalModel],
        context: ContextArtifactModel
    ) -> FinalEvaluationResult:
        """
        Evaluate if the user's original query is fully resolved.
        
        Args:
            query: Original user query
            goals: All goals in the plan
            context: Current context
        
        Returns:
            FinalEvaluationResult with resolution status and strategy
        """
        prompt = self._build_final_evaluation_prompt(query, goals, context)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "Final evaluation failed"))
            
            output = result.get("output", "").strip()
            eval_data = json.loads(output)
            
            return FinalEvaluationResult(**eval_data)
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse final evaluation output: {e}")
            return FinalEvaluationResult(
                query_resolved=False,
                reasoning="Failed to parse evaluation output",
                strategy="complete"
            )
        except Exception as e:
            logger.error(f"Final evaluation failed: {e}")
            raise
    
    def _build_final_evaluation_prompt(
        self,
        query: str,
        goals: List[GoalModel],
        context: ContextArtifactModel
    ) -> str:
        """Build final evaluation prompt"""
        
        # Format completed goals
        goals_text = []
        for goal in goals:
            status_str = "COMPLETED" if goal.status == GoalStatus.COMPLETED else goal.status.value
            goals_text.append(f"- {goal.goal_id}: {goal.description} ({goal.plugin_id}) - {status_str}")
        goals_str = "\n".join(goals_text)
        
        return f"""You are evaluating whether the user's original query has been fully resolved.

USER QUERY: {query}

GOALS EXECUTED:
{goals_str}

Your task: Determine if the user's query is fully answered/completed.

Return ONLY a valid JSON object with this structure:
{{
  "query_resolved": true | false,
  "reasoning": "Explanation of your evaluation",
  "strategy": "complete" | "add_goals" | "add_steps_to_goal",
  "suggested_additions": "Suggestion if not resolved, null otherwise"
}}

Guidelines:
- query_resolved: true if the user's query is fully answered
- strategy: "complete" if done, "add_goals" if need new goals, "add_steps_to_goal" if need more steps in existing goal
- suggested_additions: hint for what's missing

Return ONLY the JSON object, no markdown formatting, no explanations."""


# =============================================================================
# Goal Execution Loop
# =============================================================================

class GoalExecutionLoop:
    """
    Main orchestrator for goal-based execution.
    Replaces ReactAgentLoop with hierarchical goal/step structure.
    """
    
    def __init__(self):
        self.step_planner = StepPlannerAgent()
        self.context_agent = ContextAgent()
        self.goal_evaluator = GoalEvaluator()
        self.final_evaluator = FinalEvaluator()
    
    async def run(
        self,
        session_id: str,
        query: str,
        goal_plan: GoalPlanModel,
        context: ContextArtifactModel,
        event_callback: Callable[[GoalEvent], None],
        approval_event: asyncio.Event,
        get_decision: Optional[Callable[[], Optional[Dict[str, Any]]]] = None,
        timeout_seconds: int = SESSION_TIMEOUT_SECONDS
    ) -> Dict[str, Any]:
        """
        Execute the goal plan with human-in-the-loop approval.
        NOW PAUSES BETWEEN GOALS: Each goal requires separate user approval to start.
        
        Args:
            session_id: Session identifier
            query: Original user query
            goal_plan: Goal plan to execute
            context: Context artifact
            event_callback: Callback to emit events
            approval_event: Event to wait for user approval
            get_decision: Callback to get user decision
            timeout_seconds: Total session timeout
        
        Returns:
            Dict with status and results
        """
        logger.info(f"Starting goal execution loop for session {session_id}")
        
        try:
            # Execute each goal in sequence
            for goal_idx, goal in enumerate(goal_plan.goals):
                logger.info(f"Preparing goal {goal.goal_id}: {goal.description}")
                
                # Phase 0: Plan steps for this goal FIRST (before waiting for approval)
                goal.status = GoalStatus.PLANNING_STEPS
                event_callback(GoalEvent(
                    event_type="goal_started",
                    data={"goal": goal.model_dump(), "goal_index": goal_idx},
                    goal_id=goal.goal_id,
                    timestamp=datetime.now()
                ))
                
                # Create steps for the goal
                context_summary = self.step_planner._summarize_context(context)
                steps, required_inputs = await self.step_planner.create_steps(goal, context_summary)
                goal.steps = steps
                
                # Emit steps_planned event with goal index
                goal.status = GoalStatus.AWAITING_STEP_APPROVAL
                event_callback(GoalEvent(
                    event_type="steps_planned",
                    data={
                        "goal_id": goal.goal_id,
                        "goal_index": goal_idx,
                        "steps": [s.model_dump() for s in steps],
                        "required_inputs": [f.model_dump() for f in required_inputs]
                    },
                    goal_id=goal.goal_id,
                    timestamp=datetime.now()
                ))
                
                # Phase 1: Wait for user to click "Start Execution" for this goal
                logger.info(f"Waiting for execution approval for goal {goal.goal_id}")
                approval_event.clear()
                
                try:
                    await asyncio.wait_for(approval_event.wait(), timeout=GOAL_TIMEOUT_SECONDS)
                except asyncio.TimeoutError:
                    logger.error(f"Goal {goal.goal_id} execution approval timeout")
                    goal.status = GoalStatus.FAILED
                    return {"status": "failed", "error": "Execution approval timeout"}
                
                # Get decision (includes input_values and auth)
                decision = None
                if get_decision:
                    decision = get_decision()
                
                if decision and not decision.get("approved", True):
                    feedback = decision.get("feedback", "")
                    logger.info(f"Execution rejected for goal {goal.goal_id}. Feedback: {feedback}")
                    goal.status = GoalStatus.FAILED
                    return {"status": "failed", "error": f"Execution rejected: {feedback}"}
                
                # Update context with user inputs
                if decision and "input_values" in decision:
                    for key, value in decision["input_values"].items():
                        context.user_values[key] = ContextValueModel(
                            name=key,
                            description=f"User-provided value",
                            value=str(value),
                            required=True,
                            field_type="string"
                        )
                
                # Update auth
                if decision and "auth" in decision:
                    for auth_id, auth_value in decision["auth"].items():
                        context.auth[auth_id] = AuthEntryModel(
                            strategy_used=auth_value.get("strategy", "token"),
                            value=auth_value.get("value", ""),
                            valid=True
                        )
                
                # Execute goal with retry loop
                goal_completed = False
                while not goal_completed and goal.retry_count < MAX_GOAL_RETRIES:
                    # Phase 2: Execute all steps (batch)
                    goal.status = GoalStatus.EXECUTING
                    step_executor = StepExecutor(goal.goal_id)
                    logger.info(f"Executing {len(steps)} steps for goal {goal.goal_id}")
                    
                    for step in steps:
                        logger.info(f"Executing step {step.step_id}: {step.skill_id} \n Context {context}")
                        
                        observation = await step_executor.execute_step(step, context)
                        
                        # Update context with step outputs
                        if observation.success and observation.context_updates:
                            for key, value in observation.context_updates.items():
                                serialized_value = json.dumps(value) if isinstance(value, (list, dict)) else str(value)
                                context.step_outputs[key] = ContextValueModel(
                                    name=key,
                                    description=f"Output from {step.skill_id}",
                                    value=serialized_value,
                                    required=False,
                                    field_type="string"
                                )
                                # Also store in goal's step_outputs
                                goal.step_outputs[key] = value
                        
                        # Emit step executed event with observation data
                        event_callback(GoalEvent(
                            event_type="step_executed",
                            data={
                                "step_id": step.step_id,
                                "skill_id": step.skill_id,
                                "success": observation.success,
                                "summary": observation.summary,
                                "view": observation.view,
                                "data": observation.data.model_dump() if observation.data else None
                            },
                            goal_id=goal.goal_id,
                            timestamp=datetime.now()
                        ))
                        
                        if not observation.success:
                            logger.warning(f"Step {step.step_id} failed: {observation.error}")
                    
                    # Phase 3: Evaluate goal
                    goal.status = GoalStatus.EVALUATING
                    eval_result = await self.goal_evaluator.evaluate(goal, context)
                    
                    # Store evaluation in history
                    goal.evaluation_history.append({
                        "retry_count": goal.retry_count,
                        "completed": eval_result.completed,
                        "reasoning": eval_result.reasoning,
                        "strategy": eval_result.strategy,
                        "timestamp": datetime.now().isoformat()
                    })
                    
                    event_callback(GoalEvent(
                        event_type="goal_evaluated",
                        data={"evaluation": eval_result.model_dump()},
                        goal_id=goal.goal_id,
                        timestamp=datetime.now()
                    ))
                    
                    # Check if goal is complete
                    if eval_result.completed:
                        goal_completed = True
                        goal.status = GoalStatus.COMPLETED
                        logger.info(f"Goal {goal.goal_id} completed successfully")
                        
                        event_callback(GoalEvent(
                            event_type="goal_completed",
                            data={"goal_id": goal.goal_id, "goal_index": goal_idx},
                            goal_id=goal.goal_id,
                            timestamp=datetime.now()
                        ))
                    elif eval_result.strategy == "abort_goal":
                        goal.status = GoalStatus.FAILED
                        logger.error(f"Goal {goal.goal_id} aborted: {eval_result.reasoning}")
                        
                        event_callback(GoalEvent(
                            event_type="goal_failed",
                            data={"goal_id": goal.goal_id, "reason": eval_result.reasoning},
                            goal_id=goal.goal_id,
                            timestamp=datetime.now()
                        ))
                        break
                    else:
                        # Retry with more steps - need approval again
                        goal.retry_count += 1
                        logger.info(f"Goal {goal.goal_id} incomplete, retry {goal.retry_count}/{MAX_GOAL_RETRIES}")
                        
                        # Create more steps
                        failure_info = eval_result.reasoning
                        new_steps, new_required_inputs = await self.step_planner.create_more_steps(
                            goal, goal.steps, goal.step_outputs, failure_info, context_summary
                        )
                        
                        # Add new steps to goal
                        goal.steps.extend(new_steps)
                        steps = new_steps  # Update steps for next iteration
                        
                        goal.status = GoalStatus.AWAITING_STEP_APPROVAL
                        event_callback(GoalEvent(
                            event_type="steps_revised",
                            data={
                                "goal_id": goal.goal_id,
                                "steps": [s.model_dump() for s in new_steps],
                                "required_inputs": [f.model_dump() for f in new_required_inputs]
                            },
                            goal_id=goal.goal_id,
                            timestamp=datetime.now()
                        ))
                        
                        # Wait for approval again
                        approval_event.clear()
                        try:
                            await asyncio.wait_for(approval_event.wait(), timeout=GOAL_TIMEOUT_SECONDS)
                        except asyncio.TimeoutError:
                            logger.error(f"Goal {goal.goal_id} retry approval timeout")
                            goal.status = GoalStatus.FAILED
                            return {"status": "failed", "error": "Retry approval timeout"}
                        
                        # Get decision again
                        decision = None
                        if get_decision:
                            decision = get_decision()
                        
                        if decision and not decision.get("approved", True):
                            feedback = decision.get("feedback", "")
                            logger.info(f"Retry steps rejected for goal {goal.goal_id}. Feedback: {feedback}")
                            goal.status = GoalStatus.FAILED
                            return {"status": "failed", "error": f"Retry steps rejected: {feedback}"}
                
                # Phase 4: Propagate goal outputs to global context
                if goal.status == GoalStatus.COMPLETED:
                    self.context_agent.propagate_goal_outputs(goal, context)
            
            # Final evaluation
            logger.info("All goals executed, performing final evaluation")
            final_eval = await self.final_evaluator.evaluate(query, goal_plan.goals, context)
            
            event_callback(GoalEvent(
                event_type="final_evaluated",
                data={"evaluation": final_eval.model_dump()},
                goal_id=None,
                timestamp=datetime.now()
            ))
            
            if final_eval.query_resolved:
                logger.info("Query fully resolved")
                event_callback(GoalEvent(
                    event_type="complete",
                    data={"message": "Query resolved successfully"},
                    goal_id=None,
                    timestamp=datetime.now()
                ))
                return {"status": "complete", "final_evaluation": final_eval}
            else:
                logger.warning(f"Query not fully resolved: {final_eval.reasoning}")
                # Could implement plan extension here
                return {"status": "incomplete", "final_evaluation": final_eval}
            
        except Exception as e:
            logger.error(f"Goal execution loop failed: {e}", exc_info=True)
            event_callback(GoalEvent(
                event_type="error",
                data={"error": str(e)},
                goal_id=None,
                timestamp=datetime.now()
            ))
            return {"status": "failed", "error": str(e)}
