# Context Graph — Browser (Chrome Extension)

## What

An attention-weighted topic index built from a user's browsing activity. A Chrome extension records which pages a user visited, how long they engaged, and whether they extracted content — producing a per-user graph of **what was researched and how deeply**.

The graph lives as a single JSON file (`neo4j-graph-browser.json`) ingested into Neo4j. It is separate from the Cursor and Claude CLI semantic graphs. It does not model decisions, constraints, or code-level tribal knowledge. It models **research attention** — what a user actually read, for how long, and what they found worth copying.

## Why: what browser uniquely observes

Every tool in an engineer's workflow can be queried via API:

| Tool | What its API provides |
|---|---|
| JIRA | Tickets, statuses, assignees |
| Confluence | Document exists, last edited |
| GitHub | PR, comments, diff |
| Slack | Messages sent |

None of these tell you whether the engineer actually **read** the content, for how long, or whether they extracted anything from it. The browser is the only system with that signal.

The browser graph captures:
- **Attention** — dwell time and scroll depth per page, per session
- **Extraction** — whether the user copied text (binary signal of value, no content stored)
- **Recurrence** — whether the user returned to the same page across multiple sessions over time
- **Topic coverage** — which topics the user has substantive exposure to, ranked by accumulated engagement

This is the browser's contribution to the global context graph. It does not attempt to infer decisions, model thought process, or capture why the user browsed. Navigation patterns are not interpreted.

---

## What the browser graph does NOT try to do

- **Model decisions or reasoning** — visiting a page does not mean the user agrees with it or acted on it. A LinkedIn tab open next to a docs page is noise.
- **Infer intent from search queries** — a search query is input, not outcome. There is no signal that results were useful.
- **Capture thought process** — navigation order does not equal thinking order. Research arcs and pivots require LLM inference per page, which is out of scope.
- **Replace JIRA/PD/Confluence APIs** — document relationships, ticket owners, and structured work data come from source APIs, not from passive browsing observation.
- **Produce Decisions, Constraints, Insights, or Signals** — those node types belong to the Cursor and Claude CLI graphs. The browser graph has its own schema.

---

## Schema

### Node types

**User**

```json
{
  "id": "user:<user_id>",
  "label": "User",
  "properties": {
    "user_id": ""
  }
}
```

One node per user. The anchor of the graph. All sessions hang off this node.

---

**Session**

```json
{
  "id": "session:<session_id>",
  "label": "Session",
  "properties": {
    "session_id": "",
    "start_ts": "",
    "end_ts": "",
    "page_count": 0,
    "source": "chrome-extension"
  }
}
```

A browsing session — a contiguous period of activity. Sessions are keyed daily by the extension. The `source` field identifies the capture mechanism.

---

**Page**

```json
{
  "id": "page:<normalized_url>",
  "label": "Page",
  "properties": {
    "url": "",
    "normalized_url": "",
    "title": "",
    "path": "",
    "page_type": "documentation | blog | search | forum | product | generic | app",
    "lang": ""
  }
}
```

A unique URL the user visited. `normalized_url` strips query parameters and fragments for deduplication. `page_type` is derived heuristically from URL path patterns and HTML structure — no LLM inference.

---

**Domain**

```json
{
  "id": "domain:<host>",
  "label": "Domain",
  "properties": {
    "host": ""
  }
}
```

A unique hostname. Groups pages from the same origin. Allows domain-level attention queries without traversing every individual page.

---

**Topic**

```json
{
  "id": "topic:<slug>",
  "label": "Topic",
  "properties": {
    "name": "",
    "slug": "",
    "category": ""
  }
}
```

A subject area derived from page metadata (title, meta description, og tags, headings). Topics are named slugs — deterministic and reusable across sessions. They are not LLM-generated; they are extracted from structured page metadata already available in the DOM.

`category` groups topics into broader areas (e.g. `graph-ai`, `software-ecosystem`, `infra`).

---

### Relationship types

| Relationship | Direction | Meaning | Key properties |
|---|---|---|---|
| `HAS_SESSION` | User → Session | User owns this session | — |
| `VISITED` | Session → Page | Session visited this page | `seq`, `ts`, `dwell_seconds`, `scroll_depth_pct`, `copied`, `copied_text_length`, `is_terminal` |
| `NEXT` | Page → Page | Navigation sequence within a session | `session_id`, `from_seq`, `to_seq` |
| `ON_DOMAIN` | Page → Domain | Page belongs to this domain | — |
| `HAS_TOPIC` | Page → Topic | Page covers this topic | `source`, `confidence` |
| `HAS_TOPIC` | Session → Topic | Session's aggregated topic coverage | `source: "aggregated"`, `page_count`, `avg_confidence` |

