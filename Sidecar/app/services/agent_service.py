"""
Agent Service - GoalPlannerAgent, StepPlannerAgent, ContextAgent
Implements the hierarchical goal-based planning and context management
"""

import logging
import uuid
import json
from typing import Dict, Any, List, Optional, Tuple
from datetime import datetime

from app.models.agent_schemas import (
    GoalPlanRequest,
    GoalPlanResponse,
    GoalPlanModel,
    GoalModel,
    GoalStatus,
    PlanStepModel,
    ContextFieldModel,
    AuthRequirementModel,
    ContextArtifactModel,
    ContextValueModel,
    AuthEntryModel,
    GoalEvaluationResult,
    FinalEvaluationResult,
    ForeachDirective,
    FanInDirective,
    Plugin,
    Skill
)
from app.services.skill_registry import get_registry
from app.services.ai_agent import get_ai_agent

logger = logging.getLogger(__name__)


# =============================================================================
# Goal Planner Agent
# =============================================================================

class GoalPlannerAgent:
    """
    GoalPlannerAgent: Creates high-level goal plans from user queries.
    Each goal is scoped to a single plugin. Uses only plugin summaries (no skills).
    """
    
    def __init__(self):
        self.registry = get_registry()
    
    async def create_goal_plan(self, query: str) -> GoalPlanModel:
        """
        Create a goal plan from a user query.
        LLM receives plugin summaries (id, name, description, auth) - NO skills.
        
        Args:
            query: User's natural language query
        
        Returns:
            GoalPlanModel with ordered goals
        """
        logger.info(f"GoalPlannerAgent: Creating goal plan for query: {query}")
        
        # Get all plugins
        plugins = self.registry.get_all_plugins()
        
        # Format plugins for LLM
        plugins_text = self._format_plugins(plugins)
        
        # Build prompt
        prompt = self._build_goal_plan_prompt(query, plugins_text)
        
        try:
            # Call LLM
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "LLM execution failed"))
            
            response = result.get("output", "").strip()
            
            # Parse JSON response
            goals_data = json.loads(response)
            
            # Build GoalPlanModel
            plan_id = str(uuid.uuid4())
            goals = []
            
            for i, goal_data in enumerate(goals_data):
                goal = GoalModel(
                    goal_id=f"G-{i}",
                    description=goal_data.get("description", ""),
                    plugin_id=goal_data.get("plugin_id", ""),
                    status=GoalStatus.PENDING,
                    depends_on=goal_data.get("depends_on", []),
                    steps=[],
                    step_outputs={},
                    evaluation_history=[],
                    retry_count=0
                )
                goals.append(goal)
            
            plan = GoalPlanModel(
                plan_id=plan_id,
                goals=goals,
                status="draft"
            )
            
            logger.info(f"Created goal plan with {len(goals)} goals")
            return plan
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse LLM goal plan output: {e}")
            raise Exception(f"Failed to parse goal plan: {e}")
        except Exception as e:
            logger.error(f"Goal planning failed: {e}")
            raise
    
    async def refine_goal_plan(
        self,
        query: str,
        current_plan: GoalPlanModel,
        feedback: str
    ) -> GoalPlanModel:
        """
        Refine a goal plan based on user feedback.
        
        Args:
            query: Original user query
            current_plan: Current goal plan
            feedback: User feedback for refinement
        
        Returns:
            Refined GoalPlanModel
        """
        logger.info(f"GoalPlannerAgent: Refining goal plan with feedback: {feedback}")
        
        # Get all plugins
        plugins = self.registry.get_all_plugins()
        plugins_text = self._format_plugins(plugins)
        
        # Build refine prompt
        prompt = self._build_refine_prompt(query, current_plan, feedback, plugins_text)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "LLM execution failed"))
            
            response = result.get("output", "").strip()
            goals_data = json.loads(response)
            
            # Build refined plan
            goals = []
            for i, goal_data in enumerate(goals_data):
                goal = GoalModel(
                    goal_id=f"G-{i}",
                    description=goal_data.get("description", ""),
                    plugin_id=goal_data.get("plugin_id", ""),
                    status=GoalStatus.PENDING,
                    depends_on=goal_data.get("depends_on", []),
                    steps=[],
                    step_outputs={},
                    evaluation_history=[],
                    retry_count=0
                )
                goals.append(goal)
            
            refined_plan = GoalPlanModel(
                plan_id=current_plan.plan_id,
                goals=goals,
                status="draft"
            )
            
            logger.info(f"Refined goal plan with {len(goals)} goals")
            return refined_plan
            
        except Exception as e:
            logger.error(f"Goal plan refinement failed: {e}")
            raise
    
    async def extend_plan(
        self,
        query: str,
        current_plan: GoalPlanModel,
        final_eval: FinalEvaluationResult
    ) -> GoalPlanModel:
        """
        Extend a goal plan after final evaluation indicates incompleteness.
        
        Args:
            query: Original user query
            current_plan: Current goal plan
            final_eval: Final evaluation result with suggestions
        
        Returns:
            Extended GoalPlanModel
        """
        logger.info(f"GoalPlannerAgent: Extending plan based on final evaluation")
        
        # Get all plugins
        plugins = self.registry.get_all_plugins()
        plugins_text = self._format_plugins(plugins)
        
        # Build extension prompt
        prompt = self._build_extension_prompt(query, current_plan, final_eval, plugins_text)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "LLM execution failed"))
            
            response = result.get("output", "").strip()
            new_goals_data = json.loads(response)
            
            # Add new goals to existing plan
            next_goal_idx = len(current_plan.goals)
            for i, goal_data in enumerate(new_goals_data):
                goal = GoalModel(
                    goal_id=f"G-{next_goal_idx + i}",
                    description=goal_data.get("description", ""),
                    plugin_id=goal_data.get("plugin_id", ""),
                    status=GoalStatus.PENDING,
                    depends_on=goal_data.get("depends_on", []),
                    steps=[],
                    step_outputs={},
                    evaluation_history=[],
                    retry_count=0
                )
                current_plan.goals.append(goal)
            
            logger.info(f"Extended plan with {len(new_goals_data)} new goals")
            return current_plan
            
        except Exception as e:
            logger.error(f"Plan extension failed: {e}")
            raise
    
    def _format_plugins(self, plugins: List[Plugin]) -> str:
        """Format plugins for LLM prompt (no skills, just plugin metadata)"""
        lines = []
        for i, plugin in enumerate(plugins, 1):
            auth_desc = ""
            if plugin.auth_requirements:
                auth_types = [req.auth_id for req in plugin.auth_requirements]
                auth_desc = f" (requires: {', '.join(auth_types)})"
            
            lines.append(
                f"{i}. {plugin.plugin_id} - {plugin.name}\n"
                f"   Description: {plugin.description}{auth_desc}\n"
            )
        return "\n".join(lines)
    
    def _build_goal_plan_prompt(self, query: str, plugins_text: str) -> str:
        """Build prompt for goal plan creation"""
        return f"""You are a goal planner. Break down the user's query into high-level goals.

USER QUERY: {query}

AVAILABLE PLUGINS:
{plugins_text}

Your task: Create an ordered list of goals to accomplish the user's query. Each goal should:
- Focus on a single plugin
- Have a clear, specific objective
- Be ordered logically (dependencies matter)

Return ONLY a valid JSON array of goal objects with this structure:
[
  {{
    "description": "Detailed objective for this goal",
    "plugin_id": "plugin_id",
    "depends_on": ["G-0"] or []
  }}
]

Guidelines:
- Keep the number of goals MINIMAL. Combine related work into one goal when it uses the same plugin.
- Do NOT split a single plugin's workflow across multiple goals. For example, "fetch items then describe each item" using the same plugin should be ONE goal — the step planner will handle the multi-step orchestration within that goal.
- Only create separate goals when different plugins are needed, or when truly independent tasks exist.
- Use depends_on when a goal needs output from a previous goal's plugin (e.g., ["G-0"] means this goal depends on G-0 completing first)
- Keep goals focused and actionable
- Order matters - place goals that produce data before goals that consume it
- Do NOT create authentication goals - assume authentication is already handled
- Only create goals explicitly related to the task at hand

Return ONLY the raw JSON array, no markdown formatting, no explanations."""
    
    def _build_refine_prompt(
        self,
        query: str,
        current_plan: GoalPlanModel,
        feedback: str,
        plugins_text: str
    ) -> str:
        """Build prompt for goal plan refinement"""
        
        # Format current goals
        current_goals_text = []
        for goal in current_plan.goals:
            deps = f", depends_on: {goal.depends_on}" if goal.depends_on else ""
            current_goals_text.append(f"- {goal.goal_id}: {goal.description} (plugin: {goal.plugin_id}{deps})")
        current_goals_str = "\n".join(current_goals_text)
        
        return f"""You are refining a goal plan based on user feedback.

USER QUERY: {query}

CURRENT GOAL PLAN:
{current_goals_str}

USER FEEDBACK: {feedback}

AVAILABLE PLUGINS:
{plugins_text}

Your task: Create a REVISED goal plan that addresses the user's feedback.

Return ONLY a valid JSON array of goal objects with this structure:
[
  {{
    "description": "Detailed objective for this goal",
    "plugin_id": "plugin_id",
    "depends_on": ["G-0"] or []
  }}
]

Guidelines:
- Address the user's feedback
- Keep goals focused and actionable
- Use depends_on to specify goal dependencies
- Order matters

Return ONLY the raw JSON array, no markdown formatting, no explanations."""
    
    def _build_extension_prompt(
        self,
        query: str,
        current_plan: GoalPlanModel,
        final_eval: FinalEvaluationResult,
        plugins_text: str
    ) -> str:
        """Build prompt for plan extension"""
        
        # Format completed goals
        completed_goals_text = []
        for goal in current_plan.goals:
            if goal.status == GoalStatus.COMPLETED:
                completed_goals_text.append(f"- {goal.goal_id}: {goal.description} (plugin: {goal.plugin_id}) - COMPLETED")
        completed_goals_str = "\n".join(completed_goals_text) if completed_goals_text else "None yet"
        
        return f"""You are extending a goal plan because the user's query is not yet fully resolved.

USER QUERY: {query}

COMPLETED GOALS:
{completed_goals_str}

EVALUATION: {final_eval.reasoning}
SUGGESTION: {final_eval.suggested_additions or "Add more goals to complete the query"}

AVAILABLE PLUGINS:
{plugins_text}

Your task: Create ADDITIONAL goals to append to the existing plan.

Return ONLY a valid JSON array of NEW goal objects:
[
  {{
    "description": "Detailed objective for this goal",
    "plugin_id": "plugin_id",
    "depends_on": ["G-0", "G-1"] or []
  }}
]

Guidelines:
- These goals will be appended to the existing plan
- Reference existing goals in depends_on if needed (G-0, G-1, etc.)
- Focus on what's missing to complete the user's query

Return ONLY the raw JSON array, no markdown formatting, no explanations."""


