"""
Tests: Agent Mode API  (/api/agent/goals/*)

Feature: Goal-based agent planning and approval workflow
Coverage:
  1. POST /api/agent/goals/plan                  -> session created, goal plan returned
  2. POST /api/agent/goals/{id}/approve (true)   -> status becomes "approved"
  3. POST /api/agent/goals/{id}/approve (false)  -> status becomes "revised", plan updated
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock


# Minimal mock goal plan returned by GoalPlannerAgent
def _make_mock_goal_plan(session_id="ignored"):
    from app.models.agent_schemas import GoalPlanModel, GoalModel, GoalStatus
    import uuid

    goal = GoalModel(
        goal_id="G-0",
        description="Fetch last 5 commits from test/repo",
        plugin_id="github",
        status=GoalStatus.PENDING,
        depends_on=[],
        steps=[],
        step_outputs={},
        evaluation_history=[],
        retry_count=0,
    )
    plan = GoalPlanModel(
        plan_id=str(uuid.uuid4()),
        goals=[goal],
        status="pending",
    )
    return plan


def _make_mock_revised_plan():
    from app.models.agent_schemas import GoalPlanModel, GoalModel, GoalStatus
    import uuid

    goal = GoalModel(
        goal_id="G-0",
        description="Fetch last 5 commits from test/repo on branch main",
        plugin_id="github",
        status=GoalStatus.PENDING,
        depends_on=[],
        steps=[],
        step_outputs={},
        evaluation_history=[],
        retry_count=0,
    )
    return GoalPlanModel(
        plan_id=str(uuid.uuid4()),
        goals=[goal],
        status="pending",
    )


# ---------------------------------------------------------------------------
# Test 1 – Create goal plan
# ---------------------------------------------------------------------------

@pytest.mark.agent
async def test_create_goal_plan_returns_session_and_goals(bare_client):
    """
    POST /api/agent/goals/plan — should create a session and return goal_plan
    with at least one goal, plus a session_id.
    """
    with patch(
        "app.routes.agent_routes.goal_planner.create_goal_plan",
        new_callable=AsyncMock,
    ) as mock_create:
        mock_create.return_value = _make_mock_goal_plan()

        response = await bare_client.post(
            "/api/agent/goals/plan",
            json={"query": "List last 5 commits from test/repo"},
        )

    assert response.status_code == 200
    body = response.json()
    assert "session_id" in body
    assert "goal_plan" in body
    goals = body["goal_plan"]["goals"]
    assert len(goals) >= 1
    assert goals[0]["description"] != ""
    assert goals[0]["plugin_id"] == "github"


# ---------------------------------------------------------------------------
# Test 2 – Approve goal plan
# ---------------------------------------------------------------------------

@pytest.mark.agent
async def test_approve_goal_plan_sets_approved_status(bare_client):
    """
    POST /api/agent/goals/{id}/approve with approved=true returns
    {"status": "approved"}.
    """
    # First create a session
    with patch(
        "app.routes.agent_routes.goal_planner.create_goal_plan",
        new_callable=AsyncMock,
    ) as mock_create:
        mock_create.return_value = _make_mock_goal_plan()
        plan_response = await bare_client.post(
            "/api/agent/goals/plan",
            json={"query": "Test query"},
        )

    session_id = plan_response.json()["session_id"]

    approve_response = await bare_client.post(
        f"/api/agent/goals/{session_id}/approve",
        json={"approved": True},
    )

    assert approve_response.status_code == 200
    body = approve_response.json()
    assert body["status"] == "approved"


# ---------------------------------------------------------------------------
# Test 3 – Reject plan with feedback yields revised plan
# ---------------------------------------------------------------------------

@pytest.mark.agent
async def test_reject_goal_plan_with_feedback_returns_revised(bare_client):
    """
    POST /api/agent/goals/{id}/approve with approved=false + feedback triggers
    plan refinement and returns {"status": "revised"} with a new goal_plan.
    """
    # Create session
    with patch(
        "app.routes.agent_routes.goal_planner.create_goal_plan",
        new_callable=AsyncMock,
    ) as mock_create:
        mock_create.return_value = _make_mock_goal_plan()
        plan_response = await bare_client.post(
            "/api/agent/goals/plan",
            json={"query": "List commits"},
        )

    session_id = plan_response.json()["session_id"]

    # Reject with feedback — patch refine_goal_plan
    with patch(
        "app.routes.agent_routes.goal_planner.refine_goal_plan",
        new_callable=AsyncMock,
    ) as mock_refine:
        mock_refine.return_value = _make_mock_revised_plan()

        reject_response = await bare_client.post(
            f"/api/agent/goals/{session_id}/approve",
            json={
                "approved": False,
                "feedback": "Please specify the branch explicitly",
            },
        )

    assert reject_response.status_code == 200
    body = reject_response.json()
    assert body["status"] == "revised"
    assert "goal_plan" in body
    # Revised plan has the updated description
    goals = body["goal_plan"]["goals"]
    assert any("branch" in g["description"].lower() for g in goals)
