"""
Agent Mode Pydantic Models
Schemas for agent execution, context artifacts, and skill discovery
"""

from typing import Any, Dict, List, Optional, Callable, Awaitable
from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from enum import Enum


# =============================================================================
# DataPacket – the single data contract for all boundaries
# =============================================================================

class DataPacket(BaseModel):
    """Universal data container exchanged at every boundary."""
    schema_def: Optional[Dict[str, Any]] = Field(None, alias="schema", description="JSON Schema describing one row")
    rows: List[Dict[str, Any]] = Field(default_factory=list, description="Always List[dict]")

    model_config = ConfigDict(populate_by_name=True)

    # --- convenience constructors ---

    @staticmethod
    def text(content: str) -> "DataPacket":
        return DataPacket(schema_def={"text": "string"}, rows=[{"text": content}])

    @staticmethod
    def error(message: str, code: str = "UNKNOWN", details: Optional[dict] = None) -> "DataPacket":
        return DataPacket(
            schema_def={"error": "string", "code": "string", "details": "object"},
            rows=[{"error": message, "code": code, "details": details or {}}],
        )

    # --- introspection helpers ---

    def is_error(self) -> bool:
        return bool(self.rows) and "error" in self.rows[0]

    def first(self, field: str) -> Any:
        """Get a field from the first row, or None."""
        if self.rows:
            return self.rows[0].get(field)
        return None

    def column(self, field: str) -> List[Any]:
        """Collect a single field across all rows."""
        return [row.get(field) for row in self.rows if field in row]

    def model_dump(self, **kwargs):
        """Override to always use 'schema' as the key in JSON output."""
        data = super().model_dump(**kwargs)
        if "schema_def" in data:
            data["schema"] = data.pop("schema_def")
        return data


# =============================================================================
# Context and Auth Models
# =============================================================================

class ContextFieldModel(BaseModel):
    """Context field definition"""
    name: str
    description: str
    required: bool
    field_type: str = Field(default="string", description="string, number, boolean, or secret")


class AuthRequirementModel(BaseModel):
    """Authentication requirement"""
    auth_id: str
    description: str
    strategies: List[str] = Field(default_factory=list, description="token, user_password, oauth")
    # OAuth metadata for frontend
    oauth_provider: Optional[str] = None
    oauth_scopes: Optional[List[str]] = None


class ForeachDirective(BaseModel):
    """Foreach directive for fan-out execution"""
    source: str = Field(..., description="Source field in format 'step_id.field_name'")
    as_name: str = Field(..., description="Alias for current item in iteration")
    concurrency: int = Field(default=5, description="Max parallel task units")


class FanInDirective(BaseModel):
    """FanIn directive for combining multiple row results into single input"""
    source: str = Field(..., description="Source field in format 'step_id.field_name'")
    combine_field: str = Field(..., description="Which output field to extract and combine from each row")
    format: str = Field(default="structured", description="structured, array, or concatenated")


class PlanStepModel(BaseModel):
    """Single step in execution plan"""
    step_id: str
    agent_type: str = Field(..., description="context, operation, or planner")
    plugin_id: Optional[str] = None
    skill_id: Optional[str] = None
    description: Optional[str] = None
    status: str = Field(default="pending", description="pending, running, completed, failed")
    depends_on: List[str] = Field(default_factory=list)
    expected_outputs: List[str] = Field(default_factory=list)
    foreach: Optional[ForeachDirective] = None
    fanin: Optional[FanInDirective] = None
    input_mappings: Dict[str, str] = Field(default_factory=dict)
    produces: Optional[str] = Field(None)


class ExecutionPlanModel(BaseModel):
    """Execution plan with ordered steps for the fan-out engine"""
    steps: List[PlanStepModel] = Field(default_factory=list, description="Ordered steps to execute")


class ContextValueModel(BaseModel):
    """Context value"""
    name: str
    description: str
    value: str
    required: bool
    field_type: str


class AuthEntryModel(BaseModel):
    """Authentication entry"""
    strategy_used: str
    value: str
    valid: bool = True


