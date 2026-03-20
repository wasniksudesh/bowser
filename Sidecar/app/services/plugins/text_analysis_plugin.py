"""
Text Analysis Plugin - V1
Provides skills for analyzing and processing text
"""

from typing import Any, Dict
from app.models.agent_schemas import Plugin, Skill, DataPacket


# =============================================================================
# Executor Functions
# =============================================================================

async def _summarize(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Generate a summary of provided text
    
    Returns:
        DataPacket with text content
    """
    try:
        from app.services.ai_agent import get_ai_agent
        print(f"[SSW] Summarize {params}")
        
        text = params["text"]
        max_length = params.get("max_length", 100)
        
        prompt = f"""Summarize the following text in {max_length} words or less.

Return ONLY the summary text as plain text. Do not include any JSON formatting or extra text.
Input Text : {text}
"""
        
        llm = await get_ai_agent()
        result = await llm.execute_task(prompt, use_tools=False)
        
        if not result.get("success"):
            return DataPacket.error(result.get("error", "Summarization failed"), code="LLM_ERROR")
        
        summary = result.get("output", "")
        
        return DataPacket(
            schema_def={"text": "string", "summary": "string"},
            rows=[{
                "text": summary,
                "summary": summary
            }]
        )
    except Exception as e:
        return DataPacket.error(str(e), code="TEXT_ANALYSIS_ERROR")


async def _extract_entities(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Extract named entities from text
    
    Returns:
        DataPacket with entity rows
    """
    try:
        from app.services.ai_agent import get_ai_agent
        import json
        
        text = params["text"]
        
        prompt = f"""Extract named entities (people, places, organizations) from the following text.

Return ONLY a valid JSON object with this EXACT format (no markdown, no extra text):
{{"items": [{{"label": "Entity Name", "value": "PERSON|PLACE|ORG"}}]}}

Example:
{{"items": [{{"label": "John Smith", "value": "PERSON"}}, {{"label": "New York", "value": "PLACE"}}]}}

Text:
{text}

JSON:"""
        
        llm = await get_ai_agent()
        result = await llm.execute_task(prompt, use_tools=False)
        
        if not result.get("success"):
            return DataPacket.error(result.get("error", "Entity extraction failed"), code="LLM_ERROR")
        
        output = result.get("output", "").strip()
        
        # Clean markdown code blocks if present
        if output.startswith("```"):
            lines = output.split("\n")
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            output = "\n".join(lines).strip()
        
        try:
            parsed = json.loads(output)
            items = parsed.get("items", [])
        except:
            items = []
        
        # Convert items to rows
        rows = [{"label": item.get("label", ""), "value": item.get("value", ""), "entities": items} for item in items] if items else []
        
        return DataPacket(
            schema_def={"label": "string", "value": "string", "entities": "array"},
            rows=rows if rows else [{"label": "", "value": "", "entities": []}]
        )
    except Exception as e:
        return DataPacket.error(str(e), code="TEXT_ANALYSIS_ERROR")


async def _compare(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Compare two texts and highlight differences or similarities
    
    Returns:
        DataPacket with comparison result
    """
    try:
        import difflib
        
        text1 = params["text1"]
        text2 = params["text2"]
        mode = params.get("mode", "diff")
        
        if mode == "similarity":
            ratio = difflib.SequenceMatcher(None, text1, text2).ratio()
            result = f"Similarity: {ratio:.1%}"
        else:
            diff = difflib.unified_diff(
                text1.splitlines(keepends=True),
                text2.splitlines(keepends=True),
                fromfile="text1",
                tofile="text2"
            )
            result = "".join(diff)
        
        return DataPacket(
            schema_def={"text": "string", "diff_result": "string"},
            rows=[{
                "text": result,
                "diff_result": result
            }]
        )
    except Exception as e:
        return DataPacket.error(str(e), code="TEXT_ANALYSIS_ERROR")


def get_text_analysis_plugin() -> Plugin:
    """
    Returns the Text Analysis plugin with all skills
    """
    return Plugin(
        plugin_id="text_analysis",
        name="Text Analysis Plugin",
        version="1.0.0",
        description="Skills for analyzing and processing text",
        auth_requirements=[],  # No auth required
        skills=[
            # Skill 1: Summarize
            Skill(
                skill_id="summarize",
                name="Summarize Text",
                description="Generate a summary of provided text",
                input_schema={
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Text to summarize"
                        },
                        "max_length": {
                            "type": "integer",
                            "description": "Maximum summary length in words (default: 100)",
                            "default": 100
                        }
                    },
                    "required": ["text"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "summary": {
                            "type": "string",
                            "description": "The generated summary"
                        },
                        "text": {
                            "type": "string",
                            "description": "The summary text (alias for chaining)"
                        }
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_summarize,
                domains=["text", "analysis", "nlp", "content"],
                verbs=["summarize", "condense", "shorten", "analyze"],
                nouns=["text", "content", "document", "summary"],
                output_types=["text", "textBlock"]
            ),
            
            # Skill 2: Extract Entities
            Skill(
                skill_id="extractEntities",
                name="Extract Entities",
                description="Extract named entities (people, places, organizations) from text",
                input_schema={
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Text to analyze"
                        }
                    },
                    "required": ["text"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "entities": {
                            "type": "array",
                            "items": {"type": "object"},
                            "description": "Array of extracted entities with entity and type fields"
                        }
                    }
                },
                output_type="list",
                execution_type="sdk",
                execute=_extract_entities,
                domains=["text", "analysis", "nlp"],
                verbs=["extract", "find", "identify", "analyze"],
                nouns=["entities", "names", "places", "organizations"],
                output_types=["list", "table"]
            ),
            
            # Skill 3: Compare
            Skill(
                skill_id="compare",
                name="Compare Texts",
                description="Compare two texts and highlight differences or similarities",
                input_schema={
                    "type": "object",
                    "properties": {
                        "text1": {
                            "type": "string",
                            "description": "First text"
                        },
                        "text2": {
                            "type": "string",
                            "description": "Second text"
                        },
                        "mode": {
                            "type": "string",
                            "description": "Comparison mode: diff or similarity (default: diff)",
                            "enum": ["diff", "similarity"],
                            "default": "diff"
                        }
                    },
                    "required": ["text1", "text2"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "diff_result": {
                            "type": "string",
                            "description": "The comparison result"
                        },
                        "text": {
                            "type": "string",
                            "description": "The result text (alias for chaining)"
                        }
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_compare,
                domains=["text", "analysis", "comparison"],
                verbs=["compare", "diff", "analyze", "match"],
                nouns=["text", "content", "difference", "similarity"],
                output_types=["text", "textBlock"]
            )
        ]
    )
