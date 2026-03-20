# Product Requirements Document: Multi-Agent Function Orchestration System

**Version:** 1.0  
**Target Implementation:** Electron + React + Python + Grafana Integration  
**Audience:** LLM Coding Agents

---

## Executive Summary

A multi-agent AI browser that converts ad-hoc LLM workflows into deterministic, reusable Functions. Users interact via chat, agents orchestrate product integrations (starting with Grafana), and successful workflows automatically become saveable Functions that bypass LLM inference on subsequent runs.

**Core Innovation:** Functions are first-class citizens with semantic discovery, type-safe execution, and automatic UI component binding.

---

## System Architecture Overview

### Agent Hierarchy
```
PlanAgent (Orchestrator)
├─ Semantic search over Function Registry
├─ Decides: Use existing Function vs invoke ProductAgent
└─ Composes multiple Functions when needed

ProductAgent (e.g., GrafanaAgent)
├─ Exposes MCP tools to PlanAgent
├─ Executes REST/MCP/Python operations
├─ Binds results to React UI components
└─ Generates Function drafts from successful workflows
```

### Data Flow
```
User Query 
  → PlanAgent (semantic search)
    → Function found (confidence >70%) 
      → Execute deterministically → Render UI
    → Function not found or low confidence
      → ProductAgent (LLM inference)
        → Execute workflow → Render UI
          → Offer "Save as Function"
```

---

## Core Components

### 1. Function Registry

**Purpose:** Central repository of all Functions with semantic search capabilities.

**Schema:**
```
Function {
  // Identity
  id: string (e.g., "grafana.list_dashboards.v2")
  name: string (user-friendly)
  description: string (detailed, for semantic search)
  author: string (user email or "official")
  version: semver string
  visibility: "private" | "team" | "public"
  
  // Execution Definition
  execution: {
    type: "mcp" | "rest" | "python"
    
    mcp?: {
      server: string
      tool: string
    }
    
    rest?: {
      endpoint: string
      method: string
      headers: object
      input_mapping: object  // user params → API params
      output_schema: JSONSchema  // enforce structure
    }
    
    python?: {
      script_path: string
      entry_function: string
    }
  }
  
  // Type System
  input_schema: JSONSchema
  output_schema: JSONSchema
  output_data_shape: "Tabular" | "TimeSeries" | "Hierarchical" | "KeyValue" | "Graph" | "Geospatial" | "Binary"
  
  // UI Binding
  ui_compatibility: string[]  // ["ReactTable", "CardGrid"]
  default_component: string
  component_config: object
  
  // Metadata
  tags: string[]
  category: string
  permissions: string[]
  rate_limit: string
  
  // Analytics
  usage_count: number
  success_rate: float
  avg_latency_ms: number
  last_used: timestamp
  
  // Lifecycle
  status: "draft" | "active" | "deprecated"
  created_at: timestamp
  updated_at: timestamp
  change_log: ChangeEntry[]
}

ChangeEntry {
  version: string
  changes: string
  breaking: boolean
  timestamp: timestamp
}
```

**Storage:** SQLite database with vector embeddings for semantic search (use sentence-transformers for embedding generation).

---

### 2. UI Component Registry

**Purpose:** Catalog of React components with type compatibility rules.

**Schema:**
```
UIComponent {
  name: string
  description: string
  accepts: DataShape[]
  
  required_fields: {
    field_name: JSONSchema
  }
  
  optional_fields: {
    field_name: JSONSchema
  }
  
  config_schema: JSONSchema  // component-specific settings
  
  usage_count: number
  preview_image: string
  
  // For marketplace
  author: string
  visibility: "builtin" | "custom"
}

DataShape = "Tabular" | "TimeSeries" | "Hierarchical" | "KeyValue" | "Graph" | "Geospatial" | "Binary"
```

**Built-in Components (Minimum Viable Set):**
- ReactTable (Tabular)
- LineChart (TimeSeries)
- PropertyList (KeyValue)
- CardGrid (Tabular, alternative view)
- JSONViewer (fallback for any shape)

---

### 3. Semantic Function Discovery

**Algorithm:**
```
Input: user_query (string), function_registry (Function[])
Output: ranked_functions (Function[], confidence_score[])

Steps:
1. Generate embedding for user_query
2. Calculate similarity scores against all function descriptions
3. Extract parameters from user_query using LLM
4. Score each function:
   confidence = (
     0.5 × semantic_similarity +
     0.2 × parameter_match_score +
     0.2 × (usage_count / max_usage_count) +
     0.1 × user_has_used_before_bonus
   )
5. Return top 5 functions with confidence >0.5
```

**Thresholds:**
- confidence ≥ 0.85: Execute immediately, show "Using function X..."
- 0.70 ≤ confidence < 0.85: Show user choice: "Did you mean [Function A] [Function B] [Run new workflow]"
- confidence < 0.70: Invoke ProductAgent, no function suggestion

---

### 4. UI Component Matching

**Algorithm:**
```
Input: output_schema (JSONSchema), output_data (object)
Output: component (UIComponent), config (object), confidence (float)

Steps:
1. Infer data shape:
   - Has "columns" + "rows" arrays → Tabular
   - Has timestamp array + value array → TimeSeries
   - Has nested objects with parent/child → Hierarchical
   - Flat key-value pairs → KeyValue
   - Has nodes/edges → Graph
   
2. Filter components where shape ∈ component.accepts

3. Score by field coverage:
   confidence = (matched_required_fields / total_required_fields)
   
4. Select highest confidence component

5. Generate component config by mapping output_schema to component.required_fields
```

