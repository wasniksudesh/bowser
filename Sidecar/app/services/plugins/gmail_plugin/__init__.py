"""
Gmail Plugin - V1
Provides skills for interacting with Gmail via OAuth
"""

import base64
from email.mime.text import MIMEText
from typing import Any, Dict
from app.models.agent_schemas import Plugin, Skill, AuthRequirement, AuthStrategy, DataPacket

GMAIL_SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
]


# =============================================================================
# Helpers
# =============================================================================

def _build_gmail_service(access_token: str):
    from googleapiclient.discovery import build
    from google.oauth2.credentials import Credentials

    creds = Credentials(token=access_token)
    return build("gmail", "v1", credentials=creds)


def _get_access_token(auth: Dict[str, Any]) -> str:
    return auth.get("gmail_access_token", "")


# =============================================================================
# Executor Functions
# =============================================================================

async def _list_inbox_emails(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    List recent emails from Gmail inbox.

    Returns:
        DataPacket with schema {"subject", "from", "date", "snippet"}
    """
    try:
        access_token = _get_access_token(auth)
        if not access_token:
            return DataPacket.error(
                "gmail_access_token is required in auth context",
                code="AUTH_ERROR",
            )

        service = _build_gmail_service(access_token)

        limit = params.get("limit", 5)
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = 5

        results = service.users().messages().list(
            userId="me",
            labelIds=["INBOX"],
            maxResults=limit,
        ).execute()

        messages = results.get("messages", [])
        if not messages:
            return DataPacket(
                schema_def={"subject": "string", "from": "string", "date": "string", "snippet": "string"},
                rows=[],
            )

        rows = []
        for msg in messages:
            msg_data = service.users().messages().get(
                userId="me", id=msg["id"], format="full"
            ).execute()

            headers = msg_data.get("payload", {}).get("headers", [])
            subject = next(
                (h["value"] for h in headers if h["name"].lower() == "subject"),
                "No Subject",
            )
            from_addr = next(
                (h["value"] for h in headers if h["name"].lower() == "from"),
                "Unknown",
            )
            date = next(
                (h["value"] for h in headers if h["name"].lower() == "date"),
                "",
            )
            snippet = msg_data.get("snippet", "")

            rows.append({
                "subject": subject[:100],
                "from": from_addr[:80],
                "date": date,
                "snippet": snippet[:200],
            })

        return DataPacket(
            schema_def={"subject": "string", "from": "string", "date": "string", "snippet": "string"},
            rows=rows,
        )

    except Exception as exc:
        return DataPacket.error(str(exc), code="GMAIL_ERROR", details={"limit": params.get("limit")})


async def _send_email(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Send an email via Gmail.

    Params:
        to      -- recipient email address (required)
        subject -- email subject line (required)
        body    -- plain-text body content (required)

    Returns:
        DataPacket with {"status", "message_id", "to"}
    """
    try:
        access_token = _get_access_token(auth)
        if not access_token:
            return DataPacket.error(
                "gmail_access_token is required in auth context",
                code="AUTH_ERROR",
            )

        to = params.get("to", "").strip()
        subject = params.get("subject", "").strip()
        body = params.get("body", "").strip()

        if not to:
            return DataPacket.error("'to' (recipient email) is required", code="PARAM_ERROR")
        if not subject:
            return DataPacket.error("'subject' is required", code="PARAM_ERROR")
        if not body:
            return DataPacket.error("'body' is required", code="PARAM_ERROR")

        service = _build_gmail_service(access_token)

        mime_message = MIMEText(body, "plain")
        mime_message["to"] = to
        mime_message["subject"] = subject

        raw = base64.urlsafe_b64encode(mime_message.as_bytes()).decode("utf-8")

        sent = service.users().messages().send(
            userId="me",
            body={"raw": raw},
        ).execute()

        message_id = sent.get("id", "")
        return DataPacket(
            schema_def={"status": "string", "message_id": "string", "to": "string"},
            rows=[{"status": "sent", "message_id": message_id, "to": to}],
        )

    except Exception as exc:
        return DataPacket.error(str(exc), code="GMAIL_SEND_ERROR", details={"to": params.get("to")})


# =============================================================================
# Plugin Definition
# =============================================================================

def get_gmail_plugin() -> Plugin:
    """Returns the Gmail plugin with all skills."""
    return Plugin(
        plugin_id="gmail",
        name="Gmail Plugin",
        version="1.1.0",
        description="Skills for reading and sending Gmail messages via OAuth",
        auth_requirements=[
            AuthRequirement(
                auth_id="gmail_auth",
                description="Gmail authentication via OAuth 2.0",
                strategies=[
                    AuthStrategy(
                        type="oauth",
                        context_key="gmail_access_token",
                        description="OAuth 2.0 access token for Gmail API",
                        oauth_provider="google",
                        oauth_scopes=GMAIL_SCOPES,
                    )
                ],
            )
        ],
        skills=[
            Skill(
                skill_id="listInboxEmails",
                name="List Inbox Emails",
                description="List recent emails from Gmail inbox",
                input_schema={
                    "type": "object",
                    "properties": {
                        "limit": {
                            "type": "integer",
                            "description": "Number of emails to retrieve (default: 5)",
                            "default": 5,
                        }
                    },
                    "required": [],
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "subject": {"type": "string", "description": "Email subject"},
                        "from": {"type": "string", "description": "Sender email address"},
                        "date": {"type": "string", "description": "Email date"},
                        "snippet": {"type": "string", "description": "Email preview snippet"},
                    },
                },
                output_type="table",
                execution_type="sdk",
                execute=_list_inbox_emails,
                domains=["gmail", "email", "google", "mail"],
                verbs=["list", "get", "fetch", "show", "retrieve"],
                nouns=["emails", "messages", "inbox", "mail"],
                output_types=["table", "list"],
            ),
            Skill(
                skill_id="sendEmail",
                name="Send Email",
                description=(
                    "Send an email via Gmail. "
                    "Accepts a recipient address (to), subject, and plain-text body. "
                    "The body can be derived from another skill's output, "
                    "e.g. a product description from HackerNews describeProduct."
                ),
                input_schema={
                    "type": "object",
                    "properties": {
                        "to": {
                            "type": "string",
                            "description": "Recipient email address",
                        },
                        "subject": {
                            "type": "string",
                            "description": "Email subject line",
                        },
                        "body": {
                            "type": "string",
                            "description": "Plain-text email body content",
                        },
                    },
                    "required": ["to", "subject", "body"],
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "status": {"type": "string", "description": "Send status"},
                        "message_id": {"type": "string", "description": "Gmail message ID"},
                        "to": {"type": "string", "description": "Recipient address"},
                    },
                },
                output_type="text",
                execution_type="sdk",
                execute=_send_email,
                domains=["gmail", "email", "google", "mail"],
                verbs=["send", "email", "compose", "write"],
                nouns=["email", "message", "mail"],
                output_types=["text", "table"],
            ),
        ],
    )
