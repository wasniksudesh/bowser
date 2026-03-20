"""
MCP Config Tool - Loads and manages MCP servers from mcp.json configuration.

This module provides a tool that reads mcp.json and connects to configured
MCP servers via HTTP REST API, making their tools available to the agent.
"""

import json
import logging
import re
from pathlib import Path
from typing import List, Dict, Any, Optional

import httpx
from langchain_core.tools import Tool

from app.services.tools.base import BaseBrowserTool

logger = logging.getLogger(__name__)

class MCPServerConfig:
    """Configuration for a single MCP server."""
    def __init__(self, id: str, endpoint: str):
        self.id = id
        self.endpoint = endpoint.rstrip('/')  # Remove trailing slash

class MCPConfigTool(BaseBrowserTool):
    """
    Tool that loads MCP servers from mcp.json and makes their tools available.
    
    This tool reads the mcp.json configuration file, connects to each configured
    MCP server via HTTP REST API, and exposes all their tools as LangChain tools.
    """

    name = "mcp_config_loader"
    description = "Loads and manages MCP servers from configuration file"

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize the MCP Config Tool.
        
        Args:
            config_path: Path to mcp.json file. If None, looks for mcp.json
                        in the backend directory.
        """
        super().__init__()
        self.config_path = config_path or self._find_config_path()
        self.config: Optional[List[MCPServerConfig]] = None
        self.all_tools: List[Tool] = []
        self._was_invoked = False

    def _find_config_path(self) -> str:
        """Find mcp.json in the backend directory."""
        # Try to find mcp.json relative to this file
        backend_dir = Path(__file__).parent.parent.parent.parent
        config_path = backend_dir / "mcp.json"
        if config_path.exists():
            return str(config_path)
        
        # Fallback: try current working directory
        cwd_config = Path("mcp.json")
        if cwd_config.exists():
            return str(cwd_config)
        
        raise FileNotFoundError(
            f"Could not find mcp.json. Tried: {config_path}, {cwd_config}"
        )

    def _load_config(self) -> List[MCPServerConfig]:
        """Load and parse mcp.json configuration."""
        if self.config:
            return self.config
        
        try:
            with open(self.config_path, 'r') as f:
                data = json.load(f)
            
            servers = []
            for server_data in data.get("servers", []):
                server = MCPServerConfig(
                    id=server_data["id"],
                    endpoint=server_data["endpoint"]
                )
                servers.append(server)
            
            self.config = servers
            logger.info(f"Loaded MCP config from {self.config_path}: {len(servers)} servers")
            return self.config
        except Exception as e:
            logger.error(f"Failed to load MCP config from {self.config_path}: {e}")
            raise

    def run(self, input_str: str) -> str:
        """Management interface (no-op for now)."""
        config = self._load_config()
        return f"MCP Config Tool loaded {len(config)} servers from {self.config_path}"

    def _discover_tools_from_server(self, server: MCPServerConfig) -> List[Tool]:
        """
        Discover tools from a specific MCP server via HTTP REST API.
        
        Args:
            server: Server configuration to discover tools from
            
        Returns:
            List of LangChain Tool instances
        """
        langchain_tools: List[Tool] = []
        
        try:
            # Discover tools via GET /tools
            tools_url = f"{server.endpoint}/tools"
            logger.info(f"Discovering tools from '{server.id}' at {tools_url}")
            
            with httpx.Client(timeout=5.0) as client:
                response = client.get(tools_url)
                response.raise_for_status()
                tool_list = response.json().get("tools", [])
            logger.info(f"Found {len(tool_list)} tools from server '{server.id}'")
            
            for tool_def in tool_list:
                tool_name = tool_def.get("name", "")
                tool_description = tool_def.get("description", f"Tool from {server.id} server")
                
                # Sanitize tool name to only contain valid characters (a-zA-Z0-9_-)
                # Replace any invalid characters with underscores
                sanitized_tool_name = re.sub(r'[^a-zA-Z0-9_-]', '_', tool_name)
                sanitized_server_id = re.sub(r'[^a-zA-Z0-9_-]', '_', server.id)
                
                # Prefix tool name with server ID to avoid conflicts
                # Use underscore instead of dot to comply with tool name pattern: ^[a-zA-Z0-9_-]+$
                prefixed_name = f"{sanitized_server_id}_{sanitized_tool_name}"
                
                # Create tool invocation function
                def make_tool_func(base_endpoint: str, original_name: str, prefixed_tool_name: str, input_schema: Dict[str, Any]):
                    """Factory function to create tool call function with proper closure."""
                    def tool_func(input_str: str) -> str:
                        """Call the MCP tool via HTTP POST."""
                        call_url = f"{base_endpoint}/call"
                        
                        # Parse input string as JSON if possible
                        parsed_input = None
                        if input_str:
                            try:
                                parsed_input = json.loads(input_str)
                            except json.JSONDecodeError:
                                # If not JSON, treat as a plain string
                                parsed_input = input_str
                        args = {}
                        # Normalize args: handle both dict and single value cases
                        if isinstance(parsed_input, dict):
                            # Already a dict - use directly
                            args = parsed_input
                        else:
                            # Single value (int, str, etc.) - infer parameter name from schema
                            properties = input_schema.get("properties", {})
                            # if not properties:
                            #     # No schema properties - can't infer parameter name
                            #     raise ValueError(
                            #         f"Tool '{prefixed_tool_name}' received single value '{parsed_input}' "
                            #         f"but schema has no properties to infer parameter name"
                            #     )
                            if properties:
                                # Get the first (and likely only) property name
                                param_name = next(iter(properties.keys()))
                                args = {param_name: parsed_input}
                                logger.info(
                                    f"Inferred parameter '{param_name}' for single value input: {parsed_input}"
                                )
                        
                        payload = {
                            "tool": original_name,
                            "args": args
                        }

                        logger.info(f"[SSW] Calling tool '{prefixed_tool_name}' with payload: {payload}")
                        
                        try:
                            with httpx.Client(timeout=30.0) as client:
                                response = client.post(
                                    call_url,
                                    json=payload
                                )
                                response.raise_for_status()
                                result = response.json()
                                
                                # Handle different response formats
                                if isinstance(result, dict):
                                    # If result has a specific structure, extract the relevant part
                                    if "result" in result:
                                        return result["result"]
                                    elif "content" in result:
                                        return result["content"]
                                    elif "data" in result:
                                        return result["data"]
                                    else:
                                        return json.dumps(result)
                                elif isinstance(result, str):
                                    return result
                                else:
                                    return str(result)
                                
                        except httpx.RequestError as e:
                            logger.error(f"Error calling tool '{prefixed_tool_name}': {e}")
                            return f"Error calling tool: {str(e)}"
                        except httpx.HTTPStatusError as e:
                            logger.error(f"HTTP error calling tool '{prefixed_tool_name}': {e}")
                            return f"HTTP error calling tool: {e.response.status_code} - {e.response.text}"
                    
                    return tool_func
                
                # Get input schema from tool definition
                input_schema = tool_def.get("input_schema", {})
                
                # Create LangChain Tool
                tool = Tool(
                    name=prefixed_name,
                    description=tool_description,
                    func=make_tool_func(server.endpoint, tool_name, prefixed_name, input_schema)
                )
                
                langchain_tools.append(tool)
            
            logger.info(f"Created {len(langchain_tools)} LangChain tools from server '{server.id}'")
            return langchain_tools
            
        except httpx.RequestError as e:
            logger.error(f"Failed to discover tools from server '{server.id}': {e}")
            return []
        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error discovering tools from server '{server.id}': {e.response.status_code}")
            return []
        except Exception as e:
            logger.error(f"Unexpected error discovering tools from server '{server.id}': {e}")
            return []

    def discover_all_tools(self) -> List[Tool]:
        """
        Discover tools from all configured MCP servers.
        
        Returns:
            List of all LangChain Tool instances from all servers
        """
        config = self._load_config()
        all_tools = []
        
        for server in config:
            tools = self._discover_tools_from_server(server)
            all_tools.extend(tools)
        
        self.all_tools = all_tools
        logger.info(f"Discovered {len(all_tools)} total tools from {len(config)} MCP servers")
        return all_tools

    def initialize(self) -> List[Tool]:
        """
        Initialize all MCP servers and discover their tools.
        
        Returns:
            List of all discovered LangChain Tool instances
        """
        try:
            tools = self.discover_all_tools()
            return tools
        except Exception as e:
            logger.error(f"Failed to initialize MCP config tool: {e}")
            return []

    async def on_failure(self):
        """Reset MCP tool state if they were used during the session."""
        if not self._was_invoked:
            return
        
        try:
            logger.warning("MCP tools were used during failed session, but HTTP connections don't need reset")
            # For HTTP REST API, we don't need to reset connections
            # Just rediscover tools in case servers were restarted
            self.discover_all_tools()
            logger.info("MCP tools rediscovered")
        except Exception as e:
            logger.error(f"Error during MCP tool reset: {e}")

    def reset_invocation(self):
        """Reset the invocation tracking flag."""
        self._was_invoked = False

    def get_langchain_tools(self) -> List[Tool]:
        """
        Get all discovered tools as LangChain Tool instances.
        
        Returns:
            List of LangChain Tool instances
        """
        return self.all_tools
