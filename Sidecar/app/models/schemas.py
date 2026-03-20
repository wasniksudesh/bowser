"""
Pydantic Models

Purpose: Data models and schemas for API requests/responses.
"""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class BrowserTab(BaseModel):
    """Browser tab model"""
    id: str
    url: str
    title: str
    active: bool = False
    created_at: datetime = Field(default_factory=datetime.now)

class AIContext(BaseModel):
    """AI execution context"""
    url: Optional[str] = None
    dom_snapshot: Optional[str] = None
    user_input: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class Memory(BaseModel):
    """Memory model"""
    id: str
    user_id: str
    content: str
    metadata: Dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime

class AIResponse(BaseModel):
    """AI task response"""
    success: bool
    output: Optional[str] = None
    error: Optional[str] = None
    tokens_used: Optional[int] = None
    execution_time: Optional[float] = None

class LogAnalysisRequest(BaseModel):
    """Log analysis request"""
    request_id: str
    container_id: str
    web_content_view_id: int
    selected_tools: List[str]
    current_url: str
    query: str
    logs: List[Dict[str, Any]]

class LogAnalysisResponse(BaseModel):
    """Log analysis response"""
    request_id: str
    critical_logs: List[Dict[str, Any]]
    analysis_summary: str
    steps: List[str] = []
