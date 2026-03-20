"""
OAuth Routes for Gmail Plugin
Handles OAuth 2.0 flow for Gmail authentication
"""

import os
import json
import uuid
import logging
from typing import Dict, Any, Optional
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from google_auth_oauthlib.flow import Flow

from app.services.agent_service import get_session_store
from app.models.agent_schemas import AuthEntryModel

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory storage for OAuth state mappings and status
# state -> {"session_id": str, "auth_id": str, "status": "pending"|"success"|"failed", "error": Optional[str]}
_oauth_states: Dict[str, Dict[str, Any]] = {}

# Gmail OAuth scopes
GMAIL_SCOPES = ['https://www.googleapis.com/auth/gmail.readonly']


# =============================================================================
# Request/Response Models
# =============================================================================

class OAuthStartRequest(BaseModel):
    """Request to start OAuth flow"""
    session_id: str
    auth_id: str = "gmail_auth"  # Default to gmail_auth


class OAuthStartResponse(BaseModel):
    """Response with OAuth URL"""
    auth_url: str
    state: str


class OAuthStatusResponse(BaseModel):
    """Response with OAuth status"""
    status: str  # "pending", "success", "failed"
    error: Optional[str] = None


# =============================================================================
# Helper Functions
# =============================================================================

def get_client_config() -> Dict[str, Any]:
    """Load OAuth client configuration from OAUTH_CLIENT env var"""
    oauth_client_path = os.getenv("OAUTH_CLIENT")
    if not oauth_client_path:
        raise ValueError("OAUTH_CLIENT environment variable not set")
    
    if not os.path.exists(oauth_client_path):
        raise ValueError(f"OAuth client file not found: {oauth_client_path}")
    
    with open(oauth_client_path, 'r') as f:
        config = json.load(f)
    
    return config


