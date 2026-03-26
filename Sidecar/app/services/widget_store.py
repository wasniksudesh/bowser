"""
Widget Store - CRUD for ScheduledWidget persistence
"""

import json
import logging
from pathlib import Path
from typing import Dict, List, Optional

from app.models.widget_schemas import ScheduledWidget

logger = logging.getLogger(__name__)

WIDGET_DIR = Path.home() / ".bowser" / "widgets"


class WidgetStore:
    def __init__(self, base_dir: Optional[Path] = None):
        self.base_dir = base_dir or WIDGET_DIR
        self.base_dir.mkdir(parents=True, exist_ok=True)
        self._cache: Dict[str, ScheduledWidget] = {}
        self._load_all()

    def _path(self, widget_id: str) -> Path:
        return self.base_dir / f"{widget_id}.json"

    def _load_all(self) -> None:
        for path in self.base_dir.glob("*.json"):
            try:
                data = json.loads(path.read_text())
                widget = ScheduledWidget.model_validate(data)
                self._cache[widget.widget_id] = widget
            except Exception as e:
                logger.error(f"Failed to load widget from {path}: {e}")

    def save(self, widget: ScheduledWidget) -> None:
        self._cache[widget.widget_id] = widget
        path = self._path(widget.widget_id)
        path.write_text(widget.model_dump_json(indent=2))

    def get(self, widget_id: str) -> Optional[ScheduledWidget]:
        return self._cache.get(widget_id)

    def list_all(self) -> List[ScheduledWidget]:
        return list(self._cache.values())

    def list_enabled(self) -> List[ScheduledWidget]:
        return [w for w in self._cache.values() if w.schedule.enabled]

    def delete(self, widget_id: str) -> bool:
        if widget_id in self._cache:
            del self._cache[widget_id]
            path = self._path(widget_id)
            if path.exists():
                path.unlink()
            return True
        return False

    def update_last_run(self, widget_id: str, date_str: str) -> None:
        widget = self._cache.get(widget_id)
        if widget:
            widget.schedule.last_run_date = date_str
            self.save(widget)
