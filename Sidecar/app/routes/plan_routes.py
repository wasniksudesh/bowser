"""
Plan Mode Routes

Purpose: API endpoints for the browser's Plan Mode (LLM-driven planning).
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import logging
import json

logger = logging.getLogger(__name__)

router = APIRouter()

# =============================================================================
# Models
# =============================================================================

class CLOption(BaseModel):
    id: str
    text: str
    explanation: Optional[str] = None

class CLQuestion(BaseModel):
    id: str
    text: str
    options: List[CLOption]
    allowMultiple: bool

class PlanIntentRequest(BaseModel):
    intent: str

class ClarificationResponse(BaseModel):
    suggested_name: str
    questions: List[CLQuestion]

class Answer(BaseModel):
    questionId: str
    selectedOptionIds: List[str]

class PlanGenerationRequest(BaseModel):
    intent: str
    clarification_answers: List[Answer]

class PlanNodeModel(BaseModel):
    id: Optional[str] = None # Optional because LLM might not generate it locally
    title: str
    description: Optional[str] = None
    isLeaf: bool
    links: List[Dict[str, str]] = [] # List of {"title": "...", "url": "..."}
    children: List['PlanNodeModel'] = []

class PlanResponse(BaseModel):
    root: PlanNodeModel

class PlanExpansionRequest(BaseModel):
    intent: str
    parent_node_context: str # Title/Description of the node to expand

class ExpansionResponse(BaseModel):
    children: List[PlanNodeModel]

# =============================================================================
# Prompts
# =============================================================================

SYSTEM_PROMPT = """You are an expert planning assistant. Your goal is to help users break down complex goals into actionable plans.
Always return valid JSON. Do not return markdown blocks. just the raw JSON object."""

def get_clarification_prompt(intent: str) -> str:
    return f"""The user wants to: "{intent}".

Generate:
1. A concise, descriptive name for this plan (2-5 words)
2. 3-5 multiple-choice clarification questions to help scope this plan

Focus clarification questions on:
1. Experience level / Prerequisites
2. Time commitment / Deadline
3. Specific goals or constraints
4. Preferred learning style or approach (if applicable)

Return strictly a JSON object with this structure:
{{
  "suggested_name": "Plan Name Here",
  "questions": [
    {{
      "id": "q1",
      "text": "Question text?",
      "options": [
        {{ "id": "opt1", "text": "Option 1", "explanation": "Why pick this?" }},
         {{ "id": "opt2", "text": "Option 2", "explanation": "Why pick this?" }}
      ],
      "allowMultiple": false
    }}
  ]
}}
"""

def get_generation_prompt(intent: str, answers: List[Answer]) -> str:
    answers_str = json.dumps([a.model_dump() for a in answers], indent=2)
    return f"""The user wants to: "{intent}".
They answered the clarification questions as follows:
{answers_str}

Generate a HIGH-LEVEL hierarchical plan.
- The plan should have broad phases (e.g., "Week 1", "Phase 1").
- Do NOT go too deep yet (max depth 2).
- The root node should be the title of the plan.

Return strictly a JSON object with this structure:
{{
  "id": "root",
  "title": "Plan Title",
  "description": "Overall description",
  "isLeaf": false,
  "children": [
    {{
      "id": "step1",
      "title": "Step 1 Title",
      "description": "Description of step 1",
      "isLeaf": false,
      "children": [] 
    }},
    {{
      "id": "step2",
      "title": "Leaf Step Title",
      "description": "Description...",
      "isLeaf": true,
      "links": [
         {{ "title": "Resource Name", "url": "https://example.com" }}
      ],
      "children": []
    }}
  ]
}}
IMPORTANT: 
- 'isLeaf' should be true ONLY for very specific, actionable tasks (e.g. "Read Chapter 1", "Book Flight").
- High-level phases are NOT leaves.
- For leaf nodes, PROVIDE 1-3 helpful 'links' (tutorials, docs, tools) if relevant.
- Assign simple IDs (s1, s2, etc.).
"""

def get_expansion_prompt(intent: str, context: str) -> str:
    return f"""The user is working on the plan: "{intent}".
We need to expand the specific step/node: "{context}".

Generate a list of concrete sub-steps for this node.
- These should be detailed and actionable.
- If they are tasks the user can do immediately, set isLeaf=true.
- If they are still broad categories, set isLeaf=false.

