"""
Log Analysis Tools - LangChain tools for log filtering and analysis.

Purpose: Provides tools that wrap LogAnalysisService methods for use in agent execution.
"""

import logging
import json
from typing import List, Dict, Any, Optional
from langchain_core.tools import StructuredTool
from pydantic import BaseModel, Field

from .log_analysis_service import LogAnalysisService

logger = logging.getLogger(__name__)


class LogFilterInput(BaseModel):
    """Input schema for log filtering tool."""
    severity_levels: List[str] = Field(
        default=["CRITICAL", "ERROR"],
        description="List of severity levels to filter (e.g., ['CRITICAL', 'ERROR', 'WARNING'])"
    )
    keywords: Optional[List[str]] = Field(
        default=None,
        description="Optional list of keywords to search for in log messages (e.g., ['failed', 'timeout'])"
    )


def create_log_analysis_tool(logs: List[Dict[str, Any]]) -> StructuredTool:
    """
    Create a LangChain tool that filters logs based on severity levels and keywords.
    
    This tool wraps LogAnalysisService.extract_critical_logs() and makes it available
    to the agent executor. The logs are captured in the closure, so the tool operates
    on the specific log set provided when the tool is created.
    
    Args:
        logs: List of log entries to filter (from Elasticsearch or other sources)
        
    Returns:
        StructuredTool: LangChain StructuredTool instance for log filtering
    """
    
    # Create service instance (no LLM needed for filtering)
    service = LogAnalysisService(llm=None)
    
    def extract_critical_logs_impl(
        severity_levels: List[str] = ["CRITICAL", "ERROR"],
        keywords: Optional[List[str]] = None
    ) -> str:
        """
        Implementation function that filters logs based on parameters.
        
        Args:
            severity_levels: List of severity levels to filter (e.g., ["CRITICAL", "ERROR"])
            keywords: Optional list of keywords to search for in log messages
                
        Returns:
            JSON string with filtered logs count and sample
        """
        try:
            logger.info(f"Filtering logs with severity_levels={severity_levels}, keywords={keywords}")
            
            # Filter logs using the service
            filtered_logs = service.extract_critical_logs(
                logs=logs,
                severity_levels=severity_levels,
                keywords=keywords
            )
            
            # Return results (limit to first 20 for context size)
            result = {
                "total_logs": len(logs),
                "filtered_count": len(filtered_logs),
                "filtered_logs": filtered_logs[:20]  # Limit to avoid context overflow
            }
            
            if len(filtered_logs) > 20:
                result["note"] = f"Showing first 20 of {len(filtered_logs)} filtered logs"
            
            return json.dumps(result, indent=2)
            
        except Exception as e:
            logger.error(f"Log filtering failed: {e}", exc_info=True)
            return json.dumps({"error": f"Log filtering failed: {str(e)}"})
    
    return StructuredTool(
        name="extract_critical_logs",
        description=(
            "Filter logs to extract CRITICAL/ERROR severity entries based on severity levels and keywords. "
            "Use this tool to narrow down large log sets before analysis. "
            "Provide severity_levels (list of strings) and optionally keywords (list of strings)."
        ),
        func=extract_critical_logs_impl,
        args_schema=LogFilterInput
    )
