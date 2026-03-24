"""
Generative UI Routes

Single SSE streaming endpoint: POST /stream
- Makes one merged LLM call for all LLM-sourced components
- Dispatches API-sourced components to their resolvers concurrently
- Emits SSE events as each component resolves: plan, component_data, error, done

Separate endpoint kept: POST /resolve-spot-details (user-initiated, not part of layout stream)
"""

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from jsonschema import ValidationError as JsonSchemaValidationError
from jsonschema import validate
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter()

SCHEMAS_DIR = (
    Path(__file__).parent.parent.parent.parent
    / "Sources"
    / "Bowser"
    / "Views"
    / "UILibrary"
    / "Schemas"
)

# =============================================================================
# Pydantic Models
# =============================================================================


class ComponentPosition(BaseModel):
    row: int
    col: int


class ComponentSize(BaseModel):
    width: float = 1.0
    height: str = "auto"


class UIComponentSpec(BaseModel):
    id: str
    type: str
    position: ComponentPosition
    size: ComponentSize
    dataPrompt: str
    # Per-instance override of the registry dataSource default ("llm" | "api").
    # When the LLM plans a table backed by a real API it sets this to "api";
    # when it generates the data itself it sets or omits this (defaults to "llm").
    dataSource: Optional[str] = None


class GenerativeUILayout(BaseModel):
    components: List[UIComponentSpec]


class StreamRequest(BaseModel):
    leafContext: Dict[str, Any]
    availableComponents: List[Dict[str, Any]]


class SpotDetailRequest(BaseModel):
    spotId: str
    spotName: str
    spotDescription: str
    leafContext: Dict[str, Any]


class SpotDetailResponse(BaseModel):
    spotId: str
    data: Optional[Dict[str, Any]] = None
    success: bool = True
    error: Optional[str] = None


# =============================================================================
# Schema Registry
# =============================================================================


def load_component_schemas() -> Dict[str, Dict[str, Any]]:
    """Load all component schemas from the Schemas directory.

    Returns a dict keyed by component type with:
      - description, schema, example, promptInstructions, dataSource
    """
    schemas: Dict[str, Dict[str, Any]] = {}

    if not SCHEMAS_DIR.exists():
        logger.warning("Schemas directory not found: %s", SCHEMAS_DIR)
        return schemas

    registry_path = SCHEMAS_DIR / "registry.json"
    if not registry_path.exists():
        logger.warning("Registry not found: %s", registry_path)
        return schemas

    try:
        with open(registry_path) as f:
            registry = json.load(f)

        for component_type, metadata in registry.get("components", {}).items():
            schema_file = metadata.get("schemaFile")
            if not schema_file:
                continue

            schema_path = SCHEMAS_DIR / schema_file
            if not schema_path.exists():
                logger.warning("Schema file not found: %s", schema_path)
                continue

            with open(schema_path) as f:
                schema_data = json.load(f)

            # Prefer example from schema file; fall back to examples[0] if plural
            example = schema_data.get("example") or (
                schema_data.get("examples", [None])[0]
            )

            schemas[component_type] = {
                "description": metadata.get("description", schema_data.get("description", "")),
                "schema": schema_data,
                "example": example,
                "promptInstructions": metadata.get("promptInstructions"),
                "dataSource": metadata.get("dataSource", "llm"),
                "sizeHint": metadata.get("sizeHint", "auto"),
                "compatibleDataTypes": metadata.get("compatibleDataTypes", []),
            }
            logger.debug("Loaded schema for component: %s", component_type)

    except Exception:
        logger.exception("Error loading component schemas")

    return schemas


# Loaded once at module import time
COMPONENT_SCHEMAS: Dict[str, Dict[str, Any]] = load_component_schemas()


def validate_component_data(component_type: str, data: Any) -> tuple[bool, Optional[str]]:
    """Validate data against the component's JSON schema.

    Returns (is_valid, error_message).
    """
    if component_type not in COMPONENT_SCHEMAS:
        return False, f"Unknown component type: {component_type}"

    schema = COMPONENT_SCHEMAS[component_type]["schema"]
    try:
        validate(instance=data, schema=schema)
        return True, None
    except JsonSchemaValidationError as exc:
        msg = f"Schema validation failed: {exc.message}"
        logger.warning("Validation error for %s: %s", component_type, msg)
        return False, msg