# =============================================================================
# Step Planner Agent
# =============================================================================

class StepPlannerAgent:
    """
    StepPlannerAgent: Creates detailed step plans for individual goals.
    Uses skill schemas from the goal's plugin and accumulated context.
    """
    
    def __init__(self):
        self.registry = get_registry()
    
    async def create_steps(
        self,
        goal: GoalModel,
        context_summary: str
    ) -> Tuple[List[PlanStepModel], List[ContextFieldModel]]:
        """
        Create steps for a goal using skills from the goal's plugin.
        
        Args:
            goal: The goal to create steps for
            context_summary: Summary of accumulated context from previous goals
        
        Returns:
            Tuple of (steps, required_inputs)
        """
        logger.info(f"StepPlannerAgent: Creating steps for goal {goal.goal_id}")
        
        # Get skills for this goal's plugin
        skills = self.registry.get_skills_for_plugin(goal.plugin_id)
        if not skills:
            logger.warning(f"No skills found for plugin {goal.plugin_id}")
            return [], []
        
        # Format skills for LLM
        skills_text = self._format_skills(skills)
        
        # Build prompt
        prompt = self._build_step_prompt(goal, skills_text, context_summary)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "LLM execution failed"))
            
            response = result.get("output", "").strip()
            step_objects = json.loads(response)
            
            # Build PlanStepModel list
            steps = []
            available_outputs = {}  # field_name -> step_id
            
            for i, step_obj in enumerate(step_objects):
                skill_id = step_obj.get("skill_id")
                if not skill_id:
                    continue
                
                # Find the skill
                skill = None
                for s in skills:
                    if s.skill_id == skill_id:
                        skill = s
                        break
                
                if not skill:
                    logger.warning(f"Skill {skill_id} not found in plugin {goal.plugin_id}")
                    continue
                
                step_id = f"Step-{i}-0"
                
                # Extract foreach, fanin, input_mappings
                foreach_directive = None
                fanin_directive = None
                input_mappings = {}
                
                if "foreach" in step_obj:
                    foreach_data = step_obj["foreach"]
                    foreach_directive = ForeachDirective(
                        source=foreach_data.get("source", ""),
                        as_name=foreach_data.get("as", "item"),
                        concurrency=foreach_data.get("concurrency", 5)
                    )
                
                if "fanin" in step_obj:
                    fanin_data = step_obj["fanin"]
                    fanin_directive = FanInDirective(
                        source=fanin_data.get("source", ""),
                        combine_field=fanin_data.get("combine_field", ""),
                        format=fanin_data.get("format", "structured")
                    )
                
                if "input_mappings" in step_obj:
                    input_mappings = {k: str(v) for k, v in step_obj["input_mappings"].items()}
                
                # Determine dependencies
                depends_on = []
                if "properties" in skill.input_schema:
                    for field_name in skill.input_schema["properties"].keys():
                        if field_name in available_outputs:
                            provider_step_id = available_outputs[field_name]
                            if provider_step_id not in depends_on:
                                depends_on.append(provider_step_id)
                
                # Extract expected outputs
                expected_outputs = []
                if "properties" in skill.output_schema:
                    expected_outputs = list(skill.output_schema["properties"].keys())
                    for output_field in expected_outputs:
                        available_outputs[output_field] = step_id
                
                step = PlanStepModel(
                    step_id=step_id,
                    agent_type="operation",
                    plugin_id=goal.plugin_id,
                    skill_id=skill.skill_id,
                    description=skill.description,
                    depends_on=depends_on,
                    expected_outputs=expected_outputs,
                    foreach=foreach_directive,
                    fanin=fanin_directive,
                    input_mappings=input_mappings
                )
                steps.append(step)
            
            # Identify required inputs (fields not fulfilled by previous steps or context)
            required_inputs = self._extract_required_inputs(steps, skills, context_summary)
            
            logger.info(f"Created {len(steps)} steps for goal {goal.goal_id}, {len(required_inputs)} required inputs")
            return steps, required_inputs
            
        except Exception as e:
            logger.error(f"Step planning failed: {e}")
            raise
    
    async def create_more_steps(
        self,
        goal: GoalModel,
        existing_steps: List[PlanStepModel],
        outputs: Dict[str, Any],
        failure_info: str,
        context_summary: str
    ) -> Tuple[List[PlanStepModel], List[ContextFieldModel]]:
        """
        Create additional steps for a goal after evaluation indicates incompleteness.
        
        Args:
            goal: The goal
            existing_steps: Already executed steps
            outputs: Outputs from existing steps
            failure_info: Information about why the goal is incomplete
            context_summary: Context summary
        
        Returns:
            Tuple of (new_steps, required_inputs)
        """
        logger.info(f"StepPlannerAgent: Creating more steps for goal {goal.goal_id} (retry)")
        
        # Get skills for this goal's plugin
        skills = self.registry.get_skills_for_plugin(goal.plugin_id)
        if not skills:
            return [], []
        
        skills_text = self._format_skills(skills)
        
        # Build retry prompt
        prompt = self._build_retry_prompt(goal, existing_steps, outputs, failure_info, skills_text, context_summary)
        
        try:
            llm = await get_ai_agent()
            result = await llm.execute_task(prompt, use_tools=False)
            
            if not result.get("success"):
                raise Exception(result.get("error", "LLM execution failed"))
            
            response = result.get("output", "").strip()
            step_objects = json.loads(response)
            
            # Build new steps (starting from next index)
            next_step_idx = len(existing_steps)
            steps = []
            available_outputs = {}
            
            # Register outputs from existing steps
            for step in existing_steps:
                for output_field in step.expected_outputs:
                    available_outputs[output_field] = step.step_id
            
            for i, step_obj in enumerate(step_objects):
                skill_id = step_obj.get("skill_id")
                if not skill_id:
                    continue
                
                skill = None
                for s in skills:
                    if s.skill_id == skill_id:
                        skill = s
                        break
                
                if not skill:
                    continue
                
                step_id = f"Step-{next_step_idx + i}-0"
                
                # Extract directives
                foreach_directive = None
                fanin_directive = None
                input_mappings = {}
                
                if "foreach" in step_obj:
                    foreach_data = step_obj["foreach"]
                    foreach_directive = ForeachDirective(
                        source=foreach_data.get("source", ""),
                        as_name=foreach_data.get("as", "item"),
                        concurrency=foreach_data.get("concurrency", 5)
                    )
                
                if "fanin" in step_obj:
                    fanin_data = step_obj["fanin"]
                    fanin_directive = FanInDirective(
                        source=fanin_data.get("source", ""),
                        combine_field=fanin_data.get("combine_field", ""),
                        format=fanin_data.get("format", "structured")
                    )
                
                if "input_mappings" in step_obj:
                    input_mappings = {k: str(v) for k, v in step_obj["input_mappings"].items()}
                
                depends_on = []
                if "properties" in skill.input_schema:
                    for field_name in skill.input_schema["properties"].keys():
                        if field_name in available_outputs:
                            provider_step_id = available_outputs[field_name]
                            if provider_step_id not in depends_on:
                                depends_on.append(provider_step_id)
                
                expected_outputs = []
                if "properties" in skill.output_schema:
                    expected_outputs = list(skill.output_schema["properties"].keys())
                    for output_field in expected_outputs:
                        available_outputs[output_field] = step_id
                
                step = PlanStepModel(
                    step_id=step_id,
                    agent_type="operation",
                    plugin_id=goal.plugin_id,
                    skill_id=skill.skill_id,
                    description=skill.description,
                    depends_on=depends_on,
                    expected_outputs=expected_outputs,
                    foreach=foreach_directive,
                    fanin=fanin_directive,
                    input_mappings=input_mappings
                )
                steps.append(step)
            
            required_inputs = self._extract_required_inputs(steps, skills, context_summary)
            
            logger.info(f"Created {len(steps)} additional steps for goal {goal.goal_id}")
            return steps, required_inputs
            
        except Exception as e:
            logger.error(f"Retry step planning failed: {e}")
            raise
    
    def _format_skills(self, skills: List[Skill]) -> str:
        """Format skills for LLM prompt (reuse existing logic)"""
        lines = []
        for skill in skills:
            # Format inputs
            inputs = []
            if "properties" in skill.input_schema:
                for field_name in skill.input_schema["properties"].keys():
                    is_required = field_name in skill.input_schema.get("required", [])
                    req_marker = "*" if is_required else ""
                    inputs.append(f"{field_name}{req_marker}")
            inputs_str = ", ".join(inputs) if inputs else "none"
            
            # Format outputs
            outputs = []
            if "properties" in skill.output_schema:
                outputs = list(skill.output_schema["properties"].keys())
            outputs_str = ", ".join(outputs) if outputs else "none"
            
            lines.append(f"- {skill.skill_id}: {skill.description}")
            lines.append(f"  Inputs: {inputs_str}")
            lines.append(f"  Outputs: {outputs_str}")
        
        return "\n".join(lines)
    
    def _build_step_prompt(self, goal: GoalModel, skills_text: str, context_summary: str) -> str:
        """Build prompt for step planning"""
        has_previous_context = context_summary and context_summary != "No context available"
        
        reuse_block = ""
        if has_previous_context:
            reuse_block = """
If any data listed above was produced by a PREVIOUS goal using the SAME plugin,
you should reference it via cross-goal syntax (e.g. foreach source "G-0.Step-0-0")
rather than re-running the same skill. Only re-fetch if the goal explicitly requires
different parameters or a fresh query."""
        
        return f"""You are a step planner. Create detailed steps to accomplish a goal using available skills.

GOAL: {goal.description}
PLUGIN: {goal.plugin_id}

AVAILABLE CONTEXT FROM PREVIOUS GOALS:
{context_summary if has_previous_context else "None - this is the first goal"}
{reuse_block}
AVAILABLE SKILLS:
{skills_text}

Your task: Create a sequence of steps using these skills to accomplish the goal.

Return ONLY a valid JSON array of step objects:
[
  {{
    "skill_id": "skill_id",
    "foreach": {{"source": "Step-N.field", "as": "alias", "concurrency": 5}},  // optional
    "fanin": {{"source": "Step-N", "combine_field": "field", "format": "concatenated"}},  // optional
    "input_mappings": {{"param": "{{{{ alias }}}}" or "{{{{ G-0.Step-0-0.field }}}}"}}  // optional
  }}
]

Guidelines:
- Order matters - place skills that produce outputs before skills that need those outputs
- NEVER repeat the same skill_id more than once in the plan UNLESS it is used with a different directive (e.g. once plain, once with foreach, or once with fanin). A skill that already ran and produced output does not need to run again — downstream steps should reference its output.
- Use foreach when you need to process each item separately (runs N times)
- Use fanin when you want to aggregate/combine multiple results (runs once with combined input)
- IMPORTANT: "fanin" is a DIRECTIVE, not a skill_id. Always use a real skill with the fanin directive
- For within-goal references: "Step-N.field"
- For cross-goal references: "G-0.Step-N-0.field" (from previous goals)
- input_mappings: map param names to template expressions or context keys
- When using fanin, reference the combined data as "{{{{ _fanin.field_name }}}}" in input_mappings
- All input_mappings values must be strings (quoted)

EXAMPLES:

Example 1: Process multiple items then combine results
[
  {{
    "skill_id": "summarize",
    "foreach": {{"source": "G-0.Step-0-0.commit_shas", "as": "commit_sha", "concurrency": 3}},
    "input_mappings": {{"text": "{{{{ commit_sha }}}}", "max_length": "200"}}
  }},
  {{
    "skill_id": "summarize",
    "fanin": {{"source": "Step-0", "combine_field": "summary", "format": "concatenated"}},
    "input_mappings": {{"text": "{{{{ _fanin.summary }}}}", "max_length": "500"}}
  }}
]

Example 2: Fetch multiple items then analyze all together
[
  {{
    "skill_id": "http.get",
    "foreach": {{"source": "urls", "as": "url"}},
    "input_mappings": {{"url": "{{{{ url }}}}"}}
  }},
  {{
    "skill_id": "analyze",
    "fanin": {{"source": "Step-0", "combine_field": "response", "format": "array"}},
    "input_mappings": {{"data": "{{{{ _fanin.response }}}}"}}
  }}
]

Return ONLY the raw JSON array, no markdown formatting, no explanations."""
    
    def _build_retry_prompt(
        self,
        goal: GoalModel,
        existing_steps: List[PlanStepModel],
        outputs: Dict[str, Any],
        failure_info: str,
        skills_text: str,
        context_summary: str
    ) -> str:
        """Build prompt for retry step planning"""
        
        # Format existing steps
        existing_steps_text = []
        for step in existing_steps:
            existing_steps_text.append(f"- {step.step_id}: {step.skill_id} - {step.description}")
        existing_steps_str = "\n".join(existing_steps_text)
        
        return f"""You are creating additional steps for a goal that is not yet complete.

GOAL: {goal.description}

ALREADY EXECUTED STEPS:
{existing_steps_str}

EVALUATION: {failure_info}

AVAILABLE CONTEXT:
{context_summary}

AVAILABLE SKILLS:
{skills_text}

Your task: Create ADDITIONAL steps to complete the goal. These will be appended to existing steps.

Return ONLY a valid JSON array of NEW step objects:
[
  {{
    "skill_id": "skill_id",
    "foreach": {{"source": "Step-N.field", "as": "alias"}},  // optional
    "fanin": {{"source": "Step-N", "combine_field": "field"}},  // optional
    "input_mappings": {{"param": "{{{{ alias }}}}"}}  // optional
  }}
]

Guidelines:
- Reference existing steps if needed (Step-0, Step-1, etc.)
- Focus on what's missing to complete the goal
- NEVER re-run a skill that already executed successfully. If fetchLaunches already ran, do NOT add another fetchLaunches step. Reference the existing output instead.
- NEVER create one step per row — use foreach to iterate over all rows from a previous step in a single step definition.
- IMPORTANT: "fanin" is a DIRECTIVE, not a skill_id. Always use a real skill with the fanin directive
- When using fanin, reference the combined data as "{{{{ _fanin.field_name }}}}" in input_mappings

Return ONLY the raw JSON array, no markdown formatting, no explanations."""
    
    def _extract_required_inputs(
        self,
        steps: List[PlanStepModel],
        skills: List[Skill],
        context_summary: str
    ) -> List[ContextFieldModel]:
        """
        Extract required inputs that are not fulfilled by previous steps or context.
        
        Args:
            steps: The planned steps
            skills: Available skills
            context_summary: Summary of available context
        
        Returns:
            List of required context fields
        """
        available_fields = set()
        seen_user_fields = set()
        user_required = []
        
        # Parse context summary to extract available fields
        # Context summary format: "G-0.Step-0-0.field_name: value"
        if context_summary:
            for line in context_summary.split("\n"):
                if ":" in line:
                    field_part = line.split(":")[0].strip()
                    if "." in field_part:
                        # Extract the field name (last part after .)
                        field_name = field_part.split(".")[-1]
                        available_fields.add(field_name)
        
        # Walk through steps to identify required inputs
        for step in steps:
            # Find the skill
            skill = None
            for s in skills:
                if s.skill_id == step.skill_id:
                    skill = s
                    break
            
            if not skill:
                continue
            
            # Check input schema
            if "properties" in skill.input_schema:
                for field_name, field_def in skill.input_schema["properties"].items():
                    is_required = field_name in skill.input_schema.get("required", [])
                    
                    # Skip if available from previous steps or context
                    if field_name in available_fields:
                        continue
                    
                    # Skip if already added
                    if field_name in seen_user_fields:
                        continue
                    
                    seen_user_fields.add(field_name)
                    user_required.append(ContextFieldModel(
                        name=field_name,
                        description=field_def.get("description", field_name),
                        required=is_required,
                        field_type=self._infer_field_type(field_def)
                    ))
            
            # Register this step's outputs as available
            if "properties" in skill.output_schema:
                for output_field in skill.output_schema["properties"].keys():
                    available_fields.add(output_field)
        
        return user_required
    
    def _infer_field_type(self, field_def: Dict[str, Any]) -> str:
        """Infer field type from JSON schema"""
        schema_type = field_def.get("type", "string")
        
        # Check if it's a secret field
        desc_lower = field_def.get("description", "").lower()
        if "token" in desc_lower or "password" in desc_lower or "secret" in desc_lower:
            return "secret"
        
        # Map JSON schema types
        type_map = {
            "string": "string",
            "integer": "number",
            "number": "number",
            "boolean": "boolean",
            "object": "string",
            "array": "string"
        }
        
        return type_map.get(schema_type, "string")
    
    def _summarize_context(self, context: ContextArtifactModel) -> str:
        """
        Serialize context for prompt with structured output descriptions.
        For large outputs, shows schema + row count instead of full data to keep
        the prompt focused while still informing the LLM what data is available.
        """
        lines = []

        if context.user_values:
            lines.append("User-provided fields:")
            for key, value in context.user_values.items():
                if hasattr(value, 'value'):
                    display_value = value.value
                else:
                    display_value = str(value)
                lines.append(f"  {key}: {display_value}")

        if context.step_outputs:
            lines.append("")
            lines.append("AVAILABLE DATA from previous goals (use cross-goal refs to reuse):")
            for key, value in context.step_outputs.items():
                if hasattr(value, 'value'):
                    raw = value.value
                else:
                    raw = str(value) if not isinstance(value, str) else value

                # Try to parse as JSON to give a structured summary
                try:
                    parsed = json.loads(raw) if isinstance(raw, str) else raw
                    if isinstance(parsed, dict) and "rows" in parsed:
                        rows = parsed["rows"]
                        row_count = len(rows)
                        sample_keys = list(rows[0].keys()) if rows and isinstance(rows[0], dict) else []
                        lines.append(f"  {key}: DataPacket with {row_count} rows, fields={sample_keys}")
                        if rows and row_count > 0:
                            sample = {k: v for k, v in list(rows[0].items())[:4]}
                            lines.append(f"    Sample row: {json.dumps(sample, default=str)}")
                        lines.append(f"    -> Reference as \"{key}\" in foreach source or input_mappings")
                    elif isinstance(parsed, list) and len(parsed) > 0:
                        lines.append(f"  {key}: List with {len(parsed)} items")
                        if isinstance(parsed[0], dict):
                            lines.append(f"    Fields: {list(parsed[0].keys())}")
                        lines.append(f"    -> Reference as \"{key}\" in foreach source or input_mappings")
                    else:
                        display = raw[:300] if isinstance(raw, str) and len(raw) > 300 else raw
                        lines.append(f"  {key}: {display}")
                except (json.JSONDecodeError, TypeError, AttributeError):
                    display = raw[:300] if isinstance(raw, str) and len(raw) > 300 else raw
                    lines.append(f"  {key}: {display}")

        return "\n".join(lines) if lines else "No context available"


