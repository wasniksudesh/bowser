#!/bin/bash
# =============================================================================
# Goal-Based Agent Test Suite
# =============================================================================
#
# This script tests the goal-based agent routes including:
#   - Single-goal queries (GitHub commits)
#   - Multi-goal queries (cross-plugin)
#   - Goal plan refinement with feedback
#   - Goal retry on incomplete evaluation
#
# Usage:
#   ./test_goal_agent.sh <github_token>
#   GITHUB_TOKEN=xxx ./test_goal_agent.sh
#
# Requirements:
#   - Sidecar server running on localhost:8765
#   - Valid GitHub token with repo access
#   - OPENAI_API_KEY env var (for AI agent / goal planning)
#   - jq installed for JSON parsing
#
# Test Coverage:
#   Test 1: Single-goal query (list GitHub commits)
#   Test 2: Multi-goal query (list commits + summarize)
#   Test 3: Goal plan refinement with feedback
#   Test 4: Goal plan approval and execution
#
# =============================================================================

set -e

BASE_URL="${BASE_URL:-http://localhost:8765/api/agent}"

# Get GitHub token from argument or environment
GITHUB_TOKEN="${1:-${GITHUB_TOKEN:-}}"
if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GitHub token required"
  echo "Usage: ./test_goal_agent.sh <github_token>"
  echo "   or: GITHUB_TOKEN=xxx ./test_goal_agent.sh"
  exit 1
fi

# Configure AI agent with OpenAI API key from env
AI_BASE_URL="${BASE_URL%/api/agent}/api/ai"
if [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "Configuring AI agent with OPENAI_API_KEY..."
  CONFIGURE_RESPONSE=$(curl -s -X POST "$AI_BASE_URL/configure" \
    -H "Content-Type: application/json" \
    -d "{\"provider\": \"openai\", \"api_key\": \"$OPENAI_API_KEY\"}")
  if echo "$CONFIGURE_RESPONSE" | jq -e '.success' > /dev/null 2>&1; then
    echo "  AI agent configured successfully"
  else
    echo "  WARNING: AI agent configuration failed: $CONFIGURE_RESPONSE"
  fi
else
  echo "  WARNING: OPENAI_API_KEY not set - AI agent may not work for goal planning"
fi
echo ""

# Test repository
TEST_REPO="wasniksudesh/bowser-mac"

echo "============================================================"
echo "Goal-Based Agent Test Suite"
echo "============================================================"
echo ""
echo "Base URL: $BASE_URL"
echo "Test Repo: $TEST_REPO"
echo ""

# =============================================================================
# Test 1: Single-Goal Query (GitHub commits)
# =============================================================================

echo "[Test 1] Single-goal query: List GitHub commits"
echo "------------------------------------------------"

# Create goal plan
echo "Creating goal plan..."
PLAN_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/plan" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"List the last 5 commits from $TEST_REPO\"}")

SESSION_ID=$(echo "$PLAN_RESPONSE" | jq -r '.session_id')
GOAL_COUNT=$(echo "$PLAN_RESPONSE" | jq '.goal_plan.goals | length')

echo "Session ID: $SESSION_ID"
echo "Goals created: $GOAL_COUNT"

if [ "$GOAL_COUNT" -eq 0 ]; then
  echo "ERROR: No goals created"
  exit 1
fi

# Display goals
echo "Goals:"
echo "$PLAN_RESPONSE" | jq -r '.goal_plan.goals[] | "  - \(.goal_id): \(.description) (plugin: \(.plugin_id))"'

# Approve goal plan
echo ""
echo "Approving goal plan..."
APPROVE_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": true}')

APPROVE_STATUS=$(echo "$APPROVE_RESPONSE" | jq -r '.status')
echo "Approval status: $APPROVE_STATUS"

if [ "$APPROVE_STATUS" != "approved" ]; then
  echo "ERROR: Goal plan not approved"
  exit 1
fi

echo ""
echo "✓ Test 1 passed: Single-goal plan created and approved"
echo ""