# =============================================================================
# Prompt Construction
# =============================================================================

_STREAM_SYSTEM_PROMPT = """You are a UI layout and data assistant.
Given a topic context and available component types, you will:
1. Choose 3-4 components that best present the topic
2. Generate the actual data for each LLM-sourced component in one response

Return ONLY valid JSON — no markdown, no explanation."""


def _build_stream_prompt(
    leaf_context: Dict[str, Any],
    available_components: List[Dict[str, Any]],
) -> str:
    """Build the single merged prompt asking for layout + data for all LLM-sourced components.

    Components with dataSource "api" are listed so the LLM knows about them and can
    include them in the layout, but the LLM is told NOT to generate data for those —
    the resolver will fetch it from the real API at runtime.
    """
    leaf_title = leaf_context.get("title", "Unknown")
    leaf_desc = leaf_context.get("description", "")

    llm_components = []
    api_components = []
    for comp in available_components:
        default_source = comp.get("dataSource", "llm")
        supported = comp.get("supportedDataSources", [default_source])
        # A component is "api-capable" if it explicitly supports api and its default is api.
        # Components that support BOTH (like table/chart) are listed in both groups so the
        # LLM can choose per instance.
        if default_source == "api" and "llm" not in supported:
            api_components.append(comp)
        else:
            llm_components.append(comp)

    llm_block_parts = []
    for comp in llm_components:
        ctype = comp["type"]
        instructions = (comp.get("promptInstructions") or "").replace('"', "'")
        supported_sources = comp.get("supportedDataSources", [comp.get("dataSource", "llm")])
        example_str = json.dumps(comp.get("example"), indent=2) if comp.get("example") else "N/A"
        llm_block_parts.append(
            f'  "{ctype}": {{\n'
            f'    "description": "{comp.get("description", "")}",\n'
            f'    "supportedDataSources": {json.dumps(supported_sources)},\n'
            f'    "promptInstructions": "{instructions}",\n'
            f'    "example": {example_str}\n'
            f"  }}"
        )

    api_block_parts = []
    for comp in api_components:
        ctype = comp["type"]
        api_block_parts.append(
            f'  "{ctype}": {{"description": "{comp.get("description", "")}", "dataSource": "api"}}'
        )

    llm_components_block = "{\n" + ",\n".join(llm_block_parts) + "\n}" if llm_block_parts else "{}"
    api_note = ""
    if api_block_parts:
        api_components_block = "{\n" + ",\n".join(api_block_parts) + "\n}"
        api_note = f"""
API-SOURCED COMPONENTS (include in layout if relevant, but do NOT generate data for these — set dataSource to "api"):
{api_components_block}
"""

    return f"""TOPIC CONTEXT (ALL content must relate to this):
Title: {leaf_title}
Description: {leaf_desc}

LLM-SOURCED COMPONENTS (you generate the data for these):
{llm_components_block}
{api_note}
INSTRUCTIONS:
1. Select 3-4 components that comprehensively cover "{leaf_title}"
2. Always include carousel for visual content when relevant
3. Include at least one list-type component (spotList or highlightsTab) for detailed information
4. If the topic involves a location or destination, include a map component
5. For components that support both "llm" and "api" sources (e.g. table, chart), set
   dataSource to "api" if the data should come from a real API, or "llm" if you generate it
6. For every LLM-sourced component, generate ACTUAL DATA in componentData

Return this exact JSON structure:
{{
  "layout": {{
    "components": [
      {{
        "id": "comp1",
        "type": "<componentType>",
        "position": {{"row": 0, "col": 0}},
        "size": {{"width": 1.0, "height": "large"}},
        "dataPrompt": "<brief description of what data is included>",
        "dataSource": "llm"
      }}
    ]
  }},
  "componentData": {{
    "comp1": <actual data matching the component schema — ONLY for dataSource: "llm" components>
  }}
}}

CRITICAL RULES:
- componentData values must be ACTUAL DATA (real names, URLs, descriptions) — not schema definitions
- Only include a key in componentData for components with dataSource "llm"
- All content must be specifically about "{leaf_title}" — no unrelated topics
- Use real URLs where applicable (Google search URLs, Google Maps URLs, etc.)
- IDs must be comp1, comp2, comp3, comp4"""


