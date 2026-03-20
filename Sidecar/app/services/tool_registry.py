"""
Tool Registry - Central registry for all browser automation tools.

This module provides a single source of truth for all available tools
that can be used by the AI agent.
"""

import logging
import asyncio
from typing import List, Callable, Optional
from langchain_core.tools import Tool

from .tools import DOMManipulatorTool, CSSAnalyzerTool, WebScraperTool, MacNotesTool, MCPConfigTool

logger = logging.getLogger(__name__)


class ToolRegistry:
    """
    Instance-based registry for managing browser automation tools.
    
    This class maintains a registry of all available tools and provides
    methods to retrieve them in various formats. Each AIAgent instance
    should create its own ToolRegistry instance.
    """
    
    def __init__(self):
        """Initialize the tool registry with local tools and start async tool loading."""
        # Registry of all available tool instances
        # [SSW] re-add these tools back later
        self._tools = [
            # DOMManipulatorTool(),
            # CSSAnalyzerTool(),
            # WebScraperTool(),
            # MacNotesTool(),
        ]
        
        # Initialize MCP Config Tool (loads servers from mcp.json)
        try:
            self._mcp_config_tool = MCPConfigTool()
            self._tools.append(self._mcp_config_tool)
        except Exception as e:
            logger.warning(f"Failed to initialize MCP Config Tool: {e}")
            self._mcp_config_tool = None
        
        self._mcp_service = None
        self._mcp_tools = []
        self._on_tools_ready = None  # Callback to invoke when async tools are ready
        
        # Start loading async tools in the background
        # TODO -> SKIP MCP for now, do only when required. 
        # asyncio.create_task(self._initialize_async_tools())
        
        # Initialize MCP config tools synchronously (HTTP REST API)
        if self._mcp_config_tool:
            try:
                # Initialize synchronously since HTTP REST API doesn't require async
                tools = self._mcp_config_tool.initialize()
                logger.info(f"Initialized {len(tools)} MCP tools from mcp.json synchronously")
                
                # Notify callback if registered
                if self._on_tools_ready and len(tools) > 0:
                    logger.info("Invoking tools ready callback...")
                    self._on_tools_ready()
            except Exception as e:
                logger.error(f"Failed to initialize MCP config tools: {e}")
    
    def set_tools_ready_callback(self, callback: Callable):
        """
        Set a callback to be invoked when async tools are ready.
        The callback will be called with no arguments.
        """
        self._on_tools_ready = callback
        logger.info("Tools ready callback registered")

    async def _initialize_async_tools(self):
        """
        Initialize asynchronous tools (like MCP tools).
        When complete, invokes the registered callback if any.
        """
        try:
            from .tools.mcp import MCPService
            self._mcp_service = MCPService()
            old_mcp_tools = await self._mcp_service.list_tools()
            # Merge with existing MCP tools from config
            self._mcp_tools.extend(old_mcp_tools)
            logger.info(f"Initialized {len(old_mcp_tools)} additional MCP tools from Docker Gateway")
            
            # Notify callback if registered
            if self._on_tools_ready and len(old_mcp_tools) > 0:
                logger.info("Invoking tools ready callback...")
                self._on_tools_ready()
        except Exception as e:
            logger.error(f"Failed to initialize async tools: {e}")

    def get_mcp_service(self):
        """
        Get the initialized MCPService instance.
        """
        return self._mcp_service

    async def trigger_failure_hooks(self):
        """
        Trigger failure hooks on all tools that were invoked.
        """
        # Call on_failure for local tools
        for tool in self._tools:
            await tool.on_failure()
        
        # Call on_failure for MCP config tool
        if self._mcp_config_tool:
            await self._mcp_config_tool.on_failure()
        
        # Call on_failure for MCP service
        if self._mcp_service:
            await self._mcp_service.on_failure()

    def reset_all_invocations(self):
        """
        Reset invocation flags for all tools.
        """
        # Reset local tools
        for tool in self._tools:
            tool.reset_invocation()
        
        # Reset MCP config tool
        if self._mcp_config_tool:
            self._mcp_config_tool.reset_invocation()
        
        # Reset MCP service
        if self._mcp_service:
            self._mcp_service.reset_invocation()

    def get_tools(self) -> List:
        """
        Get all registered tool instances.
        
        Returns:
            List: List of all registered browser tool instances.
        """
        return self._tools + self._mcp_tools
    
    def get_langchain_tools(self) -> List[Tool]:
        """
        Get all tools as LangChain Tool instances.
        
        Returns:
            List[Tool]: List of LangChain Tool instances ready for use with agents.
        """
        # Convert local tools (excluding MCP config tool) to LangChain tools
        local_tools = []
        for tool in self._tools:
            if tool != self._mcp_config_tool:
                local_tools.append(tool.to_langchain_tool())
        
        # Get MCP tools from config tool if available
        mcp_config_tools = []
        if self._mcp_config_tool:
            mcp_config_tools = self._mcp_config_tool.get_langchain_tools()
        
        # Combine all tools
        all_tools = local_tools + mcp_config_tools + self._mcp_tools
        logger.info(
            f"Loaded {len(all_tools)} tools from registry "
            f"(Local: {len(local_tools)}, MCP Config: {len(mcp_config_tools)}, MCP Service: {len(self._mcp_tools)})"
        )
        return all_tools
    
    def get_tool_by_name(self, name: str):
        """
        Get a specific tool by its name.
        
        Args:
            name: Name of the tool to retrieve.
            
        Returns:
            BaseBrowserTool: The requested tool instance, or None if not found.
        """
        for tool in self._tools:
            if tool.name == name:
                return tool
        logger.warning(f"Tool '{name}' not found in registry")
        return None
    
    def register_tool(self, tool):
        """
        Register a new tool to the registry.
        
        Args:
            tool: Tool instance to register (must inherit from BaseBrowserTool).
        """
        if tool not in self._tools:
            self._tools.append(tool)
            logger.info(f"Registered new tool: {tool.name}")
        else:
            logger.warning(f"Tool {tool.name} already registered")
