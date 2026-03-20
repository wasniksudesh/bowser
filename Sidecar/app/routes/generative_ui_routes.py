"""
Generative UI Routes

Purpose: API endpoints for generating UI layouts and resolving component data
for the Plan Mode leaf view (LLM-driven component selection and data).
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import logging
import json
from pathlib import Path
from jsonschema import validate, ValidationError as JsonSchemaValidationError

logger = logging.getLogger(__name__)

router = APIRouter()

# Path to UI component schemas (in Swift UILibrary)
SCHEMAS_DIR = Path(__file__).parent.parent.parent.parent / "Sources" / "Bowser" / "Views" / "UILibrary" / "Schemas"

# =============================================================================
# Models
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


class GenerativeUILayout(BaseModel):
    components: List[UIComponentSpec]


class PlanRequest(BaseModel):
    leafContext: Dict[str, Any]
    availableComponents: List[Dict[str, Any]]


class PlanResponse(BaseModel):
    layout: GenerativeUILayout


class ResolveRequest(BaseModel):
    componentId: str
    componentType: str
    dataPrompt: str
    leafContext: Dict[str, Any]


class ResolveResponse(BaseModel):
    componentId: str
    data: Optional[Any] = None
    success: bool = True
    error: Optional[str] = None


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
# Schema Loading and Management
# =============================================================================

def load_component_schemas() -> Dict[str, Dict[str, Any]]:
    """Load all component schemas from the Schemas directory."""
    schemas = {}
    
    if not SCHEMAS_DIR.exists():
        logger.warning(f"Schemas directory not found: {SCHEMAS_DIR}")
        return schemas
    
    # Load registry to get component type mappings
    registry_path = SCHEMAS_DIR / "registry.json"
    if not registry_path.exists():
        logger.warning(f"Registry not found: {registry_path}")
        return schemas
    
    try:
        with open(registry_path, 'r') as f:
            registry = json.load(f)
        
        # Load each component schema
        for component_type, metadata in registry.get("components", {}).items():
            schema_file = metadata.get("schemaFile")
            if not schema_file:
                continue
            
            schema_path = SCHEMAS_DIR / schema_file
            if not schema_path.exists():
                logger.warning(f"Schema file not found: {schema_path}")
                continue
            
            with open(schema_path, 'r') as f:
                schema_data = json.load(f)
            
            schemas[component_type] = {
                "description": schema_data.get("description", metadata.get("description", "")),
                "schema": schema_data,
                "example": schema_data.get("example")
            }
            
            logger.info(f"Loaded schema for component: {component_type}")
    
    except Exception as e:
        logger.error(f"Error loading schemas: {e}")
    
    return schemas


# Load schemas at module import time
COMPONENT_SCHEMAS = load_component_schemas()


def validate_component_data(component_type: str, data: Any) -> tuple[bool, Optional[str]]:
    """Validate data against component schema.
    
    Returns:
        (is_valid, error_message)
    """
    if component_type not in COMPONENT_SCHEMAS:
        return False, f"Unknown component type: {component_type}"
    
    schema = COMPONENT_SCHEMAS[component_type]["schema"]
    
    try:
        validate(instance=data, schema=schema)
        return True, None
    except JsonSchemaValidationError as e:
        error_msg = f"Schema validation failed: {e.message}"
        logger.warning(f"Validation error for {component_type}: {error_msg}")
        return False, error_msg

# =============================================================================
# Prompts
# =============================================================================

LAYOUT_SYSTEM_PROMPT = """You are a UI layout assistant. Given a leaf node context and available component types, choose a comprehensive layout (3-4 components) that presents MAXIMUM useful information to help users understand and explore the topic deeply.

REQUIREMENTS:
- Use 3-4 components to maximize information density
- Always include at least one visual component (carousel) for images
- Include detailed lists (spotList, highlightsTab) with comprehensive information
- Diversify component types to show different aspects of the topic
- Make the layout informative, actionable, and comprehensive

Return only valid JSON, no markdown."""

RESOLVE_SYSTEM_PROMPT = """You are a data generation assistant. Your job is to generate ACTUAL DATA VALUES (not schema definitions) for UI components. 

CRITICAL: You must return a JSON object containing real data values, NOT a schema definition. 
For example, if asked for a list of spots, return actual spot names and descriptions, not a schema describing what a spot should look like.

