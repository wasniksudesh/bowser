"""
HTTP Plugin - V1
Provides skills for making generic HTTP requests
"""

from typing import Any, Dict
from app.models.agent_schemas import Plugin, Skill, AuthRequirement, AuthStrategy, DataPacket


# =============================================================================
# Executor Functions
# =============================================================================

async def _fetch_url(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Fetch content from a URL using GET request
    
    Returns:
        DataPacket with text content
    """
    try:
        import httpx
        
        url = params["url"]
        headers = params.get("headers", {}).copy()
        query_params = params.get("params", {})
        
        if token := auth.get("api_token"):
            headers.setdefault("Authorization", f"Bearer {token}")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.get(url, headers=headers, params=query_params)
            resp.raise_for_status()
            
            return DataPacket(
                schema_def={"text": "string", "response_text": "string"},
                rows=[{
                    "text": resp.text,
                    "response_text": resp.text
                }]
            )
    except Exception as e:
        status_code = getattr(e, "response", None) and getattr(e.response, "status_code", None)
        return DataPacket.error(str(e), code="HTTP_ERROR", details={"status": status_code, "url": params.get("url")})


async def _post_request(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Send a POST request to an API endpoint
    
    Returns:
        DataPacket with text content
    """
    try:
        import httpx
        
        url = params["url"]
        body = params["body"]
        headers = params.get("headers", {}).copy()
        
        if token := auth.get("api_token"):
            headers.setdefault("Authorization", f"Bearer {token}")
        
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(url, json=body, headers=headers)
            resp.raise_for_status()
            
            return DataPacket(
                schema_def={"text": "string", "response_text": "string"},
                rows=[{
                    "text": resp.text,
                    "response_text": resp.text
                }]
            )
    except Exception as e:
        status_code = getattr(e, "response", None) and getattr(e.response, "status_code", None)
        return DataPacket.error(str(e), code="HTTP_ERROR", details={"status": status_code, "url": params.get("url")})


def get_http_plugin() -> Plugin:
    """
    Returns the HTTP plugin with all skills
    """
    return Plugin(
        plugin_id="http",
        name="HTTP Plugin",
        version="1.0.0",
        description="Skills for making HTTP requests to web APIs",
        auth_requirements=[
            AuthRequirement(
                auth_id="api_token",
                description="Optional API token for authenticated requests",
                strategies=[
                    AuthStrategy(
                        type="token",
                        context_key="api_token",
                        description="Bearer token or API key"
                    )
                ]
            )
        ],
        skills=[
            # Skill 1: Fetch URL
            Skill(
                skill_id="fetchURL",
                name="Fetch URL",
                description="Fetch content from a URL using GET request",
                input_schema={
                    "type": "object",
                    "properties": {
                        "url": {
                            "type": "string",
                            "description": "URL to fetch"
                        },
                        "headers": {
                            "type": "object",
                            "description": "Optional HTTP headers",
                            "additionalProperties": {"type": "string"}
                        },
                        "params": {
                            "type": "object",
                            "description": "Optional query parameters",
                            "additionalProperties": {"type": "string"}
                        }
                    },
                    "required": ["url"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "response_text": {
                            "type": "string",
                            "description": "The response body text"
                        },
                        "text": {
                            "type": "string",
                            "description": "The response text (alias for chaining)"
                        }
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_fetch_url,
                domains=["http", "web", "api", "internet"],
                verbs=["fetch", "get", "retrieve", "download"],
                nouns=["url", "webpage", "data", "content"],
                output_types=["text", "textBlock", "custom"]
            ),
            
            # Skill 2: POST Request
            Skill(
                skill_id="postRequest",
                name="POST Request",
                description="Send a POST request to an API endpoint",
                input_schema={
                    "type": "object",
                    "properties": {
                        "url": {
                            "type": "string",
                            "description": "URL to send POST request to"
                        },
                        "body": {
                            "type": "object",
                            "description": "Request body (JSON)"
                        },
                        "headers": {
                            "type": "object",
                            "description": "Optional HTTP headers",
                            "additionalProperties": {"type": "string"}
                        }
                    },
                    "required": ["url", "body"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "response_text": {
                            "type": "string",
                            "description": "The response body text"
                        },
                        "text": {
                            "type": "string",
                            "description": "The response text (alias for chaining)"
                        }
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_post_request,
                domains=["http", "web", "api"],
                verbs=["post", "send", "create", "submit"],
                nouns=["request", "data", "payload"],
                output_types=["text", "textBlock", "custom"]
            )
        ]
    )