**Fallback Rule:** If confidence <0.7 or no match found, use JSONViewer.

---

## User Experience Flows

### Flow 1: First-Time Workflow (No Existing Function)

**Steps:**
1. User types: "Show me all Grafana dashboards with more than 5 alerts"
2. PlanAgent searches Function Registry → No match (confidence <0.7)
3. PlanAgent invokes GrafanaAgent with query
4. GrafanaAgent:
   - Uses MCP tool `grafana_list_dashboards`
   - Uses MCP tool `grafana_get_alerts`
   - Joins results (LLM determines logic)
   - Matches output to ReactTable
5. UI renders:
   ```
   Assistant: Here are your dashboards with 5+ alerts
   [ReactTable: Dashboard Name | Alert Count | Status]
   
   💡 Save this as a function?
   [Maybe Later] [Yes, Save]
   ```
6. If user clicks "Yes, Save":
   - Show Function Preview modal
   - Auto-populate: name, description, input/output schemas
   - User can edit details
   - Click "Save & Close"
7. Function added to registry with status="active"

---

### Flow 2: Existing Function (High Confidence)

**Steps:**
1. User types: "List my dashboards"
2. PlanAgent searches → Finds "grafana.list_dashboards" (confidence=0.92)
3. UI shows inline indicator:
   ```
   🔄 Using function: List Grafana Dashboards...
   ```
4. Function executes deterministically (no LLM inference)
5. UI renders result in ReactTable
6. User sees result immediately

**Transparency Requirement:** Always show which function was used. User can click function name to see details or click "Edit & Re-run" button.

---

### Flow 3: Existing Function (Modified Parameters)

**Steps:**
1. User types: "Show dashboards from org_id=5 tagged with 'production'"
2. PlanAgent searches → Finds "grafana.list_dashboards" (confidence=0.88)
3. PlanAgent extracts parameters: `{org_id: 5, tags: ["production"]}`
4. UI shows:
   ```
   🔄 Using function: List Grafana Dashboards
      with filters: org_id=5, tags=['production']
   ```
5. Function executes with modified params
6. Render result

---

### Flow 4: Low Confidence (Disambiguation)

**Steps:**
1. User types: "Show me dashboard metrics"
2. PlanAgent searches → Finds 3 functions (confidence 0.72, 0.68, 0.65)
3. UI shows:
   ```
   I found a few functions that might help:
   
   🔹 grafana.list_dashboards
      Lists all Grafana dashboards
      [Use This]
   
   🔹 grafana.dashboard_metrics
      Gets performance metrics for dashboards
      [Use This]
   
   🔹 grafana.query_dashboard_data
      Queries data from specific dashboard
      [Use This]
   
   Or [Run New Workflow]
   ```
4. User selects one → Execute that function
5. User clicks "Run New Workflow" → Invoke ProductAgent

---

### Flow 5: Function Composition

**Steps:**
1. User types: "List dashboards and create alerts for any with zero data points"
2. PlanAgent searches → Finds:
   - "grafana.list_dashboards" (0.90)
   - "grafana.create_alert" (0.85)
3. PlanAgent determines composition needed (LLM inference)
4. UI shows:
   ```
   🔄 Step 1/2: Listing dashboards...
   ✓ Found 12 dashboards
   
   🔄 Step 2/2: Checking for zero data points...
   ✓ Found 3 dashboards with no data
   
   🔄 Creating alerts for 3 dashboards...
   ```
5. Render results (likely in two tables or sections)
6. Offer to save composition:
   ```
   💡 Save this as a function?
      "Alert on empty dashboards"
   [Maybe Later] [Yes, Save]
   ```
7. If saved, create new Function that chains the two existing functions

---

### Flow 6: Function Execution Failure

**Steps:**
1. User runs existing function
2. Execution fails (API error, auth issue, etc.)
3. UI shows:
   ```
   ❌ Function failed: grafana.list_dashboards
   
   Error: 401 Unauthorized - Invalid API token
   
   [Retry] [Edit Function] [Run with LLM Instead]
   ```
4. User clicks "Edit Function":
   - Open Function Editor
   - Highlight error field (e.g., auth config)
   - User fixes → Save new version
5. User clicks "Run with LLM Instead":
   - Invoke ProductAgent
   - Treat as new workflow

---

## Function Lifecycle Management

### States
- **draft:** LLM-generated, awaiting user review
- **active:** Locked for deterministic execution
- **deprecated:** Marked obsolete, suggest alternatives

### Versioning Rules
- Minor version bump (1.0 → 1.1): Non-breaking changes (new optional param)
- Major version bump (1.0 → 2.0): Breaking changes (removed field, changed schema)
- Keep all versions in registry
- When function matches but version differs, show:
  ```
  ⚠️  Using grafana.list_dashboards v1.2
      A newer version (v2.0) is available with breaking changes
  [View Changes] [Upgrade] [Keep Current]
  ```

### Deprecation Flow
1. Admin/user marks function as deprecated
2. Suggest replacement function
3. When deprecated function matches, show:
   ```
   ⚠️  Function 'grafana.old_dashboards' is deprecated
       Use 'grafana.list_dashboards' instead
   [Migrate] [Use Anyway]
   ```

---

## Marketplace Requirements

### Function Marketplace

