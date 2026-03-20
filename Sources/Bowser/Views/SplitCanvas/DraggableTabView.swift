// SPDX-License-Identifier: MIT
// DraggableTabView.swift
// Bowser
//
// A SwiftUI wrapper that prevents window dragging when initiating tab drags.
// This solves the conflict between `isMovableByWindowBackground = true` and SwiftUI's onDrag.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Draggable Tab Modifier

/// A view modifier that makes a tab draggable without triggering window movement.
/// This is necessary because `isMovableByWindowBackground = true` causes any mouse-down
/// on the background to start a window drag, which conflicts with SwiftUI's onDrag gesture.
struct DraggableTabModifier: ViewModifier {
    let tabId: UUID
    let draggedTab: Binding<Tab?>
    let tab: Tab

    func body(content: Content) -> some View {
        DraggableTabWrapper(tabId: tabId, draggedTab: draggedTab, tab: tab) {
            content
        }
    }
}

extension View {
    /// Makes a view draggable as a tab without triggering window movement.
    /// - Parameters:
    ///   - tabId: The UUID of the tab being dragged
    ///   - draggedTab: Binding to track which tab is being dragged
    ///   - tab: The Tab being dragged
    func draggableTab(tabId: UUID, draggedTab: Binding<Tab?>, tab: Tab) -> some View {
        modifier(DraggableTabModifier(tabId: tabId, draggedTab: draggedTab, tab: tab))
    }
}

// MARK: - AppKit Wrapper

/// An NSViewRepresentable that wraps SwiftUI content in an NSView that:
/// 1. Returns `false` for `mouseDownCanMoveWindow` to prevent window dragging
/// 2. Implements `NSDraggingSource` to initiate proper drag sessions
struct DraggableTabWrapper<Content: View>: NSViewRepresentable {
    let tabId: UUID
    @Binding var draggedTab: Tab?
    let tab: Tab
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> DraggableTabNSView {
        let view = DraggableTabNSView()
        view.tabId = tabId
        view.dragCoordinator = context.coordinator

        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: content())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        context.coordinator.hostingView = hostingView

        return view
    }

    func updateNSView(_ nsView: DraggableTabNSView, context: Context) {
        nsView.tabId = tabId
        context.coordinator.hostingView?.rootView = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tabId: tabId, draggedTab: $draggedTab, tab: tab)
    }

    @MainActor
    class Coordinator: NSObject, TabDragCoordinator, NSDraggingSource {
        var tabId: UUID
        var draggedTab: Binding<Tab?>
        var tab: Tab
        var hostingView: NSHostingView<Content>?

        init(tabId: UUID, draggedTab: Binding<Tab?>, tab: Tab) {
            self.tabId = tabId
            self.draggedTab = draggedTab
            self.tab = tab
        }

        // MARK: - TabDragCoordinator

        func dragWillBegin() {
            print("[DraggableTabWrapper] Drag will begin for tab: \(tabId)")
            draggedTab.wrappedValue = tab
        }

        func dragDidEnd(operation: NSDragOperation) {
            print(
                "[DraggableTabWrapper] Drag ended for tab: \(tabId), operation: \(operation.rawValue)"
            )
            draggedTab.wrappedValue = nil
        }

        // MARK: - NSDraggingSource

        nonisolated func draggingSession(
            _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            return context == .outsideApplication ? [] : .move
        }

        nonisolated func draggingSession(
            _ session: NSDraggingSession, willBeginAt screenPoint: NSPoint
        ) {
            Task { @MainActor in
                self.dragWillBegin()
            }
        }

        nonisolated func draggingSession(
            _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
        ) {
            Task { @MainActor in
                self.dragDidEnd(operation: operation)
            }
        }
    }
}

// MARK: - Drag Source Protocol

/// Protocol for coordinating drag operations
@MainActor
protocol TabDragCoordinator: AnyObject, NSDraggingSource {
    var tabId: UUID { get }
    func dragWillBegin()
    func dragDidEnd(operation: NSDragOperation)
}

// MARK: - Custom NSView

/// Custom NSView that prevents window dragging and handles drag initiation.
///
/// Design: We do NOT override hitTest - this allows clicks to pass through naturally
/// to SwiftUI content. Instead, we use local event monitors to detect when a drag
/// gesture should be initiated (mouse moved beyond threshold while button down).
@MainActor
final class DraggableTabNSView: NSView {
    var tabId: UUID = UUID()
    weak var dragCoordinator: (any TabDragCoordinator)?

