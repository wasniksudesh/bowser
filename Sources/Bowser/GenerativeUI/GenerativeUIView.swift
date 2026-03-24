//
//  GenerativeUIView.swift
//  Bowser
//
//  Main view for displaying AI-generated UI layouts.
//  Rendering is delegated to ComponentRendererRegistry; data fetching
//  is delegated to GenerativeUIStreamClient.
//

import SwiftUI

// =============================================================================
// MARK: - Generative UI View
// =============================================================================

struct GenerativeUIView: View {

    @Bindable var planState: PlanState
    @Bindable var browserState: BrowserState

    private let streamClient = GenerativeUIStreamClient()

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    if let node = planState.selectedLeafNode {
                        if let error = planState.errorMessage {
                            errorStateView(error: error)
                        } else if planState.isLoading && planState.generativeUILayout == nil {
                            loadingStateView
                        } else if let layout = planState.generativeUILayout {
                            dynamicComponentsView(layout: layout)
                        } else {
                            emptyStateView(node: node)
                        }
                    } else {
                        noSelectionView
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task(id: planState.selectedLeafNode?.id) {
            guard let node = planState.selectedLeafNode else { return }
            await streamClient.streamLayout(for: node, planState: planState)
        }
    }

    // MARK: - Component Grid

    private func dynamicComponentsView(layout: GenerativeUILayout) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(layout.components.enumerated()), id: \.element.id) { index, spec in
                VStack(alignment: .leading, spacing: 8) {
                    Text(spec.type.capitalized.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    ComponentRendererRegistry.view(
                        for: spec,
                        data: planState.componentDataCache[spec.id],
                        isLoading: planState.loadingComponentIds.contains(spec.id),
                        browserState: browserState
                    )
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
                .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.08), value: layout.components.count)
            }
        }
        .padding(24)
    }

    // MARK: - State Views

    private var loadingStateView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Designing layout...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI is analysing your task and creating the layout")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func errorStateView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Layout Generation Failed")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Try Again") {
                Task {
                    guard let node = planState.selectedLeafNode else { return }
                    planState.errorMessage = nil
                    await streamClient.streamLayout(for: node, planState: planState)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func emptyStateView(node: PlanNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(node.title)
                .font(.title2)
                .fontWeight(.bold)
            if let description = node.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
            }
        }
        .padding(24)
    }

    private var noSelectionView: some View {
        Text("No leaf node selected")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            Text("AI-Generated Layout")
                .font(.headline)
            Spacer()

            if planState.generativeUILayout != nil {
                Button {
                    Task {
                        guard let node = planState.selectedLeafNode else { return }
                        await streamClient.streamLayout(for: node, planState: planState)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Regenerate layout")
            }

            if planState.isLoading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Loading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct GenerativeUIView_Previews: PreviewProvider {
    static var previews: some View {
        let planState = PlanState()
        let browserState = BrowserState()
        GenerativeUIView(planState: planState, browserState: browserState)
            .frame(width: 800, height: 600)
    }
}
#endif
