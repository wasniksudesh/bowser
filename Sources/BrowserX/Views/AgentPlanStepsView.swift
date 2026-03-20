//
//  AgentPlanStepsView.swift
//  Bowser
//
//  Vertical step tracker for agent execution plan
//  Shows real-time status updates from ReAct loop via SSE events
//

import SwiftUI

// =============================================================================
// MARK: - Agent Plan Steps View
// =============================================================================

/// Vertical step tracker showing execution plan
/// Steps are executed automatically by the ReAct agent loop
struct AgentPlanStepsView: View {
    
    var plan: ExecutionPlan
    @Bindable var browserState: BrowserState
    var currentThought: ThoughtData?  // Pass current thought to highlight awaiting step
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Execution Plan")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
            
            // Steps
            VStack(spacing: 0) {
                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    PlanStepRowView(
                        step: step,
                        browserState: browserState,
                        stepNumber: index + 1,
                        isLast: index == plan.steps.count - 1,
                        isAwaitingApproval: currentThought?.planStepRef == step.stepId
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// =============================================================================
// MARK: - Step Row View
// =============================================================================

/// Individual step row in the execution plan
private struct PlanStepRowView: View {
    
    var step: AgentPlanStep
    @Bindable var browserState: BrowserState

    let stepNumber: Int
    let isLast: Bool
    let isAwaitingApproval: Bool  // Whether this step is awaiting user approval
    
    @State private var isHovering: Bool = false
    @State private var isOutputExpanded: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left side: connector line and status indicator
            VStack(spacing: 0) {
                // Status indicator
                ZStack {
                    Circle()
                        .stroke(statusBorderColor, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    statusIcon
                    
                    // Pulsing ring for awaiting approval
                    if isAwaitingApproval {
                        Circle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(width: 32, height: 32)
                            .opacity(0.6)
                            .scaleEffect(1.2)
                            .animation(
                                .easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                                value: isAwaitingApproval
                            )
                    }
                }
                
                // Connector line (if not last)
                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(minHeight: isOutputExpanded && step.outputArtifact != nil ? 80 : 40)
                }
            }
            
            // Right side: step content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Step info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            // Agent type badge
                            agentTypeBadge
                            
                            // Skill name
                            if let skillId = step.skillId {
                                Text(skillId)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                        }
                        
                        // Description
                        if let description = step.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    // Status badge
                    statusBadge
                }
                
                // Output section (if completed)
                if step.status == .completed, let artifact = step.outputArtifact {
                    outputSection(artifact: artifact)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Status Icon
    
    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:
            Text("\(stepNumber)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            
        case .running:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
            
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
        }
    }
    
    private var statusBorderColor: Color {
        switch step.status {
        case .pending:
            return .gray.opacity(0.5)
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    // MARK: - Agent Type Badge
    
    private var agentTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: agentTypeIcon)
                .font(.system(size: 10))
            
            Text(step.agentType.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlColor).opacity(0.3))
        )
    }
    
    // MARK: - Status Badge
    
    @ViewBuilder
    private var statusBadge: some View {
        if isAwaitingApproval {
            // Special badge for awaiting approval
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11))
                Text("Awaiting Approval")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.yellow)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.yellow.opacity(0.2))
            )
        } else {
            switch step.status {
            case .pending:
                Text("Pending")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                    )
            case .running:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text("Running")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                )
            case .completed:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.1))
                )
            case .failed:
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Failed")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.1))
                )
            }
        }
    }
    
    private var agentTypeIcon: String {
        switch step.agentType {
        case .react:
            return "brain"
        case .tool:
            return "gearshape.2"
        case .context:
            return "doc.text"
        case .operation:
            return "gearshape.2"
        case .planner:
            return "list.bullet.clipboard"
        }
    }
    
    // MARK: - Output Section
    
    @ViewBuilder
    private func outputSection(artifact: OutputArtifact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOutputExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isOutputExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    
                    Text("Output: \(artifact.type)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            
            // Expanded output content
            if isOutputExpanded {
                StepOutputContentView(artifact: artifact, browserState: browserState)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
    }
}

// =============================================================================
// MARK: - Step Output Content View
// =============================================================================

/// Renders the full output content for a step (used when expanded)
private struct StepOutputContentView: View {
    
    let artifact: OutputArtifact
    @Bindable var browserState: BrowserState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Output metadata
            HStack {
                Image(systemName: displayTypeIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                
                Text(artifact.type.capitalized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(formatTimestamp(artifact.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            
            // Content based on display type
            outputContent
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
        }
    }
    
    // MARK: - Output Content
    
    @ViewBuilder
    private var outputContent: some View {
        switch artifact.artifactData {
        case .text(let data):
            renderText(data: data)
            
        case .table(let data):
            renderTable(data: data)
            
        case .list(let data):
            renderList(data: data)
            
        case .chart(let data):
            renderChart(data: data)
        }
    }
    
    // MARK: - Renderers
    
    @ViewBuilder
    private func renderText(data: TextArtifactData) -> some View {
        let textData = TextBlockData(
            content: data.content,
            format: TextFormat(rawValue: data.format) ?? .plain
        )
        TextBlockComponent(data: textData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderTable(data: TableArtifactData) -> some View {
        let tableColumns = data.columns.map { col in
            TableColumn(key: col.key, label: col.label)
        }
        let tableData = TableData(columns: tableColumns, rows: data.rows)
        TableComponent(data: tableData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderList(data: ListArtifactData) -> some View {
        let listItems = data.items.map { item in
            ListItem(label: item.label, value: item.value)
        }
        let listData = ListData(items: listItems)
        ListComponent(data: listData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderChart(data: ChartArtifactData) -> some View {
        let chartDatasets = data.datasets.map { ds in
            ChartDataset(label: ds.label, values: ds.values)
        }
        let chartData = ChartData(
            chartType: ChartType(rawValue: data.chartType) ?? .bar,
            labels: data.labels,
            datasets: chartDatasets
        )
        ChartComponent(data: chartData, isLoading: false)
    }
    
    // MARK: - Helpers
    
    private var displayTypeIcon: String {
        switch artifact.artifactData {
        case .table:
            return "tablecells"
        case .chart:
            return "chart.bar"
        case .text:
            return "doc.text"
        case .list:
            return "list.bullet"
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentPlanStepsView_Previews: PreviewProvider {
    static var previews: some View {
        let browserState = BrowserState()
        let plan = ExecutionPlan(
            planId: "test-plan",
            steps: [
                AgentPlanStep(
                    stepId: "step-1",
                    agentType: .context,
                    pluginId: nil,
                    skillId: nil,
                    description: "Collect required context from user"
                ),
                AgentPlanStep(
                    stepId: "step-2",
                    agentType: .operation,
                    pluginId: "github",
                    skillId: "listCommits",
                    description: "Fetch last 5 commits from repository"
                ),
                AgentPlanStep(
                    stepId: "step-3",
                    agentType: .operation,
                    pluginId: "github",
                    skillId: "getCommitDiff",
                    description: "Get diff for each commit"
                )
            ]
        )
        
        plan.steps[0].status = .completed
        plan.steps[0].outputArtifact = OutputArtifact(
            artifactId: "artifact-1",
            type: "text",
            artifactData: .text(TextArtifactData(content: "Context collected successfully", format: "plain"))
        )
        
        return ScrollView {
            AgentPlanStepsView(plan: plan, browserState: browserState, currentThought: nil)
        }
        .frame(width: 600, height: 500)
    }
}
#endif