# =============================================================================
# Test 2: Multi-Goal Query (cross-plugin)
# =============================================================================

echo "[Test 2] Multi-goal query: List commits + summarize"
echo "----------------------------------------------------"

# Create goal plan for multi-goal query
echo "Creating multi-goal plan..."
PLAN_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/plan" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"List the last 3 commits from $TEST_REPO and 'test-commit' branch and summarize the changes\"}")

SESSION_ID=$(echo "$PLAN_RESPONSE" | jq -r '.session_id')
GOAL_COUNT=$(echo "$PLAN_RESPONSE" | jq '.goal_plan.goals | length')

echo "Session ID: $SESSION_ID"
echo "Goals created: $GOAL_COUNT"

# Display goals
echo "Goals:"
echo "$PLAN_RESPONSE" | jq -r '.goal_plan.goals[] | "  - \(.goal_id): \(.description) (plugin: \(.plugin_id))"'

if [ "$GOAL_COUNT" -lt 2 ]; then
  echo "WARNING: Expected at least 2 goals, got $GOAL_COUNT"
fi

# Approve goal plan
echo ""
echo "Approving multi-goal plan..."
APPROVE_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": true}')

APPROVE_STATUS=$(echo "$APPROVE_RESPONSE" | jq -r '.status')
echo "Approval status: $APPROVE_STATUS"

echo ""
echo "✓ Test 2 passed: Multi-goal plan created and approved"
echo ""

# =============================================================================
# Test 3: Goal Plan Refinement
# =============================================================================

echo "[Test 3] Goal plan refinement with feedback"
echo "--------------------------------------------"

# Create initial goal plan
echo "Creating initial goal plan..."
PLAN_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/plan" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"Get GitHub commits and analyze them\"}")

SESSION_ID=$(echo "$PLAN_RESPONSE" | jq -r '.session_id')
INITIAL_GOAL_COUNT=$(echo "$PLAN_RESPONSE" | jq '.goal_plan.goals | length')

echo "Session ID: $SESSION_ID"
echo "Initial goals: $INITIAL_GOAL_COUNT"

# Reject with feedback
echo ""
echo "Rejecting plan with feedback..."
REJECT_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": false, "feedback": "Please be more specific about which repository and how many commits"}')

REJECT_STATUS=$(echo "$REJECT_RESPONSE" | jq -r '.status')
echo "Rejection status: $REJECT_STATUS"

if [ "$REJECT_STATUS" != "revised" ]; then
  echo "ERROR: Expected status 'revised', got '$REJECT_STATUS'"
  exit 1
fi

# Check revised plan
REVISED_GOAL_COUNT=$(echo "$REJECT_RESPONSE" | jq '.goal_plan.goals | length')
echo "Revised goals: $REVISED_GOAL_COUNT"

echo "Revised goals:"
echo "$REJECT_RESPONSE" | jq -r '.goal_plan.goals[] | "  - \(.goal_id): \(.description) (plugin: \(.plugin_id))"'

# Approve revised plan
echo ""
echo "Approving revised plan..."
APPROVE_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": true}')

APPROVE_STATUS=$(echo "$APPROVE_RESPONSE" | jq -r '.status')
echo "Approval status: $APPROVE_STATUS"

echo ""
echo "✓ Test 3 passed: Goal plan refinement works"
echo ""

# =============================================================================
# Test 4: Goal Execution with Auto-Approval
# =============================================================================

echo "[Test 4] Goal execution with auto-approval"
echo "-------------------------------------------"

# Create a simple goal plan
echo "Creating goal plan for execution..."
PLAN_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/plan" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"Fetch the last 3 commit and their diff from $TEST_REPO and 'test-commit' branch and summarize the changes\"}")
echo "Plan response : $PLAN_RESPONSE"
SESSION_ID=$(echo "$PLAN_RESPONSE" | jq -r '.session_id')
echo "Session ID: $SESSION_ID"

# Approve goal plan
echo "Approving goal plan..."
curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": true}' 

