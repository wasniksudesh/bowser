//
//  HomescreenWidgetView.swift
//  Bowser
//
//  Draggable, resizable, closable widget on the homescreen
//  Wraps AgentOutputView with interaction controls
//

import SwiftUI

// =============================================================================
// MARK: - Homescreen Widget View
// =============================================================================

/// A single widget displayed on the homescreen, wrapping an AgentOutputView
struct HomescreenWidgetView: View {
    
    @Bindable var browserState: BrowserState
    let widget: HomescreenWidgetInstance
    let componentData: Any?
    let onClose: () -> Void
    let onPositionChanged: (CGPoint) -> Void
    let onSizeChanged: (CGSize) -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var isResizing = false
    @State private var resizeStartSize: CGSize = .zero
    
    private let minSize = CGSize(width: 200, height: 160)
    private let maxSize = CGSize(width: 600, height: 500)
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar (drag handle)
            titleBar
            
            Divider()
                .opacity(0.5)
            
            // Content area
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
        }
        .frame(width: widget.size.width, height: widget.size.height)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(
                    color: .black.opacity(isDragging ? 0.3 : 0.15),
                    radius: isDragging ? 16 : 8,
                    y: isDragging ? 8 : 4
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.primary.opacity(isHovering ? 0.15 : 0.08),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottomTrailing) {
            resizeHandle
        }
        .position(
            x: widget.position.x + dragOffset.width,
            y: widget.position.y + dragOffset.height
        )
        .gesture(dragGesture)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
    }
    
    // MARK: - Title Bar
    
    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
            
            Text(widget.query)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }
    
    // MARK: - Resize Handle
    
    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isResizing {
                            isResizing = true
                            resizeStartSize = widget.size
                        }
                        let newWidth = max(minSize.width, min(maxSize.width, resizeStartSize.width + value.translation.width))
                        let newHeight = max(minSize.height, min(maxSize.height, resizeStartSize.height + value.translation.height))
                        onSizeChanged(CGSize(width: newWidth, height: newHeight))
                    }
                    .onEnded { _ in
                        isResizing = false
                    }
            )
            .padding(4)
            .opacity(isHovering ? 1 : 0)
    }
    
    // MARK: - Drag Gesture
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation
            }
            .onEnded { value in
                isDragging = false
                let newPosition = CGPoint(
                    x: widget.position.x + value.translation.width,
                    y: widget.position.y + value.translation.height
                )
                dragOffset = .zero
                onPositionChanged(newPosition)
            }
    }
}

// =============================================================================
// MARK: - Widget Layer
// =============================================================================

/// Overlay layer that renders all visible widgets on the homescreen
struct HomescreenWidgetLayer: View {
    
    @Bindable var browserState: BrowserState
    @Bindable var widgetManager: WidgetManager
    
    var body: some View {
        ZStack {
            ForEach(widgetManager.visibleWidgets) { widget in
                HomescreenWidgetView(
                    browserState: browserState,
                    widget: widget,
                    componentData: widgetManager.cachedData[widget.widgetId],
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            widgetManager.hideWidget(widget.id)
                        }
                    },
                    onPositionChanged: { newPos in
                        widgetManager.updatePosition(widget.id, position: newPos)
                    },
                    onSizeChanged: { newSize in
                        widgetManager.updateSize(widget.id, size: newSize)
                    }
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}