# =============================================================================
# Context Agent
# =============================================================================

class ContextAgent:
    """
    ContextAgent: Validates context completeness and creates versioned artifacts.
    Handles cross-goal output propagation.
    """
    
    def validate_context(self, context: Dict[str, Any], required: List[ContextFieldModel]) -> bool:
        """Check if all required context fields are provided"""
        for field in required:
            if field.required and field.name not in context:
                return False
        return True
    
    def create_context_artifact(
        self,
        values: Dict[str, Any],
        auth: Dict[str, Any],
        required_fields: List[ContextFieldModel]
    ) -> ContextArtifactModel:
        """Create a context artifact with protected user values"""
        user_values = {}
        
        for field in required_fields:
            value = values.get(field.name, "")
            user_values[field.name] = ContextValueModel(
                name=field.name,
                description=field.description,
                value=str(value),
                required=field.required,
                field_type=field.field_type
            )
        
        auth_entries = {}
        for auth_id, auth_value in auth.items():
            value = auth_value.get("value", "")
            is_valid = bool(value and len(value) >= 10)
            auth_entries[auth_id] = AuthEntryModel(
                strategy_used=auth_value.get("strategy", "token"),
                value=value,
                valid=is_valid
            )
        
        return ContextArtifactModel(
            version=1,
            user_values=user_values,
            step_outputs={},
            auth=auth_entries
        )
    
    def propagate_goal_outputs(
        self,
        goal: GoalModel,
        context: ContextArtifactModel
    ) -> ContextArtifactModel:
        """
        Propagate goal outputs to global context with goal-scoped namespacing.
        
        Args:
            goal: The completed goal
            context: Current context artifact
        
        Returns:
            Updated context artifact
        """
        logger.info(f"Propagating outputs from goal {goal.goal_id}")
        
        # Copy goal's step_outputs to global context with goal prefix
        for key, value in goal.step_outputs.items():
            # Add goal prefix if not already present
            if not key.startswith(f"{goal.goal_id}."):
                global_key = f"{goal.goal_id}.{key}"
            else:
                global_key = key
            
            # Wrap value in ContextValueModel if not already wrapped
            if isinstance(value, ContextValueModel):
                context.step_outputs[global_key] = value
            else:
                # Serialize lists/dicts to JSON strings
                serialized_value = json.dumps(value) if isinstance(value, (list, dict)) else str(value)
                context.step_outputs[global_key] = ContextValueModel(
                    name=global_key,
                    description=f"Output from goal {goal.goal_id}",
                    value=serialized_value,
                    required=False,
                    field_type="string"
                )
        
        return context


# =============================================================================
# Session Store (In-Memory for V1)
# =============================================================================

class SessionStore:
    """In-memory session storage for goal-based agent"""
    
    def __init__(self):
        self._sessions: Dict[str, Dict[str, Any]] = {}
    
    def create_session(self, query: str) -> str:
        """Create a new session"""
        session_id = str(uuid.uuid4()).upper()
        self._sessions[session_id] = {
            "id": session_id,
            "query": query,
            "status": "planning_goals",
            "timestamp": datetime.now(),
            "goal_plan": None,
            "context_artifact": None,
            "current_goal_index": 0,
            "event_queue": None,
            "approval_event": None,
            "last_decision": None,
            "revision_count": 0
        }
        return session_id
    
    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get a session by ID"""
        return self._sessions.get(session_id)
    
    def update_session(self, session_id: str, updates: Dict[str, Any]):
        """Update session data"""
        if session_id in self._sessions:
            self._sessions[session_id].update(updates)
    
    def list_sessions(self) -> List[Dict[str, Any]]:
        """List all sessions"""
        return list(self._sessions.values())


# Global session store
_session_store = SessionStore()


def get_session_store() -> SessionStore:
    """Get the global session store"""
    return _session_store
