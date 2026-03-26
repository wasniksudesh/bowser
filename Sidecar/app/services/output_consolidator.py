"""
Output Consolidator - Converts agent step outputs into a single UIComponentType
After all goals complete, picks the best UIComponentType and formats
the combined data to match that component's JSON schema.
"""

import json
import logging
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from app.services.ai_agent import get_ai_agent

logger = logging.getLogger(__name__)


COMPONENT_METADATA = [
    {
        "type": "carousel",
        "displayName": "Product/Image Carousel",
        "description": "Cards with image or webpage preview, title, and description. Supports a direct image URL or falls back to an iframe of the product page URL. Best for products, startups, or visual content.",
        "requiredFields": ["title"],
        "optionalFields": ["url", "description", "image"],
        "dataShape": "array of {title, url?, description?, image?}",
        "sizeHint": "large"
    },
    {
        "type": "spotList",
        "displayName": "Spot List",
        "description": "Vertical list of items with names and descriptions. Best for lists of named things.",
        "requiredFields": ["name", "description"],
        "optionalFields": ["url"],
        "dataShape": "{spots: [{name, description, url?}]}",
        "sizeHint": "medium"
    },
    {
        "type": "destinationCard",
        "displayName": "Destination Card",
        "description": "Compact card with title, subtitle, badge. Best for a single item highlight.",
        "requiredFields": ["title", "subtitle", "badge"],
        "optionalFields": ["badgeLabel"],
        "dataShape": "{title, subtitle, badge, badgeLabel?}",
        "sizeHint": "small"
    },
    {
        "type": "highlightsTab",
        "displayName": "Highlights Tabs",
        "description": "Tabbed interface for categorized content. Best for comparing categories.",
        "requiredFields": ["tabs"],
        "optionalFields": [],
        "dataShape": "{tabs: [{id, title, description, spots: [{id, name, description}]}]}",
        "sizeHint": "large"
    },
    {
        "type": "table",
        "displayName": "Data Table",
        "description": "Sortable table with columns and rows. Best for structured tabular data.",
        "requiredFields": ["columns", "rows"],
        "optionalFields": [],
        "dataShape": "{columns: [{key, label}], rows: [[string]]}",
        "sizeHint": "medium"
    },
    {
        "type": "chart",
        "displayName": "Chart",
        "description": "Bar/line/pie chart. Best for numeric trends and comparisons.",
        "requiredFields": ["chartType", "labels", "datasets"],
        "optionalFields": [],
        "dataShape": "{chartType: 'bar'|'line'|'pie', labels: [string], datasets: [{label, values: [number]}]}",
        "sizeHint": "medium"
    },
    {
        "type": "textBlock",
        "displayName": "Text Block",
        "description": "Rich text display. Best for summaries, descriptions, code.",
        "requiredFields": ["content"],
        "optionalFields": ["format"],
        "dataShape": "{content: string, format: 'plain'|'markdown'|'code'}",
        "sizeHint": "auto"
    },
    {
        "type": "list",
        "displayName": "List",
        "description": "Simple bullet list or key-value pairs. Best for properties or enumerated items.",
        "requiredFields": ["items"],
        "optionalFields": [],
        "dataShape": "{items: [{label, value?}]}",
        "sizeHint": "small"
    }
]


class ConsolidatedOutput(BaseModel):
    """Result of consolidating agent step outputs into a UIComponent."""
    component_type: str = Field(..., description="UIComponentType value (e.g. 'carousel')")
    component_data: Any = Field(..., description="Data shaped to match the component's JSON schema")
    summary: str = Field(default="", description="Brief text summary of the output")


