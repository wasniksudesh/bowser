"""
Tests: configuration and health endpoints.

Feature: Sidecar connectivity + service configuration
Coverage:
  1. GET  /health            -> 200 + {"status": "healthy"}
  2. POST /api/configure     -> reconfigures agent + mem0 successfully
  3. POST /api/configure     -> unknown provider returns 500
"""

import os
import pytest
from unittest.mock import AsyncMock, patch


# ---------------------------------------------------------------------------
# Test 1 – Health check
# ---------------------------------------------------------------------------

@pytest.mark.config
async def test_health_returns_healthy(bare_client):
    """GET /health must return status=healthy — no LLM needed."""
    response = await bare_client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert "version" in body
    assert "timestamp" in body


# ---------------------------------------------------------------------------
# Test 2 – Configure succeeds with a valid provider
# ---------------------------------------------------------------------------

@pytest.mark.config
async def test_configure_valid_provider_succeeds(bare_client):
    """
    POST /api/configure with a recognised provider must succeed.
    We patch reconfigure_ai_agent + Mem0Service.reconfigure so no real
    LLM is initialised.
    """
    with (
        patch("app.main.reconfigure_ai_agent", new_callable=AsyncMock) as mock_reconf,
        patch("app.main.mem0_service") as mock_mem0,
    ):
        mock_reconf.return_value = None
        mock_mem0.reconfigure = AsyncMock(return_value=None)

        response = await bare_client.post(
            "/api/configure",
            json={"provider": "openai", "api_key": "sk-test", "model": "gpt-4o"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert "openai" in body["message"].lower()


# ---------------------------------------------------------------------------
# Test 3 – Configure with invalid provider returns 500
# ---------------------------------------------------------------------------

@pytest.mark.config
async def test_configure_invalid_provider_returns_error(bare_client):
    """
    POST /api/configure with an unsupported provider propagates the ValueError
    raised by get_llm and returns HTTP 500.
    """
    from app.utils.factory import get_llm

    with patch("app.main.reconfigure_ai_agent", new_callable=AsyncMock) as mock_reconf:
        mock_reconf.side_effect = ValueError("Unsupported LLM provider: banana")

        response = await bare_client.post(
            "/api/configure",
            json={"provider": "banana", "api_key": "key"},
        )

    assert response.status_code == 500
