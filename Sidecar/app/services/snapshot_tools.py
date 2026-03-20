import logging
import httpx
import base64
from typing import List, Optional, Dict
from langchain_core.tools import Tool
from langchain_core.messages import HumanMessage

logger = logging.getLogger(__name__)

# Global storage for screenshots captured during agent execution
_screenshot_cache: Dict[str, str] = {}

def get_screenshot_cache() -> Dict[str, str]:
    """Get the current screenshot cache."""
    return _screenshot_cache

def clear_screenshot_cache():
    """Clear all screenshots from cache."""
    _screenshot_cache.clear()
    logger.info("Screenshot cache cleared")

def get_cached_screenshots() -> List[Dict[str, str]]:
    """Get all cached screenshots as a list of {title, data_url} dicts."""
    return [{"container_id": k, "data_url": v} for k, v in _screenshot_cache.items()]


def _infer_context_from_url(url: Optional[str]) -> Optional[str]:
    """
    Infer contextual description from URL patterns.
    
    Args:
        url: URL of the webpage
        
    Returns:
        Inferred context description or None
    """
    if not url:
        return None
    
    url_lower = url.lower()
    
    # Check for common monitoring/observability tools
    if "grafana" in url_lower:
        return "Grafana metrics/monitoring dashboard"
    if "prometheus" in url_lower:
        return "Prometheus metrics viewer"
    if "kibana" in url_lower:
        return "Kibana log viewer and search interface"
    if "datadog" in url_lower:
        return "Datadog monitoring dashboard"
    if "newrelic" in url_lower:
        return "New Relic APM dashboard"
    
    # Check for generic patterns
    if "metrics" in url_lower or "monitoring" in url_lower:
        return "Metrics/monitoring dashboard"
    if "logs" in url_lower or "logging" in url_lower:
        return "Log viewer/search interface"
    if "trace" in url_lower or "tracing" in url_lower:
        return "Distributed tracing interface"
    if "alert" in url_lower:
        return "Alerting/notification dashboard"
    
    return None


def create_snapshot_tools(
    container_id: str, 
    title: str, 
    callback_port: int,
    description: Optional[str] = None,
    url: Optional[str] = None
) -> List[Tool]:
    """
    Create snapshot tools for a webpage container.
    
    Each webpage gets three tools:
    - get_screenshot: Capture screenshot
    - get_dom_text: Extract DOM text
    - run_page_script: Execute JavaScript
    
    These tools make HTTP callbacks to main.js which executes them on the actual WCV.
    
    Args:
        container_id: Unique identifier for the webpage container
        title: Title of the webpage
        callback_port: Port for HTTP callbacks to main.js
        description: Optional contextual description (e.g., "Grafana metrics dashboard")
        url: Optional URL for auto-inferring context if description not provided
    """
    
    # Build contextual description for tool descriptions
    context = description or _infer_context_from_url(url) or title
    
    logger.info(f"Creating snapshot tools for {container_id}: context='{context}'")
    
    callback_url = f"http://localhost:{callback_port}"
    
    def get_screenshot_impl(dummy_input: str = "") -> str:
        """Capture a screenshot of the webpage."""
        try:
            response = httpx.post(
                callback_url,
                json={
                    "tool_name": "get_screenshot",
                    "container_id": container_id,
                    "params": {}
                },
                timeout=30.0
            )
            response.raise_for_status()
            result = response.json()
            
            if result.get("success"):
                # Store screenshot in cache for vision analysis
                screenshot_data = result['result']
                cache_key = f"{container_id}:{title}"
                _screenshot_cache[cache_key] = screenshot_data
                
                logger.info(f"Screenshot captured for {title}, data length: {len(screenshot_data)}, cached as: {cache_key}")
                
                # Return a reference - the actual image will be sent in the vision call
                return f"[SCREENSHOT_CAPTURED: {cache_key}] Screenshot of '{title}' has been captured and cached for visual analysis."
            else:
                return f"Failed to capture screenshot: {result.get('error', 'Unknown error')}"
        except Exception as e:
            logger.error(f"Screenshot capture failed: {e}")
            return f"Error capturing screenshot: {str(e)}"
    
    def get_dom_text_impl(selector: str = "") -> str:
        """Extract text content from the webpage DOM."""
        try:
            response = httpx.post(
                callback_url,
                json={
                    "tool_name": "get_dom_text",
                    "container_id": container_id,
                    "params": {"selector": selector}
                },
                timeout=30.0
            )
            response.raise_for_status()
            result = response.json()
            
            if result.get("success"):
                text = result['result']
                if len(text) > 5000:
                    text = text[:5000] + "...(truncated)"
                return text
            else:
                return f"Failed to extract DOM text: {result.get('error', 'Unknown error')}"
        except Exception as e:
            logger.error(f"DOM text extraction failed: {e}")
            return f"Error extracting DOM text: {str(e)}"
    
    def run_page_script_impl(script: str) -> str:
        """Execute JavaScript on the webpage."""
        try:
            response = httpx.post(
                callback_url,
                json={
                    "tool_name": "run_page_script",
                    "container_id": container_id,
                    "params": {"script": script}
                },
                timeout=30.0
            )
            response.raise_for_status()
            result = response.json()
            
            if result.get("success"):
                return str(result['result'])
            else:
                return f"Failed to run script: {result.get('error', 'Unknown error')}"
        except Exception as e:
            logger.error(f"Script execution failed: {e}")
            return f"Error running script: {str(e)}"
    
    tools = [
        Tool(
            name=f"get_screenshot_{container_id}",
            description=f"Capture a screenshot of: {context}. Use this when you need visual information from this specific webpage.",
            func=get_screenshot_impl
        ),
        # Tool(
        #     name=f"get_dom_text_{container_id}",
        #     description=f"Extract text content from the webpage: {title}. You can optionally provide a CSS selector to filter specific elements. If no selector is provided, returns all body text.",
        #     func=get_dom_text_impl
        # ),
        # Tool(
        #     name=f"run_page_script_{container_id}",
        #     description=f"Execute JavaScript code on the webpage: {title}. Use this to interact with the page or extract specific data. The script should return a value.",
        #     func=run_page_script_impl
        # )
    ]
    
    logger.info(f"Created {len(tools)} snapshot tools for container {container_id} ({title})")
    
    return tools
