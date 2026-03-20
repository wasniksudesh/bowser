//
//  PlanModeView.swift
//  Bowser
//
//  Main view for Plan Mode with intent input
//

import SwiftUI

// =============================================================================
// MARK: - Plan Mode View
// =============================================================================

/// Main view for Plan Mode
/// Phase 2: Shows intent input field
/// Future phases will add clarification, plan tree, etc.
struct PlanModeView: View {

    @Bindable var browserState: BrowserState

    // Use the shared planState from browserState
    private var planState: PlanState {
        browserState.planState
    }

    var body: some View {
        VStack(spacing: 0) {
            if planState.currentPlanId == nil {
                // Show plan list (default view
                // Show plan list (default view
                PlanListView(planState: browserState.planState)
            } else if !planState.hasSubmittedIntent {
                // Intent input phase
                intentInputView
            } else if planState.selectedLeafNode != nil {
                // Phase 6: Leaf Execution View
                LeafExecutionView(planState: browserState.planState, browserState: browserState)
            } else if planState.planRoot != nil {
                // Plan view (Phase 4)
                PlanTreeView(planState: browserState.planState)
            } else if !planState.clarificationQuestions.isEmpty || planState.isLoading {
                // Clarification phase
                ClarificationView(planState: browserState.planState)
            } else {
                // Loading initial questions
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Intent Input View

    private var intentInputView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue.gradient)
                .padding(.bottom, 8)

            // Title
            Text("What do you want to plan?")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Examples
            VStack(alignment: .leading, spacing: 8) {
                Text("Examples:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                exampleButton("Prepare for Google interviews")
                exampleButton("Learn competitive programming")
                exampleButton("Plan a 10-day Japan trip")
                exampleButton("Start swimming classes")
            }
            .padding(.horizontal, 16)

            // Intent input field
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    "Enter your intent...", text: $browserState.planState.intent, axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .lineLimit(3...6)
                .onSubmit {
                    planState.submitIntent()
                }

                // Error message
                if let error = planState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)

            // Submit button
            Button(action: {
                planState.submitIntent()
            }) {
                HStack {
                    Text("Start Planning")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    planState.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.gray
                        : Color.blue
                )
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(planState.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.vertical, 32)
    }

    // MARK: - Example Button

    private func exampleButton(_ text: String) -> some View {
        Button(action: {
            planState.intent = text
        }) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlColor).opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Placeholder Next Phase

    private var placeholderNextPhase: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Intent Submitted")
                .font(.title3)
                .fontWeight(.semibold)

            Text("\"(planState.intent)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("Phase 3 will add clarification questions here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

            // Reset button
            Button("Start Over") {
                planState.reset()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.vertical, 32)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct PlanModeView_Previews: PreviewProvider {
        static var previews: some View {
            PlanModeView(browserState: BrowserState())
                .frame(width: 280, height: 600)
        }
    }
#endif