Return only a valid JSON data object, no markdown or explanation."""


def get_layout_prompt(leaf_context: Dict[str, Any], available_components: List[Dict[str, Any]]) -> str:
    import json as _json
    leaf_title = leaf_context.get("title", "Unknown")
    leaf_desc = leaf_context.get("description", "")
    
    return f"""TOPIC CONTEXT (all components MUST relate to this):
Title: {leaf_title}
Description: {leaf_desc}

Available component types (use "type" from each):
{_json.dumps(available_components, indent=2)}

INSTRUCTIONS:
1. Create 3-4 components that comprehensively cover the topic "{leaf_title}"
2. Always include carousel for visual content
3. Include spotList or highlightsTab for detailed information
4. Each dataPrompt should request COMPREHENSIVE, SPECIFIC information about "{leaf_title}"
5. Make sure ALL components are directly relevant to "{leaf_title}" - NO unrelated content
6. If the query is about a destination, place, or location, include a "map" component with targetURL set to a Google Maps search URL formatted as: https://www.google.com/maps/search/?api=1&query=<URL-encoded-search-term>

Return a JSON object with this exact structure:
{{
  "components": [
    {{
      "id": "comp1",
      "type": "carousel",
      "position": {{ "row": 0, "col": 0 }},
      "size": {{ "width": 1.0, "height": "large" }},
      "dataPrompt": "Detailed instruction requesting comprehensive data specifically about {leaf_title}"
    }},
    {{
      "id": "comp2",
      "type": "spotList",
      "position": {{ "row": 1, "col": 0 }},
      "size": {{ "width": 1.0, "height": "auto" }},
      "dataPrompt": "Detailed instruction requesting specific, actionable items about {leaf_title}"
    }}
  ]
}}

IDs: comp1, comp2, comp3, comp4. Row/col: 0-based grid. Maximize information density!"""


def get_resolve_prompt(data_prompt: str, leaf_context: Dict[str, Any], component_type: str) -> str:
    """Generate prompt with exact schema for the component type."""
    import json as _json
    
    leaf_title = leaf_context.get("title", "Unknown topic")
    leaf_desc = leaf_context.get("description", "")
    
    # Get schema and example for this component type
    schema_info = COMPONENT_SCHEMAS.get(component_type)
    if not schema_info:
        return f"""Generate data for component type "{component_type}".

CRITICAL CONTEXT - All content MUST be specifically about:
Topic: {leaf_title}
Description: {leaf_desc}

Do NOT include content about unrelated topics.

Data instruction: {data_prompt}

Return a valid JSON object."""
    
    # Extract only the properties definition from the schema, not the meta-schema fields
    schema = schema_info["schema"]
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    
    # Build a simplified schema description
    schema_description = f"""{{
  "type": "object",
  "required": {_json.dumps(required)},
  "properties": {_json.dumps(properties, indent=4)}
}}"""
    
    example_json = _json.dumps(schema_info["example"], indent=2) if schema_info.get("example") else "No example available"
    
    # Add component-specific instructions
    additional_instructions = ""
    if component_type == "highlightsTab":
        additional_instructions = f"""
SPECIAL INSTRUCTIONS FOR highlightsTab:
- Set "sectionTitle" based on the topic type (e.g., "Highlights by Destination" for travel, "Highlights by Brand" for products, "Key Categories" for general topics)
- Generate sectionTitle that makes sense for "{leaf_title}"
- Each tab should represent a distinct aspect or category related to "{leaf_title}"
- Include comprehensive spot information with URLs"""
    elif component_type == "spotList":
        additional_instructions = f"""
SPECIAL INSTRUCTIONS FOR spotList:
- Each spot MUST include a "url" field with a real, searchable URL (Google search or direct website)
- URLs should be specific and actionable (e.g., "https://www.google.com/search?q=Sassi+di+Matera")
- Include 5-8 spots for maximum information density
- Make descriptions detailed and informative (not generic)"""
    elif component_type == "carousel":
        additional_instructions = f"""
SPECIAL INSTRUCTIONS FOR carousel:
- Find 4-6 high-quality, relevant images
- Use real image URLs from web search
- Include specific, descriptive captions
- Images should directly relate to "{leaf_title}" """
    elif component_type == "map":
        additional_instructions = f"""
