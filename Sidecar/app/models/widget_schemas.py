"""
Widget System Pydantic Models
Schemas for agent definitions, scheduled widgets, and artifacts
"""

from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field
from datetime import datetime

from app.models.agent_schemas import GoalPlanModel


class ConsolidatedOutputModel(BaseModel):
    """Consolidated output from an agent run, mapped to a UIComponentType."""
    component_type: str = Field(..., description="UIComponentType value (e.g. 'carousel')")
    component_data: Any = Field(..., description="Data shaped to match the component's JSON schema")
    summary: str = Field(default="", description="Brief text summary")


class AgentDefinitionModel(BaseModel):
    """Persisted agent definition for re-execution by the scheduler."""
    definition_id: str
    query: str
    goal_plan: GoalPlanModel
    output_component_type: str = Field(..., description="UIComponentType the agent produces")
    folder_id: Optional[str] = None


class ScheduleConfig(BaseModel):
    """Schedule configuration for a widget."""
    frequency: str = Field(default="daily", description="Only 'daily' supported for now")
    enabled: bool = True
    last_run_date: Optional[str] = None


class ScheduledWidget(BaseModel):
    """A widget that re-runs an agent on a schedule and stores output in an artifact."""
    widget_id: str
    agent_definition: AgentDefinitionModel
    schedule: ScheduleConfig = Field(default_factory=ScheduleConfig)
    artifact_id: str
    created_at: str = Field(default_factory=lambda: datetime.now().isoformat())


class ArtifactEntry(BaseModel):
    """Single date-segmented entry in an artifact."""
    date: str
    data: Any = Field(..., description="component_data in the UIComponent schema format")


class ArtifactDocument(BaseModel):
    """Persistent artifact file storing date-segmented agent outputs."""
    artifact_id: str
    widget_id: str
    component_type: str = Field(..., description="UIComponentType for rendering")
    entries: List[ArtifactEntry] = Field(default_factory=list)
    unread: bool = Field(default=False)


# =============================================================================
# Request / Response Models
# =============================================================================

class CreateWidgetRequest(BaseModel):
    """Request to create a scheduled widget from a completed agent session."""
    definition_id: str
    query: str
    goal_plan: Dict[str, Any]
    output_component_type: str
    folder_id: Optional[str] = None
    frequency: str = "daily"


class CreateWidgetResponse(BaseModel):
    widget_id: str
    artifact_id: str
    message: str


class WidgetListItem(BaseModel):
    widget_id: str
    query: str
    output_component_type: str
    frequency: str
    last_run_date: Optional[str] = None
    folder_id: Optional[str] = None
    created_at: str