---

### VISITED edge — attention properties

The `VISITED` edge carries the attention signal. These are the most important properties in the schema:

| Property | Type | Description |
|---|---|---|
| `seq` | int | Visit sequence number within the session |
| `ts` | ISO8601 | Timestamp of visit |
| `dwell_seconds` | int | Time user spent on this page |
| `scroll_depth_pct` | float | How far down the page the user scrolled (0–100) |
| `copied` | bool | Whether the user copied any text from this page |
| `copied_text_length` | int | Length of the longest copy event on this page |
| `is_terminal` | bool | Whether this was the last page in the session |

**`copied` is the strongest single attention signal.** It is a zero-inference, privacy-safe indicator that the user found something on the page worth extracting. The content is never stored — only the boolean and length.

**`dwell_seconds` + `scroll_depth_pct` together** give an engagement proxy: a page with 30s dwell and 10% scroll was skimmed. A page with 4min dwell and 80% scroll was read.

---

### Cross-session URL properties

Each URL entry in the flush JSON carries two additional fields populated from the persistent cross-session store:

| Property | Description |
|---|---|
| `cross_session_visits` | Total number of visits across all sessions and days |
| `first_seen_at` | ISO8601 timestamp of the first ever visit to this URL |

A URL with `cross_session_visits >= 3` on different days is a strong relevance signal — the user returned to it independently. This is captured by `background.js` in a persistent `url_cross_sessions` store, not in the daily-keyed session data.

---

### HAS_TOPIC edge — topic derivation

Two sources, distinguished by the `source` property:

| `source` | Meaning |
|---|---|
| `"derived"` | Derived from this page's metadata (title, headings, OG tags) at extraction time |
| `"aggregated"` | Aggregated from all pages in the session that share this topic |

`confidence` on derived edges reflects extraction quality (0.5 base, incremented for `<main>` element, OG title, canonical URL, word count > 200). It is a structural quality score, not a semantic relevance score.

---

## Capture pipeline

```
Chrome extension (content.js, background.js)
  │
  │  Records per-tab:
  │  - URL, title, page_type
  │  - dwell_seconds (visibility-based)
  │  - scroll_depth_pct (content.js)
  │  - copied (copy event listener)
  │  - copied_text_length (max copy event length)
  │
  ▼
chrome.storage.local (daily-keyed sites map)
  │
  │  On flush (every 5 min or manual):
  │  - Annotates each URL with cross_session_visits, first_seen_at
  │    from persistent url_cross_sessions store
  │
  ▼
{ddMMyy}_{domain-slug}.json  (per-domain daily flush)
  │
  │  ETL step (not yet implemented):
  │  - Maps site flush → neo4j-graph-browser.json format
  │  - Deduplicates pages, derives topics, aggregates session topics
  │
  ▼
neo4j-graph-browser.json
  │
  ▼
ingest.py → Neo4j
```

---

## Demo graph

An engineer researches audio APIs for a macOS meeting recorder feature over one session:

```
user:u1
└── HAS_SESSION → session:sess_audio-research
    │  start: 10:00, end: 10:45, pages: 6
    │
    ├── VISITED (seq:1, dwell:180s, scroll:72%, copied:false) →
    │   page:developer.apple.com/avcapturesession
    │   └── ON_DOMAIN → domain:developer.apple.com
    │   └── HAS_TOPIC → topic:avcapturesession (confidence:0.9)
    │
    ├── VISITED (seq:2, dwell:420s, scroll:91%, copied:true, copied_text_length:340) →
    │   page:developer.apple.com/avaudioengine
    │   └── ON_DOMAIN → domain:developer.apple.com
    │   └── HAS_TOPIC → topic:avaudioengine (confidence:0.9)
    │
    ├── VISITED (seq:3, dwell:45s, scroll:18%, copied:false) →
    │   page:stackoverflow.com/q/avcapturesession-vs-avaudioengine
    │   └── ON_DOMAIN → domain:stackoverflow.com
    │   └── HAS_TOPIC → topic:avcapturesession (confidence:0.75)
    │
    ├── VISITED (seq:4, dwell:600s, scroll:88%, copied:true, copied_text_length:820) →
    │   page:github.com/issues/cef-audio-crash-sck
    │   └── ON_DOMAIN → domain:github.com
    │   └── HAS_TOPIC → topic:screencapturekit (confidence:0.8)
    │
    ├── NEXT chains: seq1→seq2→seq3→seq4→seq5→seq6
    │
    └── HAS_TOPIC (aggregated, page_count:2) → topic:avcapturesession
    └── HAS_TOPIC (aggregated, page_count:2) → topic:avaudioengine
    └── HAS_TOPIC (aggregated, page_count:1) → topic:screencapturekit
```

