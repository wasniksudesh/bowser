"""
AI Routes

Purpose: API endpoints for AI task execution and orchestration.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator
from typing import Dict, Any, Optional, List
import logging

logger = logging.getLogger(__name__)

router = APIRouter()

# Import log analysis service
from app.services.log_analysis_service import LogAnalysisService

class AITaskRequest(BaseModel):
    """Request model for AI task execution"""
    task: str
    context: Optional[Dict[str, Any]] = None
    user_id: Optional[str] = "default"

class AITaskResponse(BaseModel):
    """Response model for AI task execution"""
    success: bool
    output: Optional[Any] = None
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class AIConfigureRequest(BaseModel):
    """Request model for AI agent configuration"""
    provider: str
    api_key: str
    model: Optional[str] = None

class ResolveURLRequest(BaseModel):
    """Request model for URL resolution"""
    query: str

class ResolveURLResponse(BaseModel):
    """Response model for URL resolution"""
    url: str
    steps: List[str]

class SnapshotToolDef(BaseModel):
    """Definition for a snapshot tool (webpage)"""
    container_id: str
    title: str
    description: Optional[str] = None  # Contextual description (e.g., "Grafana metrics dashboard showing CPU/memory")
    url: Optional[str] = None          # URL for auto-deriving context if description not provided

class AgentExecuteRequest(BaseModel):
    """Request model for multi-tool agent execution"""
    prompt: str
    static_tools: List[str]
    snapshot_tools: List[SnapshotToolDef]
    callback_port: int
    logs: Optional[List[Dict[str, Any]]] = None  # Optional logs for log analysis tool
    
    @field_validator('prompt')
    @classmethod
    def validate_prompt_not_empty(cls, v: str) -> str:
        """Ensure prompt is not empty or whitespace-only"""
        if not v or not v.strip():
            raise ValueError("Prompt cannot be empty. Please provide a task or question for the agent to execute.")
        return v.strip()  # Return trimmed version

class AgentExecuteResponse(BaseModel):
    """Response model for agent execution"""
    output: str
    error: Optional[str] = None

@router.post("/execute", response_model=AITaskResponse)
async def execute_ai_task(request: AITaskRequest):
    """
    Execute an AI task using the LangChain agent.
    
    The agent can perform DOM manipulation, CSS analysis,
    web scraping, and contextual reasoning.
    """
    try:
        # Get AI agent from app state
        from app.main import ai_agent
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        # Execute task
        result = await ai_agent.execute_task(
            task=request.task,
            context=request.context
        )
        
        if result["success"]:
            return AITaskResponse(
                success=True,
                output=result["output"],
                metadata={"steps": result.get("intermediate_steps", [])}
            )
        else:
            return AITaskResponse(
                success=False,
                error=result.get("error", "Unknown error")
            )
            
    except Exception as e:
        logger.error(f"AI task execution failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/status")
async def get_ai_status():
    """Get AI service status"""
    from app.main import ai_agent
    
    return {
        "status": "active" if ai_agent else "inactive",
        "model": ai_agent.agent.model_name if ai_agent else None,
        "provider": ai_agent.provider if ai_agent else None,
    }

@router.post("/configure")
async def configure_ai_agent(request: AIConfigureRequest):
    """
    Reconfigure the AI agent with a new provider and API key.
    """
    try:
        from app.main import ai_agent
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        await ai_agent.reconfigure(
            provider=request.provider,
            api_key=request.api_key,
            model=request.model
        )
        
        return {"success": True, "message": f"Successfully reconfigured to {request.provider}"}
        
    except Exception as e:
        logger.error(f"AI reconfiguration failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/chat")
async def chat_with_ai(request: AITaskRequest):
    """
    Chat with AI assistant (conversation mode).
    Uses memory for context-aware responses.
    """
    try:
        from app.main import ai_agent, mem0_service
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        # Search relevant memories
        relevant_memories = []
        if mem0_service:
            relevant_memories = await mem0_service.search_memory(
                query=request.task,
                user_id=request.user_id,
                limit=3
            )
        
        # Add memories to context
        context = request.context or {}
        context["relevant_memories"] = relevant_memories
        
        # Execute chat task
        result = await ai_agent.execute_task(
            task=request.task,
            context=context
        )
        
        # Store new memory
        if mem0_service and result["success"]:
            await mem0_service.add_memory(
                messages=[
                    {"role": "user", "content": request.task},
                    {"role": "assistant", "content": result["output"]},
                ],
                user_id=request.user_id,
                metadata={"type": "chat"}
            )
        return AITaskResponse(
            success=result["success"],
            output=result.get("output"),
            error=result.get("error")
        )
        
    except Exception as e:
        logger.error(f"Chat failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/resolve-url", response_model=ResolveURLResponse)
async def resolve_url(request: ResolveURLRequest):
    """
    Resolve a natural language query to a direct URL using LLM.
    
    This is used by Auto-URL mode to convert queries like
    "generate gpg keys on github" into direct URLs like
    "https://github.com/settings/keys"
    """

    try:
        from app.main import ai_agent
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        # Create a specific prompt for URL resolution
        url_resolution_prompt = f"""Convert this natural language query into a single, direct URL.

