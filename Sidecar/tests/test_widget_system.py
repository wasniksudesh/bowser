"""
Tests: Widget System (ArtifactStore, WidgetStore, OutputConsolidator heuristics, Widget API routes)

High-signal tests covering the critical data paths:
  1. ArtifactStore: create, append, dedup, mark-read, latest/full retrieval
  2. WidgetStore: save, get, list, delete, update_last_run, enabled filtering
  3. OutputConsolidator: heuristic fallback for carousel, spotList, table, textBlock
  4. Widget routes: create, list, get, delete (via ASGI test client)
"""

import json
import uuid
import pytest
from pathlib import Path

from app.models.widget_schemas import (
    ArtifactDocument,
    ArtifactEntry,
    ScheduledWidget,
    ScheduleConfig,
    AgentDefinitionModel,
)
from app.models.agent_schemas import GoalPlanModel, GoalModel, GoalStatus
from app.services.artifact_store import ArtifactStore
from app.services.widget_store import WidgetStore
from app.services.output_consolidator import OutputConsolidator, ConsolidatedOutput


# =============================================================================
# Helpers
# =============================================================================

def _make_goal_plan() -> GoalPlanModel:
    return GoalPlanModel(
        plan_id="plan-test",
        goals=[
            GoalModel(
                goal_id="G-0",
                description="Test goal",
                plugin_id="hackernews",
                status=GoalStatus.COMPLETED,
            )
        ],
        status="completed",
    )


def _make_widget(widget_id: str = "w-test1", artifact_id: str = "a-test1") -> ScheduledWidget:
    return ScheduledWidget(
        widget_id=widget_id,
        agent_definition=AgentDefinitionModel(
            definition_id="def-1",
            query="Show HN launches",
            goal_plan=_make_goal_plan(),
            output_component_type="carousel",
        ),
        schedule=ScheduleConfig(frequency="daily", enabled=True),
        artifact_id=artifact_id,
    )


# =============================================================================
# ArtifactStore Tests
# =============================================================================

