//
//  WorkflowCanvasView.swift
//  Bowser
//
//  Visual node graph for agent workflow execution.
//  Displays goals as connected nodes with status indicators.
//  Tap to select (drives sidebar output). Double-tap to expand/collapse steps.
//

import SwiftUI

// =============================================================================
// MARK: - Workflow Canvas View
// =============================================================================

struct WorkflowCanvasView: View {
    
    @Bindable var session: AgentSession
    
    private let nodeWidth: CGFloat = 260
    private let connectorHeight: CGFloat = 32
    
    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(spacing: 0) {
                ForEach(Array(session.goals.enumerated()), id: \.element.id) { index, goal in
                    VStack(spacing: 0) {
                        if index > 0 {
                            connectorLine
                        }
                        
                        WorkflowNodeView(
                            goal: goal,
                            isSelected: session.selectedWorkflowNodeId == goal.goalId,
                            onTap: {
                                withAnimation(ArcTheme.springAnimation) {
                                    if session.selectedWorkflowNodeId == goal.goalId {
                                        session.selectedWorkflowNodeId = nil
                                    } else {
                                        session.selectedWorkflowNodeId = goal.goalId
                                    }
                                }
                            },
                            onExpandToggle: {
                                withAnimation(ArcTheme.springAnimation) {
                                    goal.isExpanded.toggle()
                                }
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Connector Line
    
    private var connectorLine: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 2, height: connectorHeight - 8)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.4))
        }
    }
}

// =============================================================================
// MARK: - Workflow Node View
// =============================================================================

struct WorkflowNodeView: View {
    
    @Bindable var goal: GoalInfo
    let isSelected: Bool
    let onTap: () -> Void
    let onExpandToggle: () -> Void
    
    @State private var isHovering = false
    
    private let nodeWidth: CGFloat = 260
    
    var body: some View {
        VStack(spacing: 0) {
            // Main node header
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        pluginIcon
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(goal.pluginId)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                
                                if goal.isForeach {
                                    foreachBadge
                                }
                            }
                            
                            Text(goal.description)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        
                        Spacer(minLength: 4)
                        
                        VStack(spacing: 4) {
                            statusIndicator
                            
                            if !goal.steps.isEmpty {
                                expandChevron
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    
                    // Inline error bar for failed goals
                    if goal.status == .failed, let errorMsg = goal.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text(errorMsg)
                                .font(.system(size: 11))
                                .lineLimit(2)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .padding(.top, 2)
                    }
                }
                .frame(width: nodeWidth, alignment: .leading)
                .background(nodeBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(ArcTheme.hoverAnimation) {
                    isHovering = hovering
                }
            }
            
            // Expanded step list
            if goal.isExpanded && !goal.steps.isEmpty {
                expandedStepsView
            }
        }
    }
    
    // MARK: - Foreach Badge
    
    private var foreachBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "repeat")
                .font(.system(size: 8, weight: .bold))
            Text("each")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.purple)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.purple.opacity(0.12))
        )
        .help(goal.foreachSource.map { "Iterates over: \($0)" } ?? "Fan-out step")
    }
    
    // MARK: - Expand Chevron
    
    private var expandChevron: some View {
        Button(action: onExpandToggle) {
            Image(systemName: goal.isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Expanded Steps
    
    private var expandedStepsView: some View {
        VStack(spacing: 0) {
            // Connecting line from node to steps container
            Rectangle()
                .fill(borderColor.opacity(0.4))
                .frame(width: 1, height: 6)
            
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(goal.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepRow(step: step)
                    
                    if index < goal.steps.count - 1 {
                        Divider()
                            .padding(.leading, 30)
                    }
                }
            }
            .frame(width: nodeWidth - 16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Plugin Icon
    
    private var pluginIcon: some View {
        let iconName = iconForPlugin(goal.pluginId)
        return Image(systemName: iconName)
            .font(.system(size: 16))
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(iconColor.opacity(0.12))
            )
    }
    
    private var iconColor: Color {
        switch goal.status {
        case .completed: return .green
        case .failed: return .red
        case .executing, .planningSteps: return .cyan
        case .awaitingStart: return .orange
        case .pending: return .secondary
        }
    }
    
    private func iconForPlugin(_ pluginId: String) -> String {
        let lower = pluginId.lowercased()
        if lower.contains("github") { return "chevron.left.forwardslash.chevron.right" }
        if lower.contains("http") || lower.contains("fetch") || lower.contains("api") { return "globe" }
        if lower.contains("hacker") || lower.contains("news") { return "newspaper" }
        if lower.contains("slack") || lower.contains("message") { return "bubble.left" }
        if lower.contains("email") || lower.contains("mail") { return "envelope" }
        if lower.contains("db") || lower.contains("database") || lower.contains("sql") { return "cylinder" }
        if lower.contains("file") || lower.contains("pdf") || lower.contains("doc") { return "doc" }
        if lower.contains("summarize") || lower.contains("llm") || lower.contains("ai") { return "brain" }
        if lower.contains("chart") || lower.contains("analyz") { return "chart.bar" }
        if lower.contains("search") { return "magnifyingglass" }
        if lower.contains("transform") || lower.contains("convert") { return "arrow.triangle.2.circlepath" }
        return "gearshape"
    }
    
    // MARK: - Status Indicator
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch goal.status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.5))
        case .planningSteps, .executing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .awaitingStart:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }
    
    // MARK: - Styling
    
    private var nodeBackground: some View {
        Group {
            switch goal.status {
            case .completed:
                Color.green.opacity(0.06)
            case .failed:
                Color.red.opacity(0.06)
            case .executing, .planningSteps:
                Color.cyan.opacity(0.08)
            case .awaitingStart:
                Color.orange.opacity(0.06)
            case .pending:
                Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.5 : 0.3)
            }
        }
    }
    
    private var borderColor: Color {
        if isSelected {
            return Color.blue.opacity(0.9)
        }
        if isHovering {
            return Color.blue.opacity(0.6)
        }
        return Color.blue.opacity(0.4)
    }
}