class ContextArtifactModel(BaseModel):
    """Context artifact with versioning and protected user values"""
    version: int = 1
    user_values: Dict[str, ContextValueModel] = Field(default_factory=dict)
    step_outputs: Dict[str, ContextValueModel] = Field(default_factory=dict)
    auth: Dict[str, AuthEntryModel] = Field(default_factory=dict)

    def resolve_param(self, field_name: str, input_sources: Optional[Dict[str, str]] = None) -> Optional[str]:
        """
        Resolve a parameter value from context.
        
        Priority:
        1. Iteration-scoped values (_iter.{field} or _fanin.{field}) - from foreach/fanin execution
        2. User-provided values (user_values) - original user input
        3. Input sources mapping (input_sources) - explicit mappings from plan
        4. Step outputs (step_outputs) - outputs from previous steps
        
        This ensures that:
        - Foreach/fanin iterations can override parameters temporarily
        - User values are never permanently overwritten
        - Explicit mappings take precedence over implicit lookups
        """
        # Priority 1: Check for iteration-scoped values (foreach/fanin)
        iter_key = f"_iter.{field_name}"
        if iter_key in self.step_outputs:
            return self.step_outputs[iter_key].value
        
        fanin_key = f"_fanin.{field_name}"
        if fanin_key in self.step_outputs:
            return self.step_outputs[fanin_key].value
        
        # Priority 2: Check user-provided values
        if field_name in self.user_values:
            return self.user_values[field_name].value

        # Priority 3: Check explicit input_sources mapping
        if input_sources and field_name in input_sources:
            source_key = input_sources[field_name]
            if source_key in self.step_outputs:
                return self.step_outputs[source_key].value

        # Priority 4: Search step_outputs for namespaced keys
        for key in reversed(list(self.step_outputs.keys())):
            if key.endswith(f".{field_name}"):
                return self.step_outputs[key].value

        return None




# =============================================================================
# Fan-Out Execution Models
# =============================================================================

class RowStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    OK = "ok"
    FAILED = "failed"


class RowResult(BaseModel):
    """Single row in a RowSet – value is now a DataPacket."""
    index: int
    value: Optional[DataPacket] = None
    error: Optional[str] = None
    status: RowStatus = RowStatus.PENDING


class RowSet(BaseModel):
    """Typed container for row-based outputs with index alignment"""
    step_id: str
    field: str
    count: int = 0
    rows: List[RowResult] = Field(default_factory=list)


class TaskUnit(BaseModel):
    """Individual fan-out execution unit"""
    task_id: str
    parent_step_id: str
    index: int
    inputs: Dict[str, Any] = Field(default_factory=dict)
    status: RowStatus = RowStatus.PENDING
    retry_count: int = 0


class OutputShape(str, Enum):
    SCALAR = "scalar"
    ROW_SET = "row_set"


class StepOutput(BaseModel):
    """Shape-annotated output stored in session memory"""
    step_id: str
    shape: OutputShape
    view: str = Field(default="text", description="text | table | json | error")
    data: DataPacket = Field(default_factory=lambda: DataPacket(rows=[]))
    row_set: Optional[RowSet] = Field(None)


# =============================================================================
# Goal-Based Agent Models
# =============================================================================

class GoalStatus(str, Enum):
    """Status of a goal in the execution pipeline"""
    PENDING = "pending"
    PLANNING_STEPS = "planning_steps"
    AWAITING_STEP_APPROVAL = "awaiting_step_approval"
    EXECUTING = "executing"
    EVALUATING = "evaluating"
    COMPLETED = "completed"
    FAILED = "failed"


class GoalModel(BaseModel):
    """Single goal in the goal plan"""
    goal_id: str = Field(..., description="Goal identifier (G-0, G-1, etc.)")
    description: str = Field(..., description="Detailed objective for this goal")
    plugin_id: str = Field(..., description="Which plugin this goal uses")
    status: GoalStatus = Field(default=GoalStatus.PENDING)
    depends_on: List[str] = Field(default_factory=list, description="Goal IDs this depends on")
    steps: List[PlanStepModel] = Field(default_factory=list, description="Steps planned for this goal")
    step_outputs: Dict[str, Any] = Field(default_factory=dict, description="Accumulated outputs from steps")
    evaluation_history: List[Dict[str, Any]] = Field(default_factory=list, description="Track evaluations and retries")
    retry_count: int = Field(default=0)


class GoalPlanModel(BaseModel):
    """Goal plan with ordered goals"""
    plan_id: str
    goals: List[GoalModel]
    status: str = Field(default="draft", description="draft, approved, executing, completed, failed")


class SessionStatus(str, Enum):
    """Status of an agent session"""
    PLANNING_GOALS = "planning_goals"
    AWAITING_GOAL_APPROVAL = "awaiting_goal_approval"
    EXECUTING = "executing"
    COMPLETED = "completed"
    FAILED = "failed"


# =============================================================================
# Request/Response Models
# =============================================================================

class GoalPlanRequest(BaseModel):
    """Request to generate a goal plan"""
    query: str = Field(..., description="User's natural language query")


