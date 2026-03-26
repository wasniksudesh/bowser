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
        let currentVersionNumber = session.planVersions.count + 1
        
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // Current (active) version
                versionRow(
                    label: "v\(currentVersionNumber) - Current",
                    timestamp: session.planVersions.last?.timestamp ?? session.timestamp,
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    goalCount: session.goals.count,
                    isActive: true
                )
                
                // Past versions (newest first)
                ForEach(session.planVersions.reversed()) { version in
                    versionRow(
                        label: "v\(version.versionNumber)",
                        timestamp: version.timestamp,
                        icon: version.outcome == .rejected ? "xmark.circle.fill" : "arrow.triangle.2.circlepath",
                        iconColor: version.outcome == .rejected ? .red : .secondary,
                        goalCount: version.goalDescriptions.count,
                        isActive: false,
                        outcome: version.outcome
                    )
                }
                
                Spacer()
            }
            .padding(12)
        }
    }
    
    private func versionRow(label: String, timestamp: Date, icon: String, iconColor: Color, goalCount: Int, isActive: Bool, outcome: PlanVersionOutcome? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? .primary : .secondary)
                    
                    if let outcome = outcome {
                        Text(outcome.rawValue.capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(outcome == .rejected ? .red : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill((outcome == .rejected ? Color.red : Color.secondary).opacity(0.1))
                            )
                    }
                }
                
                HStack(spacing: 8) {
                    Text(formatTimestamp(timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    Text("\(goalCount) goals")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? ArcTheme.activeTabBackground : Color.clear)
        )
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
