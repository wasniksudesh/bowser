"""
Shared pytest fixtures for Bowser Sidecar tests.

All LLM-dependent routes import `ai_agent` from `app.main` at call time:
    from app.main import ai_agent
So patching `app.main.ai_agent` with a MockAIAgent before each request is
sufficient — no lifespan startup needed.
"""

import json
import pytest
import importlib
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


# ---------------------------------------------------------------------------
# MockAIAgent
# ---------------------------------------------------------------------------

class MockAIAgent:
    """
    Minimal drop-in for AIAgent used during tests.
    Responses are set via `set_response(json_dict)` before each test call.
    """

    def __init__(self):
        self._responses: list[str] = []

    def set_response(self, payload: dict | list | str):
        """Queue a JSON response string to be returned by the next execute_task call."""
        if isinstance(payload, (dict, list)):
            self._responses.append(json.dumps(payload))
        else:
            self._responses.append(payload)

    async def execute_task(self, task: str, context=None, use_tools: bool = True) -> dict:
        if self._responses:
            return {"success": True, "output": self._responses.pop(0)}
        return {"success": False, "error": "No mock response queued"}

    async def cleanup(self):
        pass


# ---------------------------------------------------------------------------
# app import (deferred so we can patch before lifespan runs)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"


@pytest.fixture
async def mock_agent():
    """Return a fresh MockAIAgent instance, wired into app.main.ai_agent."""
    agent = MockAIAgent()

    import app.main as main_module
    original = main_module.ai_agent
    main_module.ai_agent = agent
    yield agent
    main_module.ai_agent = original


@pytest.fixture
async def client(mock_agent):
    """
    AsyncClient backed by the FastAPI app WITHOUT running the lifespan.
    app.main.ai_agent is already set to mock_agent by the time requests arrive.
    """
    from app.main import app

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as ac:
        yield ac


@pytest.fixture
async def bare_client():
    """
    AsyncClient with NO mock_agent — used for routes that don't call LLM
    (redactor, execution engine unit tests, health check).
    """
    from app.main import app

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as ac:
        yield ac