    private var dragStartPoint: NSPoint?
    private var mouseDownEvent: NSEvent?
    private let dragThreshold: CGFloat = 5.0
    private var isDragging: Bool = false

    // Mark as nonisolated(unsafe) to allow access from deinit
    // These are only accessed from the main thread in practice
    private nonisolated(unsafe) var mouseDownMonitor: Any?
    private nonisolated(unsafe) var mouseDraggedMonitor: Any?
    private nonisolated(unsafe) var mouseUpMonitor: Any?

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupEventMonitors()
        } else {
            removeEventMonitors()
        }
    }

    deinit {
        // Remove monitors synchronously to avoid weak reference issues during deallocation
        // Must be done synchronously in deinit - no async dispatch allowed
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDraggedMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func setupEventMonitors() {
        // Remove any existing monitors first
        removeEventMonitors()

        // Monitor mouseDown to track potential drag start
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.handleMouseDown(event)
            return event  // Always pass through - don't consume
        }

        // Monitor mouseDragged to detect drag threshold
        mouseDraggedMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] event in
            if let strongSelf = self, strongSelf.isDragging {
                // We've started a drag session, consume the event
                return nil
            }
            self?.handleMouseDragged(event)
            return event  // Pass through unless we're dragging
        }

        // Monitor mouseUp to reset state
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            self?.handleMouseUp(event)
            return event  // Always pass through
        }
    }

    private func removeEventMonitors() {
        // Remove monitors synchronously - must be called on main thread
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDraggedMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
    }

    private func isEventInOurView(_ event: NSEvent) -> Bool {
        guard let window = self.window, event.window == window else {
            return false
        }
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        return bounds.contains(locationInView)
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard isEventInOurView(event) else { return }

        print(
            "[DEBUG mouseDown] Tab \(tabId) - INTERCEPTED at locationInWindow: \(event.locationInWindow)"
        )
        dragStartPoint = event.locationInWindow
        mouseDownEvent = event
        isDragging = false
        // Don't consume - let SwiftUI handle the click
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard let startPoint = dragStartPoint, !isDragging else {
            return
        }

        // Only handle if we started in our view
        guard mouseDownEvent != nil else { return }

        let currentPoint = event.locationInWindow
        let distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)

        if distance > dragThreshold {
            print("[DraggableTabNSView] mouseDragged distance: \(distance) - Starting drag!")
            // Start drag session
            isDragging = true
            startDragSession(with: event)
            dragStartPoint = nil
            mouseDownEvent = nil
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        let wasDragging = isDragging

        if dragStartPoint != nil || wasDragging {
            print("[DEBUG mouseUp] Tab \(tabId) - wasDragging=\(wasDragging)")
        }

        // Reset state
        dragStartPoint = nil
        mouseDownEvent = nil
        isDragging = false
        // Don't consume - let SwiftUI handle the click
    }

    private func startDragSession(with event: NSEvent) {
        print("[DraggableTabNSView] Starting drag session for tab: \(tabId)")

        // Create pasteboard item
        let pasteboardItem = NSPasteboardItem()

        // Use setData for custom type (matches data(forType:) extraction in drop handler)
        if let data = tabId.uuidString.data(using: .utf8) {
            pasteboardItem.setData(data, forType: .bowserTabId)
        }
        // Also set as string for fallback compatibility
        pasteboardItem.setString(tabId.uuidString, forType: .string)

        // Create dragging item
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Create drag image from the view's content
        let dragImage = createDragImage()
        let draggingFrame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: bounds.height
        )

        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)

        // Get coordinator as the dragging source
        guard let coordinator = dragCoordinator else {
            print("[DraggableTabNSView] No coordinator available for drag source")
            return
        }

        // Begin dragging session
        beginDraggingSession(with: [draggingItem], event: event, source: coordinator)
    }

    private func createDragImage() -> NSImage {
        // Create a snapshot of this view for the drag image
        guard let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }

        cacheDisplay(in: bounds, to: bitmapRep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)

        // Make it semi-transparent
        let transparentImage = NSImage(size: bounds.size)
        transparentImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: bounds.size), from: .zero, operation: .sourceOver,
            fraction: 0.7)
        transparentImage.unlockFocus()

        return transparentImage
    }
}