SPECIAL INSTRUCTIONS FOR map:
- Generate a valid Google Maps search URL for "{leaf_title}"
- Format: https://www.google.com/maps/search/?api=1&query=<URL-encoded-query>
- Example: https://www.google.com/maps/search/?api=1&query=Starbucks+near+Times+Square
- Replace spaces with + in the query parameter
- Include relevant location context in the search query
- Set title to something descriptive like "Map View" or "Nearby Locations"
- Set searchQuery to the human-readable search terms used"""
    
    return f"""🎯 YOUR TASK: Generate actual DATA (not a schema) for a "{component_type}" UI component.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL CONTEXT - All content MUST be about:
Topic: {leaf_title}
Description: {leaf_desc}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  STRICT REQUIREMENT: Do NOT include ANY content about topics other than "{leaf_title}"

📋 Data instruction: {data_prompt}
{additional_instructions}

CONTENT QUALITY REQUIREMENTS:
✓ Use web search to find REAL, current information
✓ Include specific names, places, URLs (not generic placeholders)
✓ Provide detailed descriptions (not one-liners)
✓ Make content actionable - users should be able to click and explore
✓ Maximize information density - be comprehensive

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📐 DATA FORMAT SPECIFICATION (for reference only):
{schema_description}

✅ EXAMPLE OF CORRECT OUTPUT (this is actual data, not a schema):
{example_json}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚨 CRITICAL: Return ONLY actual data in JSON format - DO NOT return a schema definition.
Your response should look like the EXAMPLE above, with real values, NOT like the FORMAT SPECIFICATION.
No markdown code blocks, no explanations, just the raw JSON data object."""


# =============================================================================
# Helpers
# =============================================================================


async def _call_llm(prompt: str, system_prompt: str = LAYOUT_SYSTEM_PROMPT) -> Dict[str, Any]:
    from app.main import ai_agent
    if not ai_agent:
        raise HTTPException(status_code=503, detail="AI service not initialized")

    full_prompt = f"{system_prompt}\n\n{prompt}"
    content = ""
    try:
        result = await ai_agent.execute_task(
            task=full_prompt,
            context={"mode": "json_mode"},
            use_tools=False,
        )
        if not result.get("success"):
            raise Exception(result.get("error", "LLM call failed"))
        content = result.get("output", "")
        if "```json" in content:
            content = content.split("```json")[1].split("```")[0].strip()
        elif "```" in content:
            content = content.split("```")[1].split("```")[0].strip()
        return json.loads(content)
    except json.JSONDecodeError as e:
        logger.error(f"Generative UI: failed to decode JSON from LLM: {e}. Content: {content}")
        raise HTTPException(status_code=500, detail="LLM returned invalid JSON")
    except Exception as e:
        logger.error(f"Generative UI LLM failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Endpoints
# =============================================================================


@router.post("/plan", response_model=PlanResponse)
async def plan_layout(request: PlanRequest):
    """Generate a UI layout (list of components) for the given leaf context."""
    logger.info("Generating layout for leaf: %s", request.leafContext.get("title"))
    prompt = get_layout_prompt(request.leafContext, request.availableComponents)
    data = await _call_llm(prompt)
    components = [
        UIComponentSpec(
            id=c["id"],
            type=c["type"],
            position=ComponentPosition(**c["position"]),
            size=ComponentSize(**c.get("size", {"width": 1.0, "height": "auto"})),
            dataPrompt=c.get("dataPrompt", ""),
        )
        for c in data.get("components", [])
    ]
    return PlanResponse(layout=GenerativeUILayout(components=components))


@router.post("/resolve", response_model=ResolveResponse)
async def resolve_component_data(request: ResolveRequest):
    """Resolve data for a single UI component from the data prompt and leaf context."""
    logger.info("Resolving data for component %s (%s)", request.componentId, request.componentType)
    
    # Build prompt with web search guidance
    base_prompt = get_resolve_prompt(
        request.dataPrompt,
        request.leafContext,
        request.componentType,
    )
    enhanced_prompt = f"{base_prompt}\n\nIMPORTANT: Use web search to find current, accurate, real-world information. Return actual URLs for images, real place names, and up-to-date data."
    
    try:
        # Use web search for data resolution
        from app.main import ai_agent
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        full_prompt = f"{RESOLVE_SYSTEM_PROMPT}\n\n{enhanced_prompt}"
        content = ""
        
        result = await ai_agent.execute_task(
            task=full_prompt,
            context={"mode": "json_mode", "enable_web_search": True},
            use_tools=True,  # Enable tool use for web search
        )
        print(f"Resolve Result {result}")
        
        if not result.get("success"):
            raise Exception(result.get("error", "LLM call failed"))
        
        content = result.get("output", "")
        
        # Clean up markdown code blocks
        if "```json" in content:
            content = content.split("```json")[1].split("```")[0].strip()
        elif "```" in content:
            content = content.split("```")[1].split("```")[0].strip()
        
        data = json.loads(content)
        print(f"Resolve Data {data}")
        
        # Check if LLM returned a schema instead of data
        if isinstance(data, dict) and any(key in data for key in ['$schema', 'properties', 'required', 'title', 'type']) and 'properties' in data:
            logger.error(f"LLM returned a schema instead of data for {request.componentId}")
            logger.error(f"Returned schema: {json.dumps(data, indent=2)[:500]}")
            return ResolveResponse(
                componentId=request.componentId,
                data=None,
                success=False,
                error="LLM returned a schema definition instead of actual data. This is a prompt interpretation error.",
            )
        
        # Validate data against schema
        is_valid, validation_error = validate_component_data(request.componentType, data)
        if not is_valid:
            logger.error(f"Schema validation failed for {request.componentId}: {validation_error}")
            logger.error(f"Invalid data: {json.dumps(data, indent=2)}")
            return ResolveResponse(
                componentId=request.componentId,
                data=None,
                success=False,
                error=f"Data validation failed: {validation_error}",
            )
        
        return ResolveResponse(
            componentId=request.componentId,
            data=data,
            success=True,
            error=None,
        )
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON for {request.componentId}: {e}. Content: {content[:200]}")
        return ResolveResponse(
            componentId=request.componentId,
            data=None,
            success=False,
            error="Invalid JSON response from LLM",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Resolve failed for %s", request.componentId)
        return ResolveResponse(
            componentId=request.componentId,
            data=None,
            success=False,
            error=str(e),
        )


@router.post("/resolve-spot-details", response_model=SpotDetailResponse)
async def resolve_spot_details(request: SpotDetailRequest):
    """Resolve detailed information for a specific spot including images, summary, ratings, and citations."""
    logger.info("Resolving spot details for: %s", request.spotName)
    
    leaf_title = request.leafContext.get("title", "Unknown")
    leaf_desc = request.leafContext.get("description", "")
    
    # Build comprehensive prompt for spot details
    prompt = f"""Generate comprehensive, enriched details for a specific spot/resource.

