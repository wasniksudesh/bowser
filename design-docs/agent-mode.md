# Bowser Agentic Execution – V1
# Cursor Prompt (Definitions → Responsibilities → Principles → LLD → E2E)

====================================================================
1. PURPOSE & SCOPE
====================================================================

This document defines V1 of Bowser’s agentic execution system.

V1 goals:
- Context-driven execution
- Plugin-based skills
- Centralized authentication via Context
- Notebook-style, replayable execution

Out of scope for V1:
- Vault / secret manager
- Prune / Fix / Validation agents
- Workflow automation
- Multi-user collaboration

====================================================================
2. CORE TERMS & DEFINITIONS
====================================================================

--------------------------------------------------------------------
2.1 PlannerAgent
--------------------------------------------------------------------

The PlannerAgent is the orchestration brain of the system.

It is responsible for:
- Interpreting user intent
- Selecting plugins and skills
- Creating an execution plan
- Determining when execution must pause
- Resuming execution after context updates
- Tracking step status and replay boundaries

--------------------------------------------------------------------
2.2 ContextAgent
--------------------------------------------------------------------

The ContextAgent is the sole interface between the system and the user.

It is responsible for:
- Collecting missing user inputs
- Collecting authentication on behalf of plugins
- Prompting the user via UI
- Storing all collected information as ContextArtifacts
- Re-prompting users on authentication failures

--------------------------------------------------------------------
2.3 OperationAgent
--------------------------------------------------------------------

An OperationAgent executes exactly one skill.

It is responsible for:
- Consuming context and auth supplied by PlannerAgent
- Executing a single plugin skill
- Producing exactly one output artifact

--------------------------------------------------------------------
2.4 Plugin
--------------------------------------------------------------------

A Plugin is a capability bundle that exposes skills and declares authentication needs.

A plugin:
- Declares authentication requirements
- Exposes one or more skills
- Does not manage user interaction

--------------------------------------------------------------------
2.5 Skill
--------------------------------------------------------------------

A Skill is a single executable operation exposed by a plugin.

A skill:
- Declares its functional inputs (no auth)
- Produces a typed artifact
- Is executed by an OperationAgent

--------------------------------------------------------------------
2.6 ContextArtifact
--------------------------------------------------------------------

A ContextArtifact is a versioned, immutable snapshot of all user-provided context.

It contains:
- User inputs (repo, limits, preferences)
- Authentication metadata
- Version history

--------------------------------------------------------------------
2.7 PlanStep
--------------------------------------------------------------------

A PlanStep represents one step in execution.

It binds:
- An agent
- A context version
- Input artifacts
- Output artifacts
- Execution status

--------------------------------------------------------------------
2.8 Artifact
--------------------------------------------------------------------

An Artifact is immutable output produced by a step.

Artifacts are:
- Typed
- Inspectable
- Versioned via lineage (never overwritten)

====================================================================
3. RESPONSIBILITIES & NON-RESPONSIBILITIES
====================================================================

--------------------------------------------------------------------
3.1 PlannerAgent
--------------------------------------------------------------------

PlannerAgent MUST:
- Build execution plans
- Enforce context and auth presence
- Pause execution when data is missing
- Resume execution from paused steps
- Invalidate downstream steps on context edits

PlannerAgent MUST NOT:
- Prompt users
- Handle secrets directly
- Modify artifacts

--------------------------------------------------------------------
3.2 ContextAgent
--------------------------------------------------------------------

ContextAgent MUST:
- Prompt users for missing context
- Prompt users for authentication
- Store all responses as ContextArtifacts
- Allow editing of any context field
- Create a new context version on every edit

ContextAgent MUST NOT:
- Execute skills
- Make planning decisions

--------------------------------------------------------------------
3.3 OperationAgent
--------------------------------------------------------------------

OperationAgent MUST:
- Execute exactly one skill
- Use context and auth blindly
- Produce one output artifact

