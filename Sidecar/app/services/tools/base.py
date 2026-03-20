"""
Base class for all browser automation tools.

This module provides the abstract base class that all browser tools must inherit from.
"""

from abc import ABC, abstractmethod
from langchain_core.tools import Tool


class BaseBrowserTool(ABC):
    """
    Abstract base class for browser automation tools.
    
    All tools must define a name, description, and implement the run method.
    """
    
    name: str
    description: str
    _was_invoked: bool = False

    def to_langchain_tool(self) -> Tool:
        """
        Convert this tool to a LangChain Tool instance.
        
        Returns:
            Tool: A LangChain Tool instance configured with this tool's properties.
        """
        # Wrap the run method to track invocation
        def wrapped_run(input_str: str) -> str:
            self._was_invoked = True
            return self.run(input_str)

        return Tool(
            name=self.name,
            func=wrapped_run,
            description=self.description,
        )

    async def on_failure(self) -> None:
        """
        Hook called when an agent execution fails or times out.
        Only called if this tool was invoked during the session.
        """
        pass

    def reset_invocation(self) -> None:
        """Reset the invocation tracking flag."""
        self._was_invoked = False

    @abstractmethod
    def run(self, input_str: str) -> str:
        """
        Execute the tool's main functionality.
        
        Args:
            input_str: Input string containing the tool's parameters.
            
        Returns:
            str: Result of the tool execution.
        """
        pass
