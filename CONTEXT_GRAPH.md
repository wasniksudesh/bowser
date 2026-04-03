# Context Graph — Capturing Tribal Knowledge from AI-Assisted Development

## What

A structured knowledge graph that captures **why** a codebase works the way it does — decisions, constraints, operational patterns, and tribal knowledge — as a byproduct of day-to-day AI-assisted development.

The graph lives as a single append-only JSON file (`semantics.json`) in each repository. Every time an AI agent (Cursor) completes a task — implementing a feature, debugging an incident, analyzing data — it writes the reasoning, constraints, and decisions it encountered into the graph.

## Why

Code explains **what** exists. It doesn't explain:
- Why this approach was chosen over alternatives
- What was tried before and why it failed
- Which metrics are misleading during incidents
- What breaks if you change something that looks safe
- Which two services can't run concurrently and why

This knowledge lives in engineers' heads. When they leave, it leaves with them. Onboarding a new engineer means months of rediscovery.

The context graph captures this knowledge **at the moment it's produced** — during implementation, debugging, and planning — not as a separate documentation effort.

**Local graphs** (per-developer, per-repo) feed into a **global graph** (enterprise-wide), giving agents and engineers access to collective institutional knowledge.

## How

A Cursor rule (`.cursor/rules/semantics.mdc`) instructs the AI agent to write to `semantics.json` whenever it completes a task that produced graph-worthy knowledge. The agent only writes when:

1. The task is complete (code applied, conclusion reached)
2. All mandatory fields can be populated
3. The knowledge would save a new engineer 30+ minutes of confusion

The graph is append-only. Corrections use SUPERSEDES (new decision replaces old) and LIFTED (constraint removed). Old entries stay for historical context.

---

## Schema

### Node types

**Decision** — a choice made between alternatives.

| Field | Required | Description |
|---|---|---|
| `id` | yes | `decision:<slug>` |
| `type` | yes | `"Decision"` |
| `label` | yes | What was decided |
| `scope` | yes | `system`, `subsystem:<name>`, or `module:<name>` |
| `trigger` | yes | What prompted this decision |
| `rationale` | yes | Why this option was chosen |
| `alternatives` | yes (≥1) | `[{ "option": "", "rejected_because": "" }]` |
| `confidence` | yes | `"high"`, `"medium"`, or `"low"` |
| `uncertainty` | when not high | What could invalidate this decision |
| `created_at` | yes | ISO8601 |

Gate: *"Was there a choice between alternatives?"* No alternatives = not a decision.

**Constraint** — an external force that limits choices.

| Field | Required | Description |
|---|---|---|
| `id` | yes | `constraint:<slug>` |
| `type` | yes | `"Constraint"` |
| `label` | yes | What is constrained |
| `scope` | yes | `system`, `subsystem:<name>`, or `module:<name>` |
| `description` | yes | Full description |
| `source` | yes | See source enum below |
| `hard` | yes | `true` if violation causes failure |
| `symptom` | when hard | What breaks if violated |
| `created_at` | yes | ISO8601 |

Gate: *"Is this imposed on us, not chosen by us?"* If it was a choice, it's a Decision.

Source enum: `platform`, `observed-failure`, `user-requirement`, `api-limitation`, `performance`, `business-rule`, `legal`, `environment`, `dependency`, `organizational`, `plan`

**Insight** — tribal knowledge that doesn't fit Decision or Constraint.

| Field | Required | Description |
|---|---|---|
| `id` | yes | `insight:<slug>` |
| `type` | yes | `"Insight"` |
| `label` | yes | One-line summary |
| `scope` | yes | `system`, `subsystem:<name>`, or `module:<name>` |
| `body` | yes | Full explanation |
| `failure_without` | yes | What goes wrong if someone doesn't know this |
| `created_at` | yes | ISO8601 |

Gate: *"Would someone be fooled or waste significant time without this?"*

**Signal** — operational pattern where observation misleads interpretation.