OperationAgent MUST NOT:
- Ask the user questions
- Modify context
- Retry authentication
- Execute multiple skills

On auth failure, OperationAgent MUST emit a structured AuthFailure.

====================================================================
4. CORE DESIGN PRINCIPLES (NON-NEGOTIABLE)
====================================================================

1. Context is the single source of truth.
2. All user interaction flows through ContextAgent.
3. Context fields are always editable.
4. Context edits create new versions; old versions are preserved.
5. Authentication is declared at the plugin level.
6. Skills never declare authentication in inputSchema.
7. Multiple plugins may reuse the same authId.
8. Context prompts the user only once per authId.
9. Authentication strategies are OR-based (any one is acceptable).
10. Agents are narrowly scoped and non-overlapping.
11. Artifacts are immutable and append-only.
12. Every execution step is replayable.
13. Replays generate new artifacts.
14. No hidden memory or implicit state is allowed.
15. There is no vault integration in V1; secrets are opaque strings.

====================================================================
5. LOW-LEVEL DESIGN (LLD)
====================================================================

--------------------------------------------------------------------
5.1 Artifact Store
--------------------------------------------------------------------

Artifacts are append-only and immutable.

interface Artifact {
  artifactId: string
  type: string
  data: any
  producedByStep: string
  contextVersionUsed: number
  timestamp: number
}

class ArtifactStore {
  put(artifact: Artifact): void
  get(artifactId: string): Artifact
  listByStep(stepId: string): Artifact[]
}

--------------------------------------------------------------------
5.2 ContextArtifact (LLD)
--------------------------------------------------------------------

interface ContextArtifact {
  artifactId: string
  type: "context"
  version: number
  parentVersion?: number
  values: Record<string, any>
  auth: Record<string, {
    strategyUsed: string
    value: string
    valid: boolean
  }>
  timestamp: number
}

Rules:
- Immutable
- New version on every edit
- Never overwritten

--------------------------------------------------------------------
5.3 Plugin (LLD)
--------------------------------------------------------------------

interface Plugin {
  pluginId: string
  name: string
  version: string
  authRequirements: AuthRequirement[]
  skills: Skill[]
}

--------------------------------------------------------------------
5.4 AuthRequirement (LLD)
--------------------------------------------------------------------

interface AuthRequirement {
  authId: string
  description: string
  strategies: AuthStrategy[]   // OR
}

type AuthStrategy =
  | { type: "token"; contextKey: string }
  | { type: "oauth"; provider: string; scopes: string[]; contextKey: string }
  | { type: "user_password"; contextKey: string }

--------------------------------------------------------------------
5.5 Skill (LLD)
--------------------------------------------------------------------

interface Skill {
  skillId: string
  description: string
  inputSchema: JSONSchema
  outputArtifactType: string
  execute(input: any, auth: AuthContext): Promise<Artifact>
}

--------------------------------------------------------------------
5.6 PlannerAgent (LLD)
--------------------------------------------------------------------

class PlannerAgent {
  intent: string
  availablePlugins: Plugin[]
  contextArtifact: ContextArtifact
  artifactStore: ArtifactStore

  plan(): ExecutionPlan
  checkMissingContext(plan: ExecutionPlan): MissingContext[]
  pauseForContext(missing: MissingContext[]): void
  resumeFrom(stepId: string): void
  invalidateDownstream(stepId: string): void
}

--------------------------------------------------------------------
5.7 ExecutionPlan (LLD)
--------------------------------------------------------------------

interface ExecutionPlan {
  planId: string
  steps: PlanStep[]
}

interface PlanStep {
  stepId: string
  agentType: "ContextAgent" | "OperationAgent"
  pluginId?: string
  skillId?: string
  contextVersionUsed: number
  inputArtifacts: string[]
  outputArtifacts: string[]
  status: "pending" | "completed" | "invalidated"
}