**Categories:**
- Data Retrieval
- Data Modification
- Monitoring & Alerts
- Reporting
- Administration

**Visibility Levels:**
- **Private:** Only creator sees it
- **Team:** Everyone in organization
- **Public:** Available to all (requires approval)

**UI Requirements:**
```
Marketplace View:
- Search bar with semantic search
- Filter by category, author, data shape
- Sort by popularity, recency, rating
- Each function card shows:
  - Name + description
  - Author + verification badge (if official)
  - Usage count + success rate
  - Input/Output types
  - Compatible UI components
  - [Preview] [Install] [Clone & Modify]
```

**Preview Mode:**
- Show full function definition
- Display example inputs/outputs
- Show which UI component it uses
- Link to documentation (if available)

**Install Flow:**
1. User clicks "Install"
2. System checks permissions
3. Add to user's Function Registry
4. Show success notification with quick-start example

**Clone & Modify:**
1. Creates copy with status="draft"
2. Opens Function Editor
3. User modifies as needed
4. Save as new private function

---

### UI Component Marketplace

**Categories:**
- Tables & Grids
- Charts & Graphs
- Cards & Lists
- Maps & Spatial
- Custom Visualizations

**Each Component Card Shows:**
- Preview image/animation
- Accepts data shapes
- Configuration options
- Usage count
- Author
- [Preview] [Install] [View Code]

**Install Flow:**
1. Downloads component bundle
2. Registers in UIComponent registry
3. Immediately available for function binding

---

## Function Editor Specification

### When to Show Editor

| Trigger | Action |
|---------|--------|
| User clicks "Yes, Save" after workflow | Show with auto-populated fields |
| User clicks "Edit Function" on existing | Show with pre-filled data |
| User says "create a function to..." | Show empty editor |
| User clicks function name in UI | Show read-only view with "Edit" button |

### Editor Layout

**Tabs:**
1. **Basic Info**
   - Name (required)
   - Description (required, used for semantic search)
   - Tags (multi-select)
   - Category (dropdown)
   - Visibility (private/team/public)

2. **Execution**
   - Type selector: MCP | REST | Python
   - Configuration based on type:
     - MCP: Server dropdown, Tool dropdown
     - REST: Endpoint, Method, Headers, Request body template
     - Python: Script upload, Entry function name

3. **Input/Output**
   - Input Schema (JSON Schema editor)
   - Output Schema (JSON Schema editor)
   - Data Shape selector
   - Example input/output (helps with testing)

4. **UI Binding**
   - Auto-detected compatible components (read-only)
   - Default component selector (dropdown)
   - Component configuration (dynamic form based on component.config_schema)

5. **Testing**
   - Input values (form based on input_schema)
   - [Run Test] button
   - Output display area
   - Success/failure indicator

6. **Advanced**
   - Permissions required
   - Rate limit
   - Timeout
   - Retry policy

**Actions:**
- [Test Run] - Execute with sample data
- [Save Draft] - Save without activating
- [Save & Activate] - Make available for use
- [Cancel] - Discard changes

**Validation Rules:**
- Name must be unique within user's registry
- Description minimum 20 characters
- Input/output schemas must be valid JSON Schema
- At least one UI component must be compatible
- Test run must succeed before activation

---

## Error Handling & Resilience

### Error Types & Responses

**1. Function Execution Failure**
```
Display:
❌ Function 'X' failed
Error: [specific error message]

Options:
[Retry] [Edit Function] [Run with LLM Instead] [Report Issue]

Logging:
- Log to function analytics (decrement success_rate)
- Capture full error trace
- If failure rate >30%, auto-mark as "needs_review"
```

**2. Function Not Found (Low Confidence)**
```
Display:
I couldn't find an existing function for this.
Running a new workflow...

[Workflow executes via ProductAgent]

After success:
💡 Save this as a function?
```

**3. Component Binding Failure**
```
Display:
⚠️  Couldn't match output to a UI component.
Showing raw data instead.

[JSONViewer renders output]

Options:
[Suggest Component] [Create Custom Component]
```

**4. API/MCP Tool Unavailable**
```
Display:
❌ Grafana service is unavailable
Error: Connection timeout

Options:
[Check Service Status] [Retry] [Use Cached Results] (if available)

System Action:
- Mark service as degraded in health dashboard
- Pause function executions for 5 minutes
- Send notification to admins
```

**5. Schema Validation Failure**
```
Display:
⚠️  Function output doesn't match expected schema
Expected: {dashboards: [], total: number}
Received: {data: [...]}

Options:
[View Raw Output] [Update Function Schema] [Report Bug]

System Action:
- Fall back to JSONViewer
- Flag function for review
- Offer schema auto-correction if possible
```

### Fallback Strategies

**When Function Fails:**
1. Retry once (in case of transient error)
2. If retry fails, offer "Run with LLM Instead"
3. LLM execution bypasses function, uses ProductAgent directly
4. User can still save new workflow as updated function

**When Component Matching Fails:**
1. Use JSONViewer as universal fallback
2. Log mismatch for analytics
3. Suggest creating custom component or updating function schema

**When Service Unavailable:**
1. Check for cached results (if caching enabled)
2. Show estimated downtime
3. Offer to queue request for later execution

---

## Design Patterns to Follow

### 1. Progressive Disclosure
**Principle:** Don't show complexity until needed.

