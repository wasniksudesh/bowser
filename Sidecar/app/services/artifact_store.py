"""
Artifact Store - Date-segmented JSON artifact persistence
Each widget has one artifact file. Daily runs append a new date entry.
"""

import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from app.models.widget_schemas import ArtifactDocument, ArtifactEntry

logger = logging.getLogger(__name__)

ARTIFACT_DIR = Path.home() / ".bowser" / "artifacts"


class ArtifactStore:
    def __init__(self, base_dir: Optional[Path] = None):
        self.base_dir = base_dir or ARTIFACT_DIR
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def _path(self, artifact_id: str) -> Path:
        return self.base_dir / f"{artifact_id}.json"

    def create(self, artifact_id: str, widget_id: str, component_type: str) -> ArtifactDocument:
        doc = ArtifactDocument(
            artifact_id=artifact_id,
            widget_id=widget_id,
            component_type=component_type
        )
        self._save(doc)
        return doc

    def get(self, artifact_id: str) -> Optional[ArtifactDocument]:
        path = self._path(artifact_id)
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text())
            return ArtifactDocument.model_validate(data)
        except Exception as e:
            logger.error(f"Failed to load artifact {artifact_id}: {e}")
            return None

    def append_entry(
        self,
        artifact_id: str,
        date_str: str,
        data: Any,
    ) -> bool:
        """
        Append (or replace) data for a specific date.
        Returns True if new entry was added, False if date already existed.
        """
        doc = self.get(artifact_id)
        if not doc:
            logger.error(f"Artifact {artifact_id} not found")
            return False

        existing_dates = {e.date for e in doc.entries}
        if date_str in existing_dates:
            for entry in doc.entries:
                if entry.date == date_str:
                    entry.data = data
                    break
            logger.info(f"Updated existing entry for {date_str} in artifact {artifact_id}")
        else:
            doc.entries.append(ArtifactEntry(date=date_str, data=data))
            logger.info(f"Appended new entry for {date_str} to artifact {artifact_id}")

        doc.unread = True
        self._save(doc)
        return date_str not in existing_dates

    def mark_read(self, artifact_id: str) -> None:
        doc = self.get(artifact_id)
        if doc:
            doc.unread = False
            self._save(doc)

    def is_unread(self, artifact_id: str) -> bool:
        doc = self.get(artifact_id)
        return doc.unread if doc else False

    def get_entry_dates(self, artifact_id: str) -> List[str]:
        doc = self.get(artifact_id)
        return [e.date for e in doc.entries] if doc else []

    def get_entry(self, artifact_id: str, date_str: str) -> Optional[ArtifactEntry]:
        doc = self.get(artifact_id)
        if not doc:
            return None
        for entry in doc.entries:
            if entry.date == date_str:
                return entry
        return None

    def get_latest_entry(self, artifact_id: str) -> Optional[ArtifactEntry]:
        doc = self.get(artifact_id)
        if not doc or not doc.entries:
            return None
        return doc.entries[-1]

    def delete(self, artifact_id: str) -> bool:
        path = self._path(artifact_id)
        if path.exists():
            path.unlink()
            return True
        return False

    def _save(self, doc: ArtifactDocument) -> None:
        path = self._path(doc.artifact_id)
        path.write_text(doc.model_dump_json(indent=2))
