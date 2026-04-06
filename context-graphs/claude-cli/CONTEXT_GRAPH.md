# Context Graph — Claude Code CLI

## What

The same append-only `semantics.json` graph used by Cursor, extended to capture knowledge produced during **interactive terminal sessions** — debugging, incident investigation, build analysis, data exploration. Claude Code CLI writes to the same graph file in the repository root.

The schema is a superset of the Cursor schema. All Cursor node types and relationships are valid. CLI adds two new node types and one new relationship that cover knowledge produced through command execution and investigation.

---

## How CLI differs from Cursor

| Dimension | Cursor | Claude Code CLI |
|---|---|---|
| Primary artifact | Source code (static) | Command output (ephemeral) |
| Knowledge trigger | Code analysis, user discussion | Tool execution, observed system behavior |
| Session nature | Conclusion-oriented | Investigation-oriented |
| Key failure | Wrong design decision | Wrong interpretation of runtime signal |
| Verification | Read the code | Re-run the command |
| Unique knowledge | Architecture decisions | Ruled-out hypotheses, command output patterns |

---

## Shared schema (from Cursor)

All four node types — **Decision**, **Constraint**, **Insight**, **Signal** — are identical to the Cursor schema. See `context-graphs/cursor/CONTEXT_GRAPH.md` for full field definitions.

CLI extends Signal with two additional fields:

```json
{
  "id": "signal:<slug>",
  "type": "Signal",
  "scope": "...",
  "observation": "",
  "appears_to_mean": "",
  "actually_means": "",
  "conditions": "",
  "evidence": "",
  "command": "",
  "output_pattern": "",
  "lifetime": "permanent | session",
  "created_at": ""
}
```

| New field | Required | Description |
|---|---|---|
| `command` | no | The command that surfaces this signal (makes it reproducible) |
| `output_pattern` | no | What output to look for in command results |
| `lifetime` | yes | `permanent` = write to graph; `session` = discard after session |

`lifetime: "session"` is for signals that are true only of the current system state (e.g. "this specific instance has 3 orphaned rows"). Only `lifetime: "permanent"` entries are written to `semantics.json`.

---

## CLI-only node types

### Finding

An investigation conclusion — what was determined through systematic inquiry. Not a decision (no alternatives chosen), not a constraint (not externally imposed), but a **verified answer to a question** that would otherwise require re-investigation.

```json
{
  "id": "finding:<slug>",
  "type": "Finding",
  "label": "",
  "scope": "system | subsystem:<name> | module:<name>",
  "question": "",
  "answer": "",
  "ruled_out": [""],
  "evidence": [""],
  "confidence": "high | medium | low",
  "conditions": "",
  "lifetime": "permanent | session",
  "created_at": ""
}
```

| Field | Required | Description |
|---|---|---|
| `question` | yes | The question the investigation was answering |
| `answer` | yes | The verified conclusion |
| `ruled_out` | yes (≥1) | Hypotheses explicitly eliminated and how |
| `evidence` | yes (≥1) | Commands run, logs checked, data queried |
| `confidence` | yes | `high` / `medium` / `low` |
| `conditions` | yes | When this finding holds (system state, version, environment) |
| `lifetime` | yes | `permanent` if the finding generalizes; `session` if incident-specific |

Gate: *"Would another engineer spend 30+ minutes re-investigating this same question?"* Only write Finding when confidence is `medium` or `high`. If the investigation was inconclusive, nothing is written.

### RuledOut (inline, not a standalone node)

Hypothesis elimination is captured inside `Finding.ruled_out[]` as structured strings:

```json
"ruled_out": [
  "flaky test — ruled out by running suite 5 times locally, all passed",
  "dependency version conflict — ruled out by running `mvn dependency:tree`, no conflicts found",
  "CI environment variable — ruled out by comparing CI env to staging, identical relevant vars"
]
```

This avoids creating orphaned nodes for hypotheses that went nowhere.

---

## CLI-only relationship type

| Relationship | Direction | When to use |
|---|---|---|
| `RULED_OUT` | Finding → Signal\|Constraint | Investigation explicitly eliminated this as a cause |

