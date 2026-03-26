//
//  AgentModeMainView.swift
//  Bowser
//
//  Main content view for Agent Mode
//  Displays query, context artifact, plan steps, and outputs
//

import SwiftUI

// =============================================================================
// MARK: - Agent Mode Main View
// =============================================================================

/// Main content area for Agent Mode
/// Shown in the detail pane when agent mode is active
struct AgentModeMainView: View {
    
    @Bindable var browserState: BrowserState
    
    private var agentState: AgentState {
        browserState.agentState
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
            if let session = agentState.currentSession {
                mainContentView(session: session)
            } else {
                emptyStateView
            }
            
            // Chat bar at bottom
            AgentChatBarView(browserState: browserState)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - Main Content View
    
    private func mainContentView(session: AgentSession) -> some View {
        let hasGoals = !session.goals.isEmpty
        let showWorkflowLayout = hasGoals && session.status != .planning
        
        return Group {
            if showWorkflowLayout {
                workflowLayoutView(session: session)
            } else {
                planningPhaseView(session: session)
            }
        }
    }
    
    // MARK: - Planning Phase (vertical scroll, before workflow is ready)
    
    private func planningPhaseView(session: AgentSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AgentQueryHeaderView(query: session.query, status: session.status)
                
                if session.status == .awaitingApproval, let plan = session.executionPlan {
                    GoalPlanApprovalView(
                        plan: plan,
                        onApprove: {
                            Task {
                                await agentState.approveGoalPlan(approved: true)
                            }
                        },
                        onReject: { feedback in
                            Task {
                                await agentState.approveGoalPlan(approved: false, feedback: feedback)
                            }
                        }
                    )
                }
                
                if session.status == .planning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Planning workflow...")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer().frame(height: 80)
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Workflow Layout (canvas + sidebar, after goals exist)
    
    private func workflowLayoutView(session: AgentSession) -> some View {
        VStack(spacing: 0) {
            // Compact top bar with query + status
            AgentQueryHeaderView(query: session.query, status: session.status)
                .padding(.bottom, 8)
            
            Divider()
            
            // Workflow canvas (left) + sidebar (right)
            // HSplitView renders a draggable divider between the two panes.
            // No idealWidth on either child — letting HSplitView own the split position.
            HSplitView {
                WorkflowCanvasWithRunButton(
                    session: session,
                    agentState: agentState
                )
                .frame(minWidth: 180, maxWidth: .infinity, maxHeight: .infinity)
                
                WorkflowSidebarView(session: session, browserState: browserState, agentState: agentState)
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            
            // Completion actions at bottom
            if session.status == .completed, let output = session.consolidatedOutput {
                Divider()
                completionActionsBar(output: output, session: session)
            }
            
            Spacer().frame(height: 70)
        }
    }
    
    // (Run button is now inside WorkflowCanvasWithRunButton)
    
    // MARK: - Completion Actions Bar
    
    private func completionActionsBar(output: ConsolidatedOutput, session: AgentSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
            
            Text("Workflow completed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            
            Text(output.componentType)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.1))
                )
            
            Spacer()
            
            WorkflowCompletionButtons(
                output: output,
                session: session,
                browserState: browserState
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
            
            VStack(spacing: 8) {
                Text("Agent Mode")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Execute tasks with AI agents")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Example queries:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                exampleQueryButton("List last 3 GitHub commits, get their diffs and summarize changes")
                exampleQueryButton("Analyze website performance metrics")
                exampleQueryButton("Fetch and compare API responses")
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Bottom padding for chat bar
            Spacer()
                .frame(height: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func exampleQueryButton(_ text: String) -> some View {
        Button(action: {
            Task {
                await agentState.submitQuery(text)
            }
        }) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlColor).opacity(0.3))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
}


// =============================================================================
// MARK: - Workflow Canvas with Run Button
// =============================================================================

/// Wraps WorkflowCanvasView in a bright-bordered box with inputs at the bottom
/// and a small "Run" button on the bottom boundary edge.
struct WorkflowCanvasWithRunButton: View {
    
    @Bindable var session: AgentSession
    let agentState: AgentState
    
    private var showRunButton: Bool {
        session.executionPlan != nil
            && session.status == .ready
            && !session.goals.contains(where: { $0.status == .awaitingStart })
    }
    
    private let runButtonHeight: CGFloat = 30
    
    private var canvasBorderShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 10,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            WorkflowCanvasView(session: session)
                .clipShape(canvasBorderShape)
                .overlay(
                    canvasBorderShape
                        .stroke(Color.blue.opacity(0.45), lineWidth: 1.5)
                )
                .padding(.leading, 16)
                .padding(.trailing, 0)
                .padding(.top, 12)
                .padding(.bottom, showRunButton ? runButtonHeight / 2 : 0)
            
            if showRunButton {
                Button(action: {
                    Task {
                        await agentState.runAgent()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Run")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue)
                    )
                    .frame(height: runButtonHeight)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// =============================================================================
// MARK: - Workflow Inputs Section
// =============================================================================

/// Auth tokens and required inputs bar shown above the workflow canvas
/// when a goal is awaiting start and needs user-provided values.
struct WorkflowInputsSection: View {
    
    @Bindable var goal: GoalInfo
    let session: AgentSession
    let agentState: AgentState
    @State private var inputValues: [String: String] = [:]
    
    private var hasAuthFields: Bool {
        guard let auth = session.contextArtifact?.auth else { return false }
        return !auth.isEmpty
    }
    
    private var allAuthFilled: Bool {
        guard let auth = session.contextArtifact?.auth else { return true }
        return !auth.values.contains { $0.value.isEmpty }
    }
    
    private var canStart: Bool {
        for field in goal.requiredInputs where field.required {
            if inputValues[field.name]?.isEmpty ?? true {
                return false
            }
        }
        if !allAuthFilled { return false }
        return true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                
                Text("Inputs Required")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(goal.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Auth inputs
            if hasAuthFields, let auth = session.contextArtifact?.auth {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(auth.keys.sorted()), id: \.self) { authId in
                        if let authEntry = auth[authId] {
                            HStack(spacing: 10) {
                                HStack(spacing: 4) {
                                    Text(authId.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                    
                                    if !authEntry.value.isEmpty {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.green)
                                    }
                                }
                                .frame(width: 140, alignment: .leading)
                                
                                SecureField("Enter \(authEntry.strategyUsed)", text: Binding(
                                    get: { session.contextArtifact?.auth[authId]?.value ?? "" },
                                    set: { newValue in
                                        session.contextArtifact?.auth[authId]?.value = newValue
                                        session.contextArtifact?.auth[authId]?.valid = !newValue.isEmpty
                                    }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                            }
                        }
                    }
                }
            }
            
            // Required field inputs
            if !goal.requiredInputs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parameters")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(goal.requiredInputs) { field in
                        HStack(spacing: 10) {
                            HStack(spacing: 2) {
                                Text(field.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.primary)
                                if field.required {
                                    Text("*")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.red)
                                }
                            }
                            .frame(width: 120, alignment: .leading)
                            
                            if field.fieldType == "secret" {
                                SecureField(field.description, text: Binding(
                                    get: { inputValues[field.name] ?? "" },
                                    set: { inputValues[field.name] = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                            } else {
                                TextField(field.description, text: Binding(
                                    get: { inputValues[field.name] ?? "" },
                                    set: { inputValues[field.name] = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                            }
                        }
                    }
                }
            }
            
            // Start button
            HStack {
                Spacer()
                
                Button(action: {
                    Task {
                        await agentState.startGoalExecution(
                            goalId: goal.goalId,
                            inputValues: inputValues.isEmpty ? nil : inputValues
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("Start Execution")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(canStart ? Color.green : Color.green.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// =============================================================================
// MARK: - Workflow Completion Buttons
// =============================================================================

/// Compact Schedule/Export buttons for the workflow completion bar
struct WorkflowCompletionButtons: View {
    
    let output: ConsolidatedOutput
    let session: AgentSession
    @Bindable var browserState: BrowserState
    @State private var exportStatus: String?
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { /* TODO: implement schedule sheet */ }) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Schedule")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            
            Button(action: { exportAsWidget() }) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.on.rectangle")
                    Text("Export Widget")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
            }
            .buttonStyle(.plain)
            
            if let status = exportStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func exportAsWidget() {
        Task {
            exportStatus = "Creating..."
            do {
                let url = URL(string: "http://localhost:8765/api/widgets/create")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                var goalPlanDict: [String: Any] = ["plan_id": session.id.uuidString, "goals": []]
                if let plan = session.executionPlan {
                    let goals = plan.steps.map { step -> [String: Any] in
                        [
                            "goal_id": step.id.uuidString,
                            "description": step.description ?? "",
                            "plugin_id": step.pluginId ?? "",
                            "status": "completed"
                        ]
                    }
                    goalPlanDict["goals"] = goals
                }
                
                let body: [String: Any] = [
                    "definition_id": session.id.uuidString,
                    "query": session.query,
                    "goal_plan": goalPlanDict,
                    "output_component_type": output.componentType,
                    "folder_id": browserState.currentFolderId?.uuidString ?? "",
                    "frequency": "daily"
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    exportStatus = "Failed"
                    return
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let widgetId = json?["widget_id"] as? String ?? ""
                
                let widgetInstance = HomescreenWidgetInstance(
                    widgetId: widgetId,
                    agentDefinitionId: session.id,
                    folderId: browserState.currentFolderId,
                    query: session.query,
                    outputComponentType: output.componentType
                )
                browserState.widgetManager.addWidget(widgetInstance)
                
                if let componentData = output.componentData {
                    browserState.widgetManager.updateCachedData(widgetId: widgetId, data: componentData)
                }
                
                withAnimation {
                    exportStatus = "Done!"
                }
            } catch {
                exportStatus = "Error"
            }
        }
    }
}

// =============================================================================
// MARK: - Goal Plan Approval View
// =============================================================================

/// View for approving or rejecting a goal plan
struct GoalPlanApprovalView: View {
    
    let plan: ExecutionPlan
    let onApprove: () -> Void
    let onReject: (String) -> Void
    
    @State private var showFeedbackField: Bool = false
    @State private var feedback: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal Plan Ready")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Review the proposed goals and approve to continue")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Goals list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        // Step number
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.blue))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let description = step.description {
                                Text(description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                            }
                            
                            if let pluginId = step.pluginId {
                                Text("Plugin: \(pluginId)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    )
                }
            }
            
            // Feedback field (shown when rejecting)
            if showFeedbackField {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provide feedback for plan revision:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField("e.g., Please be more specific about the repository", text: $feedback, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .lineLimit(3...6)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if showFeedbackField {
                    // Cancel feedback
                    Button(action: {
                        showFeedbackField = false
                        feedback = ""
                    }) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Submit feedback
                    Button(action: {
                        if !feedback.isEmpty {
                            onReject(feedback)
                            showFeedbackField = false
                            feedback = ""
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Revise Plan")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(feedback.isEmpty ? Color.orange.opacity(0.5) : Color.orange)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(feedback.isEmpty)
                } else {
                    // Reject button
                    Button(action: {
                        showFeedbackField = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle")
                            Text("Reject")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Approve button
                    Button(action: onApprove) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Approve Plan")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

// =============================================================================
// MARK: - Agent Query Header View
// =============================================================================

/// Displays the user's query at the top
struct AgentQueryHeaderView: View {
    
    let query: String
    let status: SessionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Query")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Status indicator
                statusBadge
            }
            
            Text(query)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            statusIcon
            
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor.opacity(0.15))
        )
    }
    
    private var statusIcon: some View {
        Group {
            switch status {
            case .planning:
                Image(systemName: "brain")
            case .awaitingContext:
                Image(systemName: "doc.text")
            case .awaitingApproval:
                Image(systemName: "hand.thumbsup")
            case .executing:
                Image(systemName: "pause.circle")
            case .running:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            case .awaitingInput:
                Image(systemName: "hand.raised")
            case .ready:
                Image(systemName: "checkmark.circle")
            case .clarifying:
                Image(systemName: "bubble.left")
            }
        }
        .font(.system(size: 11))
    }
    
    private var statusText: String {
        switch status {
        case .planning:
            return "Planning"
        case .awaitingContext, .awaitingInput:
            return "Awaiting Input"
        case .awaitingApproval:
            return "Awaiting Approval"
        case .executing:
            return "Ready"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .ready:
            return "Ready"
        case .clarifying:
            return "Clarifying"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .planning:
            return .blue
        case .awaitingContext, .awaitingInput:
            return .orange
        case .awaitingApproval:
            return .orange
        case .executing:
            return .purple
        case .running:
            return .cyan
        case .completed:
            return .green
        case .failed:
            return .red
        case .ready:
            return .green
        case .clarifying:
            return .yellow
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentModeMainView_Previews: PreviewProvider {
    static var previews: some View {
        let browserState = BrowserState()
        
        // Create mock session
        let session = AgentSession(query: "List last 5 GitHub commits and summarize changes")
        session.contextArtifact = ContextArtifact(
            version: 1,
            values: [
                "repo": ContextValue(
                    name: "repo",
                    description: "GitHub repository",
                    value: "octocat/hello-world",
                    required: true,
                    fieldType: .string
                ),
                "limit": ContextValue(
                    name: "limit",
                    description: "Number of commits",
                    value: "5",
                    required: false,
                    fieldType: .number
                )
            ],
            auth: [:]
        )
        
        browserState.agentState.currentSession = session
        
        return AgentModeMainView(browserState: browserState)
            .frame(width: 800, height: 600)
    }
}
#endif
