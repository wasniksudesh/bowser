"""
Execution Engine - OpenClaw Fan-Out Runtime
Handles foreach expansion, task units, concurrency control, and RowSet collection
"""

import asyncio
import json
import logging
import re
from typing import Any, Dict, List, Optional

from app.models.agent_schemas import (
    PlanStepModel,
    ExecutionPlanModel,
    ContextArtifactModel,
    ContextValueModel,
    RowSet,
    RowResult,
    RowStatus,
    TaskUnit,
    Skill,
    DataPacket
)

logger = logging.getLogger(__name__)


# =============================================================================
# Template Resolver
# =============================================================================

_TEMPLATE_RE = re.compile(r"\{\{\s*(\w+)(?:\.(\w+))?\s*\}\}")


def resolve_template(template: str, alias: str, item: Any) -> Any:
    """
    Resolve '{{ alias }}' or '{{ alias.field }}' against an item.
    
    Examples:
        resolve_template("{{ commit }}", "commit", "abc123") -> "abc123"
        resolve_template("{{ inst.id }}", "inst", {"id": "i-123"}) -> "i-123"
        resolve_template("literal", "x", "y") -> "literal"
    
    Also handles DataPacket items - extracts from first row.
    """
    template_str = str(template).strip()
    match = _TEMPLATE_RE.fullmatch(template_str)
    
    if not match:
        return template  # literal passthrough
    
    var_name, field_name = match.groups()
    
    if var_name != alias:
        return template  # wrong variable name
    
    # Handle DataPacket items - extract value from first row
    actual_item = item
    if isinstance(item, DataPacket) and item.rows:
        first_row = item.rows[0]
        if field_name and field_name in first_row:
            # Direct field access from DataPacket
            return first_row[field_name]
        elif len(first_row) == 1:
            # Single-field DataPacket, return the value
            actual_item = list(first_row.values())[0]
        else:
            # Multi-field DataPacket, use as dict
            actual_item = first_row
    
    if field_name and isinstance(actual_item, dict):
        return actual_item.get(field_name, template)
    
    return actual_item  # scalar


# =============================================================================
# Execution Node
# =============================================================================

class ExecutionNode:
    """Wraps a plan step in the DAG"""
    
    def __init__(self, step: PlanStepModel):
        self.step = step
        self.is_vectorized = step.foreach is not None
        self.task_units: List[TaskUnit] = []
        self.status = "pending"  # pending, running, completed, failed
        self.dependencies: List[str] = step.depends_on.copy()
    
    @property
    def step_id(self) -> str:
        return self.step.step_id


# =============================================================================
# Execution Graph
# =============================================================================

class ExecutionGraph:
    """
    DAG built from frozen plan.
    Manages node dependencies and foreach expansion.
    """
    
    def __init__(self):
        self.nodes: Dict[str, ExecutionNode] = {}
    
    @classmethod
    def from_plan(cls, plan: ExecutionPlanModel) -> "ExecutionGraph":
        """Build execution graph from frozen plan"""
        graph = cls()
        
        for step in plan.steps:
            node = ExecutionNode(step)
            graph.nodes[step.step_id] = node
        
        logger.info(f"Built execution graph with {len(graph.nodes)} nodes")
        return graph
    
    def get_node(self, step_id: str) -> Optional[ExecutionNode]:
        """Get a node by step_id"""
        return self.nodes.get(step_id)
    
    def expand_foreach(self, node_id: str, row_set: RowSet) -> List[TaskUnit]:
        """
        Expand a vectorized node into N TaskUnits.
        Called after a dependency produces a RowSet.
        """
        node = self.nodes.get(node_id)
        if not node or not node.is_vectorized:
            return []
        
        task_units = []
        for row in row_set.rows:
            tu = TaskUnit(
                task_id=f"{node.step_id}#{row.index}",
                parent_step_id=node.step_id,
                index=row.index,
                inputs={},
                status=RowStatus.PENDING
            )
            task_units.append(tu)
        
        node.task_units = task_units
        logger.info(f"Expanded {node_id} into {len(task_units)} task units")
        return task_units
    
    def get_ready_nodes(self) -> List[ExecutionNode]:
        """Returns nodes whose dependencies are all completed"""
        ready = []
        for node in self.nodes.values():
            if node.status == "pending":
                deps_completed = all(
                    self.nodes[dep_id].status == "completed"
                    for dep_id in node.dependencies
                    if dep_id in self.nodes
                )
                if deps_completed:
                    ready.append(node)
        return ready