| Field | Required | Description |
|---|---|---|
| `id` | yes | `signal:<slug>` |
| `type` | yes | `"Signal"` |
| `label` | yes | One-line summary |
| `scope` | yes | `system`, `subsystem:<name>`, or `module:<name>` |
| `observation` | yes | What you see |
| `appears_to_mean` | yes | What it looks like |
| `actually_means` | yes | What it really is |
| `conditions` | yes | When this interpretation applies |
| `evidence` | yes | How we know (incident, analysis) |
| `created_at` | yes | ISO8601 |

Gate: *"Has someone been fooled by this, or would they be?"*

### Relationship types

| Relationship | Direction | Meaning |
|---|---|---|
| `SHAPED_BY` | Decision → Constraint | Constraint forced this decision |
| `SUPERSEDES` | Decision → Decision | New replaces old |
| `ABANDONED` | Decision → Decision | Considered and rejected |
| `EXPLAINS` | Insight → Decision\|Constraint\|Signal | Clarifies the target |
| `CONTRADICTS` | Constraint → Constraint | Two constraints are in tension |
| `LIFTED` | Constraint → Decision | Constraint removed, enabling new decision |
| `CAUSES` | Constraint\|Signal → Constraint\|Signal | Runtime causal chain |

### Entry format

Each entry is a relationship between two fully-embedded nodes:

```json
{
  "id": "rel-<from-slug>-<REL>-<to-slug>",
  "created_at": "2026-04-03T00:00:00Z",
  "from": { },
  "rel": "SHAPED_BY",
  "to": { },
  "properties": {
    "edge_context": "Why this relationship exists, readable from either direction",
    "inferred": false
  }
}
```

`edge_context` is the most important field. It makes every entry self-contained — a reader can understand the relationship without traversing to other entries.

### Scope hierarchy

| Scope | Contains | Expected size |
|---|---|---|
| `system` | Architecture-level decisions, cross-cutting constraints | ~10-20 nodes |
| `subsystem:<name>` | Module-boundary decisions, interface contracts | ~5-15 per subsystem |
| `module:<name>` | Implementation decisions, tactical workarounds | ~3-10 per module |

For enterprise rollup: `system` and `subsystem` scope entries are candidates for the global graph. `module` scope stays local.

### Graph health

- **Fan-out cap**: ≤ 5 edges per node. Decompose superhubs by introducing intermediate decisions.
- **Prefer chains over stars**: each node should be a step in a reasoning chain, not a hub.
- **Orphan prohibition**: every node must have at least one relationship.
- **Reuse before creating**: check existing nodes before creating new ones.

---

## Demo graph

A macOS app uses CEF (Chromium Embedded Framework) for browser rendering, ScreenCaptureKit (SCK) for screen recording, and has two independent microphone capture services. Here's the graph that captured why:

```
constraint:cef-sck-audio-conflict [system, hard]
│  "CEF audio renderer crashes if Core Audio graph
│   is modified while SCK runs"
│
├── SHAPED_BY ← decision:mic-avcapturesession [subsystem:meeting-recorder]
│   │  "Use AVCaptureSession for mic, not AVAudioEngine"
│   │
│   ├── EXPLAINS ← insight:dictation-vs-meeting-mic [system]
│   │    "Two mic services exist intentionally — unifying
│   │     them reintroduces the crash"
│   │
│   └── ABANDONED ← decision:mic-avaudioengine [subsystem:meeting-recorder]
│        "AVAudioEngine was tried first but crashes CEF
│         when SCK is active"
│
└── SHAPED_BY ← decision:mic-before-sck [subsystem:meeting-recorder]
     "Start mic before SCK — reversing the order
      triggers the same crash"
```

**5 nodes, 4 edges.** One hard constraint drives two implementation decisions. One abandoned decision records the dead end. One insight prevents a future engineer from "cleaning up" the apparent duplication.

---

## Walkthrough: query traversal

### Query 1: "I want to refactor MicCaptureService to use AVAudioEngine"

**Step 1 — Semantic match.** Query matches `decision:mic-avcapturesession` (label mentions both MicCaptureService and AVAudioEngine).