--------------------------------------------------------------------
5.8 ContextAgent (LLD)
--------------------------------------------------------------------

class ContextAgent {
  requiredFields: ContextField[]
  requiredAuth: AuthRequirement[]
  currentContext?: ContextArtifact

  promptUser(): UIResponse
  createContextArtifact(response: UIResponse): ContextArtifact
  rePromptOnAuthFailure(authId: string): ContextArtifact
}

interface ContextField {
  name: string
  description: string
  required: boolean
}

--------------------------------------------------------------------
5.9 OperationAgent (LLD)
--------------------------------------------------------------------

class OperationAgent {
  skill: Skill
  context: ContextArtifact
  inputArtifacts: Artifact[]

  execute(): Promise<Artifact>
}

On auth failure:
throw AuthFailure(authId, reason)

--------------------------------------------------------------------
5.10 Replay Engine (LLD)
--------------------------------------------------------------------

class ReplayEngine {
  replayFromStep(stepId: string, newContext: ContextArtifact): void
}

Replay algorithm:
1. Mark step as invalidated
2. Mark all downstream steps as invalidated
3. Re-run steps sequentially
4. Produce new artifacts

====================================================================
8. AUTH FAILURE HANDLING
====================================================================

1. OperationAgent throws AuthFailure(authId, reason)
2. Planner marks auth as invalid in Context
3. Planner pauses execution
4. ContextAgent re-prompts the user
5. New ContextArtifact version is created
6. Planner resumes from the failed step

====================================================================
9. SKILL DISCOVERY (PLANNER)
====================================================================

The PlannerAgent MUST discover relevant skills without exposing the full
skill catalog to the LLM.

Skill discovery is a two-phase process:

PHASE 1 — DETERMINISTIC NARROWING (NON-LLM)
- Planner extracts intent signals (domains, verbs, nouns) from user input
- Planner queries the SkillRegistry using skill metadata
- Planner applies hard filters (domain match, output compatibility, auth)
- Result is a small candidate set (<= 10 skills)

PHASE 2 — LLM SELECTION (SMALL SET ONLY)
- Planner invokes LLM with:
  - user intent
  - candidate skill summaries only
- LLM selects skills and ordering
- LLM NEVER sees the full skill list

All skills MUST declare machine-filterable metadata:
- domains
- verbs
- nouns
- output types

The SkillRegistry MUST support lookup by these fields.

If no suitable skills are found, Planner MUST ask ContextAgent for
clarification.

This design ensures scalability, determinism, and prevents LLM overload.


====================================================================
10. END-TO-END DRY RUN
====================================================================

Use case:
"List last 5 GitHub commits and summarise all changes done"

--------------------------------------------------------------------
9.1 User Input
--------------------------------------------------------------------

User enters:
"List last 5 GitHub commits and summarise all changes done"

--------------------------------------------------------------------
9.2 Planning
--------------------------------------------------------------------

Planner infers:
- limit = 5
- requires GitHub plugin
- requires authId = "github"

Plan:
s1 → github.listCommits
s2 → github.getCommitDiff

--------------------------------------------------------------------
9.3 Context Collection
--------------------------------------------------------------------

ContextAgent prompts:
- repo
- auth choice (OAuth / token / password)

User provides:
repo = "octocat/hello-world"
github_token = "ghp_abc123"

ContextArtifact v1 created.

--------------------------------------------------------------------
9.4 Execution
--------------------------------------------------------------------

s1 executes with context v1 → commit list artifact
s2 executes with context v1 → diff artifact

Planner generates summary text.

--------------------------------------------------------------------
9.5 Context Edit & Replay
--------------------------------------------------------------------

User edits:
limit = 10

ContextArtifact v2 created.
s1 and s2 invalidated.

User clicks "Replay from s1".
Steps re-run with context v2.
New artifacts created.

====================================================================
END OF SPEC
====================================================================
