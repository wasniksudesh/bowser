"""
Tests: Plan Mode API  (/api/plan/*)

Feature: LLM-driven hierarchical planning
Coverage:
  1. POST /api/plan/clarify   -> returns questions with options
  2. POST /api/plan/generate  -> returns plan tree with root + children
  3. POST /api/plan/expand    -> returns child nodes for a given parent
"""

import json
import pytest


# Minimal LLM JSON fixtures — deliberately small
_CLARIFY_JSON = {
    "suggested_name": "Learn Python",
    "questions": [
        {
            "id": "q1",
            "text": "What is your experience level?",
            "options": [
                {"id": "opt1", "text": "Beginner", "explanation": "No prior experience"},
                {"id": "opt2", "text": "Intermediate", "explanation": "Some experience"},
            ],
            "allowMultiple": False,
        }
    ],
}

_GENERATE_JSON = {
    "id": "root",
    "title": "Learn Python in 30 Days",
    "description": "A structured plan for learning Python",
    "isLeaf": False,
    "children": [
        {
            "id": "s1",
            "title": "Week 1 – Basics",
            "description": "Variables, types, control flow",
            "isLeaf": False,
            "children": [],
        },
        {
            "id": "s2",
            "title": "Install Python",
            "description": "Download and install Python 3",
            "isLeaf": True,
            "links": [{"title": "python.org", "url": "https://python.org"}],
            "children": [],
        },
    ],
}

_EXPAND_JSON = {
    "children": [
        {
            "id": "sub1",
            "title": "Write your first script",
            "description": "Create hello_world.py",
            "isLeaf": True,
            "links": [],
            "children": [],
        }
    ]
}


# ---------------------------------------------------------------------------
# Test 1 – Clarification returns questions
# ---------------------------------------------------------------------------

@pytest.mark.plan
async def test_clarify_returns_questions(client, mock_agent):
    """POST /api/plan/clarify — LLM returns clarification questions."""
    mock_agent.set_response(_CLARIFY_JSON)

    response = await client.post(
        "/api/plan/clarify",
        json={"intent": "Learn Python programming"},
    )

    assert response.status_code == 200
    body = response.json()
    assert "suggested_name" in body
    assert isinstance(body["questions"], list)
    assert len(body["questions"]) >= 1

    q = body["questions"][0]
    assert "id" in q
    assert "text" in q
    assert len(q["options"]) >= 2


# ---------------------------------------------------------------------------
# Test 2 – Generate returns a plan tree
# ---------------------------------------------------------------------------

@pytest.mark.plan
async def test_generate_returns_plan_tree(client, mock_agent):
    """POST /api/plan/generate — LLM returns a root node with children."""
    mock_agent.set_response(_GENERATE_JSON)

    response = await client.post(
        "/api/plan/generate",
        json={
            "intent": "Learn Python programming",
            "clarification_answers": [
                {"questionId": "q1", "selectedOptionIds": ["opt1"]}
            ],
        },
    )

    assert response.status_code == 200
    body = response.json()
    root = body["root"]
    assert root["title"] == "Learn Python in 30 Days"
    assert root["isLeaf"] is False
    assert len(root["children"]) == 2

    # Verify leaf node has links
    leaf = next(c for c in root["children"] if c["isLeaf"])
    assert len(leaf.get("links", [])) >= 1


# ---------------------------------------------------------------------------
# Test 3 – Expand returns child nodes
# ---------------------------------------------------------------------------

@pytest.mark.plan
async def test_expand_returns_children(client, mock_agent):
    """POST /api/plan/expand — LLM returns sub-steps for a parent node."""
    mock_agent.set_response(_EXPAND_JSON)

    response = await client.post(
        "/api/plan/expand",
        json={
            "intent": "Learn Python programming",
            "parent_node_context": "Week 1 – Basics: Variables, types, control flow",
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert "children" in body
    assert len(body["children"]) >= 1
    child = body["children"][0]
    assert "title" in child
    assert "isLeaf" in child