# =============================================================================
# API Resolver (placeholder — wire up your metrics/database API here)
# =============================================================================


async def _resolve_from_api(
    component_type: str,
    leaf_context: Dict[str, Any],
) -> Optional[Any]:
    """Resolve data for API-sourced components.

    Replace the body of this function with your actual API call
    (e.g. metrics server, database query, etc.).
    """
    logger.info("API resolver called for component type: %s", component_type)
    # Placeholder — returns None so the component renders as loading/empty
    # until a real data source is wired up.
    return None


# =============================================================================
# JSON Parsing Helpers
# =============================================================================


def _strip_markdown_fences(content: str) -> str:
    """Remove markdown code fences if the LLM wrapped its response."""
    if "```json" in content:
        return content.split("```json")[1].split("```")[0].strip()
    if "```" in content:
        return content.split("```")[1].split("```")[0].strip()
    return content.strip()


def _is_schema_not_data(data: Any) -> bool:
    """Detect if the LLM returned a JSON schema definition instead of actual data."""
    return (
        isinstance(data, dict)
        and "properties" in data
        and any(k in data for k in ("$schema", "required", "type"))
        and not any(k in data for k in ("spots", "tabs", "items", "content", "targetURL", "title", "chartType"))
    )


# =============================================================================
# SSE Helpers
# =============================================================================


def _sse_event(event_type: str, payload: Any) -> str:
    return f"event: {event_type}\ndata: {json.dumps(payload)}\n\n"


# =============================================================================
# Streaming Endpoint
# =============================================================================


