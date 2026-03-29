"""
OAuth Routes for Gmail Plugin
Handles OAuth 2.0 flow for Gmail authentication via a WKWebView popup sheet.

Two completion paths (belt-and-suspenders):

  Fast path (WKWebView intercepts redirect before it loads):
    1. POST /gmail/start  -> {auth_url, state}
    2. WKWebView decidePolicyFor intercepts redirect URL
    3. Frontend extracts code+state, calls POST /gmail/exchange
    4. Backend exchanges code for token, stores on session

  Fallback path (redirect actually loads):
    1. POST /gmail/start  -> {auth_url, state}
    2. Google redirects to GET /gmail/callback?code=...&state=...
    3. Backend exchanges code for token, stores on session
    4. Returns HTML that calls window.webkit.messageHandlers.oauthComplete
    5. WKWebView's WKScriptMessageHandler signals completion to Swift
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

# state -> {"session_id": str, "auth_id": str, "flow": Flow}
_oauth_states: Dict[str, Dict[str, Any]] = {}

# state -> True once _exchange_and_store completes successfully.
# Polled by GET /gmail/status/{state} from the Swift frontend.
_oauth_completed: Dict[str, bool] = {}

GMAIL_SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
]

# For "installed" app types Google accepts http://localhost:<any-port>.
# Point it at our own server so the GET callback works as a fallback.
REDIRECT_URI = "http://localhost:8765/api/oauth/gmail/callback"

_CREDENTIALS_DEFAULT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "secrets", "credentials.json")
)


# =============================================================================
# Request / Response Models
# =============================================================================

class OAuthStartRequest(BaseModel):
    session_id: str
    auth_id: str = "gmail_auth"

class OAuthStartResponse(BaseModel):
    auth_url: str
    state: str

class OAuthExchangeRequest(BaseModel):
    code: str
    state: str

class OAuthExchangeResponse(BaseModel):
    status: str
    error: Optional[str] = None


# =============================================================================
# Helpers
# =============================================================================

def _get_client_config() -> Dict[str, Any]:
    """
    Load OAuth client config.
    Resolution: OAUTH_CLIENT env var -> secrets/credentials.json
    """
    path = os.getenv("OAUTH_CLIENT") or _CREDENTIALS_DEFAULT
    if not os.path.exists(path):
        raise ValueError(
            f"OAuth credentials file not found at '{path}'. "
            "Place credentials.json in the secrets/ directory or set OAUTH_CLIENT."
        )
    with open(path, "r") as f:
        return json.load(f)


def _exchange_and_store(code: str, state: str) -> str:
    """
    Exchange an authorization code for tokens and store the access token
    on the agent session.  Returns the session_id on success.

    Shared by both POST /exchange (fast path) and GET /callback (fallback).

    We reuse the original Flow object from _oauth_states so that the PKCE
    code_verifier generated during authorization_url() is present for fetch_token().
    """
    state_data = _oauth_states.pop(state, None)
    if not state_data:
        raise ValueError("Invalid or expired state token")

    session_id = state_data["session_id"]
    auth_id = state_data["auth_id"]
    flow = state_data["flow"]  # reuse — preserves code_verifier

    flow.fetch_token(code=code)

    access_token = flow.credentials.token
    logger.info("Obtained tokens for session %s", session_id)

    session_store = get_session_store()
    session = session_store.get_session(session_id)
    if not session:
        raise ValueError(f"Session not found: {session_id}")

    context_artifact = session.get("context_artifact")
    if not context_artifact:
        raise ValueError(f"Context artifact not found for session {session_id}")

    if not hasattr(context_artifact, "auth"):
        context_artifact.auth = {}

    context_artifact.auth[auth_id] = AuthEntryModel(
        strategy_used="oauth",
        value=access_token,
        valid=True,
    )
    session_store.update_session(session_id, {"context_artifact": context_artifact})

    # Mark as completed so the Swift poller can detect it
    _oauth_completed[state] = True

    logger.info("OAuth exchange completed for session %s", session_id)
    return session_id


# =============================================================================
# Endpoints
# =============================================================================

@router.post("/gmail/start", response_model=OAuthStartResponse)
async def start_gmail_oauth(request: OAuthStartRequest):
    """Return the Google authorization URL for the frontend to open."""
    try:
        client_config = _get_client_config()
        state = str(uuid.uuid4())

        flow = Flow.from_client_config(
            client_config,
            scopes=GMAIL_SCOPES,
            redirect_uri=REDIRECT_URI,
        )
        auth_url, _ = flow.authorization_url(
            access_type="offline",
            include_granted_scopes="true",
            state=state,
            prompt="consent",
        )

        # Store the flow object — its code_verifier must survive until fetch_token()
        _oauth_states[state] = {
            "session_id": request.session_id,
            "auth_id": request.auth_id,
            "flow": flow,
        }

        logger.info(
            "Started OAuth flow for session %s, state: %s",
            request.session_id, state,
        )
        return OAuthStartResponse(auth_url=auth_url, state=state)

    except Exception as exc:
        logger.error("Error starting OAuth flow: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


@router.get("/gmail/status/{state}")
async def get_oauth_status(state: str):
    """
    Polled by the Swift OAuthSheet every second to detect completion.
    Returns {"completed": true} once _exchange_and_store has run successfully.
    Cleans up after being read as completed so memory doesn't grow unbounded.
    """
    completed = _oauth_completed.pop(state, False)
    pending = state in _oauth_states
    return {"completed": completed, "pending": pending}


@router.post("/gmail/exchange", response_model=OAuthExchangeResponse)
async def exchange_gmail_code(request: OAuthExchangeRequest):
    """
    Fast path: WKWebView intercepted the redirect, extracted code+state,
    and POSTs them here for server-side token exchange.
    """
    try:
        _exchange_and_store(request.code, request.state)
        return OAuthExchangeResponse(status="success")
    except Exception as exc:
        logger.error("Error exchanging OAuth code: %s", exc)
        return OAuthExchangeResponse(status="failed", error=str(exc))


@router.get("/gmail/callback")
async def gmail_oauth_callback(
    code: str = Query(..., description="Authorization code from Google"),
    state: str = Query(..., description="State token for CSRF protection"),
):
    """
    Fallback path: Google actually redirected the WKWebView here.

    Exchanges the code server-side, then returns a small HTML page whose
    JavaScript calls window.webkit.messageHandlers.oauthComplete to signal
    completion back to the Swift WKWebView.
    """
    try:
        _exchange_and_store(code, state)
        logger.info("GET callback exchanged code successfully (fallback path)")

        return HTMLResponse(content="""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Authenticated</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif;
         display: flex; justify-content: center; align-items: center;
         height: 100vh; margin: 0;
         background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
  .box { text-align: center; background: white; padding: 40px 60px;
         border-radius: 16px; box-shadow: 0 10px 40px rgba(0,0,0,.2); }