# =============================================================================
# Fan-In Engine
# =============================================================================

class FanInEngine:
    """
    Combines multiple row results from a RowSet into a single input.
    Executes skill once with combined data instead of per-row execution.
    """
    
    def __init__(self):
        pass
    
    async def execute_fan_in(
        self,
        step: PlanStepModel,
        source_row_set: RowSet,
        skill: Skill,
        base_context: ContextArtifactModel,
        skill_executor_fn
    ) -> tuple["DataPacket", ContextArtifactModel]:
        """
        Combine RowSet results and execute skill once with combined input.
        
        Args:
            step: The plan step with fanin directive
            source_row_set: The RowSet to combine
            skill: The skill definition
            base_context: Base context artifact
            skill_executor_fn: Function to execute skill (from ReactAgentLoop)
        
        Returns:
            Tuple of (DataPacket, updated_context)
        """
        if not step.fanin:
            raise ValueError("Step must have fanin directive")
        
        logger.info(
            f"Executing fan-in for {step.step_id}: "
            f"combining {source_row_set.count} items"
        )
        
        # Combine row values based on combine_field
        combined_data = self._combine_row_set_values(
            source_row_set,
            step.fanin.combine_field,
            step.fanin.format
        )
        
        # Create context with combined data injected via input_mappings
        task_context = self._create_combined_context(
            base_context,
            step.input_mappings,
            combined_data
        )
        
        # Execute skill once with combined input - returns DataPacket
        logger.info(f"Executing {step.step_id} with combined input")
        data_packet = await skill_executor_fn(skill, task_context)
        
        logger.info(f"Fan-in completed for {step.step_id}")
        
        return data_packet, task_context
    
    def _combine_row_set_values(
        self,
        row_set: RowSet,
        combine_field: str,
        format: str
    ) -> Any:
        """
        Extract and combine values from RowSet based on combine_field.
        
        Args:
            row_set: The RowSet with per-row results
            combine_field: Which field to extract from each row's value
            format: How to format the combined data (structured, array, concatenated)
        
        Returns:
            Combined data in requested format
        """
        # Collect successful results only
        successful_rows = [
            row for row in row_set.rows if row.status == RowStatus.OK
        ]
        
        # Extract the specified field from each row
        extracted_values = []
        for row in successful_rows:
            if row.value is None:
                continue
            
            # row.value is now a DataPacket
            from app.models.agent_schemas import DataPacket
            if isinstance(row.value, DataPacket):
                # Extract field from DataPacket rows
                for dp_row in row.value.rows:
                    if combine_field in dp_row:
                        extracted_values.append(dp_row[combine_field])
            elif isinstance(row.value, dict):
                value = row.value.get(combine_field)
                if value is not None:
                    extracted_values.append(value)
            else:
                # Fallback: use value directly
                extracted_values.append(row.value)
        
        # Format based on requested format
        if format == "array":
            return extracted_values
        elif format == "concatenated":
            # Join with separator
            return "\n---\n".join(str(v) for v in extracted_values)
        else:  # structured (default)
            return {
                "items": extracted_values,
                "count": len(extracted_values),
                "total_rows": row_set.count,
                "source_step": row_set.step_id,
                "source_field": row_set.field
            }
    
    def _create_combined_context(
        self,
        base_context: ContextArtifactModel,
        input_mappings: Dict[str, str],
        combined_data: Any
    ) -> ContextArtifactModel:
        """
        Create context with combined data injected via input_mappings.
        
        Args:
            base_context: Base context artifact
            input_mappings: Template mappings (e.g., {"text": "{{ combined }}"})
            combined_data: The combined data to inject
        
        Returns:
            Context with combined data injected
        
        IMPORTANT: Resolved values go into step_outputs, NOT user_values,
        to avoid overriding user-provided fields.
        """
        # Clone base context with new structure
        task_context = ContextArtifactModel(
            version=base_context.version,
            user_values=base_context.user_values.copy(),
            step_outputs=base_context.step_outputs.copy(),
            auth=base_context.auth.copy()
        )
        
        # Inject combined data into context based on input_mappings
        for param_name, template in input_mappings.items():
            # Check if template is a placeholder (contains {{) or a literal value
            template_str = str(template).strip()
            
            if "{{" in template_str and "}}" in template_str:
                # Template placeholder - inject combined_data
                value_to_inject = combined_data
            else:
                # Literal value - use as-is
                value_to_inject = template
            
            # Convert to string for ContextValueModel
            if isinstance(value_to_inject, (list, dict)):
                str_value = json.dumps(value_to_inject)
            elif not isinstance(value_to_inject, str):
                str_value = str(value_to_inject)
            else:
                str_value = value_to_inject
            
            # Inject into step_outputs instead of user_values to avoid overriding
            # user-provided fields. Use a special prefix to indicate these are
            # fanin-scoped values.
            task_context.step_outputs[f"_fanin.{param_name}"] = ContextValueModel(
                name=f"_fanin.{param_name}",
                description=f"Combined data from fanin",
                value=str_value,
                required=False,
                field_type="string"
            )
        
        return task_context


