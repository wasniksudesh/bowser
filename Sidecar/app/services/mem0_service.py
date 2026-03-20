"""
Mem0 Memory Service

Purpose: Manages short-term and long-term memory for AI conversations.
Provides context-aware memory for personalized interactions.
"""


import os
import logging
from typing import List, Dict, Any, Optional
from mem0 import Memory
from app.config import *

logger = logging.getLogger(__name__)

class Mem0Service:
    """
    Memory management service using Mem0.
    Handles user context, conversation history, and personalization.
    """
    
    def __init__(self, provider: Optional[str] = None, model: Optional[str] = None, api_key: Optional[str] = None):
        self.memory = None
        self.config = {}
        self._setup_config(provider, api_key, model)
        
    def _setup_config(self, provider: Optional[str] = None, api_key: Optional[str] = None, model: Optional[str] = None):
        """Generate Mem0 configuration based on provider and config.py"""
        
        # Determine LLM settings
        llm_provider = provider or LLM_CONFIG["provider"]
        llm_model = model or LLM_CONFIG["model"]
        llm_api_key = api_key or LLM_CONFIG["api_key"]

        # Determine Embedder settings - default to user-defined EMBEDDER_CONFIG if no overrides
        # But if a specific provider is passed to Mem0Service, we might want to align embedder?
        # Typically, user wants to configure them separately or together.
        # If provider is passed, we use it for both for consistency if requested.
        embedder_provider = provider or EMBEDDER_CONFIG["provider"]
        embedder_model = EMBEDDER_CONFIG["model"] # Keep default embedder model unless we want more complex mapping
        embedder_api_key = api_key or EMBEDDER_CONFIG["api_key"]

        # Map provider names to Mem0 supported providers
        if llm_provider == "claude":
            llm_provider = "anthropic"
        
        # Generate a dynamic collection name based on the embedder model to avoid dimension mismatch
        sanitized_model = embedder_model.replace("/", "_").replace("-", "_").lower()
        collection_name = f"bowser_memory_{sanitized_model}"
        
        self.config = {
            "llm": {
                "provider": llm_provider,
                "config": {
                    "model": llm_model,
                    "api_key": os.getenv(llm_api_key) if llm_api_key.isupper() else llm_api_key,
                }
            },
            "embedder": {
                "provider": embedder_provider,
                "config": {
                    "model": embedder_model,
                    "api_key": os.getenv(embedder_api_key) if embedder_api_key.isupper() else embedder_api_key,
                }
            },
            "vector_store": {
                "provider": "qdrant",
                "config": {
                    "collection_name": collection_name,
                    "path": VECTOR_STORE_PATH,
                }
            },
        }

    async def reconfigure(self, provider: str, api_key: str, model: Optional[str] = None):
        """Dynamically reconfigure the memory service"""
        logger.info(f"Reconfiguring Mem0 Service to provider: {provider}")
        self._setup_config(provider, api_key, model)
        await self.initialize()

    async def initialize(self):
        """Initialize Mem0 memory service"""
        try:
            # Initialize Mem0 Memory
            self.memory = Memory.from_config(self.config)
            assert self.memory.vector_store.__class__.__name__.lower().startswith("qdrant"), f"Unexpected vector store: {type(self.memory.vector_store)}"
            logger.info("Mem0 service initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize Mem0: {e}")
            # Continue without memory if initialization fails
            logger.warning("Running without memory service")
    
    async def add_memory(
        self,
        messages: List[Dict[str, str]],
        user_id: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Add new memory from conversation messages."""
        try:
            if not self.memory:
                return {"success": False, "error": "Memory service not initialized"}
            
            result = self.memory.add(
                messages=messages,
                user_id=user_id,
                metadata=metadata or {}
            )
            
            return {
                "success": True,
                "memory_id": result.get("id"),
                "memories_added": result.get("results", []),
            }
            
        except Exception as e:
            logger.error(f"Failed to add memory: {e}")
            return {"success": False, "error": str(e)}
    
    async def search_memory(
        self,
        query: str,
        user_id: str,
        limit: int = 5
    ) -> List[Dict[str, Any]]:
        """Search relevant memories for a query."""
        try:
            if not self.memory:
                return []
            
            results = self.memory.search(
                query=query,
                user_id=user_id,
                limit=limit
            )
            
            return results.get("results", [])
            
        except Exception as e:
            logger.error(f"Memory search failed: {e}")
            return []
    
    async def get_all_memories(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all memories for a user"""
        try:
            if not self.memory:
                return []
            
            memories = self.memory.get_all(user_id=user_id)
            return memories.get("results", [])
            
        except Exception as e:
            logger.error(f"Failed to get memories: {e}")
            return []
    
    async def update_memory(
        self,
        memory_id: str,
        data: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Update an existing memory"""
        try:
            if not self.memory:
                return {"success": False, "error": "Memory service not initialized"}
            
            result = self.memory.update(memory_id=memory_id, data=data)
            return {
                "success": True,
                "updated": result,
            }
            
        except Exception as e:
            logger.error(f"Failed to update memory: {e}")
            return {"success": False, "error": str(e)}
    
    async def delete_memory(self, memory_id: str) -> Dict[str, Any]:
        """Delete a memory"""
        try:
            if not self.memory:
                return {"success": False, "error": "Memory service not initialized"}
            
            self.memory.delete(memory_id=memory_id)
            
            return {"success": True}
            
        except Exception as e:
            logger.error(f"Failed to delete memory: {e}")
            return {"success": False, "error": str(e)}
    
    async def cleanup(self):
        """Cleanup resources"""
        logger.info("Mem0 service cleanup completed")