Query: {request.query}

Instructions:
1. Interpret the user's intent
2. Identify the specific webpage or resource they want to access
3. Construct the exact URL that leads to that resource
4. Return ONLY the URL, nothing else

Example:
Query: "generate gpg keys on github"
URL: https://github.com/settings/keys

Now resolve this query: {request.query}
Return only the URL:"""

        print('[SSW] resolution-prompt', url_resolution_prompt)
        # Execute task with URL resolution context (simple LLM call, no tools needed)
        result = await ai_agent.execute_task(
            task=url_resolution_prompt,
            context={"mode": "url_resolution", "task_type": "resolve_url"},
            use_tools=False
        )
        
        if not result["success"]:
            raise HTTPException(
                status_code=500, 
                detail=result.get("error", "Failed to resolve URL")
            )
        
        # Extract URL from result
        output = result.get("output", "").strip()
        
        # Clean up the output - remove markdown code blocks if present
        if output.startswith("```"):
            lines = output.split("\n")
            output = "\n".join(lines[1:-1]) if len(lines) > 2 else output
        output = output.strip()
        
        # Remove any leading/trailing quotes
        if output.startswith('"') and output.endswith('"'):
            output = output[1:-1]
        if output.startswith("'") and output.endswith("'"):
            output = output[1:-1]
        
        # Default steps for UI visualization
        steps = [
            "Interpreting request",
            "Finding destination",
            "Constructing URL"
        ]
        
        return ResolveURLResponse(
            url=output,
            steps=steps
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"URL resolution failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/analyze-logs")
async def analyze_logs(request: dict):
    """
    Analyze Kibana logs using LLM with function-calling.
    
    This endpoint:
    1. Receives logs extracted from Kibana
    2. Uses LLM function-calling to filter CRITICAL logs
    3. Generates a human-readable analysis summary
    4. Returns filtered logs and summary to frontend
    """
    try:
        from app.main import ai_agent
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        # Extract request data
        request_id = request.get('request_id', 'unknown')
        container_id = request.get('container_id')
        query = request.get('query', 'Analyze logs for failures')
        logs = request.get('logs', [])
        
        logger.info(f"[{request_id}] Log analysis request: container={container_id}, logs={len(logs)}, query={query}")
        
        # Validate logs
        if not logs:
            raise HTTPException(status_code=400, detail="No logs provided")
        
        # Create log analysis service with AI agent's LLM
        log_service = LogAnalysisService(llm=ai_agent.llm)
        
        # Perform analysis
        result = await log_service.analyze(
            logs=logs,
            query=query,
            request_id=request_id
        )
        
        logger.info(f"[{request_id}] Analysis complete: {len(result['critical_logs'])} critical logs found")
        
        return {
            "request_id": request_id,
            "critical_logs": result["critical_logs"],
            "analysis_summary": result["analysis_summary"],
            "steps": result.get("steps", [])
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Log analysis failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/agent-execute", response_model=AgentExecuteResponse)
async def agent_execute(request: AgentExecuteRequest):
    """
    Execute multi-tool agent with static tools and webpage snapshot tools.
    
    This endpoint uses a two-phase approach for vision support:
    1. Phase 1: Agent gathers data (screenshots, logs) using tools
    2. Phase 2: Vision-enabled LLM analyzes the gathered images
    """
    try:
        from app.main import ai_agent
        from app.services.snapshot_tools import create_snapshot_tools, get_screenshot_cache, clear_screenshot_cache
        from app.services.log_analysis_tools import create_log_analysis_tool
        from langchain_core.messages import HumanMessage, SystemMessage
        
        if not ai_agent:
            raise HTTPException(status_code=503, detail="AI service not initialized")
        
        # Validate prompt is not empty
        if not request.prompt or not request.prompt.strip():
            logger.warning("Agent execute request received with empty prompt")
            raise HTTPException(
                status_code=400, 
                detail="Prompt cannot be empty. Please provide a task or question for the agent to execute."
            )
        
        prompt_preview = request.prompt[:50] + "..." if len(request.prompt) > 50 else request.prompt
        logger.info(f"Agent execute request: prompt={prompt_preview}, static_tools={request.static_tools}, snapshot_tools={len(request.snapshot_tools)}, logs={len(request.logs) if request.logs else 0}")
        
        # Clear any previous screenshots
        clear_screenshot_cache()
        
        all_tools = []
        
        # Create log analysis tool if logs are provided
        if request.logs and len(request.logs) > 0:
            log_tool = create_log_analysis_tool(logs=request.logs)
            all_tools.append(log_tool)
            logger.info(f"Created log analysis tool with {len(request.logs)} logs")
        
        # Create snapshot tools for each webpage
        for snapshot_tool in request.snapshot_tools:
            snapshot_tools_list = create_snapshot_tools(
                container_id=snapshot_tool.container_id,
                title=snapshot_tool.title,
                callback_port=request.callback_port,
                description=snapshot_tool.description,
                url=snapshot_tool.url
            )
            all_tools.extend(snapshot_tools_list)
        
        logger.info(f"Created total of {len(all_tools)} tools ({len([t for t in all_tools if 'screenshot' in t.name])} snapshot tools)")
        
        from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
        from langgraph.prebuilt import create_react_agent
        from langgraph.checkpoint.memory import MemorySaver
        
        # Build dynamic system prompt based on available tools
        tool_descriptions = []
        
        if any('extract_critical_logs' in t.name for t in all_tools):
            tool_descriptions.append("""
