#!/bin/bash
# =============================================================================
# Goal-by-Goal Execution Flow Test
# =============================================================================
#
# This script tests the new goal-by-goal execution flow where:
# 1. User submits query -> Plan created with goals + required_auth
# 2. User approves plan
# 3. For each goal:
#    a. Steps are created and shown
#    b. User clicks "Start Execution" button
#    c. Steps execute and outputs are shown
#    d. Goal is completed and collapsed
#    e. Next goal becomes active
#
# Usage:
#   ./test_goal_by_goal.sh <github_token>
#
# =============================================================================

set -e

BASE_URL="${BASE_URL:-http://localhost:8765/api/agent}"
GITHUB_TOKEN="${1:-${GITHUB_TOKEN:-}}"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GitHub token required"
  echo "Usage: ./test_goal_by_goal.sh <github_token>"
  exit 1
fi

# Configure AI agent
AI_BASE_URL="${BASE_URL%/api/agent}/api/ai"
if [ -n "${OPENAI_API_KEY:-}" ]; then
  echo "Configuring AI agent..."
  curl -s -X POST "$AI_BASE_URL/configure" \
    -H "Content-Type: application/json" \
    -d "{\"provider\": \"openai\", \"api_key\": \"$OPENAI_API_KEY\"}" > /dev/null
fi

echo ""
echo "=========================================="
echo "Test: Goal-by-Goal Execution Flow"
echo "=========================================="
echo ""

# Step 1: Create goal plan with multi-goal query
echo "Step 1: Creating goal plan..."
QUERY="List the last 3 commits from bowser-mac repo and create a summary of changes"

PLAN_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/plan" \
  -H "Content-Type: application/json" \
  -d "{\"query\": \"$QUERY\"}")

SESSION_ID=$(echo "$PLAN_RESPONSE" | jq -r '.session_id')
GOAL_COUNT=$(echo "$PLAN_RESPONSE" | jq '.goal_plan.goals | length')

echo "✓ Plan created with $GOAL_COUNT goals"
echo "  Session ID: $SESSION_ID"
echo ""

# Display goals
echo "Goals in plan:"
echo "$PLAN_RESPONSE" | jq -r '.goal_plan.goals[] | "  - \(.goal_id): \(.description) (plugin: \(.plugin_id))"'
echo ""

# Step 2: Approve the goal plan
echo "Step 2: Approving goal plan..."
APPROVE_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/approve" \
  -H "Content-Type: application/json" \
  -d '{"approved": true}')

APPROVE_STATUS=$(echo "$APPROVE_RESPONSE" | jq -r '.status')
echo "✓ Plan approval status: $APPROVE_STATUS"
echo ""

# Step 3: Start the execution loop (this will start processing goals one by one)
echo "Step 3: Starting execution loop..."
curl -s -X POST "$BASE_URL/goals/$SESSION_ID/run" \
  -H "Content-Type: application/json" > /dev/null

echo "✓ Execution loop started"
echo ""

# Step 4: Listen to events and approve each goal as it comes
echo "Step 4: Monitoring events and approving goals..."
echo ""