Use `RULED_OUT` when the eliminated hypothesis is already a node in the graph (a Signal or Constraint that looked relevant but wasn't the cause). The `edge_context` must explain what evidence ruled it out.

---

## Full relationship set (CLI)

| Relationship | Direction | Meaning |
|---|---|---|
| `SHAPED_BY` | Decision → Constraint | Constraint forced this decision |
| `SUPERSEDES` | Decision → Decision | New replaces old |
| `ABANDONED` | Decision → Decision | Considered and rejected |
| `EXPLAINS` | Insight → Decision\|Constraint\|Signal | Clarifies the target |
| `CONTRADICTS` | Constraint → Constraint | Two constraints in tension |
| `LIFTED` | Constraint → Decision | Constraint removed, enabling decision |
| `CAUSES` | Constraint\|Signal → Constraint\|Signal | Runtime causal chain |
| `RULED_OUT` | Finding → Signal\|Constraint | Investigation eliminated this cause |

---

## Capture sources (CLI)

| Source | Produces | When |
|---|---|---|
| Build log analysis | Finding, Constraint, Signal | Claude reads CI/build output |
| Test failure investigation | Finding, Constraint | Iterative test debugging |
| Incident debugging | Finding, Signal, Constraint | Live system investigation |
| Data / metric analysis | Signal, Finding | Querying DBs, metrics, logs |
| Dependency inspection | Constraint, Decision | Version pinning, conflict resolution |
| Git archaeology | Decision (SUPERSEDES) | `git log` / `git blame` reveals prior decision |
| Diff / config comparison | Signal, Constraint | Comparing env/staging/prod configs |
| User-stated constraints | Constraint | User explains a requirement during CLI session |

---

## When to write (CLI)

Same gate as Cursor, with one additional condition:

Write to `semantics.json` ONLY when ALL of these are true:
1. Investigation reached a **verified conclusion** (not a hypothesis)
2. `lifetime: "permanent"` — the finding generalizes beyond this specific incident
3. All mandatory fields can be populated
4. Would save a new engineer 30+ minutes of re-investigation

NEVER write:
- Mid-investigation before ruling out alternatives
- Session-specific state ("3 orphaned rows exist right now")
- Unverified hypotheses
- Findings that are obvious from reading the code or docs

---

## Use case: JIRA-PLAT-42 → PR-123 → Build-456 (failing)

**Setup:** A Jira ticket reports OOM errors in CI on the payment service. A PR is raised. The CI build fails consistently. Claude Code CLI is used to investigate.

**Artifacts:**
- `JIRA-PLAT-42` — "CI builds on payment-service OOM intermittently under load tests"
- `PR-123` — Adds parallel execution to the load test suite
- `Build-456` — Failing CI build on `payment-service` repo
- `Repo-R` — `payment-service` monorepo

---

### Investigation session

Claude Code CLI runs the following sequence:

```
1. cat ci-build-456.log | grep -i "outofmemory\|heap space"
   → Multiple OOM errors in test phase

2. grep "maxParallelForks\|forkEvery" build.gradle
   → maxParallelForks not set (defaults to all CPUs)

3. cat .github/workflows/ci.yml | grep -i "Xmx\|memory\|heap"
   → -Xmx512m set on runner, no per-fork limit

4. grep -r "@Tag.*LoadTest\|@Category.*LoadTest" src/test
   → 47 load tests, each allocating ~200MB in setup

5. git log --oneline --diff-filter=M build.gradle | head -10
   → PR-123 added 12 new load tests, bumping parallelism impact

6. Run locally: ./gradlew test -Dorg.gradle.jvmargs="-Xmx512m"
   → Reproduces OOM locally under constrained heap
```

**Hypotheses ruled out:**
- Flaky test — OOM is deterministic under 512m heap
- Dependency conflict — `mvn dependency:tree` clean
- New test logic — OOM occurs even on old tests when heap is constrained

**Conclusion:** CI runners cap per-fork heap at 512m. With maxParallelForks unset (defaults to CPU count = 8), 8 forks × 200MB = 1.6GB needed but only 512m available. PR-123 added 12 tests but didn't set `maxParallelForks`.

---

### Graph structure

```
constraint:ci-runner-fork-heap-limit [subsystem:ci, hard]
"Each CI runner fork is capped at 512m heap.
 Default maxParallelForks × per-test allocation exceeds this."
│
├── CAUSES → signal:oom-ci-not-local [subsystem:ci]
│   "OOM in CI but not local looks like a flaky test —
│    actually it's fork heap exhaustion at default parallelism"
│        │
│        └── RULED_OUT ← finding:build-456-oom-root-cause [module:payment-service-build]
│            "Root cause: unset maxParallelForks × 200MB per test > 512m fork limit"
│
└── SHAPED_BY ← decision:serialize-load-tests [module:payment-service-build]
    "Set maxParallelForks=1 for load test suite"
```

**4 nodes, 3 edges.** One hard environment constraint causes one misleading signal, drives one implementation decision, and the finding connects the investigation to the signal it ruled out.

---

### Entries written to `semantics.json`

**Entry 1 — Constraint CAUSES Signal**

```json
{
  "id": "rel-constraint:ci-runner-fork-heap-limit-CAUSES-signal:oom-ci-not-local",
  "created_at": "2026-04-03T10:22:00Z",
  "from": {
    "id": "constraint:ci-runner-fork-heap-limit",
    "type": "Constraint",
    "label": "CI runner forks are capped at 512m heap",
    "scope": "subsystem:ci",
    "description": "GitHub Actions runners set -Xmx512m per JVM fork. With maxParallelForks unset, Gradle spawns one fork per CPU core. Memory-intensive tests (>100MB each) exhaust the per-fork limit under default parallelism.",
    "source": "environment",
    "hard": true,
    "symptom": "OutOfMemoryError in test phase on CI. Passes locally because developer machines have more heap available by default.",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "rel": "CAUSES",
  "to": {
    "id": "signal:oom-ci-not-local",
    "type": "Signal",
    "label": "OOM in CI but not local looks like a flaky test",
    "scope": "subsystem:ci",
    "observation": "OutOfMemoryError in CI test phase, same tests pass locally",
    "appears_to_mean": "Test is flaky or has a race condition specific to CI environment",
    "actually_means": "CI forks are heap-constrained. Default maxParallelForks × per-test allocation exceeds the limit. Not flaky — deterministic under constrained heap.",
    "conditions": "Any test suite where individual tests allocate >100MB and maxParallelForks is not explicitly set",
    "evidence": "Build-456 investigation: reproduced locally with -Xmx512m, consistent OOM on same tests",
    "command": "./gradlew test -Dorg.gradle.jvmargs=\"-Xmx512m\"",
    "output_pattern": "OutOfMemoryError: Java heap space",
    "lifetime": "permanent",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "properties": {
    "edge_context": "The 512m fork cap is the root cause. The misleading surface signal is that tests pass locally — this makes engineers assume flakiness before checking heap limits. The signal documents this trap so the next engineer skips straight to checking maxParallelForks.",
    "inferred": true
  }
}
```

**Entry 2 — Decision SHAPED_BY Constraint**

```json
{
  "id": "rel-decision:serialize-load-tests-SHAPED_BY-constraint:ci-runner-fork-heap-limit",
  "created_at": "2026-04-03T10:22:00Z",
  "from": {
    "id": "decision:serialize-load-tests",
    "type": "Decision",
    "label": "Set maxParallelForks=1 for load test suite in payment-service",
    "scope": "module:payment-service-build",
    "trigger": "Build-456 OOM failure after PR-123 added parallel load tests. JIRA-PLAT-42.",
    "rationale": "Load tests each allocate ~200MB. With default parallelism (8 cores), 8 forks × 200MB exceeds the 512m CI runner limit. Serializing load tests trades CI speed for reliability.",
    "alternatives": [
      {
        "option": "Increase CI runner heap",
        "rejected_because": "GitHub Actions standard runners impose -Xmx512m per fork; this is not a configurable value at the workflow level"
      },
      {
        "option": "Reduce per-test allocation",
        "rejected_because": "Load tests require realistic data volumes to be meaningful; reducing allocation would invalidate test results"
      }
    ],
    "confidence": "high",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "rel": "SHAPED_BY",
  "to": {
    "id": "constraint:ci-runner-fork-heap-limit",
    "type": "Constraint",
    "label": "CI runner forks are capped at 512m heap",
    "scope": "subsystem:ci",
    "description": "GitHub Actions runners set -Xmx512m per JVM fork. With maxParallelForks unset, Gradle spawns one fork per CPU core. Memory-intensive tests (>100MB each) exhaust the per-fork limit under default parallelism.",
    "source": "environment",
    "hard": true,
    "symptom": "OutOfMemoryError in test phase on CI. Passes locally because developer machines have more heap available by default.",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "properties": {
    "edge_context": "The constraint makes parallelism infeasible for any test that allocates >100MB. maxParallelForks=1 in build.gradle is not a performance oversight — it is the only option given the CI heap cap. Removing it will reintroduce OOM on CI.",
    "inferred": true
  }
}
```

**Entry 3 — Finding RULED_OUT Signal**

```json
{
  "id": "rel-finding:build-456-oom-root-cause-RULED_OUT-signal:oom-ci-not-local",
  "created_at": "2026-04-03T10:22:00Z",
  "from": {
    "id": "finding:build-456-oom-root-cause",
    "type": "Finding",
    "label": "Payment service CI OOM is heap exhaustion at default fork parallelism, not test flakiness",
    "scope": "module:payment-service-build",
    "question": "Why does the payment service test suite OOM in CI but pass locally?",
    "answer": "CI runner forks are capped at 512m heap. Gradle's default maxParallelForks equals CPU count (8 on the runner). Load tests each allocate ~200MB. 8 × 200MB = 1.6GB required, 512m available. Fix: set maxParallelForks=1 in the load test suite configuration.",
    "ruled_out": [
      "Flaky test — OOM is 100% reproducible under -Xmx512m locally; not environment-specific timing",
      "Dependency conflict — gradle dependencies output clean, no version conflicts introduced in PR-123",
      "New test logic in PR-123 — OOM occurs on pre-existing load tests when heap is constrained, not only new tests"
    ],
    "evidence": [
      "ci-build-456.log: OutOfMemoryError on 14 tests across 3 test classes",
      "Local reproduction: ./gradlew test -Dorg.gradle.jvmargs=-Xmx512m fails on same tests",
      ".github/workflows/ci.yml: -Xmx512m confirmed per-fork in JVM args"
    ],
    "confidence": "high",
    "conditions": "Applies to any JVM build on GitHub Actions standard runners with memory-intensive parallel tests and unset maxParallelForks",
    "lifetime": "permanent",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "rel": "RULED_OUT",
  "to": {
    "id": "signal:oom-ci-not-local",
    "type": "Signal",
    "label": "OOM in CI but not local looks like a flaky test",
    "scope": "subsystem:ci",
    "observation": "OutOfMemoryError in CI test phase, same tests pass locally",
    "appears_to_mean": "Test is flaky or has a race condition specific to CI environment",
    "actually_means": "CI forks are heap-constrained. Default maxParallelForks × per-test allocation exceeds the limit.",
    "conditions": "Any test suite where individual tests allocate >100MB and maxParallelForks is not explicitly set",
    "evidence": "Build-456 investigation",
    "command": "./gradlew test -Dorg.gradle.jvmargs=\"-Xmx512m\"",
    "output_pattern": "OutOfMemoryError: Java heap space",
    "lifetime": "permanent",
    "created_at": "2026-04-03T10:22:00Z"
  },
  "properties": {
    "edge_context": "The finding explicitly ruled out flakiness by reproducing the OOM deterministically under constrained heap. The RULED_OUT edge connects the investigation conclusion to the signal it disproves, so future traversal from the signal lands directly on the verified root cause.",
    "inferred": true
  }
}
```

---

### What the graph captures that code doesn't

After the PR is merged and Build-456 is fixed, `build.gradle` has `maxParallelForks=1` with a comment. What the code does **not** capture:

1. **Why 1 specifically** — the Signal explains the 512m × default-parallelism arithmetic causing the failure
2. **What was ruled out** — the Finding's `ruled_out` list saves the next engineer from spending hours on flakiness
3. **The generalization** — the Constraint applies to any memory-intensive test on GitHub Actions, not just this suite
4. **The misleading surface** — the Signal documents that "passes locally" is not evidence of flakiness

Six months later, when a different team hits the same OOM on a different service, a query for `"OOM CI passing local"` lands on `signal:oom-ci-not-local` instantly. The constraint, decision, and finding are already there. No re-investigation needed.

---

## Graph health (CLI additions)

Same rules as Cursor (fan-out cap ≤5, prefer chains over stars, orphan prohibition, reuse before creating) plus:

- **`lifetime: "session"` entries are never written** — discard at session end
- **Inconclusive investigations produce nothing** — if `confidence` is `low` or the question has no verified answer, nothing is written
- **`ruled_out` must be populated** — a Finding without ruled_out hypotheses is not a Finding, it's a guess
- **Findings should connect to existing nodes** — use `RULED_OUT` when the hypothesis is already a Signal or Constraint in the graph
