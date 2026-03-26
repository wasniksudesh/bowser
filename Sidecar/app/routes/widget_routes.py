"""
Widget Routes - API endpoints for scheduled widgets and artifacts
"""

import uuid
import logging
from typing import Optional

from fastapi import APIRouter, HTTPException

from app.models.widget_schemas import (
    CreateWidgetRequest,
    CreateWidgetResponse,
    WidgetListItem,
    AgentDefinitionModel,
    ScheduleConfig,
    ScheduledWidget,
    ConsolidatedOutputModel,
)
from app.models.agent_schemas import GoalPlanModel
from app.services.widget_store import WidgetStore
from app.services.artifact_store import ArtifactStore
from app.services.scheduler import WidgetScheduler

logger = logging.getLogger(__name__)

router = APIRouter()

_widget_store: Optional[WidgetStore] = None
_artifact_store: Optional[ArtifactStore] = None
_scheduler: Optional[WidgetScheduler] = None


def init_widget_services():
    """Initialize widget services. Called from main.py lifespan."""
    global _widget_store, _artifact_store, _scheduler
    _widget_store = WidgetStore()
    _artifact_store = ArtifactStore()
    _scheduler = WidgetScheduler(_widget_store, _artifact_store)
    _scheduler.start()
    return _widget_store, _artifact_store, _scheduler


def shutdown_widget_services():
    global _scheduler
    if _scheduler:
        _scheduler.stop()


@router.post("/create", response_model=CreateWidgetResponse)
async def create_widget(request: CreateWidgetRequest):
    if not _widget_store or not _artifact_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget_id = f"w-{uuid.uuid4().hex[:8]}"
    artifact_id = f"a-{uuid.uuid4().hex[:8]}"

    try:
        goal_plan = GoalPlanModel.model_validate(request.goal_plan)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid goal_plan: {e}")

    definition = AgentDefinitionModel(
        definition_id=request.definition_id,
        query=request.query,
        goal_plan=goal_plan,
        output_component_type=request.output_component_type,
        folder_id=request.folder_id,
    )

    widget = ScheduledWidget(
        widget_id=widget_id,
        agent_definition=definition,
        schedule=ScheduleConfig(frequency=request.frequency),
        artifact_id=artifact_id,
    )

    _artifact_store.create(artifact_id, widget_id, request.output_component_type)
    _widget_store.save(widget)

    logger.info(f"Created widget {widget_id} with artifact {artifact_id}")
    return CreateWidgetResponse(
        widget_id=widget_id,
        artifact_id=artifact_id,
        message=f"Widget created. Scheduled {request.frequency}."
    )


@router.get("/list")
async def list_widgets():
    if not _widget_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widgets = _widget_store.list_all()
    return [
        WidgetListItem(
            widget_id=w.widget_id,
            query=w.agent_definition.query,
            output_component_type=w.agent_definition.output_component_type,
            frequency=w.schedule.frequency,
            last_run_date=w.schedule.last_run_date,
            folder_id=w.agent_definition.folder_id,
            created_at=w.created_at,
        )
        for w in widgets
    ]


@router.get("/{widget_id}")
async def get_widget(widget_id: str):
    if not _widget_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget = _widget_store.get(widget_id)
    if not widget:
        raise HTTPException(status_code=404, detail="Widget not found")
    return widget.model_dump()


@router.delete("/{widget_id}")
async def delete_widget(widget_id: str):
    if not _widget_store or not _artifact_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget = _widget_store.get(widget_id)
    if not widget:
        raise HTTPException(status_code=404, detail="Widget not found")

    _artifact_store.delete(widget.artifact_id)
    _widget_store.delete(widget_id)
    return {"deleted": True}


@router.post("/{widget_id}/trigger")
async def trigger_widget(widget_id: str):
    if not _scheduler:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    success = await _scheduler.trigger_now(widget_id)
    if not success:
        raise HTTPException(status_code=404, detail="Widget not found or trigger failed")
    return {"triggered": True, "widget_id": widget_id}


@router.get("/{widget_id}/artifact")
async def get_artifact(widget_id: str):
    if not _widget_store or not _artifact_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget = _widget_store.get(widget_id)
    if not widget:
        raise HTTPException(status_code=404, detail="Widget not found")

    doc = _artifact_store.get(widget.artifact_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Artifact not found")

    return doc.model_dump()


@router.get("/{widget_id}/artifact/latest")
async def get_latest_artifact_entry(widget_id: str):
    if not _widget_store or not _artifact_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget = _widget_store.get(widget_id)
    if not widget:
        raise HTTPException(status_code=404, detail="Widget not found")

    entry = _artifact_store.get_latest_entry(widget.artifact_id)
    if not entry:
        raise HTTPException(status_code=404, detail="No artifact entries yet")

    return {
        "component_type": widget.agent_definition.output_component_type,
        "entry": entry.model_dump()
    }


@router.post("/{widget_id}/artifact/mark-read")
async def mark_artifact_read(widget_id: str):
    if not _widget_store or not _artifact_store:
        raise HTTPException(status_code=503, detail="Widget services not initialized")

    widget = _widget_store.get(widget_id)
    if not widget:
        raise HTTPException(status_code=404, detail="Widget not found")

    _artifact_store.mark_read(widget.artifact_id)
    return {"marked_read": True}
