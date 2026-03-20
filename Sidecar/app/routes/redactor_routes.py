"""
Redactor Routes - API endpoints for content redaction
"""

import logging
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.services.redactor_service import get_redactor_service

logger = logging.getLogger(__name__)
router = APIRouter()


class RedactRequest(BaseModel):
    """Request model for redaction"""
    type: Literal["text", "image"] = Field(..., description="Type of content to redact")
    content: str = Field(..., description="Content to redact (text or base64 image)")


class RedactResponse(BaseModel):
    """Response model for redaction"""
    type: Literal["text", "image"] = Field(..., description="Type of redacted content")
    content: str = Field(..., description="Redacted content")


@router.post("/process", response_model=RedactResponse)
async def process_content(request: RedactRequest) -> RedactResponse:
    """
    Process content for redaction (PII in text, faces in images)
    
    Args:
        request: RedactRequest with type and content
        
    Returns:
        RedactResponse with redacted content
        
    Raises:
        HTTPException: If redaction fails
    """
    try:
        service = get_redactor_service()
        
        if request.type == "text":
            redacted_content = service.process_text(request.content)
        elif request.type == "image":
            redacted_content = service.process_image(request.content)
        else:
            raise HTTPException(status_code=400, detail=f"Invalid type: {request.type}")
        
        return RedactResponse(type=request.type, content=redacted_content)
        
    except HTTPException:
        raise  # Re-raise HTTP exceptions as-is
    except Exception as e:
        logger.error(f"Redaction failed: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Redaction failed: {str(e)}")


@router.get("/status")
async def get_status():
    """Get redactor service status"""
    try:
        service = get_redactor_service()
        return {
            "status": "ok",
            "service": "redactor",
            "initialized": service is not None
        }
    except Exception as e:
        logger.error(f"Status check failed: {e}")
        return {
            "status": "error",
            "service": "redactor",
            "error": str(e)
        }