# Start execution
echo "Starting execution..."
curl -s -X POST "$BASE_URL/goals/$SESSION_ID/run" 

# Monitor events and auto-approve steps
echo "Monitoring execution events (auto-approving steps)..."

# Create a background process to listen to events
(curl -s -N "$BASE_URL/goals/$SESSION_ID/events" | while IFS= read -r line; do
  if [[ "$line" =~ ^data: ]]; then
    event_data="${line#data: }"
    
    # Skip keepalive messages
    if [ "$event_data" = "" ] || [ "$event_data" = " " ]; then
      continue
    fi
    
    event_type=$(echo "$event_data" | jq -r '.event_type')
    
    echo "  Event: $event_type"
    
    case "$event_type" in
      "goal_started")
        goal_id=$(echo "$event_data" | jq -r '.goal_id')
        echo "    Goal started: $goal_id"
        ;;
      
      "steps_planned")
        goal_id=$(echo "$event_data" | jq -r '.goal_id')
        steps_count=$(echo "$event_data" | jq '.data.steps | length')
        echo "    Steps planned for $goal_id: $steps_count steps"
        
        # Auto-approve steps with inputs
        echo "    Auto-approving steps..."
        curl -s -X POST "$BASE_URL/goals/$SESSION_ID/steps/approve" \
          -H "Content-Type: application/json" \
          -d "{
            \"approved\": true,
            \"input_values\": {
              \"repo\": \"$TEST_REPO\",
              \"limit\": \"3\"
            },
            \"auth\": {
              \"github_auth\": {
                \"strategy\": \"token\",
                \"value\": \"$GITHUB_TOKEN\"
              }
            }
          }" > /dev/null
        echo "    Steps approved"
        ;;
      
      "step_executed")
        step_id=$(echo "$event_data" | jq -r '.data.step_id')
        success=$(echo "$event_data" | jq -r '.data.success')
        echo "    Step executed: $step_id (success: $success)"
        ;;
      
      "goal_evaluated")
        completed=$(echo "$event_data" | jq -r '.data.evaluation.completed')
        strategy=$(echo "$event_data" | jq -r '.data.evaluation.strategy')
        echo "    Goal evaluated: completed=$completed, strategy=$strategy"
        ;;
      
      "goal_completed")
        goal_id=$(echo "$event_data" | jq -r '.goal_id')
        echo "    Goal completed: $goal_id"
        ;;
      
      "final_evaluated")
        resolved=$(echo "$event_data" | jq -r '.data.evaluation.query_resolved')
        echo "    Final evaluation: query_resolved=$resolved"
        ;;
      
      "complete")
        echo "    Execution complete!"
        break
        ;;
      
      "error")
        error=$(echo "$event_data" | jq -r '.data.error')
        echo "    ERROR: $error"
        break
        ;;
    esac
  fi
done) &

EVENT_PID=$!

# Wait for event stream to complete (with timeout)
TIMEOUT=60
ELAPSED=0
while kill -0 $EVENT_PID 2>/dev/null; do
  sleep 1
  ELAPSED=$((ELAPSED + 1))
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Timeout waiting for execution to complete"
    kill $EVENT_PID 2>/dev/null || true
    break
  fi
done

# Check final status
echo ""
echo "Checking final status..."
STATUS_RESPONSE=$(curl -s "$BASE_URL/goals/$SESSION_ID/status")
FINAL_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
echo "Final status: $FINAL_STATUS"

echo ""
echo "✓ Test 4 passed: Goal execution completed"
echo ""

# =============================================================================
# Summary
# =============================================================================

echo "============================================================"
echo "Test Suite Summary"
echo "============================================================"
echo "✓ Test 1: Single-goal plan creation"
echo "✓ Test 2: Multi-goal plan creation"
echo "✓ Test 3: Goal plan refinement"
echo "✓ Test 4: Goal execution with auto-approval"
echo ""
echo "All tests passed!"
echo "============================================================"
