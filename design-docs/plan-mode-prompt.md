==================================================
PRODUCT SPEC: PLAN MODE (GENERIC, LLM-DRIVEN)
==================================================

Version: v1
Status: Defined
Scope: Generic Plan Mode inside browser
Non-scope: Memory, workflows, automation, multi-plan
Assumptions: Backend + LLM infra exists (LangChain OK)

==================================================
1. OVERVIEW
==================================================

Plan Mode is a structured, LLM-guided way for users to turn an intent
into an actionable, expandable plan inside the browser.

Plan Mode is not a chatbot, not a link aggregator, and not a static
roadmap generator. It is a guided planning and execution experience.

Core promise:
- Give users structure for doing things on the internet
- Keep the full journey visible
- Reveal detail only when the user asks for it
- Drive execution, not just thinking

==================================================
2. ENTRY POINT & MODES
==================================================

The browser has a left-side panel.

At the top-right of this panel, there is a mode toggle:
- Tab Mode
- Plan Mode

Switching modes:
- Does not close tabs
- Does not lose plan state
- Is reversible at any time

==================================================
3. PLAN MODE – INITIAL STATE
==================================================

When entering Plan Mode, the panel shows:

- An intent input field
- Prompt example:
  "What do you want to plan?"

Examples:
- Prepare for Google interviews
- Learn competitive programming
- Plan a 10-day Japan trip
- Start swimming classes

Plan Mode does nothing until an intent is provided.

==================================================
4. CLARIFICATION PHASE (QUESTIONS)
==================================================

Purpose:
Reduce ambiguity only as much as needed to create a useful plan.

Question characteristics:
- Mostly multiple-choice
- Asked ONE QUESTION AT A TIME
- Generated dynamically by the LLM
- Each question has 3–5 options
- Each option has a short explanation
- Free-text questions are allowed only if unavoidable

Multi-select:
- Users MAY select multiple options when applicable

Flow:
- There is NO fixed number of questions
- Questions adapt based on previous answers
- The LLM decides when enough context exists
- Once enough context exists → transition to Plan Creation

UX:
- Selecting options immediately advances the flow
- No explicit “submit” button
- No backtracking to earlier questions (v1 decision)

==================================================
5. PLAN CREATION (HIGH-LEVEL PLAN)
==================================================

Once sufficient context is gathered, the LLM creates a high-level plan.

Plan requirements:
- High-level
- Collapsed by default
- Shows the full journey at a glance
- No sub-step expansion initially

The plan answers:
"What are the major phases of this journey?"

Rendering:
- Displayed as a tree (file-explorer style)
- Steps can be expanded or collapsed
- Uneven depth is allowed
- The entire plan remains visible

Example (collapsed):

Prepare for Google Interviews
▶ Interview Strategy & Expectations
▶ Core Data Structures & Patterns
▶ Advanced Techniques
▶ Practice & Mock Interviews
▶ Review & Iteration

==================================================
6. STEP EXPANSION (LAZY, STRUCTURAL)
==================================================

Expansion is always user-initiated.

Rules:
- Only the clicked node is expanded
- No automatic deep expansion
- Expansion prioritizes STRUCTURE over CONTENT

Structural hierarchy enforced:

1. Broad step
   → Sub-topics

2. Sub-topic
   → Concepts / patterns
   → Common problem types
   → Practice buckets

3. Practice bucket
   → Easy
   → Medium
   → Hard
   (or equivalent intent-based splits)

4. Leaf node
   → Clear, executable unit

==================================================
7. LEAF NODE DEFINITION
==================================================

A node is a LEAF only if:
- The user can take a clear next action
- Further planning is unnecessary
- The task is concrete and scoped

Leaf nodes may include:
- Short description
- Curated links (optional)
- Suggested follow-up actions

==================================================
8. LEAF NODE INTERACTION (EXECUTION VIEW)
==================================================

When a leaf node is clicked:

- The left panel switches from tree view to leaf view
- Tree view is replaced, not shown alongside

Leaf view layout:

Top:
- Back button (returns to tree view)
- Leaf node title

Body:
1. Description
2. Curated links
3. Scratchpad / notepad
4. Contextual chat box

==================================================
9. LINKS & BROWSING INTEGRATION
==================================================

- Clicking a link opens a browser tab
- Tabs opened from the same leaf are grouped
- Tabs remain open regardless of mode switching
- Plan Mode never auto-navigates tabs

Links are resources, not steps.

==================================================
10. CONTEXTUAL CHAT IN LEAF VIEW
==================================================

Chat is scoped to the leaf node.

Purpose:
- Assist execution
- Clarify approach
- Provide hints or guardrails

Suggested prompts may appear, e.g.:
- Show a hint
- Recommended approach
- Common mistakes
- How hard is this relative to interviews?

Chat does not replan unless explicitly requested.

==================================================
11. COMPLETION & ADAPTATION
==================================================

Users can mark steps or sub-steps as completed.

Effects:
- Completion state is reflected in the plan tree
- The LLM may adapt future expansions based on completion
- Completed steps remain visible

Completion does NOT:
- Remove steps automatically
- Force a strict order
- Lock the plan

==================================================
12. EXAMPLES (CORRECT BEHAVIOR)
==================================================

Example: Interview Prep

Intent:
"Prepare for Google interviews"

Correct behavior:
- Dynamic MCQ clarification
- High-level plan creation
- Structural expansion:
  Data Structures → Arrays → Concepts → Practice → Easy/Medium/Hard
- Leaf nodes are executable units
- Links are specific and contextual

Example: Travel Planning

Intent:
"Plan a 10-day Europe trip"

Correct behavior:
- Clarify countries, pace, budget
- Plan shows flights, itinerary, stays
- Expansion reveals cities, then daily plans
- Leaf nodes are concrete (e.g., "2-day Paris itinerary")

==================================================
13. NON-EXAMPLES (MUST NOT HAPPEN)
==================================================

- Leaf node that only says:
  "Practice on LeetCode"
  with a homepage link

- Platform names used as steps or goals

- Initial plan fully expanded with dozens of nodes

- Fixed questionnaires regardless of intent

- UI states where:
  user clicks → panel clears → nothing renders

==================================================
14. UX PRINCIPLES (NON-NEGOTIABLE)
==================================================

1. Show the whole journey, hide the depth
2. User controls expansion
3. Execution over information
4. Graceful degradation if LLM is uncertain
5. Plan reassures, it does not pressure

==================================================
15. EXPLICIT NON-SCOPE (V1)
==================================================

- Multi-plan support (single plan only)
- Long-term memory
- Workflow automation
- Agent-to-agent wiring
- User-authored custom nodes
- Analytics or scoring

==================================================
END OF SPEC
==================================================
