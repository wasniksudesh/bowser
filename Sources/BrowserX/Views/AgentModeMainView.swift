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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Query Header
                AgentQueryHeaderView(query: session.query, status: session.status)
                
                // Goal Plan Approval (when awaiting approval)
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
                
                // Run Agent Button (shown after plan approval to start the execution loop)
                // This button starts the backend loop which will then emit goal events
                if session.executionPlan != nil &&
                   session.status == .ready {
                    Button(action: {
                        Task {
                            await agentState.runAgent()
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Start Agent Execution")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                
                // Goal-by-Goal Execution View
                // Show ONLY after execution has started (status is .running or later)
                if !session.goals.isEmpty && 
                   (session.status == .running || 
                    session.status == .awaitingInput ||
                    session.status == .completed ||
                    session.status == .failed) {
                    GoalExecutionView(session: session, agentState: agentState)
                }
                
                // Bottom padding for chat bar
                Spacer()
                    .frame(height: 80)
            }
            .padding(.top, 20)
        }
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
    
    // MARK: - Running Indicator
    
    private var runningIndicatorView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent is thinking...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                Text("Listening for events from ReAct loop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.cyan.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
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