**6 nodes (User, Session, 3 Pages + Domain nodes + Topic nodes), attention on edges.**

From this graph a research agent can determine:
- The engineer spent 7 minutes on the AVAudioEngine docs and copied 340 chars — substantive engagement
- The GitHub issue on CEF/audio/SCK got the longest dwell (10 min) and the largest copy (820 chars) — this was the most valuable page in the session
- The Stack Overflow page was skimmed (45s, 18% scroll, no copy) — not useful
- AVCaptureSession and AVAudioEngine are the dominant topics this session

---

## Walkthrough: query traversals

### Use case 1: Research agent answering "What has this user read about audio capture APIs?"

**Step 1 — Start at User node.** Traverse `HAS_SESSION` to all sessions.

**Step 2 — Filter by topic.** Find sessions with `HAS_TOPIC → topic:avcapturesession` or `topic:avaudioengine`. `avg_confidence ≥ 0.75`.

**Step 3 — Traverse VISITED edges on matching sessions.** Collect pages with `dwell_seconds > 120` (substantive read). Sort by `dwell_seconds DESC`.

**Step 4 — Check `copied: true` pages first.** Pages where the user copied text are ranked highest. `copied_text_length` breaks ties.

**Result:**
> "User has 3 sessions totalling ~45 minutes on audio capture APIs. Highest engagement: developer.apple.com/avaudioengine (7 min, copied) and a CEF/SCK GitHub issue (10 min, largest copy). One Stack Overflow page was skimmed and produced no copy. The GitHub issue is likely the most informative source the user found."

No LLM inference. Pure graph traversal on attention metrics.

---

### Use case 2: Bridge layer — connecting browser research to a Cursor semantic decision

A Cursor Decision exists:

```json
{
  "id": "decision:mic-avcapturesession",
  "trigger": "CEF audio renderer crash observed when AVAudioEngine ran alongside ScreenCaptureKit",
  "created_at": "2026-04-03T11:30:00Z"
}
```

The bridge layer runs:

1. **Temporal filter.** Sessions within ±24h of `decision.created_at` → `session:sess_audio-research` (10:00–10:45).

2. **Entity overlap.** Decision mentions `AVAudioEngine`, `AVCaptureSession`, `ScreenCaptureKit`. Pages in the session have `HAS_TOPIC` edges to `topic:avaudioengine`, `topic:avcapturesession`, `topic:screencapturekit`. Overlap: 3/3 — strong match.

3. **Attention filter.** The GitHub CEF/SCK issue has `dwell: 600s + copied: true`. This is the page most likely to have informed the decision.

4. **Bridge edge written:**

```json
{
  "type": "CONTEXT_FOR",
  "from": "session:sess_audio-research",
  "to": "decision:mic-avcapturesession",
  "properties": {
    "via_pages": ["page:github.com/issues/cef-audio-crash-sck"],
    "match_signal": "entity_overlap + temporal",
    "confidence": 0.88,
    "bridged_at": "2026-04-03T11:35:00Z"
  }
}
```

**Result:** The global graph can now answer: *"Before deciding to use AVCaptureSession, the engineer spent 10 minutes reading a GitHub issue about the CEF/SCK audio crash and copied 820 characters from it."*

---

### Use case 3: Attention ranking for an enterprise agent

An enterprise agent asks: *"Which engineers have substantive exposure to ScreenCaptureKit?"*

Query:
1. Find all `Topic` nodes where `slug = "screencapturekit"`.
2. Traverse incoming `HAS_TOPIC` edges (`source: "aggregated"`).
3. For each matching Session, follow `HAS_SESSION ← User`.
4. Rank by: `sum(dwell_seconds on SCK pages) + bonus for any copied:true`.

Output: ranked user list with evidence — not a guess, not self-reported skill, but measured reading time and extraction events.

This is useful for:
- Finding the right person to review a PR touching SCK
- Identifying who to ask during an incident
- Onboarding routing (who can mentor this topic)

---

### Use case 4: Cross-session recurrence as relevance signal

A Page has `cross_session_visits: 4` over 3 weeks. The user has returned to it independently on 4 separate occasions.

