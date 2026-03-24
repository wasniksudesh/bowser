"""
Tests: Generative UI API  (/api/generative-ui/*)

Feature: Server-driven UI layout and component data resolution
Coverage:
  1. POST /api/generative-ui/plan    -> returns layout with valid component types
  2. POST /api/generative-ui/resolve -> returns data for a specific component
  3. POST /api/generative-ui/plan    -> empty leafContext returns graceful 500
"""

import pytest


# Minimal payloads — one component each so the mock LLM response is tiny

_LAYOUT_JSON = {
    "components": [
        {
            "id": "comp1",
            "type": "spotList",
            "position": {"row": 0, "col": 0},
            "size": {"width": 1.0, "height": "auto"},
            "dataPrompt": "List top attractions in Rome",
        }
    ]
}

_RESOLVE_JSON = {
    "spots": [
        {
            "name": "Colosseum",
            "description": "Ancient Roman amphitheatre",
            "url": "https://en.wikipedia.org/wiki/Colosseum",
        }
    ]
}

_LEAF_CONTEXT = {"title": "Rome, Italy", "description": "Exploring Rome"}
_AVAILABLE_COMPONENTS = [
    {"type": "spotList", "description": "Vertical list of locations"},
    {"type": "carousel", "description": "Image gallery"},
]


# ---------------------------------------------------------------------------
# Test 1 – Layout plan returns valid component types
# ---------------------------------------------------------------------------

@pytest.mark.genui
async def test_layout_plan_returns_components(client, mock_agent):
    """POST /api/generative-ui/plan — returns a layout with known component types."""
    mock_agent.set_response(_LAYOUT_JSON)

    response = await client.post(
        "/api/generative-ui/plan",
        json={
            "leafContext": _LEAF_CONTEXT,
            "availableComponents": _AVAILABLE_COMPONENTS,
        },
    )

    assert response.status_code == 200
    body = response.json()
    layout = body["layout"]
    assert "components" in layout
    assert len(layout["components"]) >= 1

    comp = layout["components"][0]
    assert "id" in comp
    assert "type" in comp
    assert "dataPrompt" in comp
    # position and size must be present
    assert "position" in comp
    assert "row" in comp["position"] and "col" in comp["position"]


# ---------------------------------------------------------------------------
# Test 2 – Resolve returns component data
# ---------------------------------------------------------------------------

@pytest.mark.genui
async def test_resolve_returns_component_data(client, mock_agent):
    """POST /api/generative-ui/resolve — returns data for a spotList component."""
    mock_agent.set_response(_RESOLVE_JSON)

    response = await client.post(
        "/api/generative-ui/resolve",
        json={
            "componentId": "comp1",
            "componentType": "spotList",
            "dataPrompt": "List top attractions in Rome",
            "leafContext": _LEAF_CONTEXT,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["componentId"] == "comp1"
    assert body["success"] is True
    assert body["data"] is not None


# ---------------------------------------------------------------------------
# Test 3 – Empty leaf context triggers a 500 (LLM cannot produce valid JSON)
# ---------------------------------------------------------------------------

@pytest.mark.genui
async def test_layout_plan_llm_failure_returns_500(client, mock_agent):
    """
    POST /api/generative-ui/plan when the LLM returns invalid JSON should
    return HTTP 500 with an error detail.
    """
    # Queue malformed JSON as the mock LLM response
    mock_agent.set_response("NOT VALID JSON {{")

    response = await client.post(
        "/api/generative-ui/plan",
        json={
            "leafContext": {"title": "", "description": ""},
            "availableComponents": [],
        },
    )

    assert response.status_code == 500
