"""
Gmail Plugin - V1
Provides skills for interacting with Gmail via OAuth
"""

from typing import Any, Dict
from app.models.agent_schemas import Plugin, Skill, AuthRequirement, AuthStrategy, DataPacket


# =============================================================================
# Executor Functions
# =============================================================================

async def _list_inbox_emails(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    List recent emails from Gmail inbox
    
    Returns:
        DataPacket with schema {"subject", "from", "date", "snippet"}
    """
    try:
        from googleapiclient.discovery import build
        from google.oauth2.credentials import Credentials
        
        # Get access token from auth context
        access_token = auth.get("gmail_access_token", "")
        if not access_token:
            return DataPacket.error(
                "gmail_access_token is required in auth context",
                code="AUTH_ERROR"
            )
        
        # Create credentials object
        creds = Credentials(token=access_token)
        
        # Build Gmail service
        service = build('gmail', 'v1', credentials=creds)
        
        # Get limit parameter
        limit = params.get("limit", 5)
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = 5
        
        # List messages from inbox
        results = service.users().messages().list(
            userId='me',
            labelIds=['INBOX'],
            maxResults=limit
        ).execute()
        
        messages = results.get('messages', [])
        
        if not messages:
            return DataPacket(
                schema_def={
                    "subject": "string",
                    "from": "string",
                    "date": "string",
                    "snippet": "string"
                },
                rows=[]
            )
        
        # Fetch full message details
        rows = []
        for msg in messages:
            msg_data = service.users().messages().get(
                userId='me',
                id=msg['id'],
                format='full'
            ).execute()
            
            # Extract headers
            headers = msg_data.get('payload', {}).get('headers', [])
            subject = next((h['value'] for h in headers if h['name'].lower() == 'subject'), 'No Subject')
            from_addr = next((h['value'] for h in headers if h['name'].lower() == 'from'), 'Unknown')
            date = next((h['value'] for h in headers if h['name'].lower() == 'date'), '')
            
            # Get snippet
            snippet = msg_data.get('snippet', '')
            
            rows.append({
                "subject": subject[:100],  # Truncate long subjects
                "from": from_addr[:80],
                "date": date,
                "snippet": snippet[:200]  # Truncate long snippets
            })
        
        return DataPacket(
            schema_def={
                "subject": "string",
                "from": "string",
                "date": "string",
                "snippet": "string"
            },
            rows=rows
        )
        
    except Exception as e:
        return DataPacket.error(
            str(e),
            code="GMAIL_ERROR",
            details={"limit": params.get("limit")}
        )


def get_gmail_plugin() -> Plugin:
    """
    Returns the Gmail plugin with all skills
    """
    return Plugin(
        plugin_id="gmail",
        name="Gmail Plugin",
        version="1.0.0",
        description="Skills for interacting with Gmail via OAuth",
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
                        oauth_scopes=["https://www.googleapis.com/auth/gmail.readonly"]
                    )
                ]
            )
        ],
        skills=[
            # Skill: List Inbox Emails
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
                            "default": 5
                        }
                    },
                    "required": []
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "subject": {
                            "type": "string",
                            "description": "Email subject"
                        },
                        "from": {
                            "type": "string",
                            "description": "Sender email address"
                        },
                        "date": {
                            "type": "string",
                            "description": "Email date"
                        },
                        "snippet": {
                            "type": "string",
                            "description": "Email preview snippet"
                        }
                    }
                },
                output_type="table",
                execution_type="sdk",
                execute=_list_inbox_emails,
                domains=["gmail", "email", "google", "mail"],
                verbs=["list", "get", "fetch", "show", "retrieve"],
                nouns=["emails", "messages", "inbox", "mail"],
                output_types=["table", "list"]
            )
        ]
    )
