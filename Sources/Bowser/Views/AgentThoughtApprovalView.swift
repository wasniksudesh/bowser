//
//  AgentThoughtApprovalView.swift
//  Bowser
//
//  View for approving/rejecting ReAct agent proposed actions
//

import SwiftUI

// =============================================================================
// MARK: - Agent Thought Approval View
// =============================================================================

/// View showing a proposed action awaiting user approval
struct AgentThoughtApprovalView: View {
    
    let thought: ThoughtData
    let onApprove: () -> Void
    let onReject: (String?) -> Void
    
    @State private var showFeedbackField: Bool = false
    @State private var feedbackText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            thoughtCard
        }
    }
    
    private var headerSection: some View {
        HStack {
            Image(systemName: thought.actionType == "clarify" ? "bubble.left.fill" : "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(thought.actionType == "clarify" ? .blue : .yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(thought.actionType == "clarify" ? "Additional Input Needed" : "Action Awaiting Approval")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if thought.actionType == "clarify" {
                    Text("Fill in the requested fields above and click Save Context")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let planStepRef = thought.planStepRef {
                    Text("Step: \(planStepRef)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private var thoughtCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            reasoningSection
            Divider()
            actionDetailsSection
            if showFeedbackField {
                feedbackSection
            }
            Divider()
            actionButtonsSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reasoning")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Text(thought.reasoning)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
    
    private var actionDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Action Type:")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Text(thought.actionType)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
            }
            if let skillId = thought.skillId {
                HStack {
                    Text("Skill:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(skillId)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.purple.opacity(0.1))
                        )
                }
            }
            if !thought.params.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parameters:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    ForEach(thought.params.keys.sorted(), id: \.self) { key in
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("\(key):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(describing: thought.params[key] ?? ""))")
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }
    
    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Feedback (optional)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            TextField("Explain why you're rejecting this action...", text: $feedbackText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .lineLimit(3...6)
        }
    }
    
    private var actionButtonsSection: some View {
        Group {
            if thought.actionType == "clarify" {
                Text("Use the Save Context button above to submit your response.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                approvalButtons
            }
        }
    }
    
    private var approvalButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                if showFeedbackField {
                    onReject(feedbackText.isEmpty ? nil : feedbackText)
                    showFeedbackField = false
                    feedbackText = ""
                } else {
                    showFeedbackField = true
                }
            }) {
                HStack {
                    Image(systemName: showFeedbackField ? "paperplane.fill" : "xmark.circle")
                    Text(showFeedbackField ? "Submit Rejection" : "Reject")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(showFeedbackField ? .white : .red)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(showFeedbackField ? Color.red : Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            if showFeedbackField {
                Button(action: {
                    showFeedbackField = false
                    feedbackText = ""
                }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            if !showFeedbackField {
                Button(action: onApprove) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Approve")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentThoughtApprovalView_Previews: PreviewProvider {
    static var previews: some View {
        let thought = ThoughtData(
            reasoning: "The user wants to list the last 5 commits. I need to use the listCommits skill with the repository parameter from context.",
            actionType: "execute_skill",
            skillId: "listCommits",
            params: [
                "repo": "octocat/hello-world",
                "limit": 5
            ],
            inputSources: [
                "repo": "user_values.repo"
            ],
            planStepRef: "step-1"
        )
        
        return AgentThoughtApprovalView(
            thought: thought,
            onApprove: {
                print("Approved")
            },
            onReject: { feedback in
                print("Rejected with feedback: \(feedback ?? "none")")
            }
        )
        .frame(width: 600)
        .padding()
    }
}
#endif