# Start event stream in background and process events
(curl -s -N "$BASE_URL/goals/$SESSION_ID/events" 2>/dev/null || true) | while IFS= read -r line; do
  # Skip keepalive and empty lines
  if [[ ! "$line" =~ ^data: ]]; then
    continue
  fi
  
  # Extract JSON from "data: {...}"
  EVENT_JSON="${line#data: }"
  
  # Parse event type
  EVENT_TYPE=$(echo "$EVENT_JSON" | jq -r '.event_type')
  GOAL_ID=$(echo "$EVENT_JSON" | jq -r '.goal_id // empty')
  
  case "$EVENT_TYPE" in
    "goal_started")
      GOAL_DESC=$(echo "$EVENT_JSON" | jq -r '.data.goal.description')
      echo "→ Goal started: $GOAL_ID"
      echo "  Description: $GOAL_DESC"
      ;;
      
    "steps_planned")
      STEP_COUNT=$(echo "$EVENT_JSON" | jq '.data.steps | length')
      REQUIRED_INPUTS=$(echo "$EVENT_JSON" | jq '.data.required_inputs | length')
      echo "→ Steps planned for $GOAL_ID: $STEP_COUNT steps"
      
      # Display steps
      echo "$EVENT_JSON" | jq -r '.data.steps[] | "    \(.step_id): \(.skill_id) - \(.description)"'
      
      if [ "$REQUIRED_INPUTS" -gt 0 ]; then
        echo "  Required inputs: $REQUIRED_INPUTS"
        echo "$EVENT_JSON" | jq -r '.data.required_inputs[] | "    - \(.name): \(.description)"'
      fi
      
      echo ""
      echo "  [UI would show 'Start Execution' button here]"
      echo "  Simulating user clicking 'Start Execution'..."
      echo ""
      
      # Approve goal execution (simulate user clicking "Start Execution")
      sleep 1
      APPROVAL_RESPONSE=$(curl -s -X POST "$BASE_URL/goals/$SESSION_ID/goals/$GOAL_ID/start" \
        -H "Content-Type: application/json" \
        -d "{
          \"approved\": true,
          \"input_values\": {},
          \"auth\": {
            \"github_auth\": {
              \"strategy\": \"token\",
              \"value\": \"$GITHUB_TOKEN\"
            }
          }
        }")
      
      APPROVAL_STATUS=$(echo "$APPROVAL_RESPONSE" | jq -r '.status')
      echo "  ✓ Goal execution approved: $APPROVAL_STATUS"
      echo ""
      ;;
      
    "step_executed")
      STEP_ID=$(echo "$EVENT_JSON" | jq -r '.data.step_id')
      SUCCESS=$(echo "$EVENT_JSON" | jq -r '.data.success')
      SUMMARY=$(echo "$EVENT_JSON" | jq -r '.data.summary')
      
      if [ "$SUCCESS" = "true" ]; then
        echo "  ✓ Step executed: $STEP_ID"
      else
        echo "  ✗ Step failed: $STEP_ID"
      fi
      echo "    Summary: $SUMMARY"
      ;;
      
    "goal_evaluated")
      COMPLETED=$(echo "$EVENT_JSON" | jq -r '.data.evaluation.completed')
      REASONING=$(echo "$EVENT_JSON" | jq -r '.data.evaluation.reasoning')
      echo "→ Goal evaluated: $GOAL_ID"
      echo "  Completed: $COMPLETED"
      echo "  Reasoning: $REASONING"
      echo ""
      ;;
      
    "goal_completed")
      echo "✓ Goal completed: $GOAL_ID"
      echo "  [UI would collapse this goal and expand next goal]"
      echo ""
      ;;
      
    "goal_failed")
      REASON=$(echo "$EVENT_JSON" | jq -r '.data.reason // "Unknown"')
      echo "✗ Goal failed: $GOAL_ID"
      echo "  Reason: $REASON"
      echo ""
      ;;
      
    "final_evaluated")
      RESOLVED=$(echo "$EVENT_JSON" | jq -r '.data.evaluation.query_resolved')
      REASONING=$(echo "$EVENT_JSON" | jq -r '.data.evaluation.reasoning')
      echo "→ Final evaluation:"
      echo "  Query resolved: $RESOLVED"
      echo "  Reasoning: $REASONING"
      echo ""
      ;;
      
    "complete")
      echo "=========================================="
      echo "✓ Execution completed successfully!"
      echo "=========================================="
      break
      ;;
      
    "error")
      ERROR=$(echo "$EVENT_JSON" | jq -r '.data.error')
      echo "✗ Error: $ERROR"
      break
      ;;
  esac
done

echo ""
echo "Test completed!"
