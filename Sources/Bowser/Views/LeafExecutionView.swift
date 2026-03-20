//
//  LeafExecutionView.swift
//  Bowser
//
//  Detail view for executing a specific plan step (leaf node)
//

import SwiftUI

// =============================================================================
// MARK: - Leaf Execution View
// =============================================================================

/// Detail view for a leaf node in the plan
/// Allows user to see instructions, use scratchpad, and mark as complete
struct LeafExecutionView: View {

  @Bindable var planState: PlanState
  @Bindable var browserState: BrowserState

  var body: some View {
    if let node = planState.selectedLeafNode {
      VStack(spacing: 0) {
        // Header
        headerView(node: node)

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 24) {

            // Description / Instructions 
            if let description = node.description {
              VStack(alignment: .leading, spacing: 8) {
                Text("INSTRUCTIONS")
                  .font(.caption)
                  .fontWeight(.bold)
                  .foregroundStyle(.secondary)

                Text(description)
                  .font(.body)
                  .foregroundStyle(.primary)
                  .padding(12)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(
                    RoundedRectangle(cornerRadius: 8)
                      .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                  )
              }
            }

            // Scratchpad
            VStack(alignment: .leading, spacing: 8) {
              Text("SCRATCHPAD")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

              // Safe binding for optional selected node
              TextEditor(
                text: Binding(
                  get: { planState.selectedLeafNode?.scratchpadContent ?? "" },
                  set: { planState.selectedLeafNode?.scratchpadContent = $0 }
                )
              )
              .font(.system(.body, design: .monospaced))
              .frame(minHeight: 120)
              .padding(4)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
              )
            }

            // Relevant Links (Mock)
            if !node.links.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Text("RESOURCES")
                  .font(.caption)
                  .fontWeight(.bold)
                  .foregroundStyle(.secondary)

                ForEach(node.links) { link in
                  Button(action: {
                    let tab = browserState.createTab(url: link.url)
                    node.openedTabIds.insert(tab.id)
                  }) {
                    HStack {
                      Image(systemName: "link")
                        .font(.system(size: 12))
                      Text(link.title)
                        .underline()
                      Spacer()
                      if !node.openedTabIds.isDisjoint(with: browserState.tabs.map { $0.id }) {
                        Text("Open")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                          .padding(.horizontal, 6)
                          .padding(.vertical, 2)
                          .background(Color.secondary.opacity(0.1))
                          .cornerRadius(4)
                      }
                    }
                  }
                  .buttonStyle(.plain)
                  .padding(.vertical, 4)
                }
              }
            }
          }

          // Chat Section
          VStack(alignment: .leading, spacing: 12) {
            Text("AI TUTOR")
              .font(.caption)
              .fontWeight(.bold)
              .foregroundStyle(.secondary)

            VStack(spacing: 0) {
              // Chat History
              if node.chatHistory.isEmpty {
                Text("Ask for help with this step...")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .center)
                  .padding(.vertical, 20)
              } else {
                ForEach(node.chatHistory) { msg in
                  HStack(alignment: .top) {
                    if msg.role == "user" {
                      Spacer()
                      Text(msg.content)
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 250, alignment: .trailing)
                    } else {
                      Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                        .font(.caption)
                        .padding(.top, 4)

                      Text(msg.content)
                        .padding(10)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 250, alignment: .leading)
                      Spacer()
                    }
                  }
                  .padding(.vertical, 4)
                }
              }

              if node.isChatLoading {
                HStack {
                  ProgressView()
                    .controlSize(.small)
                  Text("Thinking...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  Spacer()
                }
                .padding(.vertical, 8)
              }

              Divider().padding(.vertical, 8)

              // Input Area
              HStack {
                TextField("Ask a question...", text: $chatInput)
                  .textFieldStyle(.plain)
                  .onSubmit {
                    sendChat(node: node)
                  }

                Button(action: {
                  sendChat(node: node)
                }) {
                  Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(chatInput.isEmpty ? Color.gray : Color.blue)
                }
                .buttonStyle(.plain)
                .disabled(chatInput.isEmpty)
              }
              .padding(8)
              .background(Color(nsColor: .controlBackgroundColor))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
              )
            }
            .padding(12)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            )
          }
        }

        // Footer Actions
        footerView(node: node)
      }
      .background(Color.clear)
    } else {
      // Fallback (shouldn't be reached if controlled properly)
      Text("No step selected")
    }
  }

  // MARK: - Subviews

  private func headerView(node: PlanNode) -> some View {
    HStack(spacing: 12) {
      Button(action: {
        withAnimation {
          planState.selectedLeafNode = nil
        }
      }) {
        Image(systemName: "chevron.left")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Text(node.title)
        .font(.headline)
        .foregroundStyle(.primary)
        .lineLimit(1)

      Spacer()

      // Status Indicator
      if node.isCompleted {
        HStack(spacing: 4) {
          Image(systemName: "checkmark.circle.fill")
          Text("Completed")
        }
        .font(.caption)
        .foregroundStyle(.green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
  }

  private func footerView(node: PlanNode) -> some View {
    VStack(spacing: 0) {
      Divider()

      HStack {
        Spacer()

        Button(action: {
          toggleCompletion(node: node)
        }) {
          Text(node.isCompleted ? "Mark as Incomplete" : "Mark as Complete")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(node.isCompleted ? Color.secondary : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(node.isCompleted ? Color.gray.opacity(0.1) : Color.blue)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
      }
      .padding(16)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
  }

  @State private var chatInput: String = ""

  // MARK: - Actions

  private func sendChat(node: PlanNode) {
    guard !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let message = chatInput
    chatInput = ""  // Clear input immediately
    planState.sendChatMessage(node: node, message: message)
  }

  private func toggleCompletion(node: PlanNode) {
    withAnimation {
      node.isCompleted.toggle()
    }
  }
}
