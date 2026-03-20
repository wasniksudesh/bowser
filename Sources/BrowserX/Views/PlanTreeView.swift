//
//  PlanTreeView.swift
//  Bowser
//
//  Tree view for visualizing the generated plan
//

import SwiftUI

// =============================================================================
// MARK: - Plan Tree View
// =============================================================================

/// Displays the plan structure as a collapsible tree
struct PlanTreeView: View {

  @Bindable var planState: PlanState

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 8) {
        // Back button
        Button(action: {
          planState.exitToList()
        }) {
          Image(systemName: "chevron.left")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.blue)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Back to plans")
        
        Text(planState.currentPlanName.isEmpty ? (planState.planRoot?.title ?? "Plan") : planState.currentPlanName)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer()

        // Actions menu (placeholder)
        Button(action: {}) {
          Image(systemName: "ellipsis.circle")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

      Divider()

      // Tree content
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          if let root = planState.planRoot {
            ForEach(root.children) { child in
              PlanNodeView(node: child, planState: planState, depth: 0)
            }
          }
        }
        .padding(.vertical, 8)
      }
    }
  }
}

// =============================================================================
// MARK: - Plan Node View
// =============================================================================

/// Recursive view for a single node in the plan tree
struct PlanNodeView: View {

  var node: PlanNode
  var planState: PlanState
  var depth: Int

  // Derived expansion state from planState
  private var isExpanded: Bool {
    planState.expandedNodeIds.contains(node.id)
  }

  // Derived selection state
  private var isSelected: Bool {
    planState.selectedLeafNode?.id == node.id
  }

  // Derived loading state
  private var isLoading: Bool {
    planState.loadingNodeIds.contains(node.id)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {

      // Node Row
      HStack(spacing: 6) {
        // Indentation
        ForEach(0..<depth, id: \.self) { _ in
          Spacer().frame(width: 12)
        }

        // Disclosure / Loading / Leaf Icon
        if isLoading {
          ProgressView()
            .controlSize(.mini)
            .scaleEffect(0.6)
            .frame(width: 16, height: 16)
        } else if !node.children.isEmpty || !node.isLeaf {
          Button(action: {
            toggleExpansion()
          }) {
            Image(systemName: "chevron.right")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.secondary)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .frame(width: 16, height: 16)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        } else {
          // Leaf node icon
          Image(systemName: isSelected ? "circle.inset.filled" : "circle")
            .font(.system(size: 8))
            .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.5))
            .frame(width: 16, height: 16)
        }

        // Content
        Button(action: {
          if node.isLeaf {
            selectNode()
          } else {
            toggleExpansion()
          }
        }) {
          HStack(spacing: 8) {
            Text(node.title)
              .font(.system(size: 13, weight: node.isLeaf ? .regular : .medium))
              .foregroundStyle(isSelected ? .blue : .primary)

            // Show "Expand to generate" hint for lazy nodes
            if node.children.isEmpty && !node.isLeaf {
              Text("(Expand)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            } else if let description = node.description {
              Text(description)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? .blue.opacity(0.8) : .secondary)
                .lineLimit(1)
            }

            Spacer()

            // Execution status (placeholder)
            if node.isCompleted {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
            }
          }
          .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isSelected ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04))
          .opacity(isSelected ? 1.0 : 0.0)  // Only show background when selected for now
      )

      // Recursive Children
      if isExpanded && !node.children.isEmpty {
        ForEach(node.children) { child in
          PlanNodeView(node: child, planState: planState, depth: depth + 1)
        }
      }
    }
  }

  private func toggleExpansion() {
    if node.children.isEmpty && !node.isLeaf {
      // Lazy expand
      if !isExpanded {
        print("[PlanTreeView] Triggering lazy expansion for: \(node.title)")
        planState.generateSubSteps(for: node)
      }
    } else {
      // Normal toggle
      withAnimation(.snappy(duration: 0.2)) {
        if isExpanded {
          planState.expandedNodeIds.remove(node.id)
        } else {
          planState.expandedNodeIds.insert(node.id)
        }
      }
    }
  }

  private func selectNode() {
    print("[PlanTreeView] Selected leaf: \(node.title)")
    planState.selectedLeafNode = node
  }
}
