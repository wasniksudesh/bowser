// SnapshotOverlayWindow.swift - Fullscreen transparent overlay for rectangle screenshot capture
// Mimics macOS screenshot: crosshair cursor, rubber-band rectangle, region capture

import AppKit
import Foundation

// =============================================================================
// MARK: - Snapshot Overlay Window
// =============================================================================

/// Fullscreen transparent panel for drawing a capture rectangle.
/// Similar to macOS screenshot: crosshair cursor, dark scrim outside the selection,
/// clear inside. On mouseUp, captures the region and copies to clipboard.
final class SnapshotOverlayWindow: NSPanel {

    struct CaptureResult {
        let image: NSImage
        let captureRect: NSRect
        let centerPoint: CGPoint
    }

    private let onComplete: @MainActor (CaptureResult?) -> Void
    private var captureView: SnapshotCaptureView!

    init(onComplete: @escaping @MainActor (CaptureResult?) -> Void) {
        self.onComplete = onComplete

        guard let screen = NSScreen.main else {
            super.init(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        captureView = SnapshotCaptureView(frame: screen.frame) { [weak self] result in
            self?.finishCapture(result)
        }
        contentView = captureView
    }

    func beginCapture() {
        makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    override func cancelOperation(_ sender: Any?) {
        finishCapture(nil)
    }

    override var canBecomeKey: Bool { true }

    // MARK: - Private

    private func finishCapture(_ result: CaptureResult?) {
        NSCursor.pop()
        orderOut(nil)
        onComplete(result)
    }
}

// =============================================================================
// MARK: - Snapshot Capture View
// =============================================================================

/// Custom NSView that handles mouse drag to draw a selection rectangle
/// and captures the screen region on completion.
private final class SnapshotCaptureView: NSView {

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false
    private let onCapture: (SnapshotOverlayWindow.CaptureResult?) -> Void

    init(frame: NSRect, onCapture: @escaping (SnapshotOverlayWindow.CaptureResult?) -> Void) {
        self.onCapture = onCapture
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false

        guard currentRect.width > 4 && currentRect.height > 4 else {
            onCapture(nil)
            return
        }

        captureRegion()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCapture(nil)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()

        guard currentRect.width > 0, currentRect.height > 0 else { return }

        NSColor.clear.setFill()
        currentRect.fill(using: .copy)

        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath(rect: currentRect)
        path.lineWidth = 1.5
        path.stroke()

        drawDimensions()
    }

    private func drawDimensions() {
        let text = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let labelX = currentRect.midX - size.width / 2
        let labelY = currentRect.minY - size.height - 6
        (text as NSString).draw(at: NSPoint(x: labelX, y: max(labelY, 2)), withAttributes: attrs)
    }

    // MARK: - Screen Capture

    private func captureRegion() {
        guard let screen = window?.screen ?? NSScreen.main else {
            onCapture(nil)
            return
        }

        // Convert from view coordinates (origin bottom-left) to screen coordinates
        let screenFrame = screen.frame
        let flippedRect = CGRect(
            x: screenFrame.origin.x + currentRect.origin.x,
            y: screenFrame.origin.y + (screenFrame.height - currentRect.origin.y - currentRect.height),
            width: currentRect.width,
            height: currentRect.height
        )

        // Hide overlay before capture to exclude it from the screenshot
        window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            guard let cgImage = CGWindowListCreateImage(
                flippedRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                onCapture(nil)
                return
            }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            // Convert view-local center to screen coordinates (bottom-left origin)
            let center = CGPoint(
                x: screenFrame.origin.x + currentRect.midX,
                y: screenFrame.origin.y + currentRect.midY
            )

            onCapture(SnapshotOverlayWindow.CaptureResult(
                image: image,
                captureRect: currentRect,
                centerPoint: center
            ))
        }
    }
}