@router.post("/stream")
async def stream_layout(request: StreamRequest):
    """Single SSE endpoint that streams layout plan and component data.

    SSE event types:
      plan           — layout skeleton (component list) ready; Swift renders skeletons
      component_data — one component's data resolved; Swift renders the component
      error          — a single component failed; Swift shows error state for it
      done           — all components resolved; stream closes
    """
    logger.info("Starting generative UI stream for: %s", request.leafContext.get("title"))

    async def event_generator():
        from app.main import ai_agent

        if not ai_agent:
            yield _sse_event("error", {"message": "AI service not initialized"})
            return

        # ------------------------------------------------------------------
        # Step 1: Enrich available_components with server-side schema data
        #         (promptInstructions, examples, supportedDataSources live in
        #          COMPONENT_SCHEMAS, not in what the Swift client sends)
        # ------------------------------------------------------------------
        enriched_components = []
        for comp in request.availableComponents:
            ctype = comp.get("type", "")
            schema_info = COMPONENT_SCHEMAS.get(ctype, {})
            enriched = {**comp}
            enriched.setdefault("promptInstructions", schema_info.get("promptInstructions"))
            enriched.setdefault("supportedDataSources", [enriched.get("dataSource", "llm")])
            if not enriched.get("example"):
                enriched["example"] = schema_info.get("example")
            enriched_components.append(enriched)

        # ------------------------------------------------------------------
        # Step 2: Single merged LLM call — plan + all LLM component data
        # ------------------------------------------------------------------
        prompt = _build_stream_prompt(request.leafContext, enriched_components)
        full_prompt = f"{_STREAM_SYSTEM_PROMPT}\n\n{prompt}"

        content = ""
        try:
            result = await ai_agent.execute_task(
                task=full_prompt,
                context={"mode": "json_mode", "enable_web_search": True},
                use_tools=True,
            )
            if not result.get("success"):
                raise RuntimeError(result.get("error", "LLM call failed"))
            content = _strip_markdown_fences(result.get("output", ""))
            merged = json.loads(content)
        except json.JSONDecodeError as exc:
            logger.error("LLM returned invalid JSON: %s. Content: %.300s", exc, content)
            yield _sse_event("error", {"message": "LLM returned invalid JSON"})
            return
        except Exception as exc:
            logger.exception("LLM call failed")
            yield _sse_event("error", {"message": str(exc)})
            return

        # ------------------------------------------------------------------
        # Step 2: Parse layout and emit plan event so Swift shows skeletons
        # ------------------------------------------------------------------
        raw_layout = merged.get("layout", {})
        raw_components = raw_layout.get("components", [])
        if not raw_components:
            yield _sse_event("error", {"message": "LLM returned no components"})
            return

        components: List[UIComponentSpec] = []
        for c in raw_components:
            try:
                components.append(
                    UIComponentSpec(
                        id=c["id"],
                        type=c["type"],
                        position=ComponentPosition(**c["position"]),
                        size=ComponentSize(**c.get("size", {"width": 1.0, "height": "auto"})),
                        dataPrompt=c.get("dataPrompt", ""),
                        dataSource=c.get("dataSource"),
                    )
                )
            except Exception:
                logger.warning("Skipping malformed component spec: %s", c)

        if not components:
            yield _sse_event("error", {"message": "No valid component specs in LLM response"})
            return

        layout = GenerativeUILayout(components=components)
        yield _sse_event("plan", layout.model_dump())

        # ------------------------------------------------------------------
        # Step 3: Emit component_data events concurrently
        #   - LLM-sourced: data already in merged["componentData"]
        #   - API-sourced: fire API calls now, emit when ready
        # ------------------------------------------------------------------
        llm_data: Dict[str, Any] = merged.get("componentData", {})
        # Use a queue so we can yield from a single coroutine while tasks run
        queue: asyncio.Queue = asyncio.Queue()

        async def _process_llm_component(comp: UIComponentSpec) -> None:
            data = llm_data.get(comp.id)
            if data is None:
                await queue.put(_sse_event(
                    "error",
                    {"componentId": comp.id, "message": "LLM did not return data for this component"},
                ))
                return

            if _is_schema_not_data(data):
                logger.error("LLM returned schema instead of data for %s", comp.id)
                await queue.put(_sse_event(
                    "error",
                    {"componentId": comp.id, "message": "LLM returned a schema instead of data"},
                ))
                return

            is_valid, validation_error = validate_component_data(comp.type, data)
            if not is_valid:
                logger.error("Validation failed for %s: %s", comp.id, validation_error)
                await queue.put(_sse_event(
                    "error",
                    {"componentId": comp.id, "message": f"Data validation failed: {validation_error}"},
                ))
                return

            await queue.put(_sse_event("component_data", {"componentId": comp.id, "data": data}))

        async def _process_api_component(comp: UIComponentSpec) -> None:
            try:
                data = await _resolve_from_api(comp.type, request.leafContext)
                if data is not None:
                    is_valid, validation_error = validate_component_data(comp.type, data)
                    if is_valid:
                        await queue.put(_sse_event(
                            "component_data", {"componentId": comp.id, "data": data}
                        ))
                        return
                    logger.error("API data validation failed for %s: %s", comp.id, validation_error)
                # data is None or invalid — emit error so Swift can show empty state
                await queue.put(_sse_event(
                    "error",
                    {"componentId": comp.id, "message": "API resolver returned no data"},
                ))
            except Exception as exc:
                logger.exception("API resolver failed for %s", comp.id)
                await queue.put(_sse_event(
                    "error", {"componentId": comp.id, "message": str(exc)}
                ))

        # Launch all component tasks concurrently.
        # Per-instance dataSource (set by the LLM in the plan) takes priority over
        # the registry default, so a table can be "llm" or "api" depending on context.
        component_tasks = []
        for comp in components:
            schema_info = COMPONENT_SCHEMAS.get(comp.type, {})
            registry_default = schema_info.get("dataSource", "llm")
            effective_source = comp.dataSource or registry_default
            if effective_source == "api":
                task = asyncio.create_task(_process_api_component(comp))
            else:
                task = asyncio.create_task(_process_llm_component(comp))
            component_tasks.append(task)

        # Drain the queue as tasks complete
        remaining = len(component_tasks)
        done_tasks = 0

        async def _drain_queue():
            nonlocal done_tasks
            while done_tasks < remaining:
                try:
                    event = await asyncio.wait_for(queue.get(), timeout=60.0)
                    yield event
                    done_tasks += 1
                except asyncio.TimeoutError:
                    yield ": keepalive\n\n"

        async for event in _drain_queue():
            yield event

        # Wait for all tasks to finish cleanly
        await asyncio.gather(*component_tasks, return_exceptions=True)
        yield _sse_event("done", {})

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# =============================================================================
# Spot Detail Endpoint (user-initiated, kept separate from layout stream)
# =============================================================================


