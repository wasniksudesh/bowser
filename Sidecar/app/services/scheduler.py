"""
Widget Scheduler - asyncio background task for running scheduled widgets
Checks every hour, triggers daily widgets once per day
"""

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any, Callable, Dict, Optional

from app.models.widget_schemas import ScheduledWidget
from app.services.artifact_store import ArtifactStore
from app.services.widget_store import WidgetStore
from app.services.output_consolidator import OutputConsolidator

logger = logging.getLogger(__name__)

CHECK_INTERVAL = 3600  # 1 hour


class WidgetScheduler:
    def __init__(
        self,
        widget_store: WidgetStore,
        artifact_store: ArtifactStore,
    ):
        self.widget_store = widget_store
        self.artifact_store = artifact_store
        self.consolidator = OutputConsolidator()
        self._task: Optional[asyncio.Task] = None
        self._running = False

    def start(self) -> None:
        if self._task is None or self._task.done():
            self._running = True
            self._task = asyncio.create_task(self._run_loop())
            logger.info("WidgetScheduler started")

    def stop(self) -> None:
        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
            logger.info("WidgetScheduler stopped")

    async def _run_loop(self) -> None:
        while self._running:
            try:
                await self._check_and_run()
            except Exception as e:
                logger.error(f"Scheduler loop error: {e}", exc_info=True)
            await asyncio.sleep(CHECK_INTERVAL)

    async def _check_and_run(self) -> None:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        widgets = self.widget_store.list_enabled()

        for widget in widgets:
            if widget.schedule.last_run_date == today:
                continue

            if widget.schedule.frequency == "daily":
                logger.info(f"Running scheduled widget {widget.widget_id}")
                try:
                    await self._execute_widget(widget, today)
                    self.widget_store.update_last_run(widget.widget_id, today)
                except Exception as e:
                    logger.error(f"Failed to execute widget {widget.widget_id}: {e}", exc_info=True)

    async def _execute_widget(self, widget: ScheduledWidget, date_str: str) -> None:
        from app.services.goal_executor import GoalExecutionLoop
        from app.services.agent_service import ContextAgent
        from app.models.agent_schemas import ContextArtifactModel
        import uuid

        definition = widget.agent_definition
        goal_executor = GoalExecutionLoop()

        collected_outputs: Dict[str, Any] = {}

        def auto_event_callback(event):
            if event.event_type == "step_result":
                step_id = event.data.get("step_id", "")
                output = event.data.get("output")
                if output:
                    collected_outputs[step_id] = output
            elif event.event_type == "goal_completed":
                goal_data = event.data.get("goal", {})
                step_outputs = goal_data.get("step_outputs", {})
                for k, v in step_outputs.items():
                    collected_outputs[k] = v

        # Auto-approve: the approval_event fires immediately so the loop
        # never blocks waiting for user input.
        approval_event = asyncio.Event()
        approval_event.set()

        def auto_approve_decision() -> Optional[Dict[str, Any]]:
            return {"approved": True}

        context_agent = ContextAgent()
        context = context_agent.create_context_artifact(
            values={}, auth={}, required_fields=[]
        )

        session_id = f"sched-{widget.widget_id}-{uuid.uuid4().hex[:6]}"

        result = await goal_executor.run(
            session_id=session_id,
            query=definition.query,
            goal_plan=definition.goal_plan,
            context=context,
            event_callback=auto_event_callback,
            approval_event=approval_event,
            get_decision=auto_approve_decision,
            timeout_seconds=300
        )

        if result.get("status") == "complete" and collected_outputs:
            consolidated = await self.consolidator.consolidate(
                query=definition.query,
                goal_outputs=collected_outputs,
                hint_component=definition.output_component_type
            )

            self.artifact_store.append_entry(
                artifact_id=widget.artifact_id,
                date_str=date_str,
                data=consolidated.component_data
            )

            logger.info(f"Widget {widget.widget_id} run complete, output stored for {date_str}")
        else:
            logger.warning(f"Widget {widget.widget_id} run did not complete successfully: {result.get('status')}")

    async def trigger_now(self, widget_id: str) -> bool:
        widget = self.widget_store.get(widget_id)
        if not widget:
            return False

        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        try:
            await self._execute_widget(widget, today)
            self.widget_store.update_last_run(widget_id, today)
            return True
        except Exception as e:
            logger.error(f"Manual trigger failed for {widget_id}: {e}", exc_info=True)
            return False