// =============================================================================
// MARK: - Workflow Step Row
// =============================================================================

struct WorkflowStepRow: View {
    
    let step: GoalStepInfo
    
    var body: some View {
        HStack(spacing: 8) {
            stepStatusIcon
            
            VStack(alignment: .leading, spacing: 1) {
                Text(step.skillId)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                Text(step.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 2)
            
            if step.output != nil {
                Image(systemName: "eye.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
    
    @ViewBuilder
    private var stepStatusIcon: some View {
        switch step.status {
        case .pending:
            Circle()
                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 10, height: 10)
        case .running:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
                .frame(width: 10, height: 10)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct WorkflowCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        let session = AgentSession(query: "Fetch HN top stories and summarize")
        let g0 = GoalInfo(goalId: "G-0", description: "Fetch top 10 stories from Hacker News", pluginId: "hackernews_fetch", status: .completed)
        g0.steps = [
            GoalStepInfo(stepId: "S-0", skillId: "fetchStories", description: "Fetch top stories from HN API", status: .completed),
            GoalStepInfo(stepId: "S-1", skillId: "parseStories", description: "Parse story metadata", status: .completed),
        ]
        g0.isExpanded = true
        
        let g1 = GoalInfo(goalId: "G-1", description: "Summarize each story", pluginId: "llm_summarize", status: .executing, isForeach: true, foreachSource: "G-0.stories")
        g1.steps = [
            GoalStepInfo(stepId: "S-2", skillId: "summarize", description: "Generate summary for each story", status: .running),
        ]
        
        let g2 = GoalInfo(goalId: "G-2", description: "Format output as table", pluginId: "transform_table", status: .failed)
        g2.errorMessage = "Transformation failed: missing required field 'title'"
        
        session.goals = [g0, g1, g2]
        session.selectedWorkflowNodeId = "G-0"
        
        return WorkflowCanvasView(session: session)
            .frame(width: 500, height: 600)
    }
}
#endif