- extract_critical_logs: Filter logs to extract CRITICAL/ERROR entries based on severity levels and keywords.
  Use this to narrow down large log sets before analysis. Provide JSON input like:
  {{"severity_levels": ["CRITICAL", "ERROR"], "keywords": ["failed", "timeout"]}}""")
        
        if any('screenshot' in t.name for t in all_tools):
            tool_descriptions.append("""
- get_screenshot_*: Capture screenshots of specific webpages. Each tool is labeled with context
  (e.g., "Grafana metrics dashboard", "Kibana log viewer"). Choose the appropriate tool based on
  what information you need. For example:
  * Use Grafana/metrics tools when analyzing performance or resource usage
  * Use Kibana/log tools when investigating errors or events
  * Use the tool description to understand what each webpage contains
  
  IMPORTANT: When you capture screenshots, they will be automatically analyzed visually.
  Just capture the relevant screenshots and I will analyze them for you.""")
        
        tools_section = "\n".join(tool_descriptions) if tool_descriptions else "- No specific tools available"
        
        system_prompt = f"""You are an AI assistant that can analyze multiple webpages and logs simultaneously.

Available Tools:
{tools_section}

Instructions:
1. Read each tool's description carefully - it tells you what the webpage/data contains
2. Choose tools based on what information you need to answer the question
3. If you have logs, use extract_critical_logs first to filter before analyzing
4. If you need to correlate information (e.g., metrics + logs), use multiple tools
5. Capture screenshots of relevant webpages - they will be visually analyzed
6. Be concise and direct in your analysis

Remember: Tool descriptions contain important context about what each webpage shows. Use this to make intelligent decisions about which tools to invoke."""

        # Create localized checkpointer for this request
        checkpointer = MemorySaver()
        
        # Create LangGraph agent
        graph = create_react_agent(
            ai_agent.llm, 
            all_tools,
            checkpointer=checkpointer,
            prompt=system_prompt
        )
        
        # Phase 1: Run agent to gather data (screenshots, etc.)
        logger.info("Phase 1: Running agent to gather data...")
        config = {"configurable": {"thread_id": "agent_execute_request"}}
        result = await graph.ainvoke({"messages": [HumanMessage(content=request.prompt)]}, config=config)
        
        messages = result.get("messages", [])
        initial_output = messages[-1].content if messages else ""
        
        # Phase 2: Check if we have screenshots to analyze with vision
        screenshot_cache = get_screenshot_cache()
        
        if screenshot_cache:
            logger.info(f"Phase 2: Analyzing {len(screenshot_cache)} screenshots with vision model...")
            logger.info(f"Screenshot cache keys: {list(screenshot_cache.keys())}")
            logger.info(f"Initial output from Phase 1: {initial_output[:200]}..." if len(initial_output) > 200 else f"Initial output from Phase 1: {initial_output}")
            
            # Build multimodal message content for vision analysis
            # Include the initial analysis from Phase 1 for context
            context_text = f"""Based on the user's question: "{request.prompt}"

