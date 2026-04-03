# Python AI Sidecar - FastAPI Server
# Provides AI analysis endpoints for the Swift browser shell
# IPC FLOW: Swift URLSession -> HTTP Request -> FastAPI -> AI Processing -> JSON Response

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, Dict, Any
from contextlib import asynccontextmanager
import logging
import sys
import os

# Import routes and services
from app.routes import ai_routes, browser_routes, memory_routes
from app.services.ai_agent import get_ai_agent, reconfigure_ai_agent
from app.services.mem0_service import Mem0Service
from app.services.skill_registry import get_registry
from app.services.plugins import discover_plugins
from app.config import *

# =============================================================================
# Configuration
# =============================================================================

# Configure logging to stream to stdout (visible in terminal)
logging.basicConfig(
    level=logging.INFO,
    format="[Sidecar] %(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Global service instances
ai_agent = None
mem0_service = None

# =============================================================================
# Application Lifespan
# =============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan manager.
    Initializes services on startup and cleans up on shutdown.
    """
    global ai_agent, mem0_service
    
    logger.info("Initializing AI services...")
    
    # Initialize singleton AI Agent
    ai_agent = await get_ai_agent()
    
    # Initialize Mem0 memory service
    mem0_service = Mem0Service()

    ## lets only initialise after user has configured API-Keys. 
    # await mem0_service.initialize()
    
    logger.info("AI services initialized successfully")
    
    # Register plugins with the skill registry
    await register_plugins()
    
    # Auto-configure if API key is available
    await auto_configure_on_startup()
    
    # Initialize widget services (scheduler, stores)
    from app.routes.widget_routes import init_widget_services, shutdown_widget_services
    init_widget_services()
    logger.info("Widget services initialized (scheduler started)")
    
    yield
    
    # Cleanup on shutdown
    logger.info("Shutting down AI services...")
    shutdown_widget_services()
    if ai_agent:
        await ai_agent.cleanup()
    if mem0_service:
        await mem0_service.cleanup()

async def register_plugins():
    """
    Automatically discover and register all available plugins with the skill registry.
    This makes plugins and their skills available to the agent system.
    """
    try:
        logger.info("Auto-discovering and registering plugins...")
        registry = get_registry()
        
        # Discover all plugin getter functions
        plugin_getters = discover_plugins()
        
        if not plugin_getters:
            logger.warning("No plugins discovered in plugins directory")
            return
        
        # Call each getter to instantiate plugins and register them
        registered_count = 0
        for plugin_getter in plugin_getters:
            try:
                plugin = plugin_getter()
                registry.register_plugin(plugin)
                logger.info(f"Registered plugin: {plugin.plugin_id} with {len(plugin.skills)} skills")
                registered_count += 1
            except Exception as e:
                logger.error(f"Failed to register plugin from {plugin_getter.__name__}: {e}")
        
        logger.info(f"Successfully registered {registered_count}/{len(plugin_getters)} plugins")
    except Exception as e:
        logger.error(f"Failed to register plugins: {e}")
        raise

async def auto_configure_on_startup():
    """
    Auto-configure AI services on startup if credentials are available.
    Checks for stored API keys and automatically configures the agent.
    """
    global ai_agent, mem0_service
    
    try:
        # Check for environment variables first
        provider = os.getenv("AI_PROVIDER")
        api_key = os.getenv("AI_API_KEY") or os.getenv("OPENAI_API_KEY")
        model = os.getenv("AI_MODEL")
        
        if api_key and provider:
            logger.info(f"[Auto-Configure] Found API credentials in environment, configuring {provider}...")
            
            # Configure AI Agent singleton
            await reconfigure_ai_agent(
                provider=provider,
                api_key=api_key,
                model=model
            )
            
            # Configure Mem0 Service
            if mem0_service:
                await mem0_service.reconfigure(
                    provider=provider,
                    api_key=api_key,
                    model=model
                )
            
            # Wire transcription service if OpenAI
            if provider.lower() == "openai":
                try:
                    from openai import AsyncOpenAI
                    from app.services.transcription_service import set_openai_client
                    set_openai_client(AsyncOpenAI(api_key=api_key))
                    logger.info("[Auto-Configure] Transcription service wired with OpenAI client")
                except Exception as te:
                    logger.warning(f"[Auto-Configure] Could not wire transcription client: {te}")
            
            logger.info(f"[Auto-Configure] Successfully configured all services to {provider}")
        else:
            # Try OPENAI_API_KEY directly for transcription even without full AI config
            openai_key = os.getenv("OPENAI_API_KEY")
            if openai_key:
                try:
                    from openai import AsyncOpenAI
                    from app.services.transcription_service import set_openai_client
                    set_openai_client(AsyncOpenAI(api_key=openai_key))
                    logger.info("[Auto-Configure] Transcription service wired from OPENAI_API_KEY")
                except Exception as te:
                    logger.warning(f"[Auto-Configure] Could not wire transcription client: {te}")
            logger.info("[Auto-Configure] No full AI credentials found, waiting for manual configuration")
    except Exception as e:
        logger.warning(f"[Auto-Configure] Failed to auto-configure on startup: {e}")

# =============================================================================
# FastAPI App
# =============================================================================

app = FastAPI(
    title="Bowser AI Sidecar",
    description="Local AI agent for the Bowser browser shell",
    version="1.0.0",
    lifespan=lifespan,
)

# Enable CORS for local Swift client
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for local development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# =============================================================================
# Request/Response Models
# =============================================================================

class AnalyzeRequest(BaseModel):
    """Request body for /analyze endpoint"""
    content: str

class AnalyzeResponse(BaseModel):
    """Response body from /analyze endpoint"""
    result: str
    timestamp: str

class HealthResponse(BaseModel):
    """Response body from /health endpoint"""
    status: str
    version: str
    timestamp: str

class ConfigureRequest(BaseModel):
    """Request model for unified service configuration"""
    provider: str
    api_key: str
    model: Optional[str] = None

# =============================================================================
# Endpoints
# =============================================================================

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint for sidecar liveness.
    The Swift app calls this on startup to verify connectivity.
    """
    logger.info("Health check requested")
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        timestamp=datetime.utcnow().isoformat()
    )


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze_content(request: AnalyzeRequest):
    """
    Analyze content using AI.
    
    This is a stub endpoint that will be expanded with actual AI capabilities.
    Currently returns a placeholder analysis result.
    
    IPC FLOW:
    1. Swift app sends POST request with content (URL, page text, etc.)
    2. This endpoint processes the content
    3. Returns analysis result as JSON
    4. Swift app displays result in sidebar
    """
    logger.info(f"Analyze requested for content: {request.content[:50]}...")
    
    # Stub AI analysis - replace with actual AI processing
    # Examples: summarization, entity extraction, sentiment analysis
    try:
        # Simulate AI processing
        analysis_result = f"Analysis complete for: {request.content[:100]}"
        
        # In a real implementation, you would:
        # 1. Parse the content (URL, HTML, text)
        # 2. Call an AI model (local or API)
        # 3. Return structured analysis
        
        # Example with Ollama (uncomment to use):
        # import ollama
        # response = ollama.chat(
        #     model='llama3',
        #     messages=[{'role': 'user', 'content': f'Summarize this: {request.content}'}]
        # )
        # analysis_result = response['message']['content']
        
        logger.info("Analysis completed successfully")
        return AnalyzeResponse(
            result=analysis_result,
            timestamp=datetime.utcnow().isoformat()
        )
        
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/configure")
async def configure_services(request: ConfigureRequest):
    """
    Unified configuration endpoint to set up both AI Agent and Memory Service.
    """
    try:
        global mem0_service
            
        # Configure AI Agent singleton
        await reconfigure_ai_agent(
            provider=request.provider,
            api_key=request.api_key,
            model=request.model
        )
        
        # Configure Mem0 Service
        if mem0_service:
            await mem0_service.reconfigure(
                provider=request.provider,
                api_key=request.api_key,
                model=request.model
            )

        # Wire transcription service for OpenAI-compatible providers
        transcription_status = "skipped"
        if request.provider in ("openai",) and request.api_key:
            try:
                from openai import AsyncOpenAI
                from app.services.transcription_service import set_openai_client
                set_openai_client(AsyncOpenAI(api_key=request.api_key))
                transcription_status = "reconfigured"
                logger.info("[Configure] Transcription service wired with OpenAI client")
            except Exception as te:
                transcription_status = f"failed: {te}"
                logger.warning(f"[Configure] Could not wire transcription client: {te}")

        return {
            "success": True, 
            "message": f"Successfully reconfigured all services to {request.provider}",
            "services": {
                "ai_agent": "reconfigured",
                "mem0": "reconfigured",
                "transcription": transcription_status
            }
        }
    except Exception as e:
        logger.error(f"Unified reconfiguration failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Register routes
app.include_router(ai_routes.router, prefix="/api/ai", tags=["AI"])
app.include_router(browser_routes.router, prefix="/api/browser", tags=["Browser"])
app.include_router(memory_routes.router, prefix="/api/memory", tags=["Memory"])

# Register Plan Mode routes
from app.routes import plan_routes
app.include_router(plan_routes.router, prefix="/api/plan", tags=["Plan"])

# Register Generative UI routes
from app.routes import generative_ui_routes
app.include_router(generative_ui_routes.router, prefix="/api/generative-ui", tags=["Generative UI"])

# Register Redactor routes
from app.routes import redactor_routes
app.include_router(redactor_routes.router, prefix="/api/redactor", tags=["Redactor"])

# Register Agent Mode routes
from app.routes import agent_routes
app.include_router(agent_routes.router, prefix="/api/agent", tags=["Agent"])

# Register Widget routes
from app.routes import widget_routes
app.include_router(widget_routes.router, prefix="/api/widgets", tags=["Widgets"])

# Register OAuth routes
from app.routes import oauth_routes
app.include_router(oauth_routes.router, prefix="/api/oauth", tags=["OAuth"])

# Register Transcription routes (meeting recorder + voice-to-text)
from app.routes import transcribe_routes
app.include_router(transcribe_routes.router, prefix="/api/transcribe", tags=["Transcribe"])

# Register Meeting Summary routes
from app.routes import meeting_summary_routes
app.include_router(meeting_summary_routes.router, prefix="/api/ai/meeting-summary", tags=["Meeting Summary"])

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "Bowser AI Sidecar",
        "version": "1.0.0",
        "endpoints": {
            "/health": "GET - Health check",
            "/analyze": "POST - Analyze content",
            "/api/configure": "POST - Configure AI services",
            "/api/ai": "AI routes",
            "/api/browser": "Browser routes",
            "/api/memory": "Memory routes"
        }
    }

# =============================================================================
# Development Server
# =============================================================================

if __name__ == "__main__":
    import sys
    import uvicorn
    import asyncio
    
    # Check if we should use vsock mode (VM environment)
    use_vsock = "--vsock" in sys.argv
    port = 8765
    
    # Parse port argument
    if "--port" in sys.argv:
        try:
            port_idx = sys.argv.index("--port")
            port = int(sys.argv[port_idx + 1])
        except (IndexError, ValueError):
            logger.warning("Invalid --port argument, using default 8765")
    
    if use_vsock:
        logger.info("Starting Bowser AI Sidecar in VM mode (vsock)...")
        logger.info(f"Listening on vsock port {port}")
        
        # Use vsock transport
        from app.vsock_transport import serve_vsock
        asyncio.run(serve_vsock(app, port=port))
    else:
        logger.info("Starting Bowser AI Sidecar in dev mode (TCP)...")
        logger.info(f"Listening on http://localhost:{port}")
        
        uvicorn.run(
            "app.main:app",
            host="127.0.0.1",
            port=port,
            reload=True,  # Enable hot reload for development
            log_level="info"
        )
