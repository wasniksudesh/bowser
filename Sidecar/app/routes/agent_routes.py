"""
Agent Mode Routes - Goal-Based Execution
API endpoints for the goal-based agent execution system
"""

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
import logging
import json
import asyncio
from datetime import datetime

from app.models.agent_schemas import (
    GoalPlanRequest,
    GoalPlanResponse,
    GoalApproveRequest,
    StepApproveRequest,
    GoalEvent,
    AuthRequirementModel
)
from app.services.agent_service import (
    GoalPlannerAgent,
    get_session_store
)
from app.services.skill_registry import get_registry

logger = logging.getLogger(__name__)

router = APIRouter()

# Initialize agents
goal_planner = GoalPlannerAgent()
session_store = get_session_store()
registry = get_registry()


# =============================================================================
# Routes
# =============================================================================

@router.post("/goals/plan", response_model=GoalPlanResponse)
async def create_goal_plan(request: GoalPlanRequest):
    """
    Generate a goal plan from a user query.
    LLM receives plugin summaries (no skills) and creates high-level goals.
    
    Returns:
    - GoalPlanModel with ordered goals
    - Required authentication
    - Session ID
    """
    try:
        logger.info(f"Creating goal plan for query: {request.query}")
        
        # Create a new session
        session_id = session_store.create_session(request.query)
        
        # Generate goal plan using GoalPlannerAgent
        goal_plan = await goal_planner.create_goal_plan(request.query)
        
        # Extract required auth from plugins used in goals
        required_auth = []
        seen_auth = set()
        
        for goal in goal_plan.goals:
            plugin = registry.get_plugin(goal.plugin_id)
            if plugin:
                for auth_req in plugin.auth_requirements:
                    if auth_req.auth_id not in seen_auth:
                        seen_auth.add(auth_req.auth_id)
                        
                        # Extract OAuth metadata
                        oauth_provider = None
                        oauth_scopes = None
                        for strategy in auth_req.strategies:
                            if strategy.type == "oauth":
                                oauth_provider = strategy.oauth_provider
                                oauth_scopes = strategy.oauth_scopes
                                break
                        
                        required_auth.append(AuthRequirementModel(
                            auth_id=auth_req.auth_id,
                            description=auth_req.description,
                            strategies=[s.type for s in auth_req.strategies],
                            oauth_provider=oauth_provider,
                            oauth_scopes=oauth_scopes
                        ))
        
        # Store goal plan in session
        session_store.update_session(session_id, {
            "goal_plan": goal_plan,
            "required_auth": required_auth,
            "status": "awaiting_goal_approval"
        })
        
        logger.info(
            f"Goal plan created with {len(goal_plan.goals)} goals, session {session_id}"
        )
        
        return GoalPlanResponse(
            session_id=session_id,
            goal_plan=goal_plan,
            required_auth=required_auth
        )
        
    except Exception as e:
        logger.exception("Failed to create goal plan")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/goals/{session_id}/approve")
async def approve_goal_plan(session_id: str, request: GoalApproveRequest):
    """
    Approve or reject a goal plan with optional feedback.
    If rejected, the plan is refined based on feedback.
    
    Args:
    - approved: true to approve, false to reject
    - feedback: optional feedback if rejected
    
    Returns:
    - status and optionally revised plan
    """
    try:
        logger.info(f"Received goal plan approval for session {session_id}: approved={request.approved}")
        
        # Get session
        session = session_store.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        goal_plan = session.get("goal_plan")
        if not goal_plan:
            raise HTTPException(status_code=400, detail="No goal plan found. Call /goals/plan first.")
        
        if request.approved:
            # Mark plan as approved
            goal_plan.status = "approved"
            session_store.update_session(session_id, {
                "goal_plan": goal_plan,
                "status": "ready_to_execute"
            })
            
            return {
                "status": "approved",
                "message": "Goal plan approved. Call /goals/{session_id}/run to start execution."
            }
        else:
            # Refine plan based on feedback
            if not request.feedback:
                raise HTTPException(status_code=400, detail="Feedback required when rejecting plan")
            
            # Check revision limit
            revision_count = session.get("revision_count", 0)
            if revision_count >= 5:  # MAX_GOAL_PLAN_REVISIONS
                raise HTTPException(status_code=400, detail="Maximum plan revisions reached")
            
            logger.info(f"Refining goal plan with feedback: {request.feedback}")
            
            refined_plan = await goal_planner.refine_goal_plan(
                session["query"],
                goal_plan,
                request.feedback
            )
            
            # Extract required auth again
            required_auth = []
            seen_auth = set()
            
            for goal in refined_plan.goals:
                plugin = registry.get_plugin(goal.plugin_id)
                if plugin:
                    for auth_req in plugin.auth_requirements:
                        if auth_req.auth_id not in seen_auth:
                            seen_auth.add(auth_req.auth_id)
                            
                            oauth_provider = None
                            oauth_scopes = None
                            for strategy in auth_req.strategies:
                                if strategy.type == "oauth":
                                    oauth_provider = strategy.oauth_provider
                                    oauth_scopes = strategy.oauth_scopes
                                    break
                            
                            required_auth.append(AuthRequirementModel(
                                auth_id=auth_req.auth_id,
                                description=auth_req.description,
                                strategies=[s.type for s in auth_req.strategies],
                                oauth_provider=oauth_provider,
                                oauth_scopes=oauth_scopes
                            ))
            
            session_store.update_session(session_id, {
                "goal_plan": refined_plan,
                "required_auth": required_auth,
                "revision_count": revision_count + 1,
                "status": "awaiting_goal_approval"
            })
            
            return {
                "status": "revised",
                "message": "Goal plan revised based on feedback",
                "goal_plan": refined_plan.model_dump(),
                "required_auth": [a.model_dump() for a in required_auth]
            }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to process goal plan approval")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/goals/{session_id}/run")