**Application:**
- Default view: Simple chat interface
- Function indicators: Minimal ("🔄 Using function X...")
- Editor: Only show when user initiates or low confidence
- Advanced settings: Behind "Advanced" tab in editor

**Anti-Pattern:** Showing function configuration before every execution.

---

### 2. Fail-Safe Defaults
**Principle:** System should work even when functions fail.

**Application:**
- Always have LLM fallback path
- Always have JSONViewer as UI fallback
- Default to "private" visibility for new functions
- Default to conservative rate limits

**Anti-Pattern:** Blocking user workflows when function registry is down.

---

### 3. Optimistic UI
**Principle:** Assume success, show progress immediately.

**Application:**
- Show "🔄 Using function..." instantly when matched
- Render partial results as they arrive (for multi-step)
- Show "Saving function..." toast immediately on save

**Anti-Pattern:** Waiting for confirmation before showing any feedback.

---

### 4. Explicit State Transitions
**Principle:** User always knows what's happening.

**Application:**
- Show when using existing function vs creating new workflow
- Show which step of multi-step execution
- Show when function is being saved
- Show when fallback to LLM occurs

**Anti-Pattern:** Silent switching between function execution and LLM inference.

---

### 5. Version Everything
**Principle:** All changes are tracked and reversible.

**Application:**
- Function versions with changelogs
- Ability to rollback to previous version
- Component versions
- Schema versions

**Anti-Pattern:** Overwriting function definitions without history.

---

### 6. Separation of Concerns
**Principle:** Each agent/component has single responsibility.

**Application:**
- PlanAgent: Orchestration & function discovery only
- ProductAgent: Execution & workflow generation only
- Function Registry: Storage & retrieval only
- UI Layer: Rendering only

**Anti-Pattern:** PlanAgent directly executing REST calls or ProductAgent managing function storage.

---

### 7. Type Safety at Boundaries
**Principle:** Validate all inputs/outputs at system boundaries.

**Application:**
- Validate user input against function.input_schema
- Validate function output against function.output_schema
- Validate component props against component.required_fields
- Validate API responses before processing

**Anti-Pattern:** Trusting LLM-generated schemas without validation.

---

### 8. Graceful Degradation
**Principle:** System remains usable even when parts fail.

**Application:**
- Function registry down → Use LLM directly
- Component registry down → Use JSONViewer
- MCP server down → Show error, offer REST alternative
- Embedding service down → Use keyword search

**Anti-Pattern:** Complete system failure when one service is unavailable.

---

## Analytics & Observability

### Metrics to Track

**Function-Level:**
- Usage count (total, per user, per day)
- Success rate (executions / successes)
- Average latency
- Error breakdown (by error type)
- Parameter usage distribution

**System-Level:**
- Function discovery hit rate (found function vs invoked ProductAgent)
- Confidence score distribution
- Component matching accuracy
- Cache hit rate (if implemented)
- API call volume (by service)

**User-Level:**
- Functions created
- Functions used
- Workflows saved as functions (conversion rate)
- Error rate by user
- Most-used functions

### Dashboards

**Admin Dashboard:**
- System health (service availability)
- Top functions by usage
- Functions needing review (high error rate)
- User adoption metrics
- API quota usage

**User Dashboard:**
- My functions (usage, success rate)
- Recommended functions (based on usage patterns)
- Recently used functions
- Saved functions by category

---

## Security & Permissions

### Function Permissions

**Types:**
- **read:** Can view and use function
- **write:** Can modify function
- **delete:** Can delete function
- **share:** Can change visibility

**Rules:**
- Creator has all permissions
- Team visibility → Team members have read permission
- Public visibility → All users have read permission
- Admin role can manage all functions

### Execution Permissions

**Each function declares required permissions:**
```
permissions: ["grafana:read", "grafana:write"]
```

**Before execution:**
1. Check if user has required permissions
2. If not, show error:
   ```
   ❌ Missing permissions: grafana:write
   
   This function requires write access to Grafana.
   [Request Access] [Use Different Function]
   ```

### Data Isolation

