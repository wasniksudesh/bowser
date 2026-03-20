//
//  PlanRowView.swift
//  Bowser
//
//  Individual plan row component for plan list view
//

import SwiftUI

// =============================================================================
// MARK: - Plan Row View
// =============================================================================

/// Individual plan row in the plan list
/// Similar to TabRowView with hover effects, selection, and rename support
struct PlanRowView: View {

    let plan: PlanMetadata
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onFork: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var editedName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isRenaming {
                renameView
            } else {
                normalView
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Normal View

    private var normalView: some View {
        HStack(spacing: 8) {
            // Plan icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                // Plan name
                Text(plan.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .blue : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Intent preview
                Text(plan.intent)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .blue.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Metadata (progress and time)
                HStack(spacing: 4) {
                    Text(plan.progressText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(plan.relativeTimeText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Context menu button (on hover)
            if isHovering {
                Menu {
                    Button("Rename") {
                        startRenaming()
                    }

                    Button("Fork") {
                        onFork()
                    }

                    Divider()

                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))

        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            // Double-click to rename
            startRenaming()
        }
        .onTapGesture(count: 1) {
            // Single-click to select
            onSelect()
        }
        .contextMenu {
            Button("Rename") {
                startRenaming()
            }

            Button("Fork") {
                onFork()
            }

            Divider()

            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    // MARK: - Rename View

    private var renameView: some View {
        HStack(spacing: 8) {
            // Plan icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 20)

            // Text field
            TextField("Plan name", text: $editedName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isTextFieldFocused)
                .onSubmit {
                    finishRenaming()
                }
                .onExitCommand {
                    cancelRenaming()
                }

            // Checkmark button
            Button(action: finishRenaming) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        )
        .onAppear {
            editedName = plan.name
            isTextFieldFocused = true
        }
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(0.1)
        } else if isHovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    // MARK: - Actions

    private func startRenaming() {
        editedName = plan.name
        withAnimation(.easeInOut(duration: 0.15)) {
            isRenaming = true
        }
    }

    private func finishRenaming() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty && trimmedName != plan.name {
            onRename(trimmedName)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            isRenaming = false
        }
    }

    private func cancelRenaming() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isRenaming = false
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct PlanRowView_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 8) {
                PlanRowView(
                    plan: PlanMetadata(
                        name: "Google Interview Prep",
                        intent: "Prepare for Google software engineering interviews",
                        nodeCount: 20,
                        completedNodeCount: 12
                    ),
                    isSelected: false,
                    onSelect: {},
                    onRename: { _ in },
                    onFork: {},
                    onDelete: {}
                )

                PlanRowView(
                    plan: PlanMetadata(
                        name: "Learn Swift",
                        intent: "Master Swift programming language",
                        nodeCount: 8,
                        completedNodeCount: 5
                    ),
                    isSelected: true,
                    onSelect: {},
                    onRename: { _ in },
                    onFork: {},
                    onDelete: {}
                )
            }
            .frame(width: 280)
            .padding()
        }
    }
#endif
