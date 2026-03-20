//
//  AgentState.swift
//  Bowser
//
//  State management for Agent Mode
//  Implements ReAct agent loop with SSE event streaming and user approval
//

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Agent State
// =============================================================================

/// Observable state for Agent Mode
/// Manages agent execution sessions with context artifacts and step-by-step execution
@Observable
@MainActor
final class AgentState {

    // MARK: - Session Management

    /// All agent sessions (history)
    var sessions: [AgentSession] = []

    /// Currently active session
    var currentSession: AgentSession?

    /// Loading state
    var isLoading: Bool = false

    /// Error message
    var errorMessage: String?

    // MARK: - Initialization

    init() {
        // Load sessions from storage if needed
    }

    // MARK: - API Methods

    /// Submit a new query to create a session and generate a goal plan
    func submitQuery(_ query: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // Call backend to generate goal plan
            let url = URL(string: "http://localhost:8765/api/agent/goals/plan")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = ["query": query]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to generate plan"
                isLoading = false
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // Get session_id from backend response
            guard let sessionIdString = json?["session_id"] as? String,
                let sessionId = UUID(uuidString: sessionIdString)
            else {
                errorMessage = "Invalid session ID from backend"
                isLoading = false
                return
            }

            // Create session with the backend's session ID
            let session = AgentSession(id: sessionId, query: query)
            currentSession = session
            sessions.insert(session, at: 0)

            // Parse goal_plan (backend returns goal_plan, not execution_plan)
            if let goalPlanData = json?["goal_plan"] as? [String: Any] {
                session.executionPlan = try parseGoalPlanToExecutionPlan(from: goalPlanData)
                // Also populate goals array for goal-by-goal execution
                session.goals = parseGoalsArray(from: goalPlanData)
            }

            // Parse required_auth
            if let requiredAuth = json?["required_auth"] as? [[String: Any]] {
                var authEntries: [String: AuthEntry] = [:]
                for authReq in requiredAuth {
                    if let authId = authReq["auth_id"] as? String,
                        let strategies = authReq["strategies"] as? [String],
                        let firstStrategy = strategies.first
                    {
                        authEntries[authId] = AuthEntry(
                            strategyUsed: firstStrategy,
                            value: "",
                            valid: false
                        )
                    }
                }
                if session.contextArtifact == nil {
                    session.contextArtifact = ContextArtifact(
                        version: 1, values: [:], auth: authEntries)
                } else {
                    session.contextArtifact?.auth = authEntries
                }
            }

            // Status: always awaitingApproval after plan creation
            // Auth will be collected per-goal when needed
            session.status = .awaitingApproval

            isLoading = false
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Approve the goal plan
    /// Calls POST /goals/{session_id}/approve
    func approveGoalPlan(approved: Bool, feedback: String? = nil) async {
        guard let session = currentSession else { return }

        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/approve")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var requestBody: [String: Any] = ["approved": approved]
            if let feedback = feedback {
                requestBody["feedback"] = feedback
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to approve goal plan"
                isLoading = false
                return
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let status = json?["status"] as? String
            
            if status == "approved" {
                // Update the plan status to approved
                session.executionPlan?.status = "approved"
                session.status = .ready
            } else if status == "revised" {
                // Plan was revised, parse the new goal_plan
                if let goalPlanData = json?["goal_plan"] as? [String: Any] {
                    session.executionPlan = try parseGoalPlanToExecutionPlan(from: goalPlanData)
                    // Also update goals array
                    session.goals = parseGoalsArray(from: goalPlanData)
                }
                // Update required_auth if changed
                if let requiredAuth = json?["required_auth"] as? [[String: Any]] {
                    var authEntries: [String: AuthEntry] = [:]
                    for authReq in requiredAuth {
                        if let authId = authReq["auth_id"] as? String,
                            let strategies = authReq["strategies"] as? [String],
                            let firstStrategy = strategies.first
                        {
                            authEntries[authId] = AuthEntry(
                                strategyUsed: firstStrategy,
                                value: "",
                                valid: false
                            )
                        }
                    }
                    session.contextArtifact?.auth = authEntries
                }
                session.status = .awaitingApproval
            }

            isLoading = false
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Submit context artifact values (clarify fields + auth) when user fills the form
    /// Updates the session context and transitions to awaiting plan approval
    func submitClarification(values: [String: String]) async {
        guard let session = currentSession, let context = session.contextArtifact else { return }
        for (key, value) in values {
            context.values[key]?.value = value
        }
        session.status = .awaitingApproval
    }

    /// Approve or reject the current thought (e.g. proposed steps during goal execution)
    /// Calls approveSteps to send decision to backend
    func decideAction(approved: Bool, feedback: String? = nil) async {
        await approveSteps(approved: approved, feedback: feedback)
    }

    /// Start the goal execution loop for the current session
    func runAgent() async {
        guard let session = currentSession else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/run")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to start goal execution"
                isLoading = false
                return
            }
            
            // Update session status
            session.status = .running
            
            isLoading = false
            
            // Start listening to events in the background
            Task {
                await streamEvents(for: session)
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    /// Stream events from the goal execution loop
    private func streamEvents(for session: AgentSession) async {
        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/events")!
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to stream events"
                return
            }
                        
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await handleEvent(json, for: session)
                    }
                }
            }
        } catch {
            print("Event stream error: \(error.localizedDescription)")
        }
    }
    
    /// Handle events from goal-based agent loop
    @MainActor
    private func handleEvent(_ event: [String: Any], for session: AgentSession) async {
        guard let eventType = event["event_type"] as? String else { return }
        let _ = event["goal_id"] as? String  // goalId available but not always used
        let data = event["data"] as? [String: Any] ?? [:]
        
        switch eventType {
        // Goal planning events
        case "goal_plan_created":
            // Initial goal plan created (informational)
            if let goalPlanData = data["goal_plan"] as? [String: Any] {
                do {
                    session.executionPlan = try parseGoalPlanToExecutionPlan(from: goalPlanData)
                    // Also populate goals array
                    session.goals = parseGoalsArray(from: goalPlanData)
                } catch {
                    print("Error parsing goal plan: \(error)")
                }
            }
            
        case "goal_plan_revised":
            // Goal plan revised after feedback
            if let goalPlanData = data["goal_plan"] as? [String: Any] {
                do {
                    session.executionPlan = try parseGoalPlanToExecutionPlan(from: goalPlanData)
                    // Also update goals array
                    session.goals = parseGoalsArray(from: goalPlanData)
                } catch {
                    print("Error parsing revised goal plan: \(error)")
                }
            }
            session.status = .awaitingApproval
            
        // Goal execution events
        case "goal_started":
            // A goal has started planning its steps
            if let goalIndex = data["goal_index"] as? Int {
                session.currentGoalIndex = goalIndex
                if goalIndex < session.goals.count {
                    session.goals[goalIndex].status = .planningSteps
                    // Expand current goal, collapse all others
                    for i in 0..<session.goals.count {
                        session.goals[i].isExpanded = (i == goalIndex)
                    }
                }
            }
            
        case "steps_planned":
            // Steps have been planned for a goal, show "Start Execution" button
            if let goalIndex = data["goal_index"] as? Int,
               goalIndex < session.goals.count {
                let goal = session.goals[goalIndex]
                goal.status = .awaitingStart
                
                // Parse steps
                if let stepsData = data["steps"] as? [[String: Any]] {
                    goal.steps = stepsData.compactMap { stepData -> GoalStepInfo? in
                        guard let stepId = stepData["step_id"] as? String,
                              let skillId = stepData["skill_id"] as? String,
                              let description = stepData["description"] as? String
                        else { return nil }
                        
                        return GoalStepInfo(
                            stepId: stepId,
                            skillId: skillId,
                            description: description,
                            status: .pending
                        )
                    }
                }
                
                // Parse required inputs
                if let inputsData = data["required_inputs"] as? [[String: Any]] {
                    goal.requiredInputs = inputsData.compactMap { inputData -> ContextFieldInfo? in
                        guard let name = inputData["name"] as? String,
                              let description = inputData["description"] as? String,
                              let required = inputData["required"] as? Bool,
                              let fieldType = inputData["field_type"] as? String
                        else { return nil }
                        
                        return ContextFieldInfo(
                            name: name,
                            description: description,
                            required: required,
                            fieldType: fieldType
                        )
                    }
                }
                
                session.status = .awaitingInput
            }
            
        case "steps_revised":
            // More steps added after retry for current goal
            let goalIndex = session.currentGoalIndex
            if goalIndex < session.goals.count,
               let newStepsData = data["steps"] as? [[String: Any]] {
                let goal = session.goals[goalIndex]
                
                let newSteps = newStepsData.compactMap { stepData -> GoalStepInfo? in
                    guard let stepId = stepData["step_id"] as? String,
                          let skillId = stepData["skill_id"] as? String,
                          let description = stepData["description"] as? String
                    else { return nil }
                    
                    return GoalStepInfo(
                        stepId: stepId,
                        skillId: skillId,
                        description: description,
                        status: .pending
                    )
                }
                goal.steps.append(contentsOf: newSteps)
                goal.status = .awaitingStart
                session.status = .awaitingInput
            }
            
        case "step_executed":
            // Individual step finished - update step status and store output
            if let stepId = data["step_id"] as? String,
               let success = data["success"] as? Bool {
                // Find the goal and step
                for goal in session.goals {
                    if let step = goal.steps.first(where: { $0.stepId == stepId }) {
                        step.status = success ? .completed : .failed
                        
                        // Parse and store output artifact
                        if success,
                           let view = data["view"] as? String,
                           let dataPacket = data["data"] as? [String: Any] {
                            do {
                                step.output = try parseDataPacketToArtifact(
                                    dataPacket: dataPacket,
                                    view: view,
                                    skillId: data["skill_id"] as? String ?? ""
                                )
                            } catch {
                                print("Error parsing step output: \(error)")
                            }
                        }
                        break
                    }
                }
            }
            
        case "goal_evaluated":
            // Goal evaluation result
            if let evaluation = data["evaluation"] as? [String: Any] {
                session.lastEvaluation = evaluation
            }
            
        case "goal_completed":
            // Goal completed successfully
            if let goalIndex = data["goal_index"] as? Int,
               goalIndex < session.goals.count {
                session.goals[goalIndex].status = .completed
                // Collapse this goal - next goal will be expanded when goal_started fires
                session.goals[goalIndex].isExpanded = false
            }
            
        case "goal_failed":
            let goalIndex = session.currentGoalIndex
            if goalIndex < session.goals.count {
                session.goals[goalIndex].status = .failed
            }
            
        case "final_evaluated":
            // Final query evaluation
            if let evaluation = data["evaluation"] as? [String: Any] {
                session.lastEvaluation = evaluation
            }
            
        case "plan_extended":
            // More goals added to the plan
            if let newGoalsData = data["new_goals"] as? [[String: Any]] {
                let newGoals = newGoalsData.compactMap { goalData -> GoalInfo? in
                    guard let goalId = goalData["goal_id"] as? String,
                          let description = goalData["description"] as? String,
                          let pluginId = goalData["plugin_id"] as? String
                    else { return nil }
                    
                    return GoalInfo(
                        goalId: goalId,
                        description: description,
                        pluginId: pluginId,
                        status: .pending
                    )
                }
                session.goals.append(contentsOf: newGoals)
            }
            
        case "complete":
            session.status = .completed
            session.currentThought = nil
            if let result = data["result"] as? [String: Any] {
                session.lastEvaluation = result
            }
            isLoading = false
            
        case "error":
            if let error = data["error"] as? String {
                errorMessage = error
            }
            session.status = .failed
            session.currentThought = nil
            isLoading = false
            
        default:
            break
        }
    }
    
    /// Parse goals array from goal plan data
    private func parseGoalsArray(from goalPlanData: [String: Any]) -> [GoalInfo] {
        guard let goalsData = goalPlanData["goals"] as? [[String: Any]] else {
            return []
        }
        
        return goalsData.compactMap { goalData -> GoalInfo? in
            guard let goalId = goalData["goal_id"] as? String,
                  let description = goalData["description"] as? String,
                  let pluginId = goalData["plugin_id"] as? String
            else { return nil }
            
            let statusStr = goalData["status"] as? String ?? "pending"
            let status: GoalExecutionStatus = {
                switch statusStr {
                case "planning_steps": return .planningSteps
                case "awaiting_step_approval": return .awaitingStart
                case "executing": return .executing
                case "completed": return .completed
                case "failed": return .failed
                default: return .pending
                }
            }()
            
            return GoalInfo(
                goalId: goalId,
                description: description,
                pluginId: pluginId,
                status: status
            )
        }
    }
    
    /// Update context artifact with step outputs
    private func updateContextWithOutputs(_ contextUpdates: [String: Any], for session: AgentSession) {
        guard let context = session.contextArtifact else { return }
        
        for (key, value) in contextUpdates {
            // Add to context as namespaced field (e.g., "listCommits.commit_shas")
            context.values[key] = ContextValue(
                name: key,
                description: "Output from skill execution",
                value: String(describing: value),
                required: false,
                fieldType: .string
            )
        }
    }
    
    /// Start execution for a specific goal
    /// Calls POST /goals/{session_id}/goals/{goal_id}/start
    func startGoalExecution(goalId: String, inputValues: [String: String]? = nil) async {
        guard let session = currentSession else { return }

        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/goals/\(goalId)/start")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var requestBody: [String: Any] = ["approved": true]
            
            if let inputValues = inputValues {
                requestBody["input_values"] = inputValues
            }
            
            // Build auth in backend format: {auth_id: {strategy, value}}
            var authDict: [String: Any] = [:]
            if let sessionAuth = session.contextArtifact?.auth {
                for (key, entry) in sessionAuth where !entry.value.isEmpty {
                    authDict[key] = [
                        "strategy": entry.strategyUsed,
                        "value": entry.value,
                    ]
                }
            }
            if !authDict.isEmpty {
                requestBody["auth"] = authDict
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to start goal execution"
                isLoading = false
                return
            }
            
            // Update goal status to executing
            if let goal = session.goals.first(where: { $0.goalId == goalId }) {
                goal.status = .executing
            }

            isLoading = false
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    /// Approve or reject steps during goal execution
    /// Calls POST /goals/{session_id}/steps/approve
    func approveSteps(approved: Bool, feedback: String? = nil, inputValues: [String: String]? = nil, auth: [String: [String: String]]? = nil) async {
        guard let session = currentSession else { return }

        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/steps/approve")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var requestBody: [String: Any] = ["approved": approved]
            if let feedback = feedback {
                requestBody["feedback"] = feedback
            }
            if let inputValues = inputValues {
                requestBody["input_values"] = inputValues
            }
            
            // Build auth in backend format: {auth_id: {strategy, value}}
            var authDict: [String: Any] = auth ?? [:]
            if authDict.isEmpty, let sessionAuth = session.contextArtifact?.auth {
                for (key, entry) in sessionAuth {
                    authDict[key] = [
                        "strategy": entry.strategyUsed,
                        "value": entry.value,
                    ]
                }
            }
            if !authDict.isEmpty {
                requestBody["auth"] = authDict
            }
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                errorMessage = "Failed to approve steps"
                isLoading = false
                return
            }

            isLoading = false
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Create a new empty session
    func createNewSession() {
        currentSession = nil
        errorMessage = nil
    }
    
    /// Get current session status
    /// Calls GET /goals/{session_id}/status
    func getSessionStatus() async -> SessionStatusResponse? {
        guard let session = currentSession else { return nil }
        
        do {
            let url = URL(string: "http://localhost:8765/api/agent/goals/\(session.id.uuidString)/status")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let json = json else { return nil }
            
            let status = json["status"] as? String
            let currentGoalIndex = json["current_goal_index"] as? Int ?? 0
            let goalsData = json["goals"] as? [[String: Any]] ?? []
            
            var goalStatuses: [GoalStatusInfo] = []
            for goalData in goalsData {
                if let goalId = goalData["goal_id"] as? String,
                   let description = goalData["description"] as? String,
                   let pluginId = goalData["plugin_id"] as? String,
                   let statusStr = goalData["status"] as? String {
                    goalStatuses.append(GoalStatusInfo(
                        goalId: goalId,
                        description: description,
                        pluginId: pluginId,
                        status: statusStr,
                        retryCount: goalData["retry_count"] as? Int ?? 0,
                        stepsCount: goalData["steps_count"] as? Int ?? 0
                    ))
                }
            }
            
            return SessionStatusResponse(
                sessionId: session.id.uuidString,
                status: status,
                query: json["query"] as? String,
                currentGoalIndex: currentGoalIndex,
                goals: goalStatuses
            )
        } catch {
            print("Error fetching session status: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helpers

    /// Flatten goal_plan (GoalPlan) to ExecutionPlan for UI display
    private func parseGoalPlanToExecutionPlan(from json: [String: Any]) throws -> ExecutionPlan {
        let planId = json["plan_id"] as? String ?? UUID().uuidString
        let status = json["status"] as? String ?? "draft"
        let goalsData = json["goals"] as? [[String: Any]] ?? []
        var steps: [AgentPlanStep] = []
        
        func flattenGoals(_ goals: [[String: Any]], depth: Int = 0) {
            for goalData in goals {
                guard let stepId = goalData["goal_id"] as? String,
                      let description = goalData["description"] as? String
                else { continue }
                
                let agentType: AgentType = .operation
                let pluginId = goalData["plugin_id"] as? String
                let skillId = goalData["skill_id"] as? String
                
                steps.append(AgentPlanStep(
                    stepId: stepId,
                    agentType: agentType,
                    pluginId: pluginId,
                    skillId: skillId,
                    description: description
                ))
                
                if let subGoals = goalData["sub_goals"] as? [[String: Any]], !subGoals.isEmpty {
                    flattenGoals(subGoals, depth: depth + 1)
                }
            }
        }
        flattenGoals(goalsData)
        
        return ExecutionPlan(planId: planId, steps: steps, status: status)
    }

    private func parseExecutionPlan(from json: [String: Any]) throws -> ExecutionPlan {
        let planId = json["plan_id"] as? String ?? UUID().uuidString
        let status = json["status"] as? String ?? "draft"
        let stepsData = json["steps"] as? [[String: Any]] ?? []

        let steps = stepsData.compactMap { stepData -> AgentPlanStep? in
            guard let stepId = stepData["step_id"] as? String,
                let agentTypeStr = stepData["agent_type"] as? String
            else {
                return nil
            }

            let agentType = AgentType(rawValue: agentTypeStr) ?? .operation
            let pluginId = stepData["plugin_id"] as? String
            let skillId = stepData["skill_id"] as? String
            let description = stepData["description"] as? String

            // Parse foreach directive if present
            var isForeach = false
            var foreachSource: String? = nil
            if let foreachData = stepData["foreach"] as? [String: Any],
                let source = foreachData["source"] as? String
            {
                isForeach = true
                foreachSource = source
            }

            return AgentPlanStep(
                stepId: stepId,
                agentType: agentType,
                pluginId: pluginId,
                skillId: skillId,
                description: description,
                isForeach: isForeach,
                foreachSource: foreachSource
            )
        }

        return ExecutionPlan(planId: planId, steps: steps, status: status)
    }

    private func parseContextArtifact(from json: [String: Any]) throws -> ContextArtifact {
        let version = json["version"] as? Int ?? 1
        
        // Parse both user_values and step_outputs, fallback to legacy values field
        let userValuesData = json["user_values"] as? [String: Any] ?? [:]
        let stepOutputsData = json["step_outputs"] as? [String: Any] ?? [:]
        let legacyValuesData = json["values"] as? [String: Any] ?? [:]
        let authData = json["auth"] as? [String: Any] ?? [:]

        var values: [String: ContextValue] = [:]
        
        // Parse user_values
        for (key, valueData) in userValuesData {
            if let dict = valueData as? [String: Any] {
                values[key] = ContextValue(
                    name: key,
                    description: dict["description"] as? String ?? "",
                    value: dict["value"] as? String ?? "",
                    required: dict["required"] as? Bool ?? false,
                    fieldType: ContextFieldType(rawValue: dict["field_type"] as? String ?? "string")
                        ?? .string
                )
            }
        }
        
        // Parse step_outputs (namespaced fields like "skill_id.field_name")
        for (key, valueData) in stepOutputsData {
            if let dict = valueData as? [String: Any] {
                values[key] = ContextValue(
                    name: key,
                    description: dict["description"] as? String ?? "",
                    value: dict["value"] as? String ?? "",
                    required: dict["required"] as? Bool ?? false,
                    fieldType: ContextFieldType(rawValue: dict["field_type"] as? String ?? "string")
                        ?? .string
                )
            }
        }
        
        // Fallback to legacy values field
        if values.isEmpty {
            for (key, valueData) in legacyValuesData {
                if let dict = valueData as? [String: Any] {
                    values[key] = ContextValue(
                        name: key,
                        description: dict["description"] as? String ?? "",
                        value: dict["value"] as? String ?? "",
                        required: dict["required"] as? Bool ?? false,
                        fieldType: ContextFieldType(rawValue: dict["field_type"] as? String ?? "string")
                            ?? .string
                    )
                }
            }
        }

        var auth: [String: AuthEntry] = [:]
        for (key, authEntryData) in authData {
            if let dict = authEntryData as? [String: Any] {
                auth[key] = AuthEntry(
                    strategyUsed: dict["strategy_used"] as? String ?? "token",
                    value: dict["value"] as? String ?? "",
                    valid: dict["valid"] as? Bool ?? true
                )
            }
        }

        return ContextArtifact(version: version, values: values, auth: auth)
    }

    /// Parse DataPacket (new format) to OutputArtifact
    private func parseDataPacketToArtifact(
        dataPacket: [String: Any],
        view: String,
        skillId: String
    ) throws -> OutputArtifact {
        let rows = dataPacket["rows"] as? [[String: Any]] ?? []
        let schema = dataPacket["schema"] as? [String: Any]
        
        let artifactData: ArtifactData
        
        switch view {
        case "text":
            // Text view expects schema {"text": "string"} and rows [{"text": "..."}]
            let content = rows.first?["text"] as? String ?? ""
            let textData = TextArtifactData(content: content, format: "plain")
            artifactData = .text(textData)
            
        case "error":
            // Error view expects schema {"error": "string", "code": "string", "details": "object"}
            let errorMsg = rows.first?["error"] as? String ?? "Unknown error"
            let errorCode = rows.first?["code"] as? String ?? "UNKNOWN"
            let details = rows.first?["details"] as? [String: Any]
            
            var errorText = "Error [\(errorCode)]: \(errorMsg)"
            if let details = details, !details.isEmpty {
                errorText += "\n\nDetails: \(details)"
            }
            let textData = TextArtifactData(content: errorText, format: "plain")
            artifactData = .text(textData)
            
        case "table":
            // Table view: extract columns from schema and rows from DataPacket
            let columns: [TableColumnData]
            if let schemaProps = schema?["properties"] as? [String: Any] {
                columns = schemaProps.keys.sorted().map { key in
                    TableColumnData(key: key, label: key.capitalized)
                }
            } else if let firstRow = rows.first {
                columns = firstRow.keys.sorted().map { key in
                    TableColumnData(key: key, label: key.capitalized)
                }
            } else {
                columns = []
            }
            
            // Convert rows to [[String]] format
            let tableRows = rows.map { row in
                columns.map { col in
                    if let value = row[col.key] {
                        return String(describing: value)
                    }
                    return ""
                }
            }
            
            let tableData = TableArtifactData(columns: columns, rows: tableRows)
            artifactData = .table(tableData)
            
        case "list":
            // List view: rows with label/value or first two columns
            let listItems = rows.map { row -> ListItemData in
                if let label = row["label"] as? String {
                    let value = (row["value"] as? String) ?? (row["value"].map { String(describing: $0) })
                    return ListItemData(label: label, value: value)
                }
                let keys = Array(row.keys).sorted()
                let label = keys.isEmpty ? "" : String(describing: row[keys[0]] ?? "")
                let value = keys.count > 1 ? String(describing: row[keys[1]] ?? "") : nil
                return ListItemData(label: label, value: value)
            }
            let listData = ListArtifactData(items: listItems)
            artifactData = .list(listData)
            
        case "json":
            // JSON view: render rows as formatted JSON
            let jsonData = try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            let textData = TextArtifactData(content: jsonString, format: "json")
            artifactData = .text(textData)
            
        default:
            // Unknown view type - fallback to JSON
            let jsonData = try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            let textData = TextArtifactData(content: jsonString, format: "json")
            artifactData = .text(textData)
        }
        
        return OutputArtifact(
            artifactId: UUID().uuidString,
            type: view,
            artifactData: artifactData,
            rowSet: nil
        )
    }
    
    /// Legacy parser for old artifact format (kept for backward compatibility)
    private func parseOutputArtifact(from json: [String: Any], rowSet: RowSetData? = nil) throws
        -> OutputArtifact
    {
        let artifactId = json["artifact_id"] as? String ?? UUID().uuidString
        let type = json["type"] as? String ?? "text"
        
        // Decode typed artifact data based on type field
        guard let dataJSON = json["data"] else {
            throw NSError(domain: "AgentState", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing data field"])
        }
        
        let dataJSONData = try JSONSerialization.data(withJSONObject: dataJSON)
        let decoder = JSONDecoder()
        
        let artifactData: ArtifactData
        switch type {
        case "text":
            let textData = try decoder.decode(TextArtifactData.self, from: dataJSONData)
            artifactData = .text(textData)
        case "table":
            let tableData = try decoder.decode(TableArtifactData.self, from: dataJSONData)
            artifactData = .table(tableData)
        case "list":
            let listData = try decoder.decode(ListArtifactData.self, from: dataJSONData)
            artifactData = .list(listData)
        case "chart":
            let chartData = try decoder.decode(ChartArtifactData.self, from: dataJSONData)
            artifactData = .chart(chartData)
        default:
            // Fallback to text for unknown types
            let textData = TextArtifactData(content: "Unknown artifact type: \(type)", format: "plain")
            artifactData = .text(textData)
        }

        return OutputArtifact(
            artifactId: artifactId,
            type: type,
            artifactData: artifactData,
            rowSet: rowSet
        )
    }

    private func parseRowSet(from json: [String: Any]) throws -> RowSetData {
        let stepId = json["step_id"] as? String ?? ""
        let field = json["field"] as? String ?? ""
        let count = json["count"] as? Int ?? 0
        let rowsData = json["rows"] as? [[String: Any]] ?? []

        let rows = rowsData.compactMap { rowData -> RowResultData? in
            guard let index = rowData["index"] as? Int,
                let status = rowData["status"] as? String
            else {
                return nil
            }

            let value: AnyCodable? = {
                if let val = rowData["value"] {
                    return AnyCodable(val)
                }
                return nil
            }()

            let error = rowData["error"] as? String

            return RowResultData(
                index: index,
                value: value,
                error: error,
                status: status
            )
        }

        return RowSetData(
            stepId: stepId,
            field: field,
            count: count,
            rows: rows
        )
    }
}

// =============================================================================
// MARK: - Agent Session
// =============================================================================

/// Represents one agent execution session
@Observable
final class AgentSession: Identifiable {
    let id: UUID
    let query: String
    var contextArtifact: ContextArtifact?
    var executionPlan: ExecutionPlan?
    var stepOutputs: [String: OutputArtifact] = [:]
    var status: SessionStatus
    let timestamp: Date
    
    // ReAct loop state
    var currentThought: ThoughtData?  // Current action awaiting approval
    var trajectory: [TrajectoryEntry] = []  // Execution history
    var lastEvaluation: [String: Any]?  // Latest goal evaluation
    
    // Goal-by-goal execution state
    var currentGoalIndex: Int = 0  // Which goal is currently active
    var goals: [GoalInfo] = []  // List of goals with their states
    var expandedGoalId: String?  // Which goal is currently expanded in UI

    init(id: UUID = UUID(), query: String) {
        self.id = id
        self.query = query
        self.status = .planning
        self.timestamp = Date()
    }
}

/// Information about a single goal in the plan
@Observable
final class GoalInfo: Identifiable {
    let id: UUID
    let goalId: String  // G-0, G-1, etc.
    let description: String
    let pluginId: String
    var status: GoalExecutionStatus
    var steps: [GoalStepInfo] = []
    var requiredInputs: [ContextFieldInfo] = []
    var isExpanded: Bool = false
    
    init(id: UUID = UUID(), goalId: String, description: String, pluginId: String, status: GoalExecutionStatus = .pending) {
        self.id = id
        self.goalId = goalId
        self.description = description
        self.pluginId = pluginId
        self.status = status
    }
}

/// Status of a goal in execution
enum GoalExecutionStatus: String {
    case pending = "pending"
    case planningSteps = "planning_steps"
    case awaitingStart = "awaiting_start"  // Steps ready, waiting for "Start Execution"
    case executing = "executing"
    case completed = "completed"
    case failed = "failed"
}

/// Information about a step within a goal
@Observable
final class GoalStepInfo: Identifiable {
    let id: UUID
    let stepId: String
    let skillId: String
    let description: String
    var status: StepStatus
    var output: OutputArtifact?
    
    init(id: UUID = UUID(), stepId: String, skillId: String, description: String, status: StepStatus = .pending) {
        self.id = id
        self.stepId = stepId
        self.skillId = skillId
        self.description = description
        self.status = status
    }
}

/// Context field information for required inputs
struct ContextFieldInfo: Identifiable {
    let id: UUID
    let name: String
    let description: String
    let required: Bool
    let fieldType: String
    
    init(id: UUID = UUID(), name: String, description: String, required: Bool, fieldType: String) {
        self.id = id
        self.name = name
        self.description = description
        self.required = required
        self.fieldType = fieldType
    }
}

/// Thought/action proposed by the ReAct agent
struct ThoughtData {
    let reasoning: String
    let actionType: String  // execute_skill, finish, clarify
    let skillId: String?
    let params: [String: Any]
    let inputSources: [String: String]
    let planStepRef: String?  // Reference to plan step this corresponds to
}

/// Single entry in the execution trajectory
struct TrajectoryEntry {
    let iteration: Int
    let state: String
    let thought: ThoughtData
    let observation: ObservationData?
    let timestamp: Date
}

/// Observation from skill execution
struct ObservationData {
    let success: Bool
    let artifact: OutputArtifact?
    let error: String?
    let summary: String
}

enum SessionStatus: String, Codable {
    case planning
    case awaitingContext
    case awaitingApproval  // Waiting for goal plan approval
    case executing
    case running  // Goal execution loop is running
    case completed
    case failed
    case awaitingInput  // Waiting for user input (auth or step approval)
    case ready
    case clarifying
}

// =============================================================================
// MARK: - Context Artifact
// =============================================================================

/// Versioned, editable context artifact
@Observable
final class ContextArtifact {
    var version: Int
    var values: [String: ContextValue]
    var auth: [String: AuthEntry]

    init(version: Int = 1, values: [String: ContextValue] = [:], auth: [String: AuthEntry] = [:]) {
        self.version = version
        self.values = values
        self.auth = auth
    }

    convenience init(fields: [[String: Any]]) {
        var values: [String: ContextValue] = [:]
        for field in fields {
            if let name = field["name"] as? String {
                values[name] = ContextValue(
                    name: name,
                    description: field["description"] as? String ?? "",
                    value: "",
                    required: field["required"] as? Bool ?? false,
                    fieldType: ContextFieldType(
                        rawValue: field["field_type"] as? String ?? "string") ?? .string
                )
            }
        }
        self.init(version: 1, values: values, auth: [:])
    }

    func toJSON() -> [String: Any] {
        var valuesJSON: [String: Any] = [:]
        for (key, value) in values {
            valuesJSON[key] = [
                "name": value.name,
                "description": value.description,
                "value": value.value,
                "required": value.required,
                "field_type": value.fieldType.rawValue,
            ]
        }

        var authJSON: [String: Any] = [:]
        for (key, entry) in auth {
            authJSON[key] = [
                "strategy_used": entry.strategyUsed,
                "value": entry.value,
                "valid": entry.valid,
            ]
        }

        return [
            "version": version,
            "values": valuesJSON,
            "auth": authJSON,
        ]
    }
}

/// Context field value
@Observable
final class ContextValue {
    let name: String
    let description: String
    var value: String
    let required: Bool
    let fieldType: ContextFieldType

    init(
        name: String, description: String, value: String, required: Bool,
        fieldType: ContextFieldType
    ) {
        self.name = name
        self.description = description
        self.value = value
        self.required = required
        self.fieldType = fieldType
    }
}

enum ContextFieldType: String, Codable {
    case string
    case number
    case boolean
    case secret
}

/// Authentication entry
struct AuthEntry: Codable {
    let strategyUsed: String  // "token" or "user_password"
    var value: String
    var valid: Bool
}

// =============================================================================
// MARK: - Execution Plan
// =============================================================================

/// Execution plan with steps
@Observable
final class ExecutionPlan {
    let planId: String
    var steps: [AgentPlanStep]
    var status: String  // draft, approved, executing, completed, failed

    init(planId: String, steps: [AgentPlanStep], status: String = "draft") {
        self.planId = planId
        self.steps = steps
        self.status = status
    }
}

/// Single step in execution plan
@Observable
final class AgentPlanStep: Identifiable {
    let id: UUID
    let stepId: String
    let agentType: AgentType
    let pluginId: String?
    let skillId: String?
    let description: String?
    var status: StepStatus
    var outputArtifact: OutputArtifact?
    let isForeach: Bool
    let foreachSource: String?

    init(
        id: UUID = UUID(), stepId: String, agentType: AgentType, pluginId: String?,
        skillId: String?, description: String?, isForeach: Bool = false,
        foreachSource: String? = nil
    ) {
        self.id = id
        self.stepId = stepId
        self.agentType = agentType
        self.pluginId = pluginId
        self.skillId = skillId
        self.description = description
        self.status = .pending
        self.isForeach = isForeach
        self.foreachSource = foreachSource
    }
}

enum AgentType: String, Codable {
    case context
    case operation
    case planner
    case react
    case tool
}

enum StepStatus: String, Codable {
    case pending
    case running
    case completed
    case failed
}

// =============================================================================
// MARK: - Output Artifact
// =============================================================================

/// Typed artifact data based on output_artifact_type
enum ArtifactData {
    case text(TextArtifactData)
    case table(TableArtifactData)
    case list(ListArtifactData)
    case chart(ChartArtifactData)
}

struct TextArtifactData: Codable {
    let content: String
    let format: String
}

struct TableArtifactData: Codable {
    let columns: [TableColumnData]
    let rows: [[String]]
}

struct TableColumnData: Codable {
    let key: String
    let label: String
}

struct ListArtifactData: Codable {
    let items: [ListItemData]
}

struct ListItemData: Codable {
    let label: String
    let value: String?
}

struct ChartArtifactData: Codable {
    let chartType: String
    let labels: [String]
    let datasets: [ChartDatasetData]
    
    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case labels
        case datasets
    }
}

struct ChartDatasetData: Codable {
    let label: String
    let values: [Double]
}

/// Output artifact from an operation agent
struct OutputArtifact: Identifiable {
    let id: UUID
    let artifactId: String
    let type: String
    let artifactData: ArtifactData
    let timestamp: Date
    let rowSet: RowSetData?

    init(
        id: UUID = UUID(), artifactId: String, type: String, artifactData: ArtifactData,
        rowSet: RowSetData? = nil
    ) {
        self.id = id
        self.artifactId = artifactId
        self.type = type
        self.artifactData = artifactData
        self.timestamp = Date()
        self.rowSet = rowSet
    }
}

// =============================================================================
// MARK: - RowSet (Fan-Out Results)
// =============================================================================

/// RowSet data for foreach steps
struct RowSetData: Codable {
    let stepId: String
    let field: String
    let count: Int
    let rows: [RowResultData]
}

/// Single row result
struct RowResultData: Codable {
    let index: Int
    let value: AnyCodable?
    let error: String?
    let status: String
}

// =============================================================================
// MARK: - Session Status Response
// =============================================================================

/// Response from GET /goals/{session_id}/status
struct SessionStatusResponse {
    let sessionId: String
    let status: String?
    let query: String?
    let currentGoalIndex: Int
    let goals: [GoalStatusInfo]
}

/// Goal status information
struct GoalStatusInfo {
    let goalId: String
    let description: String
    let pluginId: String
    let status: String
    let retryCount: Int
    let stepsCount: Int
}