async def run_goal_execution(session_id: str):
    """
    Start the goal execution loop in the background.
    The loop will pause at each goal for step approval via /goals/{session_id}/steps/approve.
    Events are streamed via /goals/{session_id}/events.
    
    Returns:
    - session_id and status
    """
    try:
        from app.services.goal_executor import GoalExecutionLoop
        from app.services.agent_service import ContextAgent
        
        logger.info(f"Starting goal execution loop for session: {session_id}")
        
        # Get session
        session = session_store.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Check if goal plan is approved
        goal_plan = session.get("goal_plan")
        if not goal_plan:
            raise HTTPException(status_code=400, detail="No goal plan found. Call /goals/plan first.")
        
        if goal_plan.status != "approved":
            raise HTTPException(status_code=400, detail="Goal plan not approved. Call /goals/{session_id}/approve first.")
        
        # Create initial context artifact (empty for now, will be filled per-goal)
        context_agent = ContextAgent()
        context_artifact = context_agent.create_context_artifact(
            values={},
            auth={},
            required_fields=[]
        )
        
        # Create event queue and approval event
        event_queue = asyncio.Queue()
        approval_event = asyncio.Event()
        
        # Update session with execution fields
        session_store.update_session(session_id, {
            "status": "executing",
            "context_artifact": context_artifact,
            "event_queue": event_queue,
            "approval_event": approval_event,
            "current_goal_index": 0
        })
        
        # Event callback to push to queue
        def emit_event(event: GoalEvent):
            try:
                event_queue.put_nowait(event)
            except:
                logger.error("Failed to emit event to queue")
        
        # Start the goal execution loop in background
        loop = GoalExecutionLoop()
        
        # Decision getter to check user approval/rejection
        def get_decision():
            sess = session_store.get_session(session_id)
            if sess:
                decision = sess.get("last_decision")
                # Clear decision after reading
                if decision:
                    session_store.update_session(session_id, {"last_decision": None})
                return decision
            return None
        
        async def run_loop():
            try:
                result = await loop.run(
                    session_id=session_id,
                    query=session["query"],
                    goal_plan=goal_plan,
                    context=context_artifact,
                    event_callback=emit_event,
                    approval_event=approval_event,
                    get_decision=get_decision,
                    timeout_seconds=600
                )
                
                # Update session with final result
                session_store.update_session(session_id, {
                    "status": result.get("status", "complete"),
                    "final_result": result
                })
                
                # Emit final event
                emit_event(GoalEvent(
                    event_type="complete" if result.get("status") == "complete" else "error",
                    data={"result": result},
                    goal_id=None,
                    timestamp=datetime.now()
                ))
                
            except Exception as e:
                logger.error(f"Goal execution loop failed: {e}", exc_info=True)
                session_store.update_session(session_id, {
                    "status": "failed"
                })
                emit_event(GoalEvent(
                    event_type="error",
                    data={"error": str(e)},
                    goal_id=None,
                    timestamp=datetime.now()
                ))
        
        # Start background task
        asyncio.create_task(run_loop())
        
        return {
            "session_id": session_id,
            "status": "running",
            "message": "Goal execution started. Subscribe to /goals/{session_id}/events for updates."
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to start goal execution")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/goals/{session_id}/goals/{goal_id}/start")
async def start_goal_execution(session_id: str, goal_id: str, request: StepApproveRequest):
    """
    Start execution of a specific goal after user clicks "Start Execution".
    Approves the steps and provides required inputs for this goal.
    
    Args:
    - approved: true to approve, false to reject
    - feedback: optional feedback if rejected
    - input_values: user-provided input values
    - auth: authentication tokens
    
    Returns:
    - status
    """
    try:
        logger.info(f"Received goal execution start for session {session_id}, goal {goal_id}: approved={request.approved} ; input-values={request.input_values}")
        
        # Get session
        session = session_store.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Get approval event
        approval_event = session.get("approval_event")
        if not approval_event:
            raise HTTPException(status_code=400, detail="No pending approval")
        
        # Store decision in session
        session_store.update_session(session_id, {
            "last_decision": {
                "approved": request.approved,
                "feedback": request.feedback,
                "input_values": request.input_values,
                "auth": request.auth,
                "timestamp": datetime.now()
            }
        })
        
        if request.approved:
            # Signal approval
            approval_event.set()
            return {"status": "approved", "message": f"Goal {goal_id} execution started"}
        else:
            # For rejection, we need to handle it in the loop
            approval_event.set()
            return {"status": "rejected", "message": "Goal execution rejected. Feedback recorded."}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to process goal execution start")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/goals/{session_id}/steps/approve")
