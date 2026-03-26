//
//  WorkflowCanvasView.swift
//  Bowser
//
//  Visual node graph for agent workflow execution.
//  Displays goals as connected nodes with status indicators.
//  Read-only: click to select/deselect and view output in sidebar.
//

import SwiftUI

// =============================================================================
// MARK: - Workflow Canvas View
// =============================================================================

struct WorkflowCanvasView: View {
    
    @Bindable var session: AgentSession
    
    private let nodeWidth: CGFloat = 240
    private let nodeSpacing: CGFloat = 16
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
    
    let goal: GoalInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    private let nodeWidth: CGFloat = 240
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                pluginIcon
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.pluginId)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text(goal.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer(minLength: 4)
                
                statusIndicator
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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
// MARK: - Preview
// =============================================================================

#if DEBUG
struct WorkflowCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        let session = AgentSession(query: "Fetch HN top stories and summarize")
        session.goals = [
            GoalInfo(goalId: "G-0", description: "Fetch top 10 stories from Hacker News", pluginId: "hackernews_fetch", status: .completed),
            GoalInfo(goalId: "G-1", description: "Summarize each story", pluginId: "llm_summarize", status: .executing),
            GoalInfo(goalId: "G-2", description: "Format output as table", pluginId: "transform_table", status: .pending),
        ]
        session.selectedWorkflowNodeId = "G-0"
        
        return WorkflowCanvasView(session: session)
            .frame(width: 500, height: 500)
    }
}
#endif