"""
            
            # Add Phase 1 analysis if available
            if initial_output and initial_output.strip():
                context_text += f"""Initial Analysis from Logs:
{initial_output}

---

Now, I have captured screenshots of the monitoring dashboards. Please analyze them visually and:
1. Correlate the visual metrics with the log analysis above
2. Identify any patterns or anomalies in the graphs/charts
3. Provide additional insights based on what you see
4. Combine your visual analysis with the log analysis to give a comprehensive response

"""
            else:
                context_text += "I have captured the following screenshots. Please analyze them and provide a detailed response:\n\n"
            
            message_content = [
                {
                    "type": "text",
                    "text": context_text
                }
            ]
            
            # Add each screenshot as an image
            for cache_key, data_url in screenshot_cache.items():
                # Add label for the image
                message_content.append({
                    "type": "text",
                    "text": f"\n--- Screenshot: {cache_key.split(':')[-1] if ':' in cache_key else cache_key} ---\n"
                })
                
                # Add the image (data URL format: data:image/png;base64,...)
                message_content.append({
                    "type": "image_url",
                    "image_url": {
                        "url": data_url,
                        "detail": "high"  # Use high detail for better analysis
                    }
                })
            
            # Add final instruction
            final_instruction = f"""

Please analyze these screenshots and answer the user's question: "{request.prompt}"

"""
            
            if initial_output and initial_output.strip():
                final_instruction += """IMPORTANT: Combine your visual analysis with the log analysis provided above. Your response should:
- Reference the specific errors/issues found in the logs
- Show how the visual metrics correlate with those issues
- Provide a unified, comprehensive analysis that connects logs and metrics
- Give actionable recommendations based on both data sources

"""
            
            final_instruction += """Provide specific observations about what you see in the dashboards/pages, including:
- Any critical issues, errors, or warnings visible
- Key metrics and their values (CPU, memory, disk, network, etc.)
- Trends or patterns you notice
- Time correlations between metrics spikes and log errors
- Recommendations based on what you observe

Return the response as plain text only.
Do NOT use Markdown.
Use explicit newline characters.
Insert a blank line between logical sections.
Use hyphens for lists.
"""
            
            message_content.append({
                "type": "text",
                "text": final_instruction
            })
            
            # Create vision message
            vision_message = HumanMessage(content=message_content)
            
            # Call the LLM with vision content
            try:
                vision_response = await ai_agent.llm.ainvoke([
                    SystemMessage(content="You are an expert at analyzing monitoring dashboards, logs, and metrics. Provide detailed, actionable insights based on visual analysis."),
                    vision_message
                ])
                
                output = vision_response.content if hasattr(vision_response, 'content') else str(vision_response)
                
                # Log the output for debugging
                output_preview = output[:200] + "..." if len(output) > 200 else output
                logger.info(f"Vision analysis complete. Output length: {len(output)}, Preview: {output_preview}")
                
                # Validate output is not empty
                if not output or not output.strip():
                    logger.warning("Vision analysis returned empty output, falling back to initial output")
                    output = initial_output or "Analysis completed but no output was generated."
                
            except Exception as vision_error:
                logger.error(f"Vision analysis failed: {vision_error}", exc_info=True)
                # Fall back to initial output if vision fails
                output = f"{initial_output}\n\n(Note: Visual analysis was attempted but encountered an error: {str(vision_error)})"
        else:
            # No screenshots captured, use initial output
            output = initial_output
        
        # Handle list-typed output from some models
        if isinstance(output, list):
            output_str = ""
            for part in output:
                if isinstance(part, dict) and "text" in part:
                    output_str += part["text"]
                elif isinstance(part, str):
                    output_str += part
            output = output_str
            logger.info(f"Converted list output to string, length: {len(output)}")
        
        # Final validation before returning
        if not output or not str(output).strip():
            logger.error("Final output is empty! This should not happen.")
            output = "Error: Analysis completed but no output was generated. Please check the logs for details."
        
        output_preview = str(output)[:200] + "..." if len(str(output)) > 200 else str(output)
        logger.info(f"Agent execution complete. Final output length: {len(str(output))}, Preview: {output_preview}")
        
        # Clean up screenshot cache
        clear_screenshot_cache()
        
        return AgentExecuteResponse(output=output)
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Agent execution failed: {e}", exc_info=True)
        # Clean up on error
        try:
            from app.services.snapshot_tools import clear_screenshot_cache
            clear_screenshot_cache()
        except:
            pass
        return AgentExecuteResponse(output="", error=str(e))