//
//  ClarificationView.swift
//  Bowser
//
//  Clarification questions view for Plan Mode
//

import SwiftUI

// =============================================================================
// MARK: - Clarification View
// =============================================================================

/// Shows one clarification question at a time with MCQ options
/// Auto-advances when user selects option(s)
/// LLM decides when to stop asking questions and move to plan generation
struct ClarificationView: View {

  @Bindable var planState: PlanState

  /// Current question index
  @State private var currentQuestionIndex: Int = 0

  /// Selected options for current question
  @State private var selectedOptions: Set<UUID> = []

  var body: some View {
    VStack(spacing: 0) {

      // Check for initial loading state (before questions are generated)
      if planState.isLoading && planState.clarificationQuestions.isEmpty {
        // Loading initial questions
        VStack(spacing: 16) {
          Spacer()
          ProgressView()
            .scaleEffect(1.2)
          Text("Analyzing your intent...")
            .font(.headline)
          Text("Generating clarification questions")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
        }
      }
      // Check if we have active questions to show
      else if currentQuestionIndex < planState.clarificationQuestions.count {
        // Show current question
        currentQuestionView
      }
      // All questions answered
      else {
        // Move to plan generation
        generatingPlanView
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
  }

  // MARK: - Current Question View

  private var currentQuestionView: some View {
    // Safe access (though logic guarantees index is valid)
    let question = planState.clarificationQuestions[currentQuestionIndex]

    return ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // Progress indicator
        HStack(spacing: 4) {
          ForEach(0..<planState.clarificationQuestions.count, id: \.self) { index in
            RoundedRectangle(cornerRadius: 2)
              .fill(index <= currentQuestionIndex ? Color.blue : Color.gray.opacity(0.3))
              .frame(height: 3)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)

        // Question number
        Text("Question \(currentQuestionIndex + 1) of \(planState.clarificationQuestions.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 16)

        // Question text
        Text(question.question)
          .font(.system(size: 16, weight: .semibold))
          .padding(.horizontal, 16)
          .padding(.top, 8)

        // Options
        VStack(spacing: 12) {
          ForEach(question.options) { option in
            optionButton(option, question: question)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)

        // Continue button (for multi-select questions)
        if question.allowMultipleSelection && !selectedOptions.isEmpty {
          Button(action: {
            submitAnswer()
          }) {
            HStack {
              Text("Continue")
                .font(.system(size: 14, weight: .medium))
              Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(8)
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 16)
          .padding(.top, 8)
        }

        Spacer(minLength: 32)
      }
      .padding(.bottom, 16)
    }
  }

  // MARK: - Option Button

  private func optionButton(_ option: QuestionOption, question: ClarificationQuestion) -> some View
  {
    let isSelected = selectedOptions.contains(option.id)

    return Button(action: {
      handleOptionTap(option, question: question)
    }) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          // Selection indicator
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18))
            .foregroundStyle(isSelected ? .blue : .secondary)

          // Option text
          Text(option.text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)

          Spacer()
        }

        // Explanation (if available)
        if let explanation = option.explanation {
          Text(explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 26)
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlColor).opacity(0.3))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
      )
      .contentShape(Rectangle())  // Ensure tap target covers everything
    }
    .buttonStyle(.plain)
  }

  // MARK: - Generating Plan View

  private var generatingPlanView: some View {
    VStack(spacing: 20) {
      Spacer()

      ProgressView()
        .scaleEffect(1.2)
        .padding(.bottom, 8)

      Text("Generating your plan...")
        .font(.title3)
        .fontWeight(.semibold)

      Text("Analyzing your responses")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(.vertical, 32)
    .onAppear {
      // Trigger plan generation only when this view appears
      // and we confirm loading isn't already handled elsewhere
      // or maybe just call it unconditionally as entry point
      planState.generatePlan()
    }
  }

  // MARK: - Actions

  private func handleOptionTap(_ option: QuestionOption, question: ClarificationQuestion) {
    // Logging for debug
    print("[ClarificationView] Option tapped: \(option.text)")

    if question.allowMultipleSelection {
      // Multi-select: toggle selection
      if selectedOptions.contains(option.id) {
        selectedOptions.remove(option.id)
      } else {
        selectedOptions.insert(option.id)
      }
    } else {
      // Single-select: auto-advance
      // Set selection
      selectedOptions = [option.id]
      // Submit immediately
      submitAnswer()
    }
  }

  private func submitAnswer() {
    guard currentQuestionIndex < planState.clarificationQuestions.count else { return }
    let question = planState.clarificationQuestions[currentQuestionIndex]

    // Store answer
    let selectedTexts = question.options
      .filter { selectedOptions.contains($0.id) }
      .map { $0.id.uuidString }

    planState.clarificationAnswers[question.id] = selectedTexts

    // Clear selection for next question
    selectedOptions = []

    // Always increment index to move forward
    withAnimation {
      currentQuestionIndex += 1
    }

    // Check if we need more questions from LLM
    // If we are at the end, ask LLM.
    // If it says yes, it will append questions.
    // If no, it will set loading=false, and logic will fall through to generatingPlanView
    if currentQuestionIndex >= planState.clarificationQuestions.count {
      print("[ClarificationView] Requesting next question check")
      planState.requestNextQuestion()
    }
  }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
  struct ClarificationView_Previews: PreviewProvider {
    static var previews: some View {
      let planState = PlanState()
      planState.hasSubmittedIntent = true
      planState.clarificationQuestions = [
        ClarificationQuestion(
          question: "Test Question?",
          options: [
            QuestionOption(text: "Option A"),
            QuestionOption(text: "Option B"),
          ]
        )
      ]

      return ClarificationView(planState: planState)
        .frame(width: 280, height: 600)
    }
  }
#endif