class GoalPlanResponse(BaseModel):
    """Response with goal plan and required auth"""
    session_id: str
    goal_plan: GoalPlanModel
    required_auth: List[AuthRequirementModel] = Field(default_factory=list)


class GoalApproveRequest(BaseModel):
    """Request to approve or reject a goal plan"""
    approved: bool
    feedback: Optional[str] = Field(None, description="Feedback for plan refinement if rejected")


class StepApproveRequest(BaseModel):
    """Request to approve steps and provide inputs for a goal"""
    approved: bool
    feedback: Optional[str] = Field(None, description="Feedback for step revision if rejected")
    input_values: Dict[str, Any] = Field(default_factory=dict, description="User-provided input values")
    auth: Dict[str, Any] = Field(default_factory=dict, description="Auth tokens")


class GoalEvaluationResult(BaseModel):
    """Result from evaluating a goal"""
    completed: bool = Field(..., description="Whether the goal objective was met")
    reasoning: str = Field(..., description="Explanation of the evaluation")
    strategy: str = Field(..., description="complete, retry_steps, or abort_goal")
    suggested_next_steps: Optional[str] = Field(None, description="Suggestion for retry if incomplete")


class FinalEvaluationResult(BaseModel):
    """Result from evaluating if the user query is resolved"""
    query_resolved: bool = Field(..., description="Whether the user's original query is fully resolved")
    reasoning: str = Field(..., description="Explanation of the evaluation")
    strategy: str = Field(..., description="complete, add_goals, or add_steps_to_goal")
    suggested_additions: Optional[str] = Field(None, description="Suggestion for plan extension if not resolved")


class GoalEvent(BaseModel):
    """Event emitted during goal execution"""
    event_type: str = Field(..., description="Type of event (goal_plan_created, steps_planned, etc.)")
    data: Dict[str, Any] = Field(default_factory=dict, description="Event data")
    goal_id: Optional[str] = Field(None, description="Goal ID if event is goal-specific")
    timestamp: datetime = Field(default_factory=datetime.now)


class ObservationResult(BaseModel):
    """Result from executing a skill – carries DataPacket + explicit view."""
    success: bool
    view: str = Field(default="error", description="text | table | json | error")
    data: Optional[DataPacket] = None
    context_updates: Dict[str, Any] = Field(default_factory=dict)
    error: Optional[str] = None
    summary: str = Field(default="")


# =============================================================================
# Plugin Models
# =============================================================================

# Skill executor: (params_dict, auth_dict) -> DataPacket
SkillExecutorFn = Callable[[Dict[str, Any], Dict[str, Any]], Awaitable[DataPacket]]


class AuthStrategy(BaseModel):
    """Authentication strategy"""
    type: str
    context_key: str
    description: Optional[str] = None
    # OAuth-specific fields
    oauth_provider: Optional[str] = None  # "google", "github", etc.
    oauth_scopes: Optional[List[str]] = None


class AuthRequirement(BaseModel):
    """Authentication requirement for a plugin"""
    auth_id: str
    description: str
    strategies: List[AuthStrategy]


class Skill(BaseModel):
    """Skill definition"""
    model_config = ConfigDict(arbitrary_types_allowed=True)

    skill_id: str
    name: str
    description: str
    input_schema: Dict[str, Any]
    output_type: str = Field(default="text", description="text | table | json | error")
    execution_type: str = Field(default="sdk")
    execute: SkillExecutorFn = Field(exclude=True)
    domains: List[str]
    verbs: List[str]
    nouns: List[str]
    output_types: List[str]
    output_schema: Dict[str, Any] = Field(default_factory=dict)
    plugin_id: Optional[str] = Field(None)


class SkillMetadata(BaseModel):
    """Lightweight skill metadata for discovery and lookup (no execute fn)"""
    skill_id: str
    plugin_id: str
    name: str
    description: str
    domains: List[str]
    verbs: List[str]
    nouns: List[str]
    output_types: List[str]
    output_type: str = Field(default="text", description="text | table | json | error")
    input_schema: Dict[str, Any] = Field(default_factory=dict)
    output_schema: Dict[str, Any] = Field(default_factory=dict)


class SkillCandidate(BaseModel):
    """Scored skill candidate from registry lookup"""
    skill: SkillMetadata
    score: float
    match_reasons: List[str] = Field(default_factory=list)


class Plugin(BaseModel):
    """Plugin definition"""
    plugin_id: str
    name: str
    version: str
    description: str
    auth_requirements: List[AuthRequirement] = Field(default_factory=list)
    skills: List[Skill]