async def approve_steps(session_id: str, request: StepApproveRequest):
    """
    LEGACY ENDPOINT: User decision on proposed steps for a goal.
    Use /goals/{session_id}/goals/{goal_id}/start instead.
    
    Approves or rejects the steps and provides required inputs.
    
    Args:
    - approved: true to approve, false to reject
    - feedback: optional feedback if rejected
    - input_values: user-provided input values
    - auth: authentication tokens
    
    Returns:
    - status
    """
    try:
        logger.info(f"Received step approval for session {session_id}: approved={request.approved}")
        
        # Get session
        session = session_store.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        # Get approval event
        approval_event = session.get("approval_event")
        if not approval_event:
            raise HTTPException(status_code=400, detail="No pending approval")
        
        # Store decision in session
        session_store.update_session(session_id, {
            "last_decision": {
                "approved": request.approved,
                "feedback": request.feedback,
                "input_values": request.input_values,
                "auth": request.auth,
                "timestamp": datetime.now()
            }
        })
        
        if request.approved:
            # Signal approval
            approval_event.set()
            return {"status": "approved", "message": "Steps approved, continuing execution"}
        else:
            # For rejection, we need to handle it in the loop
            approval_event.set()
            return {"status": "rejected", "message": "Steps rejected. Feedback recorded."}
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to process step approval")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/goals/{session_id}/events")
async def stream_events(session_id: str):
    """
    Server-Sent Events (SSE) endpoint for streaming goal execution events.
    
    Events include:
    - goal_plan_created: Initial goal plan ready
    - goal_plan_revised: Plan revised after feedback
    - goal_started: Starting execution of a goal
    - steps_planned: Steps created for a goal
    - steps_revised: More steps added after retry
    - step_executed: Individual step finished
    - goal_evaluated: Goal evaluation result
    - goal_completed: Goal finished successfully
    - goal_failed: Goal failed after max retries
    - final_evaluated: Final query evaluation
    - plan_extended: More goals/steps added
    - complete: Everything done
    - error: Error occurred
    """
    
    async def event_generator():
        try:
            # Get session
            session = session_store.get_session(session_id)
            if not session:
                yield f"data: {json.dumps({'error': 'Session not found'})}\n\n"
                return
            
            # Get event queue
            event_queue = session.get("event_queue")
            if not event_queue:
                yield f"data: {json.dumps({'error': 'No event queue found'})}\n\n"
                return
            
            logger.info(f"Starting SSE stream for session {session_id}")
            
            # Stream events from queue
            while True:
                try:
                    # Wait for event with timeout
                    event = await asyncio.wait_for(event_queue.get(), timeout=30.0)
                    
                    # Serialize event (use mode='json' to handle datetime serialization)
                    event_data = event.model_dump(mode='json')
                    event_json = json.dumps(event_data)
                    
                    # Send SSE event
                    yield f"data: {event_json}\n\n"
                    
                    # Check if loop is complete
                    if event.event_type in ["complete", "error"]:
                        logger.info(f"Loop completed for session {session_id}")
                        break
                    
                except asyncio.TimeoutError:
                    # Send keepalive
                    yield f": keepalive\n\n"
                    
                    # Check if session still exists
                    session = session_store.get_session(session_id)
                    if not session:
                        break
                    
                    # Check if execution is done
                    status = session.get("status")
                    if status in ["complete", "failed"]:
                        break
                
        except Exception as e:
            logger.error(f"SSE stream error: {e}", exc_info=True)
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
    
    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"
        }
    )


@router.get("/goals/{session_id}/status")
async def get_session_status(session_id: str):
    """
    Get current session and goal status.
    
    Returns:
    - Session status
    - Current goal index
    - Goal statuses
    """
    try:
        session = session_store.get_session(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="Session not found")
        
        goal_plan = session.get("goal_plan")
        
        response = {
            "session_id": session_id,
            "status": session.get("status"),
            "query": session.get("query"),
            "timestamp": session.get("timestamp").isoformat() if session.get("timestamp") else None,
            "current_goal_index": session.get("current_goal_index", 0),
            "goals": []
        }
        
        if goal_plan:
            for goal in goal_plan.goals:
                response["goals"].append({
                    "goal_id": goal.goal_id,
                    "description": goal.description,
                    "plugin_id": goal.plugin_id,
                    "status": goal.status.value,
                    "retry_count": goal.retry_count,
                    "steps_count": len(goal.steps)
                })
        
        return response
        
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to get session status")
        raise HTTPException(status_code=500, detail=str(e))