# =============================================================================
# Fan-Out Engine
# =============================================================================

class FanOutEngine:
    """
    Executes a vectorized node with concurrency control.
    Creates task-scoped context per item, runs in parallel, collects RowSet.
    """
    
    def __init__(self):
        pass
    
    async def execute_fan_out(
        self,
        step: PlanStepModel,
        source_row_set: RowSet,
        skill: Skill,
        base_context: ContextArtifactModel,
        skill_executor_fn
    ) -> RowSet:
        """
        Execute a foreach step across all rows in source_row_set.
        
        Args:
            step: The plan step with foreach directive
            source_row_set: The RowSet to iterate over
            skill: The skill definition
            base_context: Base context artifact
            skill_executor_fn: Function to execute skill (from ReactAgentLoop)
        
        Returns:
            RowSet with collected results and per-row status
        """
        if not step.foreach:
            raise ValueError("Step must have foreach directive")
        
        concurrency = step.foreach.concurrency
        alias = step.foreach.as_name
        
        logger.info(
            f"Executing fan-out for {step.step_id}: "
            f"{source_row_set.count} items, concurrency={concurrency}"
        )
        
        # Create semaphore for concurrency control
        sem = asyncio.Semaphore(concurrency)
        
        # Create task units
        task_units = []
        for row in source_row_set.rows:
            tu = TaskUnit(
                task_id=f"{step.step_id}#{row.index}",
                parent_step_id=step.step_id,
                index=row.index,
                inputs={},
                status=RowStatus.PENDING
            )
            task_units.append(tu)
        
        # Launch parallel execution
        tasks = []
        for tu, row in zip(task_units, source_row_set.rows):
            task = self._run_one(
                tu, skill, base_context, step, row.value, alias, skill_executor_fn, sem
            )
            tasks.append(task)
        
        # Wait for all tasks (capture exceptions)
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Collect into RowSet
        row_set = self._collect_row_set(step.step_id, source_row_set.field, task_units, results)
        
        logger.info(
            f"Fan-out completed: {row_set.count} total, "
            f"{sum(1 for r in row_set.rows if r.status == RowStatus.OK)} ok, "
            f"{sum(1 for r in row_set.rows if r.status == RowStatus.FAILED)} failed"
        )
        
        return row_set
    
    async def _run_one(
        self,
        task_unit: TaskUnit,
        skill: Skill,
        base_context: ContextArtifactModel,
        step: PlanStepModel,
        item_value: Any,
        alias: str,
        skill_executor_fn,
        sem: asyncio.Semaphore
    ) -> Any:
        """
        Execute a single task unit with concurrency control.
        
        Returns:
            Output data on success, raises exception on failure
        """
        async with sem:
            try:
                task_unit.status = RowStatus.RUNNING
                
                # Create task-scoped context by resolving input_mappings
                task_context = self._create_task_context(
                    base_context, step.input_mappings, alias, item_value
                )
                
                # Execute skill
                logger.debug(f"Executing {task_unit.task_id}")
                output_data = await skill_executor_fn(skill, task_context)
                
                task_unit.status = RowStatus.OK
                return output_data
                
            except Exception as e:
                task_unit.status = RowStatus.FAILED
                logger.error(f"Task {task_unit.task_id} failed: {e}")
                raise
    
    def _create_task_context(
        self,
        base_context: ContextArtifactModel,
        input_mappings: Dict[str, str],
        alias: str,
        item_value: Any
    ) -> ContextArtifactModel:
        """
        Create task-scoped context by resolving input_mappings templates.
        
        Example:
            input_mappings = {"commit_sha": "{{ commit }}"}
            alias = "commit"
            item_value = "abc123"
            -> Injects context.step_outputs["commit_sha"] = "abc123"
        
        IMPORTANT: Resolved values go into step_outputs, NOT user_values,
        to avoid overriding user-provided fields.
        """
        # Clone base context with new structure
        task_context = ContextArtifactModel(
            version=base_context.version,
            user_values=base_context.user_values.copy(),
            step_outputs=base_context.step_outputs.copy(),
            auth=base_context.auth.copy()
        )
        
        # Resolve each input_mapping template
        for param_name, template in input_mappings.items():
            template_str = str(template).strip()
            match = _TEMPLATE_RE.fullmatch(template_str)
            
            logger.info(f"Processing input_mapping: {param_name}={template_str}, alias={alias}, match={match}")
            
            if not match or match.group(1) != alias:
                # Literal or references context (not iteration) - skip injection
                # so user_values (e.g. repo) or step_outputs can provide the value
                logger.info(f"Skipping injection for {param_name}: not matching alias (match={match}, alias={alias})")
                continue
            
            logger.info(f"Resolving template for {param_name}: template={template}, alias={alias}, item_value={item_value}")
            resolved_value = resolve_template(template, alias, item_value)
            logger.info(f"Resolved value for {param_name}: {resolved_value}")
            
            # Convert to string for ContextValueModel
            if isinstance(resolved_value, (list, dict)):
                str_value = json.dumps(resolved_value)
            elif not isinstance(resolved_value, str):
                str_value = str(resolved_value)
            else:
                str_value = resolved_value
            
            # Inject into step_outputs instead of user_values to avoid overriding
            # user-provided fields. Use a special prefix to indicate these are
            # iteration-scoped values.
            task_context.step_outputs[f"_iter.{param_name}"] = ContextValueModel(
                name=f"_iter.{param_name}",
                description=f"Resolved from foreach iteration",
                value=str_value,
                required=False,
                field_type="string"
            )
            logger.info(f"Injected _iter.{param_name} = {str_value}")
        
        return task_context
    
    def _collect_row_set(
        self,
        step_id: str,
        source_field: str,
        task_units: List[TaskUnit],
        results: List[Any]
    ) -> RowSet:
        """
        Collect task results into a RowSet with index alignment.
        Results are now DataPackets.
        
        Args:
            step_id: Parent step ID
            source_field: Source field name (for tracking)
            task_units: List of task units
            results: List of DataPackets (or exceptions) from asyncio.gather
        
        Returns:
            RowSet with per-row status
        """
        from app.models.agent_schemas import DataPacket
        rows = []
        
        for tu, result in zip(task_units, results):
            if isinstance(result, Exception):
                # Task failed
                row = RowResult(
                    index=tu.index,
                    value=DataPacket.error(str(result), code="FANOUT_ERROR"),
                    error=str(result),
                    status=RowStatus.FAILED
                )
            else:
                # Task succeeded - result is a DataPacket
                row = RowResult(
                    index=tu.index,
                    value=result if isinstance(result, DataPacket) else DataPacket(rows=[result] if isinstance(result, dict) else []),
                    error=None,
                    status=RowStatus.OK
                )
            rows.append(row)
        
        return RowSet(
            step_id=step_id,
            field=source_field,
            count=len(rows),
            rows=rows
        )
