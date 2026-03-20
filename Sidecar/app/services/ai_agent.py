"""
AI Agent Service using LangChain

Purpose: Orchestrates AI tasks, manages LLM routing,
and handles agent-based workflows for browser automation.
"""

import logging
import asyncio
from typing import Dict, Any, List, Optional

# LangChain imports
# LangChain imports
from langgraph.prebuilt import create_react_agent
from langgraph.checkpoint.memory import MemorySaver
# Core components moved to langchain_core
from langchain_core.messages import SystemMessage, HumanMessage
from langchain_core.tools import Tool

from app.config import *
from app.utils.factory import get_llm
from app.config import LLM_CONFIG
from app.services.tool_registry import ToolRegistry

logger = logging.getLogger(__name__)

class SafeAgentRunner:
    """
    Runs LangChain/LangGraph Agent with:
    - agent-level timeout
    - tool-level timeout
    - tool failure hooks (e.g. MCP hard reset)
    """

    def __init__(self, graph, tool_registry):
        self.graph = graph
        self.tool_registry = tool_registry

    async def run(
        self,
        task: str,
        timeout: int = 60
    ) -> Dict[str, Any]:
        try:
            logger.info("Agent execution started (timeout=%ss)", timeout)
            
            # Reset all tool invocation tracking before starting
            if self.tool_registry:
                self.tool_registry.reset_all_invocations()

            # Execute the graph
            # We use a default thread_id for now, can be parameterized later
            config = {"configurable": {"thread_id": "default"}}
            
            result = await asyncio.wait_for(
                self.graph.ainvoke({"messages": [HumanMessage(content=task)]}, config=config),
                timeout=timeout
            )
            
            # Extract the last message content as output
            messages = result.get("messages", [])
            output = messages[-1].content if messages else ""
            
            # Extract stats/steps if available in result (depends on graph setup)
            intermediate_steps = [] # LangGraph stores history in messages, steps are implicit

            return {
                "output": output,
                "intermediate_steps": intermediate_steps
            }

        except asyncio.TimeoutError:
            logger.error("❌ Agent timed out after %ss", timeout)
            if self.tool_registry:
                await self.tool_registry.trigger_failure_hooks()

            return {
                "output": (
                    "❌ Task timed out while executing tools.\n"
                    "Affected tool sessions were reset for safety."
                )
            }

        except Exception as e:
            logger.exception("❌ Agent execution failed")
            if self.tool_registry:
                await self.tool_registry.trigger_failure_hooks()

            return {
                "output": f"❌ Agent execution failed: {str(e)}"
            }