**Step 2 — Follow SHAPED_BY edge.** Reaches `constraint:cef-sck-audio-conflict`. Hard constraint. Symptom: *"CEF audio renderer crash, 100% reproducible."*

**Step 3 — Follow ABANDONED edge.** Finds `decision:mic-avaudioengine`. Edge context: *"AVAudioEngine was the original choice. Abandoned after discovering the CEF/SCK conflict during integration testing."*

**Step 4 — Check for LIFTED.** No LIFTED edge on the constraint. It's still active.

**Result:** The graph tells the agent this was already tried and abandoned due to a hard, active constraint. The agent can give a definitive answer with evidence instead of attempting the refactor and discovering the crash.

### Query 2: "Why are there two mic capture services? Can we consolidate?"

**Step 1 — Semantic match.** Query matches `insight:dictation-vs-meeting-mic`.

**Step 2 — Read the insight.** Body explains: VoiceInputService uses AVAudioEngine (for dictation), MicCaptureService uses AVCaptureSession (for meeting recording). They share an endpoint but are never active simultaneously. `failure_without`: *"Engineer attempts to unify them, reintroducing the CEF/SCK crash during meetings."*

**Step 3 — Follow EXPLAINS edge to `decision:mic-avcapturesession`.** Rationale explains why AVCaptureSession is used specifically for meeting recording.

**Step 4 — Fan out from the decision's constraint.** `constraint:cef-sck-audio-conflict` — the underlying reason the two services must remain separate.

**Result:** The graph explains that the duplication is intentional, what would break if consolidated, and the specific constraint that prevents it. A new engineer gets the full story in one traversal instead of discovering it through a crash.

### Query 3: "Our monitoring shows metricA has been 0 for 2 hours — is the payment service down?"

*Assumes a Signal node exists in the graph:*

```json
{
  "id": "signal:metrica-zero-batch-reset",
  "type": "Signal",
  "scope": "subsystem:payments",
  "observation": "metricA reads 0 for extended periods",
  "appears_to_mean": "Payment service is down, no transactions processing",
  "actually_means": "Nightly batch job resets the counter. Service is healthy. Counter resumes after batch completes (~3 hours).",
  "conditions": "Occurs nightly between 02:00-05:00 UTC",
  "evidence": "Incident INC-2847 — 3 engineers spent 4 hours investigating before discovering the batch reset"
}
```

**Step 1 — Semantic match.** Query matches `signal:metrica-zero-batch-reset`.

**Step 2 — Read the signal.** `appears_to_mean` vs `actually_means` immediately resolves the ambiguity. `conditions` confirms the time window. `evidence` cites the incident where this was learned.

**Result:** Instead of repeating the 4-hour investigation from INC-2847, the agent (or engineer) gets the answer instantly. This is operational tribal knowledge that no amount of code reading would reveal.

---

## Capture lifecycle

```
  Engineer works with AI agent
            │
            ▼
  Agent completes task
  (code applied, conclusion reached)
            │
            ▼
  Agent checks: did this produce
  graph-worthy knowledge?
            │
     ┌──────┴──────┐
     │ NO           │ YES
     │              ▼
     │   All mandatory fields
     │   can be populated?
     │        │
     │   ┌────┴────┐
     │   │ NO      │ YES
     │   │         ▼
     │   │   Would save 30+ min
     │   │   of confusion?
     │   │        │
     │   │   ┌────┴────┐
     │   │   │ NO      │ YES
     │   │   │         ▼
     │   │   │   Append to semantics.json
     │   │   │
     └───┴───┘
     Nothing written
```

## Local → Global

```
  repo-a/semantics.json ──┐
  repo-b/semantics.json ──┼──→ Ingestion server
  repo-c/semantics.json ──┘         │
                                    ▼
                           Semantic dedup
                           (resolve slug conflicts,
                            merge equivalent nodes)
                                    │
                                    ▼
                            Global context graph
                           (system + subsystem scope)
```

Module-scope entries stay local. System and subsystem scope entries are candidates for the global graph. The ingestion server handles slug normalization and semantic deduplication across contributors.
