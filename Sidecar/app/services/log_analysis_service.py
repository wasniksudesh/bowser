"""
Log Analysis Service

Purpose: Analyzes logs using LLM with function-calling to extract CRITICAL logs
and generate human-readable summaries.
"""

import logging
import json
from typing import Dict, Any, List, Optional
from langchain_core.messages import HumanMessage, SystemMessage, AIMessage, FunctionMessage
from langchain_core.prompts import ChatPromptTemplate

logger = logging.getLogger(__name__)


class LogAnalysisService:
    """
    Service for analyzing logs with LLM function-calling.
    
    Uses function-calling to filter CRITICAL logs and generate analysis summaries.
    """
    
    # Function schema for LLM function-calling
    EXTRACT_CRITICAL_LOGS_FUNCTION = {
        "name": "extract_critical_logs",
        "description": "Filter logs to extract only CRITICAL severity entries based on severity levels and failure keywords. Use this function to narrow down logs before analysis.",
        "parameters": {
            "type": "object",
            "properties": {
                "severity_levels": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Severity levels to filter (e.g., CRITICAL, ERROR, FATAL)"
                },
                "keywords": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Keywords indicating failures (e.g., failed, exception, timeout, error)"
                }
            },
            "required": ["severity_levels"]
        }
    }
    
    def __init__(self, llm):
        """
        Initialize the log analysis service.
        
        Args:
            llm: LangChain LLM instance
        """
        self.llm = llm
    
    def extract_critical_logs(
        self, 
        logs: List[Dict[str, Any]], 
        severity_levels: List[str], 
        keywords: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """
        Filter logs based on severity levels and keywords.
        
        This is the actual implementation that gets called when the LLM
        requests to use the extract_critical_logs function.
        
        Args:
            logs: List of log entries from Elasticsearch (with _source field)
            severity_levels: Severity levels to filter for (e.g., ['CRITICAL', 'ERROR'])
            keywords: Optional keywords to search for in log messages
            
        Returns:
            Filtered list of critical log entries
        """
        levelSet = dict()
        filtered = []
        severity_levels_upper = [s.upper() for s in severity_levels]
        keywords_lower = [k.lower() for k in keywords] if keywords else []
        counter = 0
        for log in logs:
            if not isinstance(log, dict):
                logger.info('[SSW] NOT DICT !')
                continue
            
            # Elasticsearch can return logs in two formats:
            # 1. _source field (direct source data)
            # 2. fields field (array format from Elasticsearch fields API)
            source = log.get('_source', {})
            fields = log.get('fields', {})
            
            if counter == 0:
                logger.info(f"[SSW] First log structure: {log}")
                counter += 1 
            
            # Extract level - check both _source and fields
            log_level = ''
            if source and 'level' in source:
                # _source format: {"level": "CRITICAL"}
                log_level = str(source.get('level', '')).upper()
            elif fields and 'level' in fields:
                # fields format: {"level": ["CRITICAL"]}
                level_value = fields.get('level', [])
                if isinstance(level_value, list) and len(level_value) > 0:
                    log_level = str(level_value[0]).upper()
                elif isinstance(level_value, str):
                    log_level = level_value.upper()
            
            levelSet[log_level] = 1 if log_level not in levelSet else levelSet[log_level]+1
            
            # Check severity match
            if log_level in severity_levels_upper:
                filtered.append(log)
                continue
            
            # Check keywords if provided
            if keywords_lower:
                # Extract message from either source or fields
                msg = ''
                if source and 'msg' in source:
                    msg = str(source.get('msg', '')).lower()
                elif fields and 'msg' in fields:
                    msg_value = fields.get('msg', [])
                    if isinstance(msg_value, list) and len(msg_value) > 0:
                        msg = str(msg_value[0]).lower()
                    elif isinstance(msg_value, str):
                        msg = msg_value.lower()
                
                # Search in message and entire log structure
                log_str = json.dumps(log).lower()
                
                if any(kw in msg or kw in log_str for kw in keywords_lower):
                    filtered.append(log)
        
        logger.info(f"Filtered {len(filtered)} critical logs from {len(logs)} total logs")
        logger.info(f"[SSW] Loglevel dict{levelSet}")
        return filtered
    
    async def analyze(
        self, 
        logs: List[Dict[str, Any]], 
        query: str, 
        request_id: str
    ) -> Dict[str, Any]:
        """
        Analyze logs using LLM with function-calling.
        
        Flow:
        1. Send logs + query to LLM with function schema
        2. LLM decides to call extract_critical_logs function
        3. Execute function to filter logs
        4. Send filtered logs back to LLM
        5. LLM generates human-readable analysis summary
        
        Args:
            logs: List of log entries to analyze
            query: User's analysis query
            request_id: Unique request ID for tracing
            
        Returns:
            Dictionary with analysis_summary and critical_logs
        """
        logger.info(f"[{request_id}] Starting log analysis with {len(logs)} logs")
        
        try:
            # Step 1: Create system prompt
            system_prompt = f"""You are a log analysis agent specialized in analyzing Kibana logs.

Your task is to help users understand failures and issues in their logs.

Available function:
- extract_critical_logs: Filter logs to extract only CRITICAL/ERROR severity entries

Process:
1. First, call extract_critical_logs to filter for CRITICAL/ERROR logs and failure keywords
2. Then analyze the filtered logs and provide a concise summary

User query: {query}

Total logs available: {len(logs)}

You MUST call the extract_critical_logs function first before providing analysis."""

            # Step 2: Prepare messages for LLM
            messages = [
                SystemMessage(content=system_prompt),
                HumanMessage(content=f"Analyze these logs: {query}\n\nLogs sample (first 5): {json.dumps(logs[:5], indent=2)}")
            ]
            
            # Step 3: Invoke LLM with function-calling
            # For OpenAI-compatible models, bind the function
            llm_with_functions = self.llm.bind(
                functions=[self.EXTRACT_CRITICAL_LOGS_FUNCTION],
                function_call={"name": "extract_critical_logs"}  # Force function call
            )
            
            logger.info(f"[{request_id}] Invoking LLM with function-calling")
            response = await llm_with_functions.ainvoke(messages)
            
            # Step 4: Check if LLM called the function
            critical_logs = []
            if hasattr(response, 'additional_kwargs') and 'function_call' in response.additional_kwargs:
                function_call = response.additional_kwargs['function_call']
                function_name = function_call['name']
                function_args = json.loads(function_call['arguments'])
                
                logger.info(f"[{request_id}] LLM called function: {function_name} with args: {function_args}")
                
                # Execute the function
                if function_name == 'extract_critical_logs':
                    critical_logs = self.extract_critical_logs(
                        logs=logs,
                        severity_levels=function_args.get('severity_levels', ['CRITICAL', 'ERROR']),
                        keywords=function_args.get('keywords')
                    )
                    
                    logger.info(f"[{request_id}] Extracted {len(critical_logs)} critical logs")
                    
                    # Step 5: Send function result back to LLM for final analysis
                    messages.append(response)
                    messages.append(FunctionMessage(
                        name=function_name,
                        content=json.dumps({
                            "filtered_count": len(critical_logs),
                            "critical_logs_sample": critical_logs[:10]  # Send sample to LLM
                        })
                    ))
                    
                    # Get final analysis from LLM
                    logger.info(f"[{request_id}] Getting final analysis from LLM")
                    final_response = await self.llm.ainvoke(messages)
                    
                    # Extract text content
                    analysis_summary = final_response.content if hasattr(final_response, 'content') else str(final_response)
                    
                    # Handle list-typed output from some models
                    if isinstance(analysis_summary, list):
                        analysis_summary = "".join([
                            part["text"] if isinstance(part, dict) and "text" in part else str(part)
                            for part in analysis_summary
                        ])
            else:
                # Fallback: LLM didn't call function, extract manually
                logger.warning(f"[{request_id}] LLM didn't call function, extracting manually")
                critical_logs = self.extract_critical_logs(
                    logs=logs,
                    severity_levels=['CRITICAL', 'ERROR', 'FATAL'],
                    keywords=['failed', 'error', 'exception', 'timeout']
                )
                
                # Use LLM response as analysis
                analysis_summary = response.content if hasattr(response, 'content') else str(response)
                if isinstance(analysis_summary, list):
                    analysis_summary = "".join([
                        part["text"] if isinstance(part, dict) and "text" in part else str(part)
                        for part in analysis_summary
                    ])
            
            logger.info(f"[{request_id}] Log analysis complete")
            
            return {
                "analysis_summary": analysis_summary,
                "critical_logs": critical_logs,
                "steps": [
                    "Extracted logs from Kibana",
                    f"Filtered to {len(critical_logs)} critical logs",
                    "Generated analysis summary"
                ]
            }
            
        except Exception as e:
            logger.error(f"[{request_id}] Log analysis failed: {e}", exc_info=True)
            raise