class AIAgent:
    """
    Unified AI Agent class using factory pattern for LLM initialization.
    Manages LLM routing and handles agent-based workflows for browser automation.
    """
    
    def __init__(self, provider: Optional[str] = None, model: Optional[str] = None, api_key: Optional[str] = None, temperature: float = 0.7):
        # Use provided values or fallback to LLM_CONFIG
        self.provider = provider or LLM_CONFIG["provider"]
        self.model_name = model or LLM_CONFIG["model"]
        self.api_key = api_key or LLM_CONFIG["api_key"]
        self.temperature = temperature
        
        self.llm = None
        self.graph = None # Replaces self.agent
        self.executor = None # Deprecated
        self.tools = []
        self.checkpointer = None # Replaces self.memory
        self.tool_registry = None

    async def initialize(self):
        """Initialize the AI agent with LLM and tools."""
        try:
            self.llm = get_llm(
                provider=self.provider,
                model=self.model_name,
                api_key=self.api_key,
                temperature=self.temperature
            )
            
            # Initialize conversation memory (checkpointer)
            self.checkpointer = MemorySaver()
            
            # Create tool registry instance (automatically starts loading async tools)
            self.tool_registry = ToolRegistry()
            
            # Register callback to be notified when async tools are ready
            self.tool_registry.set_tools_ready_callback(self._on_async_tools_ready)
            
            # Initialize tools for browser automation (whatever is available now)
            self._initialize_tools()
            
            # Define system prompt
            system_prompt = """You are an AI assistant for a web browser with advanced capabilities.
            You can help users with:
            - DOM manipulation and CSS analysis
            - Web scraping and data extraction
            - Task automation and workflow execution
            - Contextual reasoning about web content
            
            Use the available tools to accomplish tasks efficiently."""
            
            # Create agent graph
            self._create_agent_graph(system_prompt)
            
            logger.info(f"AIAgent ({self.provider}) initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize AIAgent: {e}")
            raise

    def _initialize_tools(self):
        """Initialize LangChain tools for browser automation."""
        self.tools = self.tool_registry.get_langchain_tools()
    
    def _create_agent_graph(self, system_prompt):
        """Create the agent graph with current tools."""
        # Create LangGraph agent
        self.graph = create_react_agent(
            self.llm, 
            self.tools, 
            checkpointer=self.checkpointer,
            prompt=system_prompt
        )

    def _on_async_tools_ready(self):
        """
        Callback invoked by ToolRegistry when async tools (MCP) are ready.
        This refreshes the tools and recreates the agent/executor without
        re-initializing the entire AIAgent.
        """
        logger.info("Async tools ready callback triggered")
        
        # Refresh tools from registry (now includes MCP tools)
        self._initialize_tools()
        
        # Recreate agent and executor with updated tools
        # Recreate agent graph with updated tools
        system_prompt = """You are an AI assistant for a web browser with advanced capabilities.
            You can help users with:
            - DOM manipulation and CSS analysis
            - Web scraping and data extraction
            - Task automation and workflow execution
            - Contextual reasoning about web content
            
            Use the available tools to accomplish tasks efficiently."""
            
        self._create_agent_graph(system_prompt)
        
        logger.info(f"Agent refreshed with {len(self.tools)} total tools available")

    async def execute_task(self, task: str, context: Optional[Dict[str, Any]] = None, use_tools: bool = True) -> Dict[str, Any]:
        """
        Execute a task with the AI agent.
        
        Args:
            task: The task to execute
            context: Optional context dictionary
            use_tools: If False, performs a simple LLM call without tool registry (default: True)
        """
        try:
            if context:
                task = f"{task}\n\nContext: {context}"
            
            # Simple LLM call without tools
            if not use_tools:
                if not self.llm:
                    raise ValueError("LLM not initialized")
                
                logger.info(f"Executing simple LLM call without tools with task {task}")
                # Add system message to enforce raw output format
                messages = [
                    SystemMessage(content="You are a helpful assistant. Always return responses in the exact format requested. Never use markdown code blocks or formatting unless explicitly asked. Return raw JSON when JSON is requested, and plain text otherwise."),
                    HumanMessage(content=task)
                ]
                response = await self.llm.ainvoke(messages)
                print('[SSW] LLM response output', response)
                # Extract text content from response
                output = response.content if hasattr(response, 'content') else str(response)
                # Handle list-typed output from some models (e.g., Gemini)
                if isinstance(output, list):
                    output_str = ""
                    for part in output:
                        if isinstance(part, dict) and "text" in part:
                            output_str += part["text"]
                        elif isinstance(part, str):
                            output_str += part
                    output = output_str
                
                return {
                    "success": True,
                    "output": output,
                    "intermediate_steps": [],
                }
            
            # Agent execution with tools
            if not self.graph:
                raise ValueError("Agent graph not initialized")
            
            # Use SafeAgentRunner for reliable execution
            runner = SafeAgentRunner(self.graph, self.tool_registry)
            result = await runner.run(task)
            
            output = result.get("output", "")
            
            # Handle list-typed output from some models (e.g., Gemini)
            if isinstance(output, list):
                output_str = ""
                for part in output:
                    if isinstance(part, dict) and "text" in part:
                        output_str += part["text"]
                    elif isinstance(part, str):
                        output_str += part
                output = output_str
                
            return {
                "success": True,
                "output": output,
                "intermediate_steps": result.get("intermediate_steps", []),
            }
        except Exception as e:
            logger.error(f"Task execution failed: {e}")
            return {"success": False, "error": str(e)}

    async def reconfigure(self, provider: str, api_key: str, model: Optional[str] = None):
        """Dynamically reconfigure the agent with a new provider and API key."""
        logger.info(f"Reconfiguring AI Agent to provider: {provider}")
        self.provider = provider.lower()
        self.api_key = api_key
        if model:
            self.model_name = model
        await self.initialize()

    async def cleanup(self):
        logger.info("AI Agent cleanup completed")


# =============================================================================
# Singleton Instance
# =============================================================================

_ai_agent_instance: Optional[AIAgent] = None
_ai_agent_lock = asyncio.Lock()


async def get_ai_agent() -> AIAgent:
    """
    Get or create the singleton AIAgent instance.
    Thread-safe initialization using asyncio.Lock.
    """
    global _ai_agent_instance
    
    if _ai_agent_instance is None:
        async with _ai_agent_lock:
            # Double-check after acquiring lock
            if _ai_agent_instance is None:
                logger.info("Initializing singleton AIAgent instance")
                _ai_agent_instance = AIAgent()
                await _ai_agent_instance.initialize()
                logger.info("Singleton AIAgent instance ready")
    
    return _ai_agent_instance


async def reconfigure_ai_agent(provider: str, api_key: str, model: Optional[str] = None):
    """
    Reconfigure the singleton AIAgent instance.
    """
    global _ai_agent_instance
    
    async with _ai_agent_lock:
        if _ai_agent_instance is None:
            _ai_agent_instance = AIAgent(provider=provider, model=model, api_key=api_key)
        else:
            _ai_agent_instance.provider = provider
            _ai_agent_instance.api_key = api_key
            if model:
                _ai_agent_instance.model_name = model
        
        await _ai_agent_instance.initialize()
        logger.info(f"AIAgent reconfigured to {provider}")
    
    return _ai_agent_instance