Return strictly a JSON object with this structure:
{{
  "children": [
    {{
      "id": "sub1",
      "title": "Sub-step Title",
      "description": "Brief description",
      "isLeaf": true, 
      "links": [
         {{ "title": "Resource Name", "url": "https://example.com" }}
      ],
      "children": []
    }}
  ]
}}
IMPORTANT:
- For leaf nodes, it is CRITICAL to provide 'links' to actual learning resources (documentation, videos, articles).
- Descriptions should be detailed instructions.
"""

# =============================================================================
# Endpoints
# =============================================================================

async def _call_llm(prompt: str) -> Dict[str, Any]:
    from app.main import ai_agent
    if not ai_agent:
         raise HTTPException(status_code=503, detail="AI service not initialized")
    
    # We use a direct LLM call via the agent's LLM to ensure we get raw text we can parse as JSON
    # execute_task with use_tools=False might still have some overhead, but let's try strict invocation.
    
    full_prompt = f"{SYSTEM_PROMPT}\n\n{prompt}"
    
    try:
        # Using execute_task with use_tools=False to get a direct response
        result = await ai_agent.execute_task(
            task=full_prompt,
            context={"mode": "json_mode"}, # Hint for some models
            use_tools=False
        )
        
        if not result["success"]:
             raise Exception(result.get("error", "LLM call failed"))
        
        content = result["output"]
        
        # Clean up code blocks if present
        if "```json" in content:
            content = content.split("```json")[1].split("```")[0].strip()
        elif "```" in content:
            content = content.split("```")[1].split("```")[0].strip()
            
        return json.loads(content)
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON from LLM: {e}. Content: {content}")
        raise HTTPException(status_code=500, detail="LLM returned invalid JSON")
    except Exception as e:
        logger.error(f"LLM Interaction failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/clarify", response_model=ClarificationResponse)
async def clarify_intent(request: PlanIntentRequest):
    logger.info(f"Generating clarification for: {request.intent}")
    prompt = get_clarification_prompt(request.intent)
    data = await _call_llm(prompt)
    return ClarificationResponse(**data)

@router.post("/generate", response_model=PlanResponse)
async def generate_plan(request: PlanGenerationRequest):
    logger.info(f"Generating plan for: {request.intent}")
    prompt = get_generation_prompt(request.intent, request.clarification_answers)
    data = await _call_llm(prompt)
    return PlanResponse(root=PlanNodeModel(**data))

@router.post("/expand", response_model=ExpansionResponse)
async def expand_node(request: PlanExpansionRequest):
    logger.info(f"Expanding node '{request.parent_node_context}' for plan '{request.intent}'")
    prompt = get_expansion_prompt(request.intent, request.parent_node_context)
    data = await _call_llm(prompt)
    return ExpansionResponse(**data)


# =============================================================================
# Chat
# =============================================================================

class ChatMessage(BaseModel):
    role: str # "user" or "assistant"
    content: str

class PlanChatRequest(BaseModel):
    intent: str
    node_context: str
    history: List[ChatMessage]
    message: str

class PlanChatResponse(BaseModel):
    response: str
    updated_links: Optional[List[Dict[str, str]]] = None # [{"title": "...", "url": "..."}]
    updated_description: Optional[str] = None


def get_chat_prompt(intent: str, node_context: str, history: List[ChatMessage], message: str) -> str:
    history_str = "\n".join([f"{msg.role}: {msg.content}" for msg in history])
    
    return f"""You are an expert AI tutor helping a user with a specific step in their learning plan.
    
Overall Plan Goal: "{intent}"
Current Step: "{node_context}"

History:
{history_str}

User: {message}

Provide a helpful, concise response.
- Focus strictly on the Current Step.
- Be encouraging and practical.
- If the user asks for code, provide short snippets.

DYNAMIC UPDATES:
- If the user asks for different resources or tools, provide 'updated_links'.
- If the user wants to change the goal of this step or needs different instructions, provide 'updated_description'.

Return strictly a JSON object with this structure:
{{
  "response": "Your response here...",
  "updated_links": [ {{ "title": "New Resource", "url": "..." }} ], 
  "updated_description": "New instructions..." 
}}
(Omit updated_links/updated_description if not needed)
"""

@router.post("/chat", response_model=PlanChatResponse)
async def plan_chat(request: PlanChatRequest):
    logger.info(f"Chat message for node '{request.node_context}'")
    prompt = get_chat_prompt(request.intent, request.node_context, request.history, request.message)
    data = await _call_llm(prompt)
    return PlanChatResponse(**data)
