// SnapshotCaptureService.swift - macOS screenshot-like capture tool
// Manages the snapshot mode lifecycle and coordinates the overlay window

import AppKit
import Foundation

// =============================================================================
// MARK: - Snapshot Capture Service
// =============================================================================

/// Manages the snapshot capture workflow: overlay presentation, capture, clipboard, and popup state.
@Observable
@MainActor
final class SnapshotCaptureService {

    var isSnapshotMode: Bool = false
    var capturedImage: NSImage?
    var snapshotScreenPosition: CGPoint?
    var sourceURL: URL?

    private var overlayWindow: SnapshotOverlayWindow?
    private weak var browserState: BrowserState?

    init() {}

    func attach(to browserState: BrowserState) {
        self.browserState = browserState
    }

    /// Enter snapshot mode: present the fullscreen overlay with crosshair cursor.
    func startCapture() {
        guard !isSnapshotMode else { return }
        isSnapshotMode = true
        capturedImage = nil
        snapshotScreenPosition = nil
        sourceURL = browserState?.activeTab?.url

        let overlay = SnapshotOverlayWindow { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handleCaptureResult(result)
            }
        }
        overlay.beginCapture()
        overlayWindow = overlay
    }

    /// Cancel snapshot mode without capturing.
    func cancelCapture() {
        overlayWindow?.close()
        overlayWindow = nil
        isSnapshotMode = false
        capturedImage = nil
        snapshotScreenPosition = nil
    }

    /// Dismiss the popup bar after an action (save/ai).
    func dismiss() {
        capturedImage = nil
        snapshotScreenPosition = nil
        sourceURL = nil
    }

    // MARK: - Private

    private func handleCaptureResult(_ result: SnapshotOverlayWindow.CaptureResult?) {
        overlayWindow = nil
        isSnapshotMode = false

        guard let result else { return }

        capturedImage = result.image
        snapshotScreenPosition = result.centerPoint

        copyImageToClipboard(result.image)
    }

    private func copyImageToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
            if let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                pasteboard.setData(pngData, forType: .png)
            }
        }
    }
}