Query:
```
MATCH (s:Session)-[v:VISITED]->(p:Page)
WHERE p.cross_session_visits >= 3
AND v.copied = true
RETURN p.url, p.title, p.cross_session_visits, v.dwell_seconds
ORDER BY p.cross_session_visits DESC
```

These pages are the user's **reference material** — not incidentally visited, but returned to. A research agent surface this as: *"This engineer consistently references developer.apple.com/avcapturesession — it's likely a primary source for their audio capture work."*

---

## Attention ranking model

For a given page P and user U, the attention score is:

```
attention_score(P, U) =
  sum(dwell_seconds across all VISITED edges) × 1.0
  + sum(scroll_depth_pct / 100 × dwell_seconds) × 0.5   (depth-weighted dwell)
  + copied × 50                                           (flat bonus per copy event)
  + copied_text_length × 0.05                             (length bonus)
  + (cross_session_visits - 1) × 30                       (recurrence bonus)
```

This score is computed at query time, not stored. It provides a single number for "how much did this user engage with this page" that accounts for time, depth, extraction, and recurrence.

Topics inherit their score from the max attention_score of pages tagged with that topic.

---

## Graph health

### What keeps this graph from bloating

1. **Pages are deduplicated by `normalized_url`** — the same URL visited in 10 sessions is one Page node with 10 VISITED edges. No duplication.

2. **Topics are finite and reused** — topics are named slugs, not free-text. A new Page connecting to `topic:avcapturesession` reuses the existing node. Topics accumulate edges, not duplicate nodes.

3. **Dynamic app surfaces are excluded** — sessions in Gmail, Notion, Slack, Figma, Jira produce no Page or Topic nodes. Dwell is tracked for session completeness but not surfaced.

4. **Search result pages are excluded from topic derivation** — `page_type: "search"` pages contribute to NEXT chains but produce no `HAS_TOPIC` edges. Search queries are input, not research findings.

5. **`ingest_decision.keep: false` pages are excluded** — pages with fewer than 100 words or marked as search results are not ingested into the graph. They appear in the flush JSON for completeness but are filtered before Neo4j ingest.

### Expected growth

| Component | Growth rate | Bound |
|---|---|---|
| User nodes | 1 per user | Static |
| Session nodes | ~2–5 per user per day | Linear with time |
| Page nodes | Deduplicated by URL | Sublinear — revisits reuse nodes |
| Domain nodes | ~1 per domain ever visited | Converges quickly |
| Topic nodes | ~20–50 topics cover most engineering domains | Near-static |
| VISITED edges | 1 per session×page combination | Linear with sessions |

The graph grows in edges, not nodes. Topic and Domain node counts stabilize early. Page nodes deduplicate aggressively. Only VISITED and NEXT edges grow linearly with usage.

---

## Local → Global

```
User A browser graph ──┐
User B browser graph ──┼──→ Ingestion server
User C browser graph ──┘         │
                                 ▼
                        Normalize page URLs
                        Merge topic nodes by slug
                        Aggregate cross-user topic coverage
                                 │
                                 ▼
                         Global browser graph
                        (User + Session + Page + Domain + Topic)
```

The global graph enables cross-user queries: *"Which pages on developer.apple.com have the highest aggregate attention across all engineers who worked on audio features?"*

Only `system` and `subsystem` scoped knowledge from Cursor/CLI feeds the global semantic graph. The browser graph is fully included — all scopes — because attention data is inherently personal and user-attributed.

---

## How browser graph differs from Cursor and Claude CLI graphs

| Dimension | Cursor / Claude CLI | Browser |
|---|---|---|
| Subject | Codebase knowledge — why things are built the way they are | Research attention — what was read and how deeply |
| Node types | Decision, Constraint, Insight, Signal, Finding | User, Session, Page, Domain, Topic |
| Relationship semantics | Causal (SHAPED_BY, CAUSES, ABANDONED) | Observational (VISITED, NEXT, HAS_TOPIC) |
| Mutability | Append-only, corrections via SUPERSEDES | Sessions close; Pages accumulate edges; Topics are stable |
| Query pattern | "Why does this code work this way?" | "What has this user researched?" |
| Write trigger | Task completion — agent decides | Automatic — extension records passively |
| LLM involvement | Agent writes graph as byproduct of reasoning | No LLM per page; topics from structured metadata only |
| Consumer | Code agents, onboarding, decision lookup | Research agents, expertise routing, bridge to semantic graph |

The two graphs share a Neo4j instance and a common ingestion pipeline, but their schemas do not overlap. The connection between them is the bridge layer — sparse, confidence-scored edges from Session nodes to Decision nodes, produced by a separate bridge process using temporal overlap and entity matching.
