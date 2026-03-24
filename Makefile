# ============================================================================
# Bowser Test Harness
# ============================================================================
# Run individual feature tests during development:
#
#   make test-plan          # backend Plan Mode tests only
#   make test-agent         # backend Agent Mode tests only
#   make test-swift-cef     # Swift CEF/MockEngine tests only
#   make test               # everything
#
# API keys (for @pytest.mark.live tests):
#   export AI_API_KEY=sk-...
#   export AI_PROVIDER=openai
#   export AI_MODEL=gpt-4o
#   export GITHUB_TOKEN=ghp_...
#
# ============================================================================

PYTHON  := .venv/bin/python
PYTEST  := $(PYTHON) -m pytest
PTFLAGS := -v --tb=short

# ============================================================================
# Backend — Python (Sidecar)
# ============================================================================

.PHONY: test-backend test-config test-plan test-agent test-genui test-redactor test-engine test-live

## Run all backend tests
test-backend:
	cd Sidecar && $(PYTEST) tests/ $(PTFLAGS)

## Health + configure endpoint tests
test-config:
	cd Sidecar && $(PYTEST) tests/ -m config $(PTFLAGS)

## Plan Mode API tests  (POST /api/plan/*)
test-plan:
	cd Sidecar && $(PYTEST) tests/ -m plan $(PTFLAGS)

## Agent Mode API tests  (POST /api/agent/goals/*)
test-agent:
	cd Sidecar && $(PYTEST) tests/ -m agent $(PTFLAGS)

## Generative UI tests  (POST /api/generative-ui/*)
test-genui:
	cd Sidecar && $(PYTEST) tests/ -m genui $(PTFLAGS)

## Redactor / PII tests  (POST /api/redactor/process)
test-redactor:
	cd Sidecar && $(PYTEST) tests/ -m redactor $(PTFLAGS)

## Execution engine unit tests  (DataPacket, FanOut, FanIn)
test-engine:
	cd Sidecar && $(PYTEST) tests/ -m engine $(PTFLAGS)

## Live tests — require real API keys in environment
test-live:
	cd Sidecar && $(PYTEST) tests/ -m live $(PTFLAGS)

# ============================================================================
# Frontend — Swift (XCTest via swift-test)
# ============================================================================

.PHONY: test-frontend test-swift-cef test-swift-plan test-swift-agent

## Run all Swift tests
test-frontend:
	swift test --filter BowserTests $(PTFLAGS_SWIFT)

## CEF bridge / MockBrowserEngine tests
test-swift-cef:
	swift test --filter BowserTests.CEFBridgeTests

## Plan Mode JSON contract tests
test-swift-plan:
	swift test --filter BowserTests.PlanStateTests

## Agent Mode JSON contract + SSE parsing tests
test-swift-agent:
	swift test --filter BowserTests.AgentStateTests

# ============================================================================
# All
# ============================================================================

.PHONY: test

## Run full test suite (backend + frontend)
test: test-backend test-frontend