def _error_html(message: str) -> str:
    """Generate error HTML page"""
    return f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Authentication Failed</title>
        <style>
            body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
                   display: flex; justify-content: center; align-items: center; height: 100vh; 
                   margin: 0; background: linear-gradient(135deg, #ff6b6b 0%, #ee5a24 100%); }}
            .container {{ text-align: center; background: white; padding: 40px 60px; 
                         border-radius: 16px; box-shadow: 0 10px 40px rgba(0,0,0,0.2); max-width: 500px; }}
            .error-icon {{ font-size: 64px; margin-bottom: 20px; }}
            h1 {{ color: #333; margin-bottom: 10px; }}
            p {{ color: #666; }}
            .error-detail {{ background: #f8f8f8; padding: 12px; border-radius: 8px; 
                            margin-top: 16px; font-family: monospace; font-size: 12px; color: #c0392b; }}
        </style>
    </head>
    <body>
        <div class="container">
            <div class="error-icon">❌</div>
            <h1>Authentication Failed</h1>
            <p>Something went wrong during authentication.</p>
            <div class="error-detail">{message}</div>
            <p style="margin-top: 20px;">Please close this window and try again.</p>
        </div>
    </body>
    </html>
    """


# =============================================================================
# OAuth Endpoints
# =============================================================================

@router.post("/gmail/start", response_model=OAuthStartResponse)
async def start_gmail_oauth(request: OAuthStartRequest):
    """
    Initiate Gmail OAuth flow
    
    1. Generate state token
    2. Create authorization URL
    3. Store state -> session_id mapping
    4. Return auth URL for frontend to open in browser
    """
    try:
        # Load client configuration
        client_config = get_client_config()
        
        # Generate unique state token
        state = str(uuid.uuid4())
        
        # Create OAuth flow
        flow = Flow.from_client_config(
            client_config,
            scopes=GMAIL_SCOPES,
            redirect_uri="http://localhost:8765/api/oauth/gmail/callback"
        )
        
        # Generate authorization URL
        auth_url, _ = flow.authorization_url(
            access_type='offline',
            include_granted_scopes='true',
            state=state,
            prompt='consent'  # Force consent to get refresh token
        )
        
        # Store state mapping
        _oauth_states[state] = {
            "session_id": request.session_id,
            "auth_id": request.auth_id,
            "status": "pending",
            "error": None
        }
        
        logger.info(f"Started OAuth flow for session {request.session_id}, state: {state}")
        
        return OAuthStartResponse(
            auth_url=auth_url,
            state=state
        )
        
    except Exception as e:
        logger.error(f"Error starting OAuth flow: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/gmail/callback")
async def gmail_oauth_callback(
    code: str = Query(..., description="Authorization code from Google"),
    state: str = Query(..., description="State token for CSRF protection")
):
    """
    OAuth callback endpoint (called by Google after user authorizes)
    
    1. Verify state token
    2. Exchange authorization code for access/refresh tokens
    3. Update session context with tokens
    4. Mark OAuth flow as complete
    """
    try:
        # Verify state exists
        if state not in _oauth_states:
            logger.error(f"Invalid state token: {state}")
            return HTMLResponse(content=_error_html("Invalid state token"), status_code=400)
        
        state_data = _oauth_states[state]
        session_id = state_data["session_id"]
        auth_id = state_data["auth_id"]
        
        logger.info(f"Processing OAuth callback for session {session_id}")
        
        # Load client configuration
        client_config = get_client_config()
        
        # Create OAuth flow
        flow = Flow.from_client_config(
            client_config,
            scopes=GMAIL_SCOPES,
            redirect_uri="http://localhost:8765/api/oauth/gmail/callback",
            state=state
        )
        
        # Exchange authorization code for tokens
        flow.fetch_token(code=code)
        
        # Get credentials
        credentials = flow.credentials
        access_token = credentials.token
        refresh_token = credentials.refresh_token
        
        logger.info(f"Successfully obtained tokens for session {session_id}")
        
        # Update session context with tokens
        session_store = get_session_store()
        session = session_store.get_session(session_id)
        
        if not session:
            logger.error(f"Session not found: {session_id}")
            state_data["status"] = "failed"
            state_data["error"] = "Session not found"
            return HTMLResponse(content=_error_html("Session not found"), status_code=404)
        
        # Get or create context artifact
        context_artifact = session.get("context_artifact")
        if not context_artifact:
            logger.error(f"Context artifact not found for session {session_id}")
            state_data["status"] = "failed"
            state_data["error"] = "Context artifact not found"
            return HTMLResponse(content=_error_html("Context artifact not found"), status_code=404)
        
        # Update auth entry with tokens
        if not hasattr(context_artifact, 'auth'):
            context_artifact.auth = {}
        
        context_artifact.auth[auth_id] = AuthEntryModel(
            strategy_used="oauth",
            value=access_token,
            valid=True
        )
        
        # Update session
        session_store.update_session(session_id, {
            "context_artifact": context_artifact
        })
        
        # Mark OAuth flow as successful
        state_data["status"] = "success"
        
        logger.info(f"OAuth flow completed successfully for session {session_id}")
        
        # Return success HTML page for the user
        return HTMLResponse(content="""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Authentication Successful</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
                       display: flex; justify-content: center; align-items: center; height: 100vh; 
                       margin: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
                .container { text-align: center; background: white; padding: 40px 60px; 
                             border-radius: 16px; box-shadow: 0 10px 40px rgba(0,0,0,0.2); }
                .checkmark { font-size: 64px; margin-bottom: 20px; }
                h1 { color: #333; margin-bottom: 10px; }
                p { color: #666; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="checkmark">✅</div>
                <h1>Authentication Successful!</h1>
                <p>You can close this window and return to Bowser.</p>
            </div>
        </body>
        </html>
        """)
        
    except Exception as e:
        logger.error(f"Error in OAuth callback: {e}")
        if state in _oauth_states:
            _oauth_states[state]["status"] = "failed"
            _oauth_states[state]["error"] = str(e)
        return HTMLResponse(content=_error_html(str(e)), status_code=500)


@router.get("/gmail/status/{state}", response_model=OAuthStatusResponse)
async def get_oauth_status(state: str):
    """
    Check OAuth flow status (polled by frontend)
    
    Returns:
        - "pending": OAuth flow in progress
        - "success": OAuth completed, tokens stored in session
        - "failed": OAuth failed with error
    """
    if state not in _oauth_states:
        raise HTTPException(status_code=404, detail="State not found")
    
    state_data = _oauth_states[state]
    
    return OAuthStatusResponse(
        status=state_data["status"],
        error=state_data.get("error")
    )