@router.post("/resolve-spot-details", response_model=SpotDetailResponse)
async def resolve_spot_details(request: SpotDetailRequest):
    """Resolve detailed information for a specific spot including images, summary, ratings, and citations."""
    logger.info("Resolving spot details for: %s", request.spotName)

    leaf_title = request.leafContext.get("title", "Unknown")
    leaf_desc = request.leafContext.get("description", "")

    prompt = f"""Generate comprehensive, enriched details for a specific spot/resource.

CRITICAL CONTEXT:
Spot Name: {request.spotName}
Spot Description: {request.spotDescription}
Topic Context: {leaf_title}
Topic Description: {leaf_desc}

Generate COMPREHENSIVE details for "{request.spotName}". Use web search to find:

1. Images (4-6 high-quality images):
   - Real image URLs showing {request.spotName}
   - Include diverse angles/perspectives
   - Add descriptive captions

2. Summary (150-250 words):
   - Rich, detailed description
   - Key features and highlights
   - What makes it special/unique
   - Practical information (when to visit, what to expect, etc.)

3. Ratings & Reviews:
   - Overall rating (0-5 scale)
   - Total review count
   - 3-5 authentic review snippets with authors

4. Citations:
   - 3-5 credible sources used to generate this information
   - Include title, URL, and which section each citation supports
   - Sources should be real, authoritative websites

REQUIRED JSON SCHEMA:
{{
  "images": [
    {{"id": "img1", "url": "https://...", "caption": "Description"}}
  ],
  "summary": "Detailed, informative summary...",
  "rating": 4.5,
  "reviewCount": 1234,
  "reviewSnippets": [
    {{"id": "rev1", "text": "Review text...", "author": "Name", "rating": 5.0}}
  ],
  "citations": [
    {{"id": "cit1", "title": "Source Title", "url": "https://...", "section": "summary"}}
  ]
}}

IMPORTANT:
- Use web search to find REAL, current information
- All URLs must be valid and accessible
- Return ONLY valid JSON matching the schema above, no markdown"""

    content = ""
    try:
        from app.main import ai_agent

        if not ai_agent:
            return SpotDetailResponse(
                spotId=request.spotId, success=False, error="AI service not initialized"
            )

        result = await ai_agent.execute_task(
            task=prompt,
            context={"mode": "json_mode", "enable_web_search": True},
            use_tools=True,
        )

        if not result.get("success"):
            raise RuntimeError(result.get("error", "LLM call failed"))

        content = _strip_markdown_fences(result.get("output", ""))
        data = json.loads(content)

        required_fields = ["images", "summary", "citations"]
        for field in required_fields:
            if field not in data:
                raise ValueError(f"Missing required field: {field}")

        return SpotDetailResponse(spotId=request.spotId, data=data, success=True)

    except json.JSONDecodeError as exc:
        logger.error("Failed to decode JSON for spot %s: %s. Content: %.200s", request.spotId, exc, content)
        return SpotDetailResponse(
            spotId=request.spotId, success=False, error="Invalid JSON response from LLM"
        )
    except Exception as exc:
        logger.exception("Spot detail resolution failed for %s", request.spotId)
        return SpotDetailResponse(spotId=request.spotId, success=False, error=str(exc))
