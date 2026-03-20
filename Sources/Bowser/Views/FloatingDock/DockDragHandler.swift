// DockDragHandler.swift - Drag Gesture Handler for Floating Dock
// Enables dragging the dock to reposition it on screen

import SwiftUI
import AppKit

// =============================================================================
// MARK: - Dock Draggable Modifier
// =============================================================================

extension View {
    /// Makes the dock draggable by overlaying a drag handler
    func dockDraggable() -> some View {
        self.overlay(
            DockDragHandler()
        )
    }
}

// =============================================================================
// MARK: - Dock Drag Handler (NSViewRepresentable)
// =============================================================================

/// NSViewRepresentable that handles drag gestures for repositioning the dock
struct DockDragHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandlerView {
        DragHandlerView()
    }
    
    func updateNSView(_ nsView: DragHandlerView, context: Context) {}
}

// =============================================================================
// MARK: - Drag Handler View (NSView)
// =============================================================================

/// Custom NSView that intercepts mouse events for dragging
class DragHandlerView: NSView {
    private var mouseDownLocation: NSPoint?
    private var originalWindowOrigin: NSPoint?
    private var didDrag = false
    
    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }
        
        mouseDownLocation = event.locationInWindow
        originalWindowOrigin = window.frame.origin
        didDrag = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window,
              let mouseDownLocation = mouseDownLocation,
              let originalOrigin = originalWindowOrigin else { return }
        
        didDrag = true
        
        let currentLocation = event.locationInWindow
        let deltaX = currentLocation.x - mouseDownLocation.x
        let deltaY = currentLocation.y - mouseDownLocation.y
        
        let newOrigin = NSPoint(
            x: originalOrigin.x + deltaX,
            y: originalOrigin.y + deltaY
        )
        
        window.setFrameOrigin(newOrigin)
        
        // Save position
        FloatingDockManager.shared.savePosition(newOrigin)
    }
    
    override func mouseUp(with event: NSEvent) {
        // If we didn't drag, pass the click through to SwiftUI
        if !didDrag {
            // Let the event propagate
            super.mouseUp(with: event)
        }
        
        mouseDownLocation = nil
        originalWindowOrigin = nil
        didDrag = false
    }
}
