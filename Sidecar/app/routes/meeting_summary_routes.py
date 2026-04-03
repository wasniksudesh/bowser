# meeting_summary_routes.py - AI-powered post-meeting summarization endpoint
# POST /api/ai/meeting-summary
# Accepts transcript, user notes, template sections, and meeting title.
# Produces a structured markdown summary using the configured LLM.

import logging
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter()


# =============================================================================
# Request / Response Models
# =============================================================================

class TemplateSectionItem(BaseModel):
    title: str
    description: str = ""


class MeetingSummaryRequest(BaseModel):
    transcript: str
    notes: str = ""
    template_sections: List[TemplateSectionItem] = []
    meeting_title: str = "Meeting"
    model: Optional[str] = None


class MeetingSummaryResponse(BaseModel):
    summary: str


# =============================================================================
# Prompt Builder
# =============================================================================

def _build_prompt(req: MeetingSummaryRequest) -> str:
    """
    Build a structured LLM prompt from the meeting data.
    Template sections guide the output structure; user notes add context;
    the full transcript is the evidence base.
    """
    parts: list[str] = []

    parts.append(f"You are an expert meeting notes assistant. Your task is to produce a "
                 f"clean, structured summary of the meeting titled: \"{req.meeting_title}\".")
    parts.append("")

    if req.template_sections:
        section_names = ", ".join(f'"{s.title}"' for s in req.template_sections)
        parts.append(
            f"Structure your summary using exactly these sections (as ## headings): {section_names}. "
            f"For each section, extract and synthesize only the relevant content from the transcript."
        )
        parts.append("Section guidance:")
        for section in req.template_sections:
            if section.description:
                parts.append(f"  - {section.title}: {section.description}")
        parts.append("")
    else:
        parts.append(
            "Structure your summary with the following sections:\n"
            "## Key Discussion Points\n## Decisions Made\n## Action Items\n## Next Steps"
        )
        parts.append("")

    if req.notes.strip():
        parts.append("== PARTICIPANT NOTES ==")
        parts.append("The following notes were taken during the meeting. "
                     "Use them to identify what was considered most important:")
        parts.append(req.notes.strip())
        parts.append("")

    parts.append("== FULL TRANSCRIPT ==")
    parts.append(req.transcript.strip() if req.transcript.strip() else "(no transcript available)")
    parts.append("")
    parts.append(
        "== INSTRUCTIONS ==\n"
        "- Write in clear, concise prose. Use bullet points only inside sections where lists are natural.\n"
        "- Action items should be formatted as checkboxes: `- [ ] Owner: Task`.\n"
        "- Do NOT include filler phrases like 'The meeting discussed...' — go straight to the content.\n"
        "- Omit small talk and off-topic chatter.\n"
        "- If the transcript is sparse or unclear, still produce useful output from what is available."
    )

    return "\n".join(parts)


# =============================================================================
# Endpoint
# =============================================================================

@router.post("", response_model=MeetingSummaryResponse)
async def generate_meeting_summary(req: MeetingSummaryRequest):
    """
    Generate an AI-structured meeting summary.

    Accepts the raw transcript, user memos, and an optional template structure.
    Returns a markdown-formatted summary string.
    """
    if not req.transcript.strip() and not req.notes.strip():
        raise HTTPException(
            status_code=400,
            detail="Either transcript or notes must be provided."
        )

    try:
        from app.services.ai_agent import get_ai_agent
        from langchain_core.messages import HumanMessage, SystemMessage

        agent_service = await get_ai_agent()
        if agent_service is None:
            raise HTTPException(
                status_code=503,
                detail="AI service not configured. Set an API key via /api/configure."
            )

        prompt = _build_prompt(req)

        system_message = SystemMessage(
            content=(
                "You are a professional meeting notes assistant. "
                "Produce clean, structured markdown summaries. "
                "Be concise, accurate, and actionable."
            )
        )
        human_message = HumanMessage(content=prompt)

        # Use the LLM directly (not the full agent) for a one-shot completion
        llm = agent_service.llm if hasattr(agent_service, 'llm') else None

        if llm is None:
            # Fallback: use the agent's invoke path
            result = await agent_service.ainvoke(
                {"messages": [system_message, human_message]},
                config={"configurable": {"thread_id": "meeting-summary"}},
            )
            # Extract the last AI message
            messages = result.get("messages", [])
            ai_messages = [m for m in messages if hasattr(m, "content") and not isinstance(m, HumanMessage)]
            summary = ai_messages[-1].content if ai_messages else ""
        else:
            response = await llm.ainvoke([system_message, human_message])
            summary = response.content if hasattr(response, "content") else str(response)

        if not summary.strip():
            raise ValueError("Empty summary returned by LLM")

        logger.info(
            f"[MeetingSummary] Generated summary for '{req.meeting_title}' "
            f"({len(req.transcript)} chars transcript, {len(req.notes)} chars notes)"
        )
        return MeetingSummaryResponse(summary=summary.strip())

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[MeetingSummary] Failed to generate summary: {e}")
        raise HTTPException(status_code=500, detail=str(e))