class OutputConsolidator:
    """
    Consolidates raw agent step outputs into a single UIComponentType.
    Uses the LLM to pick the best component and format the data.
    """

    async def consolidate(
        self,
        query: str,
        goal_outputs: Dict[str, Any],
        hint_component: Optional[str] = None,
        field_mapping: Optional[Dict[str, str]] = None
    ) -> ConsolidatedOutput:
        # Deterministic fast path: skill declared both a target component and a field mapping
        if hint_component and field_mapping is not None:
            try:
                return self._mapped_consolidate(goal_outputs, hint_component, field_mapping)
            except Exception as e:
                logger.warning(f"Mapped consolidation failed, falling back to LLM: {e}")

        try:
            return await self._llm_consolidate(query, goal_outputs, hint_component)
        except Exception as e:
            logger.error(f"LLM consolidation failed, falling back to heuristic: {e}")
            return self._heuristic_consolidate(query, goal_outputs)

    def _mapped_consolidate(
        self,
        goal_outputs: Dict[str, Any],
        component_type: str,
        field_mapping: Dict[str, str]
    ) -> ConsolidatedOutput:
        """Deterministic consolidation using an explicit skill field mapping."""
        all_rows: List[Dict[str, Any]] = []
        for key, value in goal_outputs.items():
            # Prefer raw rows stored by _create_observation (keyed with ._rows suffix)
            if key.endswith("._rows") and isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        all_rows.append(item)
            elif isinstance(value, dict) and "rows" in value:
                all_rows.extend(value.get("rows", []))
            elif isinstance(value, list) and not key.endswith(".count"):
                for item in value:
                    if isinstance(item, dict):
                        all_rows.append(item)

        mapped_rows = [self._apply_field_mapping(row, field_mapping) for row in all_rows]
        return ConsolidatedOutput(
            component_type=component_type,
            component_data=mapped_rows,
            summary=f"Showing {len(mapped_rows)} items"
        )

    @staticmethod
    def _apply_field_mapping(row: Dict[str, Any], mapping: Dict[str, str]) -> Dict[str, Any]:
        """Transform a single row using {component_field: skill_field} mapping."""
        return {comp_field: row.get(skill_field, "") for comp_field, skill_field in mapping.items()}

    async def _llm_consolidate(
        self,
        query: str,
        goal_outputs: Dict[str, Any],
        hint_component: Optional[str] = None
    ) -> ConsolidatedOutput:
        ai_agent = await get_ai_agent()

        outputs_summary = self._summarize_outputs(goal_outputs)
        components_desc = json.dumps(COMPONENT_METADATA, indent=2)

        hint_str = ""
        if hint_component:
            hint_str = f"\nThe user has hinted they prefer the '{hint_component}' component type. Use it if the data is compatible."

        prompt = f"""You are a UI component selector. Given the user's query and the agent's outputs, 
pick the single best UIComponentType and format ALL the output data to match that component's schema exactly.

## User Query
{query}

## Agent Outputs
{outputs_summary}

## Available Components
{components_desc}
{hint_str}

## Instructions
1. Pick the ONE component type that best displays this data
2. Transform the agent outputs into the exact data shape required by that component
3. Return valid JSON with this exact structure:
{{
  "component_type": "<type>",
  "component_data": <data matching the component schema>,
  "summary": "<1-2 sentence summary>"
}}

IMPORTANT: Return ONLY valid JSON, no markdown fences."""

        result = await ai_agent.execute_task(
            prompt,
            context={"mode": "json_mode"},
            use_tools=False
        )

        result_text = result if isinstance(result, str) else str(result)
        result_text = result_text.strip()
        if result_text.startswith("```"):
            lines = result_text.split("\n")
            lines = [l for l in lines if not l.strip().startswith("```")]
            result_text = "\n".join(lines)

        parsed = json.loads(result_text)

        return ConsolidatedOutput(
            component_type=parsed.get("component_type", "textBlock"),
            component_data=parsed.get("component_data", {"content": result_text, "format": "plain"}),
            summary=parsed.get("summary", "")
        )

    def _summarize_outputs(self, goal_outputs: Dict[str, Any]) -> str:
        parts = []
        for key, value in goal_outputs.items():
            # Skip internal raw-rows keys — they are summarised via the ._rows entry
            if key.endswith(".count"):
                continue
            if key.endswith("._rows") and isinstance(value, list):
                parts.append(f"Output rows ({len(value)} items):")
                if value:
                    parts.append(f"  Sample row: {json.dumps(value[0], default=str)[:500]}")
                    if len(value) > 1:
                        parts.append(f"  ... and {len(value) - 1} more rows")
            elif isinstance(value, dict) and "rows" in value:
                rows = value["rows"]
                parts.append(f"Output '{key}': {len(rows)} rows")
                if rows:
                    parts.append(f"  Sample row: {json.dumps(rows[0], default=str)[:500]}")
                    if len(rows) > 1:
                        parts.append(f"  ... and {len(rows) - 1} more rows")
            elif isinstance(value, list):
                parts.append(f"Output '{key}': list with {len(value)} items")
                if value:
                    parts.append(f"  Sample: {json.dumps(value[0], default=str)[:500]}")
            elif isinstance(value, str):
                # Skip individual flattened field values — they're noise when ._rows is present
                if "._rows" not in key and not any(k.endswith("._rows") for k in goal_outputs):
                    parts.append(f"Output '{key}': {value[:500]}")
            else:
                parts.append(f"Output '{key}': {json.dumps(value, default=str)[:500]}")
        return "\n".join(parts) if parts else "No outputs available"

    def _heuristic_consolidate(
        self,
        query: str,
        goal_outputs: Dict[str, Any]
    ) -> ConsolidatedOutput:
        all_rows: List[Dict[str, Any]] = []
        for key, value in goal_outputs.items():
            # Prefer raw rows stored by _create_observation (keyed with ._rows suffix)
            if key.endswith("._rows") and isinstance(value, list):
                for item in value:
                    if isinstance(item, dict):
                        all_rows.append(item)
            elif isinstance(value, dict) and "rows" in value:
                all_rows.extend(value.get("rows", []))
            elif isinstance(value, list) and not key.endswith(".count"):
                for item in value:
                    if isinstance(item, dict):
                        all_rows.append(item)

        if all_rows:
            sample = all_rows[0]
            has_image = any(k in sample for k in ("image", "url", "image_url", "photo"))
            has_name = any(k in sample for k in ("name", "title"))
            has_description = any(k in sample for k in ("description", "desc", "summary"))

            if has_image and has_name:
                carousel_data = []
                for row in all_rows:
                    image = row.get("image") or row.get("image_url") or row.get("photo") or ""
                    title = row.get("title") or row.get("name", "")
                    url = row.get("url", "")
                    desc = row.get("description") or row.get("desc") or row.get("summary") or ""
                    carousel_data.append({
                        "title": title,
                        "image": image,
                        "url": url,
                        "description": desc,
                    })
                return ConsolidatedOutput(
                    component_type="carousel",
                    component_data=carousel_data,
                    summary=f"Showing {len(carousel_data)} items as carousel"
                )

            if has_name and has_description:
                spots = [{"name": r.get("title") or r.get("name", ""), "description": r.get("description") or r.get("desc", "")} for r in all_rows]
                return ConsolidatedOutput(
                    component_type="spotList",
                    component_data={"spots": spots},
                    summary=f"Showing {len(spots)} items"
                )

            keys = list(sample.keys())
            columns = [{"key": k, "label": k.replace("_", " ").title()} for k in keys]
            rows = [[str(row.get(k, "")) for k in keys] for row in all_rows]
            return ConsolidatedOutput(
                component_type="table",
                component_data={"columns": columns, "rows": rows},
                summary=f"Showing {len(rows)} rows in table"
            )

        all_text = ""
        for value in goal_outputs.values():
            if isinstance(value, str):
                all_text += value + "\n"
            elif isinstance(value, dict) and "text" in value:
                all_text += value["text"] + "\n"

        if all_text.strip():
            return ConsolidatedOutput(
                component_type="textBlock",
                component_data={"content": all_text.strip(), "format": "markdown"},
                summary="Text output from agent"
            )

        return ConsolidatedOutput(
            component_type="textBlock",
            component_data={"content": "Agent completed with no displayable output.", "format": "plain"},
            summary="No output"
        )
