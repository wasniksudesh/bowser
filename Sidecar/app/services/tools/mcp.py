import logging
import asyncio
from typing import List, Dict, Any, Optional
from contextlib import AsyncExitStack

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from langchain_core.tools import Tool, StructuredTool
from pydantic import BaseModel, Field, create_model

from app.services.tools.base import BaseBrowserTool

logger = logging.getLogger(__name__)

class MCPService(BaseBrowserTool):
    """
    Service to manage the lifecycle of an MCP client connection to the Docker Gateway.
    Also acts as a management tool for the MCP ecosystem.
    """

    name = "mcp_gateway"
    description = "Internal management for MCP tools"

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(MCPService, cls).__new__(cls)
            cls._instance.client = None
            cls._instance._exit_stack = None
            cls._instance.tools = []
            cls._instance._was_invoked = False
        return cls._instance

    # ---------------------------------------------------------------------
    # BaseBrowserTool interface
    # ---------------------------------------------------------------------

    def run(self, input_str: str) -> str:
        """Management interface for MCP gateway (no-op for now)."""
        return "MCP gateway is active."

    # ---------------------------------------------------------------------
    # MCP lifecycle
    # ---------------------------------------------------------------------

    async def connect(self):
        if self.client:
            return

        try:
            server_params = StdioServerParameters(
                command="docker",
                args=["mcp", "gateway", "run"],
                env=None,
            )

            self._exit_stack = AsyncExitStack()
            transport_ctx = stdio_client(server_params)
            read, write = await self._exit_stack.enter_async_context(transport_ctx)

            self.client = ClientSession(read, write)
            await self._exit_stack.enter_async_context(self.client)
            await self.client.initialize()

            logger.info("Connected to Docker MCP Gateway successfully")

        except Exception as e:
            logger.error("Failed to connect to Docker MCP Gateway: %s", e)
            self.client = None
            if self._exit_stack:
                await self._exit_stack.aclose()
                self._exit_stack = None

    async def disconnect(self):
        if self._exit_stack:
            await self._exit_stack.aclose()
            self._exit_stack = None
            self.client = None
            logger.info("Disconnected from Docker MCP Gateway")

    # ---------------------------------------------------------------------
    # Tool discovery
    # ---------------------------------------------------------------------

    def _create_pydantic_model_from_schema(self, tool_name: str, input_schema: Optional[Dict[str, Any]]) -> Optional[type[BaseModel]]:
        """
        Convert MCP tool input schema to a Pydantic model.
        
        Args:
            tool_name: Name of the tool (used for model naming)
            input_schema: JSON schema from MCP tool definition
            
        Returns:
            Pydantic model class or None if schema is empty/invalid
        """
        if not input_schema or not isinstance(input_schema, dict):
            return None
            
        properties = input_schema.get("properties", {})
        required = input_schema.get("required", [])
        
        if not properties:
            return None
        
        # Build field definitions for Pydantic model
        field_definitions = {}
        for field_name, field_info in properties.items():
            field_type = str  # Default to string
            field_description = field_info.get("description", "")
            
            # Map JSON schema types to Python types
            json_type = field_info.get("type", "string")
            if json_type == "integer":
                field_type = int
            elif json_type == "number":
                field_type = float
            elif json_type == "boolean":
                field_type = bool
            elif json_type == "array":
                field_type = List[Any]
            elif json_type == "object":
                field_type = Dict[str, Any]
            
            # Make field optional if not required
            if field_name not in required:
                field_type = Optional[field_type]
                field_definitions[field_name] = (field_type, Field(default=None, description=field_description))
            else:
                field_definitions[field_name] = (field_type, Field(..., description=field_description))
        
        # Create dynamic Pydantic model
        model_name = f"{tool_name.replace('-', '_').replace(' ', '_').title()}Input"
        return create_model(model_name, **field_definitions)

    async def list_tools(self) -> List[Tool]:
        if not self.client:
            await self.connect()

        if not self.client:
            return []

        try:
            response = await self.client.list_tools()
            mcp_tools = response.tools

            langchain_tools: List[Tool] = []

            for mcp_tool in mcp_tools:
                tool_name = mcp_tool.name
                tool_description = mcp_tool.description or f"MCP Tool: {tool_name}"
                
                # Try to get input schema
                input_schema = getattr(mcp_tool, 'inputSchema', None)
                
                # Create Pydantic model from schema if available
                pydantic_model = self._create_pydantic_model_from_schema(tool_name, input_schema)
                
                if pydantic_model:
                    # Use StructuredTool for tools with structured inputs
                    # Use factory function to properly capture tool_name
                    def make_structured_invoke(name: str):
                        async def _ainvoke(**kwargs):
                            return await self.call_tool(name, kwargs)
                        return _ainvoke
                    
                    tool = StructuredTool(
                        name=tool_name,
                        description=tool_description,
                        args_schema=pydantic_model,
                        coroutine=make_structured_invoke(tool_name),
                    )
                else:
                    # Fallback to simple Tool for single-input tools
                    # Use default parameter to capture tool_name by value
                    async def _ainvoke(input_str: str, name=tool_name):
                        return await self.call_tool(name, input_str)
                    
                    def _sync_invoke(input_str: str, name=tool_name):
                        loop = asyncio.get_event_loop()
                        if loop.is_running():
                            raise RuntimeError("Cannot call async tool from running event loop")
                        return loop.run_until_complete(self.call_tool(name, input_str))

                    tool = Tool(
                        name=tool_name,
                        description=tool_description,
                        func=_sync_invoke,
                        coroutine=_ainvoke,
                    )
                
                langchain_tools.append(tool)

            self.tools = langchain_tools
            logger.info("Discovered %d tools from Docker MCP Gateway", len(langchain_tools))
            return langchain_tools

        except Exception as e:
            logger.error("Failed to list tools from MCP Gateway: %s", e)
            return []

    # ---------------------------------------------------------------------
    # Argument normalization (CRITICAL)
    # ---------------------------------------------------------------------

    def _normalize_args(self, name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        if name != "docker":
            return args

        # Already correct
        if "cmd" in args and isinstance(args["cmd"], list):
            return args

        if "input" not in args or not isinstance(args["input"], str):
            raise ValueError("Invalid docker MCP arguments")

        tokens = args["input"].split()

        cmd = []
        i = 0
        while i < len(tokens):
            token = tokens[i]

            if token == "--format" and i + 1 < len(tokens):
                # 🔥 Re-join format argument
                format_parts = []
                i += 1
                while i < len(tokens) and not tokens[i].startswith("-"):
                    format_parts.append(tokens[i])
                    i += 1

                format_value = " ".join(format_parts)
                format_value = format_value.strip("'").strip('"')

                cmd.extend(["--format", format_value])
                continue

            cmd.append(token)
            i += 1

        return {"cmd": cmd}

    # ---------------------------------------------------------------------
    # Tool execution
    # ---------------------------------------------------------------------

    async def call_tool(
        self,
        name: str,
        arguments: str | Dict[str, Any],
        timeout: int = 10,
    ) -> str:
        self._was_invoked = True

        if not self.client:
            return "Error: MCP Client not connected"

        try:
            # Parse incoming arguments
            if isinstance(arguments, str):
                import json
                try:
                    args_dict = json.loads(arguments)
                except json.JSONDecodeError:
                    args_dict = {"input": arguments}
            else:
                args_dict = arguments

            # 🔥 Normalize docker arguments
            args_dict = self._normalize_args(name, args_dict)

            logger.info("Calling MCP tool '%s' with args: %s", name, args_dict)

            # ⏱ Tool-level timeout
            result = await asyncio.wait_for(
                self.client.call_tool(name, args_dict),
                timeout=timeout,
            )

            content = []
            for block in result.content:
                if hasattr(block, "text"):
                    content.append(block.text)
                elif hasattr(block, "data"):
                    content.append(str(block.data))

            return "\n".join(content)

        except asyncio.TimeoutError:
            logger.error("❌ MCP tool '%s' timed out after %ss", name, timeout)
            return f"❌ Tool '{name}' timed out."

        except Exception as e:
            logger.error("Error calling MCP tool '%s': %s", name, e)
            return f"Error: {str(e)}"

    # ---------------------------------------------------------------------
    # Failure recovery
    # ---------------------------------------------------------------------

    async def on_failure(self):
        """
        Hard reset MCP Gateway if it was used during the session.
        """
        if not self._was_invoked:
            return

        try:
            logger.warning("Resetting MCP Gateway session due to failure/timeout...")
            await self.disconnect()
        finally:
            await self.connect()
            logger.info("MCP Gateway session restored")
