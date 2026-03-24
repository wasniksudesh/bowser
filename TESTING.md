# Bowser Test Suite

27 high-signal tests covering the Python sidecar backend, Swift frontend contract layer, and CEF browser engine.

## Quick start

```bash
# All tests (backend + frontend)
make test

# Backend only
make test-backend

# Frontend (Swift) only
make test-frontend
```

---

## Prerequisites

### Python (backend)
```bash
cd Sidecar
source .venv/bin/activate
pip install pytest pytest-asyncio httpx
```

### Swift (frontend)
```bash
# Xcode Command Line Tools must be installed
xcode-select --instalwl
```

---

## Running tests per feature

### Backend — per feature

```bash
# Health + configure endpoints
make test-config
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m config -v

# Plan Mode  (POST /api/plan/clarify, /generate, /expand)
make test-plan
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m plan -v

# Agent Mode  (POST /api/agent/goals/plan, /approve)
make test-agent
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m agent -v

# Generative UI  (POST /api/generative-ui/plan, /resolve)
make test-genui
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m genui -v

# Redactor / PII  (POST /api/redactor/process)
make test-redactor
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m redactor -v

# Execution engine  (DataPacket, FanOut, FanIn — pure unit tests)
make test-engine
# or: cd Sidecar && .venv/bin/python -m pytest tests/ -m engine -v
```

### Frontend — per feature

```bash
# CEF engine lifecycle + MockBrowserEngine
make test-swift-cef
# or: swift test --filter BowserTests.CEFBridgeTests

# Plan Mode JSON contract (Generative UI response shapes)
make test-swift-plan
# or: swift test --filter BowserTests.PlanStateTests

# Agent Mode JSON contract + SSE event parsing
make test-swift-agent
# or: swift test --filter BowserTests.AgentStateTests
```

---

## Tests requiring real API keys

Tests marked `@pytest.mark.live` are skipped automatically when the env vars below are absent. Set them to run live integration tests:

```bash
export AI_PROVIDER=openai        # openai | gemini | anthropic
export AI_API_KEY=sk-...
export AI_MODEL=gpt-4o           # optional — uses provider default if unset
export GITHUB_TOKEN=ghp_...      # for agent live tests with GitHub plugin

make test-live
```

---

## Test file map

| File | Feature | Tests |
|------|---------|-------|
| `Sidecar/tests/test_config.py` | Health + configure | 3 |
| `Sidecar/tests/test_plan_mode.py` | Plan Mode API | 3 |
| `Sidecar/tests/test_generative_ui.py` | Generative UI API | 3 |
| `Sidecar/tests/test_agent_mode.py` | Agent Mode API | 3 |
| `Sidecar/tests/test_redactor.py` | PII redaction | 3 |
| `Sidecar/tests/test_execution_engine.py` | DataPacket / FanOut / FanIn | 3 |
| `Tests/BowserTests/CEFBridgeTests.swift` | CEF engine (MockBrowserEngine) | 3 |
| `Tests/BowserTests/PlanStateTests.swift` | Plan Mode JSON contract | 3 |
| `Tests/BowserTests/AgentStateTests.swift` | Agent Mode JSON + SSE | 3 |

**Total: 27 tests**

---

## Adding a new test

### Backend (Python)
1. Add a function `async def test_<name>(client, mock_agent):` in the relevant file under `Sidecar/tests/`.
2. Decorate with the feature marker: `@pytest.mark.plan`, `@pytest.mark.agent`, etc.
3. Use `mock_agent.set_response(...)` to queue LLM responses if needed.
4. Run with `make test-<feature>`.

### Frontend (Swift)
1. Add a `func test<Name>() async` method to the relevant `XCTestCase` subclass under `Tests/BowserTests/`.
2. Use `MockURLProtocol.register(path:json:)` + `URLProtocol.registerClass` if network interception is needed.
3. Run with `make test-swift-<feature>`.

---

## Architecture

```
Makefile                  ← per-feature make targets
│
├── Sidecar/
│   ├── pytest.ini        ← asyncio_mode=auto + feature markers
│   └── tests/
│       ├── conftest.py   ← MockAIAgent + AsyncClient fixtures
│       ├── test_config.py
│       ├── test_plan_mode.py
│       ├── test_generative_ui.py
│       ├── test_agent_mode.py
│       ├── test_redactor.py
│       └── test_execution_engine.py
│
├── Sources/BowserTestSupport/  ← CEF-free library for Swift tests
│   ├── BrowserEngineProtocol.swift
│   └── MockBrowserEngine.swift
│
└── Tests/BowserTests/
    ├── Helpers/
    │   └── MockURLProtocol.swift
    ├── CEFBridgeTests.swift
    ├── PlanStateTests.swift
    └── AgentStateTests.swift
```