</style></head><body>
<div class="box">
  <div style="font-size:64px">&#9989;</div>
  <h2>Authentication Successful</h2>
  <p id="msg">Closing&hellip;</p>
</div>
<script>
  try {
    window.webkit.messageHandlers.oauthComplete.postMessage({status:"success"});
  } catch(e) {
    document.getElementById("msg").textContent =
      "You can close this window and return to Bowser.";
  }
</script>
</body></html>""")

    except Exception as exc:
        logger.error("Error in GET callback: %s", exc)
        return HTMLResponse(content=f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Error</title>
<style>
  body {{ font-family: -apple-system, system-ui, sans-serif;
         display: flex; justify-content: center; align-items: center;
         height: 100vh; margin: 0;
         background: linear-gradient(135deg, #ff6b6b 0%, #ee5a24 100%); }}
  .box {{ text-align: center; background: white; padding: 40px 60px;
         border-radius: 16px; box-shadow: 0 10px 40px rgba(0,0,0,.2);
         max-width: 500px; }}
  .err {{ background: #f8f8f8; padding: 12px; border-radius: 8px;
          margin-top: 16px; font-family: monospace; font-size: 12px;
          color: #c0392b; }}
</style></head><body>
<div class="box">
  <div style="font-size:64px">&#10060;</div>
  <h2>Authentication Failed</h2>
  <div class="err">{exc}</div>
  <p style="margin-top:20px">Please close this window and try again.</p>
</div>
<script>
  try {{
    window.webkit.messageHandlers.oauthComplete.postMessage({{status:"failed",error:"{exc}"}});
  }} catch(e) {{}}
</script>
</body></html>""", status_code=500)
