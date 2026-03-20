"""
Memory Routes

Purpose: API endpoints for memory management (Mem0).
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import logging

logger = logging.getLogger(__name__)

router = APIRouter()

class MemoryAddRequest(BaseModel):
    """Request model for adding memory"""
    messages: List[Dict[str, str]]
    user_id: str
    metadata: Optional[Dict[str, Any]] = None

class MemorySearchRequest(BaseModel):
    """Request model for searching memory"""
    query: str
    user_id: str
    limit: int = 5

@router.post("/add")
async def add_memory(request: MemoryAddRequest):
    """Add new memory from conversation"""
    try:
        from app.main import mem0_service
        
        if not mem0_service:
            raise HTTPException(status_code=503, detail="Memory service not initialized")
        
        result = await mem0_service.add_memory(
            messages=request.messages,
            user_id=request.user_id,
            metadata=request.metadata
        )
        
        return result
        
    except Exception as e:
        logger.error(f"Failed to add memory: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/search")
async def search_memory(request: MemorySearchRequest):
    """Search relevant memories"""
    try:
        from app.main import mem0_service
        
        if not mem0_service:
            raise HTTPException(status_code=503, detail="Memory service not initialized")
        
        results = await mem0_service.search_memory(
            query=request.query,
            user_id=request.user_id,
            limit=request.limit
        )
        
        return {"results": results}
        
    except Exception as e:
        logger.error(f"Memory search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/all/{user_id}")
async def get_all_memories(user_id: str):
    """Get all memories for a user"""
    try:
        from app.main import mem0_service
        
        if not mem0_service:
            raise HTTPException(status_code=503, detail="Memory service not initialized")
        
        memories = await mem0_service.get_all_memories(user_id=user_id)
        
        return {"memories": memories}
        
    except Exception as e:
        logger.error(f"Failed to get memories: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/{memory_id}")
async def delete_memory(memory_id: str):
    """Delete a memory"""
    try:
        from app.main import mem0_service
        
        if not mem0_service:
            raise HTTPException(status_code=503, detail="Memory service not initialized")
        
        result = await mem0_service.delete_memory(memory_id=memory_id)
        
        return result
        
    except Exception as e:
        logger.error(f"Failed to delete memory: {e}")
        raise HTTPException(status_code=500, detail=str(e))
