//
//  HomescreenWidgetView.swift
//  Bowser
//
//  Grid-cell widget chrome for the homescreen widget grid.
//  Renders widget content with a title bar and close button.
//  Positioning and layout are handled by the parent LazyVGrid.
//

import SwiftUI

// =============================================================================
// MARK: - Homescreen Widget View
// =============================================================================

/// A single widget cell in the homescreen grid.
/// Shows a title bar with close button and routes content by widget kind.
struct HomescreenWidgetView: View {

    @Bindable var browserState: BrowserState
    let widget: HomescreenWidgetInstance
    let componentData: Any?
    let onClose: () -> Void

    @State private var isHovering = false

    private var descriptor: BuiltinWidgetDescriptor? {
        guard widget.kind == .builtin else { return nil }
        return browserState.widgetManager.builtinRegistry.descriptor(for: widget.outputComponentType)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.4)
            contentArea
        }
        .frame(width: widget.size.width, height: widget.size.height)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.14 : 0.07), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: descriptor?.icon ?? "cpu")
                .font(.system(size: 11))
                .foregroundStyle(widget.kind == .builtin ? Color.primary.opacity(0.65) : Color.blue)

            Text(descriptor?.displayName ?? widget.query)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch widget.kind {
        case .agent:
            ScrollView {
                AgentOutputView(
                    componentType: widget.outputComponentType,
                    componentData: componentData,
                    summary: "",
                    compact: true,
                    browserState: browserState
                )
                .padding(12)
            }
        case .builtin:
            BuiltinWidgetContentView(
                widget: widget,
                widgetManager: browserState.widgetManager
            )
        }
    }
}