class TestArtifactStore:

    def test_create_and_get(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        doc = store.create("a-1", "w-1", "carousel")

        assert doc.artifact_id == "a-1"
        assert doc.widget_id == "w-1"
        assert doc.component_type == "carousel"
        assert doc.entries == []
        assert (tmp_path / "a-1.json").exists()

        loaded = store.get("a-1")
        assert loaded is not None
        assert loaded.artifact_id == "a-1"

    def test_get_nonexistent_returns_none(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        assert store.get("nonexistent") is None

    def test_append_entry_new_date(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "carousel")

        is_new = store.append_entry("a-1", "2026-03-24", [{"url": "img1.jpg", "caption": "Launch A"}])
        assert is_new is True

        doc = store.get("a-1")
        assert len(doc.entries) == 1
        assert doc.entries[0].date == "2026-03-24"
        assert doc.unread is True

    def test_append_entry_duplicate_date_replaces(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "carousel")

        store.append_entry("a-1", "2026-03-24", [{"url": "old.jpg"}])
        is_new = store.append_entry("a-1", "2026-03-24", [{"url": "new.jpg"}])

        assert is_new is False
        doc = store.get("a-1")
        assert len(doc.entries) == 1
        assert doc.entries[0].data == [{"url": "new.jpg"}]

    def test_multiple_dates_preserved(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "table")

        store.append_entry("a-1", "2026-03-22", {"columns": [], "rows": [["a"]]})
        store.append_entry("a-1", "2026-03-23", {"columns": [], "rows": [["b"]]})
        store.append_entry("a-1", "2026-03-24", {"columns": [], "rows": [["c"]]})

        doc = store.get("a-1")
        assert len(doc.entries) == 3
        dates = [e.date for e in doc.entries]
        assert dates == ["2026-03-22", "2026-03-23", "2026-03-24"]

    def test_get_latest_entry(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "carousel")
        store.append_entry("a-1", "2026-03-23", {"old": True})
        store.append_entry("a-1", "2026-03-24", {"new": True})

        latest = store.get_latest_entry("a-1")
        assert latest is not None
        assert latest.date == "2026-03-24"
        assert latest.data == {"new": True}

    def test_mark_read(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "carousel")
        store.append_entry("a-1", "2026-03-24", {"data": True})

        assert store.is_unread("a-1") is True
        store.mark_read("a-1")
        assert store.is_unread("a-1") is False

    def test_delete(self, tmp_path: Path):
        store = ArtifactStore(base_dir=tmp_path)
        store.create("a-1", "w-1", "carousel")
        assert store.delete("a-1") is True
        assert store.get("a-1") is None
        assert store.delete("a-1") is False


# =============================================================================
# WidgetStore Tests
# =============================================================================

class TestWidgetStore:

    def test_save_and_get(self, tmp_path: Path):
        store = WidgetStore(base_dir=tmp_path)
        widget = _make_widget("w-1")
        store.save(widget)

        loaded = store.get("w-1")
        assert loaded is not None
        assert loaded.widget_id == "w-1"
        assert loaded.agent_definition.query == "Show HN launches"

    def test_list_all(self, tmp_path: Path):
        store = WidgetStore(base_dir=tmp_path)
        store.save(_make_widget("w-1", "a-1"))
        store.save(_make_widget("w-2", "a-2"))

        all_widgets = store.list_all()
        assert len(all_widgets) == 2
        ids = {w.widget_id for w in all_widgets}
        assert ids == {"w-1", "w-2"}

    def test_list_enabled_filters_disabled(self, tmp_path: Path):
        store = WidgetStore(base_dir=tmp_path)

        w1 = _make_widget("w-1", "a-1")
        w2 = _make_widget("w-2", "a-2")
        w2.schedule.enabled = False

        store.save(w1)
        store.save(w2)

        enabled = store.list_enabled()
        assert len(enabled) == 1
        assert enabled[0].widget_id == "w-1"

    def test_delete(self, tmp_path: Path):
        store = WidgetStore(base_dir=tmp_path)
        store.save(_make_widget("w-1"))

        assert store.delete("w-1") is True
        assert store.get("w-1") is None
        assert store.delete("w-1") is False

    def test_update_last_run(self, tmp_path: Path):
        store = WidgetStore(base_dir=tmp_path)
        store.save(_make_widget("w-1"))

        store.update_last_run("w-1", "2026-03-24")
        widget = store.get("w-1")
        assert widget.schedule.last_run_date == "2026-03-24"

    def test_persistence_across_instances(self, tmp_path: Path):
        store1 = WidgetStore(base_dir=tmp_path)
        store1.save(_make_widget("w-1"))

        store2 = WidgetStore(base_dir=tmp_path)
        assert store2.get("w-1") is not None
        assert store2.get("w-1").widget_id == "w-1"


# =============================================================================
# OutputConsolidator Heuristic Tests
# =============================================================================

class TestOutputConsolidatorHeuristic:
    """Tests the _heuristic_consolidate fallback (no LLM needed)."""

    def setup_method(self):
        self.consolidator = OutputConsolidator()

    def test_carousel_from_image_data(self):
        outputs = {
            "G-0.products": {
                "rows": [
                    {"title": "Product A", "image": "https://img.com/a.jpg", "url": "https://a.com"},
                    {"title": "Product B", "image": "https://img.com/b.jpg", "url": "https://b.com"},
                ]
            }
        }
        result = self.consolidator._heuristic_consolidate("Show HN launches", outputs)

        assert result.component_type == "carousel"
        assert isinstance(result.component_data, list)
        assert len(result.component_data) == 2
        assert result.component_data[0]["url"] == "https://img.com/a.jpg"
        assert result.component_data[0]["caption"] == "Product A"

    def test_spotlist_from_name_description(self):
        outputs = {
            "G-0.items": {
                "rows": [
                    {"name": "Spot 1", "description": "First spot"},
                    {"name": "Spot 2", "description": "Second spot"},
                ]
            }
        }
        result = self.consolidator._heuristic_consolidate("list spots", outputs)

        assert result.component_type == "spotList"
        assert "spots" in result.component_data
        assert len(result.component_data["spots"]) == 2

    def test_table_from_generic_dicts(self):
        outputs = {
            "G-0.data": {
                "rows": [
                    {"id": "1", "status": "open", "priority": "high"},
                    {"id": "2", "status": "closed", "priority": "low"},
                ]
            }
        }
        result = self.consolidator._heuristic_consolidate("list issues", outputs)

        assert result.component_type == "table"
        assert "columns" in result.component_data
        assert "rows" in result.component_data
        assert len(result.component_data["rows"]) == 2

    def test_textblock_from_text_output(self):
        outputs = {
            "G-0.summary": "This is a summary of the analysis.",
            "G-1.detail": "More detailed text here.",
        }
        result = self.consolidator._heuristic_consolidate("summarize", outputs)

        assert result.component_type == "textBlock"
        assert "content" in result.component_data
        assert "summary" in result.component_data["content"]
        assert "detailed" in result.component_data["content"]

    def test_empty_outputs_fallback(self):
        result = self.consolidator._heuristic_consolidate("query", {})

        assert result.component_type == "textBlock"
        assert "no displayable output" in result.component_data["content"].lower()

    def test_list_input_auto_detected(self):
        outputs = {
            "G-0.items": [
                {"title": "Item A", "image": "https://a.jpg"},
                {"title": "Item B", "image": "https://b.jpg"},
            ]
        }
        result = self.consolidator._heuristic_consolidate("list products", outputs)
        # Should detect image+title -> carousel
        assert result.component_type == "carousel"


# =============================================================================
# Widget Routes Integration Tests
# =============================================================================

class TestWidgetRoutes:
    """Tests widget API routes via the ASGI test client."""

    @pytest.fixture(autouse=True)
    def setup_widget_services(self, tmp_path: Path):
        """Patch widget services to use temp directories."""
        from app.routes import widget_routes

        self._artifact_store = ArtifactStore(base_dir=tmp_path / "artifacts")
        self._widget_store = WidgetStore(base_dir=tmp_path / "widgets")

        widget_routes._widget_store = self._widget_store
        widget_routes._artifact_store = self._artifact_store
        widget_routes._scheduler = None  # skip scheduler for route tests

        yield

        widget_routes._widget_store = None
        widget_routes._artifact_store = None
        widget_routes._scheduler = None

    @pytest.mark.anyio
    async def test_create_widget(self, bare_client):
        goal_plan = {
            "plan_id": "p-1",
            "goals": [
                {
                    "goal_id": "G-0",
                    "description": "Fetch launches",
                    "plugin_id": "hackernews",
                    "status": "completed",
                }
            ],
        }

        resp = await bare_client.post("/api/widgets/create", json={
            "definition_id": "def-1",
            "query": "Show HN launches",
            "goal_plan": goal_plan,
            "output_component_type": "carousel",
            "frequency": "daily",
        })

        assert resp.status_code == 200
        data = resp.json()
        assert "widget_id" in data
        assert "artifact_id" in data
        assert data["message"].startswith("Widget created")

        # Verify stored
        widget = self._widget_store.get(data["widget_id"])
        assert widget is not None
        assert widget.agent_definition.query == "Show HN launches"

    @pytest.mark.anyio
    async def test_list_widgets(self, bare_client):
        # Create two widgets
        for i in range(2):
            await bare_client.post("/api/widgets/create", json={
                "definition_id": f"def-{i}",
                "query": f"Query {i}",
                "goal_plan": {"plan_id": f"p-{i}", "goals": []},
                "output_component_type": "table",
                "frequency": "daily",
            })

        resp = await bare_client.get("/api/widgets/list")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2

    @pytest.mark.anyio
    async def test_get_widget(self, bare_client):
        create_resp = await bare_client.post("/api/widgets/create", json={
            "definition_id": "def-1",
            "query": "Test query",
            "goal_plan": {"plan_id": "p-1", "goals": []},
            "output_component_type": "spotList",
            "frequency": "daily",
        })
        widget_id = create_resp.json()["widget_id"]

        resp = await bare_client.get(f"/api/widgets/{widget_id}")
        assert resp.status_code == 200
        assert resp.json()["widget_id"] == widget_id

    @pytest.mark.anyio
    async def test_get_nonexistent_widget_404(self, bare_client):
        resp = await bare_client.get("/api/widgets/w-nonexistent")
        assert resp.status_code == 404

    @pytest.mark.anyio
    async def test_delete_widget(self, bare_client):
        create_resp = await bare_client.post("/api/widgets/create", json={
            "definition_id": "def-1",
            "query": "To delete",
            "goal_plan": {"plan_id": "p-1", "goals": []},
            "output_component_type": "textBlock",
            "frequency": "daily",
        })
        widget_id = create_resp.json()["widget_id"]

        resp = await bare_client.delete(f"/api/widgets/{widget_id}")
        assert resp.status_code == 200
        assert resp.json()["deleted"] is True

        # Confirm gone
        resp = await bare_client.get(f"/api/widgets/{widget_id}")
        assert resp.status_code == 404

    @pytest.mark.anyio
    async def test_artifact_lifecycle(self, bare_client):
        create_resp = await bare_client.post("/api/widgets/create", json={
            "definition_id": "def-1",
            "query": "Artifact test",
            "goal_plan": {"plan_id": "p-1", "goals": []},
            "output_component_type": "carousel",
            "frequency": "daily",
        })
        widget_id = create_resp.json()["widget_id"]
        artifact_id = create_resp.json()["artifact_id"]

        # No entries yet
        resp = await bare_client.get(f"/api/widgets/{widget_id}/artifact/latest")
        assert resp.status_code == 404

        # Manually add an entry via store
        self._artifact_store.append_entry(artifact_id, "2026-03-24", [{"url": "test.jpg"}])

        resp = await bare_client.get(f"/api/widgets/{widget_id}/artifact/latest")
        assert resp.status_code == 200
        data = resp.json()
        assert data["entry"]["date"] == "2026-03-24"

        # Full artifact
        resp = await bare_client.get(f"/api/widgets/{widget_id}/artifact")
        assert resp.status_code == 200
        assert len(resp.json()["entries"]) == 1

        # Mark read
        assert self._artifact_store.is_unread(artifact_id) is True
        resp = await bare_client.post(f"/api/widgets/{widget_id}/artifact/mark-read")
        assert resp.status_code == 200
        assert self._artifact_store.is_unread(artifact_id) is False
