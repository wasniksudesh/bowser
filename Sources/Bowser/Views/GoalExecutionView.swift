//
//  GoalExecutionView.swift
//  Bowser
//
//  View for displaying goals in collapsible sections with step-by-step execution
//

import SwiftUI

// =============================================================================
// MARK: - Goal Execution View
// =============================================================================

/// Main view for displaying goals with collapsible sections
struct GoalExecutionView: View {
    
    let session: AgentSession
    let agentState: AgentState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Display all goals
            ForEach(Array(session.goals.enumerated()), id: \.element.id) { index, goal in
                GoalCardView(
                    goal: goal,
                    goalIndex: index,
                    isCurrentGoal: index == session.currentGoalIndex,
                    session: session,
                    agentState: agentState
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

// =============================================================================
// MARK: - Goal Card View
// =============================================================================

/// Collapsible card for a single goal
struct GoalCardView: View {
    
    @Bindable var goal: GoalInfo
    let goalIndex: Int
    let isCurrentGoal: Bool
    let session: AgentSession
    let agentState: AgentState
    
    @State private var inputValues: [String: String] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Goal Header (always visible)
            goalHeaderView
            
            // Expandable content (steps and outputs)
            if goal.isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Pending state message
                    if goal.status == .pending {
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("Waiting for previous goals to complete...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    
                    // Planning steps indicator
                    if goal.status == .planningSteps {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Planning steps for this goal...")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    
                    // Auth inputs (if needed and not yet provided)
                    if goal.status == .awaitingStart && needsAuthInput {
                        authInputsView
                    }
                    
                    // Required inputs (if any)
                    if !goal.requiredInputs.isEmpty && goal.status == .awaitingStart {
                        requiredInputsView
                    }
                    
                    // Steps list
                    if !goal.steps.isEmpty {
                        stepsListView
                    }
                    
                    // Start Execution button
                    if goal.status == .awaitingStart {
                        startExecutionButton
                    }
                    
                    // Executing indicator
                    if goal.status == .executing {
                        executingIndicatorView
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardBorderColor, lineWidth: 1.5)
                )
        )
        .onTapGesture {
            // Toggle expansion
            withAnimation(.easeInOut(duration: 0.2)) {
                goal.isExpanded.toggle()
            }
        }
    }
    
    // MARK: - Goal Header
    
    private var goalHeaderView: some View {
        HStack(alignment: .top, spacing: 12) {
            // Goal number badge
            Text("\(goalIndex + 1)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(goalBadgeColor))
            
            VStack(alignment: .leading, spacing: 6) {
                // Goal description
                Text(goal.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                
                // Plugin and status
                HStack(spacing: 8) {
                    Text("Plugin: \(goal.pluginId)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    goalStatusBadge
                }
            }
            
            Spacer()
            
            // Expand/collapse indicator
            Image(systemName: goal.isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(goal.isExpanded ? 0 : 0))
        }
        .padding(16)
        .contentShape(Rectangle())
    }
    
    private var goalStatusBadge: some View {
        HStack(spacing: 4) {
            statusIcon
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
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
            switch goal.status {
            case .pending:
                Image(systemName: "circle")
            case .planningSteps:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            case .awaitingStart:
                Image(systemName: "hand.raised.fill")
            case .executing:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            }
        }
        .font(.system(size: 10))
    }
    
    private var statusText: String {
        switch goal.status {
        case .pending:
            return "Pending"
        case .planningSteps:
            return "Planning..."
        case .awaitingStart:
            return "Ready"
        case .executing:
            return "Executing"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch goal.status {
        case .pending:
            return .gray
        case .planningSteps:
            return .blue
        case .awaitingStart:
            return .orange
        case .executing:
            return .purple
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var goalBadgeColor: Color {
        switch goal.status {
        case .pending:
            return .gray
        case .planningSteps, .awaitingStart:
            return .blue
        case .executing:
            return .purple
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var cardBackgroundColor: Color {
        if isCurrentGoal {
            return Color.blue.opacity(0.03)
        } else if goal.status == .completed {
            return Color.green.opacity(0.02)
        } else {
            return Color(nsColor: .controlBackgroundColor).opacity(0.3)
        }
    }
    
    private var cardBorderColor: Color {
        if isCurrentGoal {
            return Color.blue.opacity(0.4)
        } else if goal.status == .completed {
            return Color.green.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
    
    // MARK: - Required Inputs
    
    private var requiredInputsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Required Inputs:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            
            ForEach(goal.requiredInputs) { field in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        
                        if field.required {
                            Text("*")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Text(field.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    
                    if field.fieldType == "secret" {
                        SecureField("Enter \(field.name)", text: Binding(
                            get: { inputValues[field.name] ?? "" },
                            set: { inputValues[field.name] = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                    } else {
                        TextField("Enter \(field.name)", text: Binding(
                            get: { inputValues[field.name] ?? "" },
                            set: { inputValues[field.name] = $0 }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Auth Inputs (if needed)
    
    private var needsAuthInput: Bool {
        guard let auth = session.contextArtifact?.auth else { return false }
        return auth.values.contains { $0.value.isEmpty }
    }
    
    @ViewBuilder
    private var authInputsView: some View {
        if let auth = session.contextArtifact?.auth, needsAuthInput {
            VStack(alignment: .leading, spacing: 12) {
                Text("Authentication Required:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                
                ForEach(Array(auth.keys.sorted()), id: \.self) { authId in
                    if let authEntry = auth[authId], authEntry.value.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(authId.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                            
                            SecureField("Enter \(authEntry.strategyUsed)", text: Binding(
                                get: { session.contextArtifact?.auth[authId]?.value ?? "" },
                                set: { newValue in
                                    session.contextArtifact?.auth[authId]?.value = newValue
                                    session.contextArtifact?.auth[authId]?.valid = !newValue.isEmpty
                                }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    // MARK: - Steps List
    
    private var stepsListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            
            ForEach(Array(goal.steps.enumerated()), id: \.element.id) { stepIndex, step in
                StepRowView(step: step, stepIndex: stepIndex)
            }
        }
    }
    
    // MARK: - Start Execution Button
    
    private var startExecutionButton: some View {
        Button(action: {
            Task {
                await agentState.startGoalExecution(goalId: goal.goalId, inputValues: inputValues)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14))
                Text("Start Execution")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(canStartExecution ? Color.green : Color.green.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canStartExecution)
        .padding(.horizontal, 16)
    }
    
    private var canStartExecution: Bool {
        // Check if all required inputs are filled
        for field in goal.requiredInputs where field.required {
            if inputValues[field.name]?.isEmpty ?? true {
                return false
            }
        }
        // Check if auth is provided (if needed)
        if needsAuthInput {
            return false
        }
        return true
    }
    
    // MARK: - Executing Indicator
    
    private var executingIndicatorView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            
            Text("Executing steps...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }
}

// =============================================================================
// MARK: - Step Row View
// =============================================================================

/// View for a single step within a goal
struct StepRowView: View {
    
    @Bindable var step: GoalStepInfo
    let stepIndex: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // Step number
                Text("\(stepIndex + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(stepBadgeColor))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 8) {
                        Text("Skill: \(step.skillId)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        
                        stepStatusBadge
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(stepBackgroundColor)
            )
            
            // Step output (if available and step is completed)
            if step.status == .completed, let output = step.output {
                StepOutputView(output: output)
                    .padding(.leading, 46)
                    .padding(.trailing, 16)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var stepBadgeColor: Color {
        switch step.status {
        case .pending:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var stepBackgroundColor: Color {
        switch step.status {
        case .pending:
            return Color(nsColor: .controlBackgroundColor).opacity(0.2)
        case .running:
            return Color.blue.opacity(0.05)
        case .completed:
            return Color.green.opacity(0.05)
        case .failed:
            return Color.red.opacity(0.05)
        }
    }
    
    private var stepStatusBadge: some View {
        HStack(spacing: 3) {
            statusIcon
            Text(statusText)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(statusColor.opacity(0.15))
        )
    }
    
    private var statusIcon: some View {
        Group {
            switch step.status {
            case .pending:
                Image(systemName: "circle")
            case .running:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            }
        }
        .font(.system(size: 9))
    }
    
    private var statusText: String {
        switch step.status {
        case .pending:
            return "Pending"
        case .running:
            return "Running"
        case .completed:
            return "Done"
        case .failed:
            return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch step.status {
        case .pending:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}

// =============================================================================
// MARK: - Step Output View
// =============================================================================

/// View for displaying step output artifact
struct StepOutputView: View {
    
    let output: OutputArtifact
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            
            // Render based on artifact type
            switch output.artifactData {
            case .text(let textData):
                textOutputView(textData)
            case .table(let tableData):
                tableOutputView(tableData)
            case .list(let listData):
                listOutputView(listData)
            case .chart:
                Text("Chart output")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
        )
    }
    
    private func textOutputView(_ textData: TextArtifactData) -> some View {
        Text(textData.content)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(10)
    }
    
    private func tableOutputView(_ tableData: TableArtifactData) -> some View {
        let colWidth: CGFloat = 180
        
        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Table header
                HStack(spacing: 0) {
                    ForEach(tableData.columns, id: \.key) { column in
                        Text(column.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: colWidth, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                
                Divider()
                
                // All table rows — no limit
                ForEach(Array(tableData.rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell)
                                .font(.system(size: 10))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: colWidth, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                    }
                    .background(rowIdx % 2 == 0 ? Color.clear : Color(nsColor: .controlColor).opacity(0.05))
                    
                    if rowIdx < tableData.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }
    
    private func listOutputView(_ listData: ListArtifactData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(listData.items.prefix(5).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        
                        if let value = item.value {
                            Text(value)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            if listData.items.count > 5 {
                Text("... and \(listData.items.count - 5) more items")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
    }
}