🎯 CRITICAL CONTEXT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Spot Name: {request.spotName}
Spot Description: {request.spotDescription}
Topic Context: {leaf_title}
Topic Description: {leaf_desc}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Generate COMPREHENSIVE details for "{request.spotName}". Use web search to find:

1. **Images** (4-6 high-quality images):
   - Real image URLs showing {request.spotName}
   - Include diverse angles/perspectives
   - Add descriptive captions

2. **Summary** (150-250 words):
   - Rich, detailed description
   - Key features and highlights
   - What makes it special/unique
   - Practical information (when to visit, what to expect, etc.)

3. **Ratings & Reviews**:
   - Overall rating (0-5 scale)
   - Total review count
   - 3-5 authentic review snippets with authors

4. **Citations**:
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
- Ratings/reviews should reflect actual data from web sources
- Citations should reference real websites used as sources
- Return ONLY valid JSON matching the schema above, no markdown"""

    try:
        from app.main import ai_agent
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        content = ""
        result = await ai_agent.execute_task(
            task=prompt,
            context={"mode": "json_mode", "enable_web_search": True},
            use_tools=True,  # Enable web search
        )
        
        if not result.get("success"):
            raise Exception(result.get("error", "LLM call failed"))
        
        content = result.get("output", "")
        
        # Clean up markdown code blocks
        if "```json" in content:
            content = content.split("```json")[1].split("```")[0].strip()
        elif "```" in content:
            content = content.split("```")[1].split("```")[0].strip()
        
        data = json.loads(content)
        
        # Basic validation - ensure required fields exist
        required_fields = ["images", "summary", "citations"]
        for field in required_fields:
            if field not in data:
                raise ValueError(f"Missing required field: {field}")
        
        return SpotDetailResponse(
            spotId=request.spotId,
            data=data,
            success=True,
            error=None,
        )
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON for spot {request.spotId}: {e}. Content: {content[:200]}")
        return SpotDetailResponse(
            spotId=request.spotId,
            data=None,
            success=False,
            error="Invalid JSON response from LLM",
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Spot detail resolution failed for %s", request.spotId)
        return SpotDetailResponse(
            spotId=request.spotId,
            data=None,
            success=False,
            error=str(e),
        )
