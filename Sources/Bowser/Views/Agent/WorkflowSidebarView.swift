//
//  WorkflowSidebarView.swift
//  Bowser
//
//  Right sidebar for agent workflow: Inputs, Output, Code, Versions tabs.
//  Auto-switches to Inputs when a goal needs user input,
//  and to Output when execution completes.
//

import SwiftUI

// =============================================================================
// MARK: - Sidebar Tab
// =============================================================================

enum WorkflowSidebarTab: String, CaseIterable, Identifiable {
    case inputs = "Inputs"
    case output = "Output"
    case code = "Code"
    case versions = "Versions"
    
    var id: String { rawValue }
}

// =============================================================================
// MARK: - Workflow Sidebar View
// =============================================================================

struct WorkflowSidebarView: View {
    
    @Bindable var session: AgentSession
    @Bindable var browserState: BrowserState
    let agentState: AgentState
    @State private var selectedTab: WorkflowSidebarTab = .output
    
    private var awaitingGoal: GoalInfo? {
        session.goals.first(where: { $0.status == .awaitingStart })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(WorkflowSidebarTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            // Tab content
            switch selectedTab {
            case .inputs:
                inputsTabView
            case .output:
                outputTabView
            case .code:
                codeTabView
            case .versions:
                versionsTabView
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        // Auto-select Inputs tab when a goal awaits user input
        .onChange(of: awaitingGoal?.goalId) { _, newId in
            if newId != nil {
                withAnimation(ArcTheme.hoverAnimation) {
                    selectedTab = .inputs
                }
            }
        }
        // Auto-select Output tab when workflow completes
        .onChange(of: session.status) { _, newStatus in
            if newStatus == .completed {
                withAnimation(ArcTheme.hoverAnimation) {
                    selectedTab = .output
                }
            }
        }
    }
    
    // MARK: - Inputs Tab
    
    @ViewBuilder
    private var inputsTabView: some View {
        if let goal = awaitingGoal {
            ScrollView {
                WorkflowInputsSection(
                    goal: goal,
                    session: session,
                    agentState: agentState
                )
            }
        } else {
            emptyPlaceholder(
                icon: "checkmark.circle",
                message: "No inputs required"
            )
        }
    }
    
    // MARK: - Output Tab
    
    @ViewBuilder
    private var outputTabView: some View {
        if let selectedGoalId = session.selectedWorkflowNodeId,
           let goal = session.goals.first(where: { $0.goalId == selectedGoalId }) {
            selectedGoalOutputView(goal: goal)
        } else if session.status == .completed, let output = session.consolidatedOutput {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text("Final Output")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    AgentOutputView(
                        componentType: output.componentType,
                        componentData: output.componentData,
                        summary: output.summary,
                        compact: true,
                        browserState: browserState
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        } else {
            emptyPlaceholder(
                icon: "play.circle",
                message: "Run workflow to see output"
            )
        }
    }
    
    @ViewBuilder
    private func selectedGoalOutputView(goal: GoalInfo) -> some View {
        let stepsWithOutput = goal.steps.filter { $0.output != nil }
        
        if stepsWithOutput.isEmpty {
            if goal.status == .pending || goal.status == .planningSteps {
                emptyPlaceholder(icon: "clock", message: "This step hasn't run yet")
            } else if goal.status == .executing || goal.status == .awaitingStart {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text("Executing...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyPlaceholder(icon: "exclamationmark.triangle", message: "No output available")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "cube")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
                        Text(goal.description)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    ForEach(stepsWithOutput) { step in
                        if let artifact = step.output {
                            AgentStepOutputView(artifact: artifact, browserState: browserState)
                                .padding(.horizontal, 8)
                        }
                    }
                    
                    Spacer().frame(height: 12)
                }
            }
        }
    }
    
    // MARK: - Code Tab
    
    private var codeTabView: some View {
        ScrollView {
            let yaml = session.workflowYAML
            if yaml.isEmpty {
                emptyPlaceholder(icon: "doc.text", message: "Workflow code will appear after planning")
            } else {
                Text(yaml)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .padding(12)
            }
        }
    }
    
    // MARK: - Versions Tab
    
    private var versionsTabView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("v1 - Current")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text(formatTimestamp(session.timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(ArcTheme.activeTabBackground)
            )
            .padding(12)
            
            Spacer()
        }
    }
    
    // MARK: - Helpers
    
    private func emptyPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct WorkflowSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        let browserState = BrowserState()
        let session = AgentSession(query: "Fetch HN stories")
        session.goals = [
            GoalInfo(goalId: "G-0", description: "Fetch top stories", pluginId: "hackernews_fetch", status: .completed),
            GoalInfo(goalId: "G-1", description: "Summarize stories", pluginId: "llm_summarize", status: .pending),
        ]
        
        return WorkflowSidebarView(session: session, browserState: browserState, agentState: browserState.agentState)
            .frame(width: 320, height: 500)
    }
}
#endif