**Rules:**
- Private functions: Only creator's data accessible
- Team functions: Team data pool accessible
- Public functions: Must be sandboxed (no access to user's internal APIs)

### API Token Management

**Storage:**
- User API tokens stored encrypted in electron-store
- Never stored in function definitions
- Injected at execution time

**Rotation:**
- Prompt user to update tokens on 401 errors
- Allow token re-configuration without editing function

---

## Migration & Import/Export

### Export Function
**Format:** JSON file containing Function schema.

**What's Included:**
- All function metadata
- Execution definition
- Input/output schemas
- UI binding config
- Change log

**What's Excluded:**
- API tokens/secrets
- Usage analytics
- User-specific data

**Use Cases:**
- Backup functions
- Share with team
- Version control (commit to git)

### Import Function
**Validation:**
1. Check schema version compatibility
2. Validate all required fields present
3. Check for name conflicts
4. Verify permissions available

**Import Options:**
- **Replace:** Overwrite existing function (if exists)
- **Keep Both:** Import with new name
- **Cancel:** Abort import

### Bulk Operations
- Export all functions (ZIP of JSON files)
- Import function pack (e.g., "Grafana Starter Pack")
- Migrate from v1 to v2 schema (with conversion script)

---

## Good Example: Exhaustive User Story

### Persona
**Sarah - DevOps Engineer**
- Manages 50+ Grafana dashboards
- Needs to monitor alert counts daily
- Creates reports for management
- Limited Python experience

### Scenario: Day 1 (Discovery)

**9:00 AM - First Query**
```
Sarah: "Show me all dashboards"

System:
- PlanAgent searches function registry
- No match found (confidence 0.45)
- Invokes GrafanaAgent

GrafanaAgent:
- Uses MCP tool: grafana_list_dashboards
- Returns array of 52 dashboards
- Detects output shape: Tabular
- Matches to ReactTable
- Renders:
  [ReactTable: Name | Tags | URL | Last Updated]

Sarah sees:
✅ 52 dashboards listed
💡 Save this as a function?
   [Maybe Later] [Yes, Save]

Sarah clicks "Maybe Later" (wants to explore more first)
```

**9:15 AM - More Complex Query**
```
Sarah: "Which dashboards have more than 10 alerts?"

System:
- PlanAgent searches → No match
- Invokes GrafanaAgent

GrafanaAgent (LLM reasoning):
1. Need to list dashboards
2. Need to get alerts for each
3. Need to filter by alert count
4. Need to join data

Execution:
🔄 Step 1/3: Getting dashboards...
✓ Found 52 dashboards

🔄 Step 2/3: Checking alerts...
✓ Analyzed 52 dashboards

🔄 Step 3/3: Filtering results...
✓ Found 8 dashboards with 10+ alerts

Result:
[ReactTable: Dashboard | Alert Count | Critical | Warnings]
(Shows 8 rows)

💡 Save this as a function?
   "Find high-alert dashboards"
[Maybe Later] [Yes, Save]

Sarah clicks "Yes, Save"
```

**Function Preview Modal Opens:**
```
┌─ Save Function ──────────────────────────┐
│ Name: [Find high-alert dashboards]      │
│ Description:                             │
│ [Lists Grafana dashboards with more than │
│  10 active alerts]                       │
│                                          │
│ Input:                                   │
│   alert_threshold: number (default: 10)  │
│                                          │
│ Output:                                  │
│   Tabular (dashboards with alert info)  │
│                                          │
│ UI Component: ReactTable                 │
│                                          │
│ Visibility: ● Private ○ Team ○ Public   │
│                                          │
│ [Edit Details] [Save & Close]           │
└──────────────────────────────────────────┘

Sarah reviews, clicks "Save & Close"

Toast notification:
✓ Function saved! You can now run this anytime.
```

---

### Scenario: Day 2 (Reuse)

**9:00 AM - Same Query**
```
Sarah: "Show dashboards with lots of alerts"

System:
- PlanAgent searches function registry
- Finds "find_high_alert_dashboards" (confidence 0.91)
- Executes deterministically (no LLM inference)

UI:
🔄 Using function: Find high-alert dashboards...
✓ Found 8 dashboards

[ReactTable with results appears in <2 seconds]

Sarah is delighted: "It remembered!"
```

**9:30 AM - Modified Parameters**
```
Sarah: "Show dashboards with more than 20 alerts"

System:
- PlanAgent finds same function (confidence 0.89)
- Extracts parameter: alert_threshold=20
- Executes with modified param

UI:
🔄 Using function: Find high-alert dashboards
   with alert_threshold=20
✓ Found 3 dashboards

[ReactTable with 3 rows]

Sarah sees it adapted to her new threshold
```

**10:00 AM - Sharing with Team**
```
Sarah opens Function Manager:
- Clicks "Find high-alert dashboards"
- Clicks "Edit"
- Changes visibility to "Team"
- Clicks "Save"

Toast:
✓ Function shared with team

Sarah's teammate Jake can now use this function
```

---

### Scenario: Day 3 (Composition)

**2:00 PM - Complex Request**
```
Sarah: "Show high-alert dashboards and create a summary report"

System:
- PlanAgent searches
- Finds "find_high_alert_dashboards" (0.90)
- No "create_summary_report" function exists
- Determines composition needed

Execution:
🔄 Step 1/2: Finding high-alert dashboards...
✓ Found 8 dashboards

🔄 Step 2/2: Generating summary report...
(GrafanaAgent uses LLM to create markdown report)

Result:
[ReactTable: 8 dashboards]

[Markdown Document Component:]
## Alert Summary Report
Generated: 2026-01-28 14:03

### Overview
- Total dashboards analyzed: 52
- High-alert dashboards: 8 (15%)
- Critical alerts: 23
- Warning alerts: 67

### Top Issues
1. Production API Dashboard - 18 alerts
2. Database Monitoring - 15 alerts
...

💡 Save this workflow as a function?
   "High-alert dashboard report"
[Maybe Later] [Yes, Save]

Sarah clicks "Yes, Save"

Now Sarah can generate this report with one query anytime.
```

---

### Scenario: Week 2 (Marketplace Discovery)

**Sarah explores Marketplace**
```
Opens Marketplace → Grafana category

Sees:
📊 List All Dashboards (Official)
   ⭐ 1,245 uses | 98% success
   [Installed] [View]

📊 Create Custom Dashboard (Official)
   ⭐ 890 uses | 95% success
   [Preview] [Install]

📈 Dashboard Health Check (Community)
   By: john@tech.com
   ⭐ 45 uses | 92% success
   "Checks dashboard query performance"
   [Preview] [Install]

Sarah clicks "Preview" on Dashboard Health Check:
- Sees sample input/output
- Sees it outputs Tabular → ReactTable
- Reads description
- Clicks "Install"

Toast:
✓ Function installed: dashboard_health_check
  Try it: "Check health of my dashboards"

Sarah tries it:
"Run dashboard health check"

System:
- PlanAgent finds newly installed function
- Executes
- Shows table of dashboard performance metrics

Sarah is impressed with community contribution
```

---

### Scenario: Month 2 (Power User)

**Sarah has now:**
- Created 12 functions
- Installed 5 from marketplace
- Shared 7 with team
- Composed 3 multi-step workflows

**Her typical day:**
```
9:00 AM - "Show high-alert dashboards"
  → Instant results (deterministic function)

9:30 AM - "Create weekly report"
  → Generates comprehensive report (saved composition)

10:00 AM - "Check dashboard health"
  → Runs community function

2:00 PM - "Find dashboards with no data in last 24h"
  → PlanAgent finds existing function
  → Results in seconds

5:00 PM - Sarah's manager: "How do you generate these reports so fast?"
Sarah: "I saved the workflows as functions. Want me to share them?"

Sarah opens Function Manager:
- Selects 3 reporting functions
- Changes visibility to "Team"
- Entire team now has access

Team productivity increases 40%
```

---

## Bad Examples: What Should NOT Happen

### ❌ Bad Example 1: Over-Prompting

**What Happens:**
```
User: "Show me dashboards"

System:
┌─────────────────────────────────────────┐
│ I can help you with that! But first,   │
│ please answer a few questions:         │
│                                         │
│ 1. Which organization?                 │
│ 2. Do you want to filter by tags?     │
│ 3. Should I include archived?          │
│ 4. How many results to show?           │
│ 5. Sort by what field?                 │
└─────────────────────────────────────────┘

User: "Just show me all dashboards! 😤"
```

**Why It's Bad:**
- User has to answer 5 questions for simple request
- Breaks conversation flow
- Assumes user knows all options upfront

**Correct Behavior:**
- Execute with sensible defaults
- Show results immediately
- Let user refine if needed: "Show only production dashboards"

---

### ❌ Bad Example 2: Hidden Function Execution

**What Happens:**
```
User: "List dashboards"

System:
(silently executes function)
[Table appears with results]

User later: "List dashboards with alerts"
(silently executes different function)
[Different table appears]

User: "Why did the format change?"
System: "I used a different function"
User: "What functions? I didn't know you were using functions!"
```

**Why It's Bad:**
- User has no idea functions are being used
- No transparency into system behavior
- Can't learn or control what's happening

**Correct Behavior:**
- Always show: "🔄 Using function: X..."
- Let user click function name to learn more
- Show when switching between functions

---

### ❌ Bad Example 3: Function Editor Before Results

**What Happens:**
```
User: "Show me dashboards"

System:
┌─ Create Function ────────────────────────┐
│ Before I show results, let's create a   │
│ reusable function:                       │
│                                          │
│ Name: [                               ]  │
│ Description: [                        ]  │
│ Input Schema: [                       ]  │
│ Output Schema: [                      ]  │
│                                          │
│ [Cancel] [Save & Execute]               │
└──────────────────────────────────────────┘

User: "I just want to see dashboards! Why am I filling forms?!"
```

**Why It's Bad:**
- Interrupts user's primary goal
- Forces configuration before value delivery
- Assumes user wants to save everything

**Correct Behavior:**
- Show results FIRST
- Offer to save AFTER success
- Make saving optional, not required

---

### ❌ Bad Example 4: Silent Failure

**What Happens:**
```
User: "List dashboards"

System:
🔄 Using function: list_dashboards...
(5 seconds pass)
(Nothing happens)

User: "Hello?"
(Waits 30 seconds)

System:
Here are some docs about Grafana dashboards instead.

User: "What? I wanted MY dashboards!"
```

**Why It's Bad:**
- Function failed silently
- No error message shown
- System pivoted without explanation
- User doesn't know what went wrong

**Correct Behavior:**
```
🔄 Using function: list_dashboards...
❌ Function failed
Error: 401 Unauthorized - API token expired

Options:
[Update API Token] [Retry] [Run with LLM Instead]
```

---

### ❌ Bad Example 5: Breaking Changes Without Warning

**What Happens:**
```
User has been using "list_dashboards" v1.0 for weeks

System updates to v2.0 without notice:
- Removes "starred" field
- Changes date format
- Renames "tags" to "labels"

User: "List my starred dashboards"
System: Returns all dashboards (no filtering)
User: "This used to work! What happened?"
```

**Why It's Bad:**
- No migration notice
- Breaking changes without consent
- User workflows silently broken

**Correct Behavior:**
```
⚠️  Function 'list_dashboards' has a new version (v2.0)

Breaking changes:
- Removed 'starred' field → Use 'is_favorite' instead
- Renamed 'tags' → 'labels'
- Date format changed to ISO8601

[View Full Changelog] [Upgrade Now] [Keep v1.0]

Or: "Automatically migrate my queries"
```

---

### ❌ Bad Example 6: Component Mismatch Ignored

**What Happens:**
```
Function returns time-series data:
{ timestamps: [...], values: [...] }

System silently forces it into ReactTable:
┌──────────────────────────────────────┐
│ timestamps                  | values │
├──────────────────────────────────────┤
│ [1234567890, 1234567900...] | [12... │
└──────────────────────────────────────┘

User: "Why is this a table? I wanted a graph!"
```

**Why It's Bad:**
- Wrong visualization for data type
- System ignored data shape
- User has to manually specify component

**Correct Behavior:**
- Detect data shape: TimeSeries
- Match to LineChart component
- Render graph automatically
- If confidence low, ask: "Show as [Graph] or [Table]?"

---

### ❌ Bad Example 7: No Fallback Path

**What Happens:**
```
User: "Create a dashboard for database metrics"

System:
🔄 Searching for function...
❌ No function found

(System stops, shows nothing)

User: "So... you can't help me?"
```

**Why It's Bad:**
- System gives up without trying
- No graceful degradation
- User blocked from accomplishing task

**Correct Behavior:**
```
I don't have a function for this yet.
Let me create it for you...

🔄 Creating dashboard...
(Uses ProductAgent/LLM)
✓ Dashboard created successfully

💡 Save this as a function?
   "Create database metrics dashboard"
```

---

### ❌ Bad Example 8: Marketplace Chaos

**What Happens:**
```
Marketplace shows:
- 500 functions (unsorted)
- No categories
- No ratings
- No search
- Duplicate functions with similar names:
  - grafana_dashboards
  - grafana.list.dashboards
  - list-grafana-dashboards
  - get_dashboards_grafana

User: "How do I find what I need?! 😰"
```

**Why It's Bad:**
- No organization or curation
- Can't discover relevant functions
- Duplicate/conflicting functions
- No quality signals

**Correct Behavior:**
- Clear categories (Data Retrieval, Monitoring, etc.)
- Semantic search ("show dashboards" finds list_dashboards)
- Sort by popularity/rating
- Official vs community badges
- Verification for high-quality functions
- Merge or deprecate duplicates

---

### ❌ Bad Example 9: Schema Hell

**What Happens:**
```
User saves function with output schema:
{ dashboards: Array<{name, url}> }

Later, Grafana API changes, now returns:
{ data: { items: Array<{title, link}> } }

Function executes:
❌ Error: Expected 'dashboards', got 'data'

System crashes, shows blank screen
```

**Why It's Bad:**
- No schema version tolerance
- API changes break everything
- System doesn't adapt
- User has no recovery path

**Correct Behavior:**
```
⚠️  Function output doesn't match expected schema

Expected: {dashboards: [...]}
Received: {data: {items: [...]}}

Auto-fix detected:
  Map 'data.items' → 'dashboards'
  Map 'title' → 'name'
  Map 'link' → 'url'

[Apply Auto-Fix] [View Raw Data] [Update Function Schema]
```

---

### ❌ Bad Example 10: Permission Confusion

**What Happens:**
```
User creates function that deletes dashboards

User shares function with team as "delete_old_dashboards"

Junior dev runs it:
"Delete old dashboards"

System: (silently deletes 30 dashboards)

Junior dev: "Oh no! I thought it would show me which ones to delete!"
```

**Why It's Bad:**
- No confirmation for destructive actions
- Unclear function behavior
- No permission warning
- No undo option

**Correct Behavior:**
```
⚠️  This function will DELETE dashboards

Preview:
- Production-Archive (30 days old)
- Test-Env-Old (45 days old)
- Staging-Backup (60 days old)

This action cannot be undone.

Type "DELETE" to confirm: [        ]

[Cancel] [Confirm]

After confirmation:
✓ Deleted 3 dashboards
[View Deleted Items] [Undo] (within 5 minutes)
```

---

## Critical Warnings

### ⚠️ WARNING 1: LLM Hallucination in Schemas
**Risk:** LLM generates invalid JSON Schema or incorrect field mappings.

**Mitigation:**
- Always validate generated schemas with JSON Schema validator
- Require test run before activation
- Show user the generated schema for review
- Provide schema templates for common patterns

---

### ⚠️ WARNING 2: Function Registry as Single Point of Failure
**Risk:** If function registry is down, entire system stops working.

**Mitigation:**
- Always maintain LLM fallback path
- Cache frequently used functions locally
- Graceful degradation: "Using LLM directly while registry is unavailable"
- Health check dashboard for services

---

### ⚠️ WARNING 3: Overfitting to User's First Workflow
**Risk:** User's first attempt captures suboptimal logic, becomes permanent function.

**Mitigation:**
- Always show preview before saving
- Allow easy editing after creation
- Track success rate, suggest improvements
- Version functions, allow rollback

---

### ⚠️ WARNING 4: Component Binding Ambiguity
**Risk:** Output data matches multiple components equally well.

**Mitigation:**
- Use confidence scores, show user top 3 matches
- Let user override default component
- Remember user's preferences per function
- Provide "Change visualization" button

---

### ⚠️ WARNING 5: Permission Escalation
**Risk:** Public function accesses private user data or performs unauthorized actions.

**Mitigation:**
- Sandbox public functions completely
- Require explicit permission grants
- Audit log for all function executions
- Review process for public function submissions

---

### ⚠️ WARNING 6: Token/Secret Exposure
**Risk:** API tokens stored in function definitions, exported in JSON.

**Mitigation:**
- NEVER store tokens in function definitions
- Use secure credential store (electron-store with encryption)
- Inject tokens at runtime
- Mask tokens in UI and logs
- Export excludes all secrets

---

### ⚠️ WARNING 7: Infinite Loops in Composition
**Risk:** Function A calls Function B, which calls Function A.

**Mitigation:**
- Detect circular dependencies before execution
- Limit composition depth (max 5 levels)
- Timeout on long-running compositions
- Show execution graph to user

---

### ⚠️ WARNING 8: Race Conditions in Multi-Step Functions
**Risk:** Step 2 starts before Step 1 completes, uses stale data.

**Mitigation:**
- Enforce sequential execution in compositions
- Show clear progress indicators
- Lock function during execution
- Rollback on partial failure

---

### ⚠️ WARNING 9: Semantic Search False Positives
**Risk:** Function seems relevant but does something completely different.

**Mitigation:**
- Show confidence scores to user
- Display function description before execution
- Allow user to cancel before execution starts
- Learn from user corrections (if they reject suggestions)

---

### ⚠️ WARNING 10: Marketplace Quality Degradation
**Risk:** Low-quality functions flood marketplace, users lose trust.

**Mitigation:**
- Verification process for "Official" badge
- Community ratings and reviews
- Automated quality checks (schema valid, test passes)
- Report/flag mechanism
- Admin moderation queue

---

## Success Metrics

### Primary KPIs
1. **Function Reuse Rate:** (Function executions / Total queries) × 100
   - Target: >60% after 1 month
2. **Time to Result:** Average seconds from query to rendered result
   - Target: <3 seconds for function execution, <10 seconds for new workflows
3. **Function Save Rate:** (Saved functions / Successful new workflows) × 100
   - Target: >40%
4. **User Retention:** % users who return after 7 days
   - Target: >70%

### Secondary Metrics
- Average functions per user
- Marketplace installs per week
- Team sharing rate
- Error rate (function failures / total executions)
- LLM fallback rate (lower is better)

---

## Phased Rollout Plan

### Phase 1: Core Functionality (Week 1-4)
- PlanAgent with semantic search
- GrafanaAgent with basic MCP tools
- Function Registry (SQLite)
- Function Editor (basic)
- ReactTable component
- Save/reuse flow

**Success Criteria:** User can save and reuse simple dashboard query.

---

### Phase 2: Robustness (Week 5-8)
- Error handling and retry logic
- Component matching system
- 3 additional UI components (LineChart, CardGrid, PropertyList)
- Function versioning
- Confidence scoring refinement

**Success Criteria:** 90% function success rate, component auto-matching works.

---

### Phase 3: Collaboration (Week 9-12)
- Team sharing
- Function Marketplace (basic)
- Import/export
- Permission system
- Analytics dashboard

**Success Criteria:** 50% of functions shared with team, 10 marketplace installs.

---

### Phase 4: Advanced Features (Week 13-16)
- Function composition
- Custom components
- Python UDF support
- Advanced editor features
- REST API function type

**Success Criteria:** Users create composed functions, marketplace has 50+ functions.

---

## Testing Requirements

### Unit Tests
- Function Registry CRUD operations
- Semantic search accuracy
- Schema validation
- Component matching algorithm
- Input parameter extraction

### Integration Tests
- End-to-end: User query → Function execution → UI render
- MCP tool invocation
- Error handling flows
- Multi-step composition
- Marketplace install/export

### User Acceptance Tests
- Can user save function after first workflow?
- Can user reuse function with different parameters?
- Does system gracefully handle function failures?
- Can user share function with team?
- Can user discover and install marketplace functions?

### Performance Tests
- Semantic search <500ms for 10,000 functions
- Function execution overhead <100ms
- Component rendering <1 second for 1,000 rows
- Marketplace search <300ms

---

## Documentation Requirements

### User Documentation
- Quick Start Guide
- Function Creation Tutorial
- Marketplace User Guide
- Troubleshooting Common Issues
- Best Practices for Function Design

### Developer Documentation
- System Architecture Diagram
- API Reference (Function Registry, Component Registry)
- Agent Communication Protocol
- Schema Specifications
- Extension Guide (how to add new ProductAgents)

### Video Tutorials
- "Your First Function" (3 min)
- "Sharing Functions with Your Team" (2 min)
- "Exploring the Marketplace" (4 min)
- "Creating Custom Components" (5 min)

---

## Open Questions for Implementation

1. **Embedding Model:** Which sentence-transformer model for semantic search? (recommend: all-MiniLM-L6-v2 for speed/accuracy balance)

2. **Caching Strategy:** Should function results be cached? For how long?

3. **Offline Mode:** Should functions work offline with cached data?

4. **Multi-Language Support:** Should functions support internationalization?

5. **Rate Limiting:** Per-user or per-function rate limits for API calls?

6. **Audit Logging:** How detailed? Store how long?

7. **Backup Strategy:** How often to backup function registry? Where?

8. **Update Mechanism:** How to push function registry updates to users?

---

## Final Implementation Checklist

Before considering system complete, verify:

- [ ] User can save workflow as function in <3 clicks
- [ ] Function executes in <3 seconds
- [ ] System transparently shows which function is being used
- [ ] Errors show clear messages with recovery options
- [ ] Function editor validates schemas before saving
- [ ] Component matching works for all 5 built-in components
- [ ] Team sharing allows permissions control
- [ ] Marketplace has search, categories, and ratings
- [ ] Export/import preserves all function data (except secrets)
- [ ] System gracefully degrades when services are unavailable
- [ ] All security warnings addressed
- [ ] Analytics dashboard shows key metrics
- [ ] Documentation complete and accurate
- [ ] 5 example functions work end-to-end

---

**End of PRD**

This document is designed to be consumed by LLM coding agents. All ambiguity has been resolved. All edge cases documented. All warnings explicit. Implementation can now proceed deterministically.