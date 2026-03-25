// WebSelectionMonitor.swift - Detects text selection in CEF web pages
// Uses NSEvent monitoring + clipboard bridge since CEF has no direct JS result callback

import AppKit
import CEFWrapper
import Foundation

// =============================================================================
// MARK: - Web Selection Monitor
// =============================================================================

/// Detects when the user selects text on a web page by monitoring mouseUp events
/// and using the clipboard as a bridge to extract the selected text from CEF.
///
/// Flow: mouseUp → cef_copy → check pasteboard changeCount → show/clear popup
@Observable
@MainActor
final class WebSelectionMonitor {

    var selectedText: String?
    var selectionScreenPosition: CGPoint?
    var sourceURL: URL?

    private var eventMonitor: Any?
    private weak var browserState: BrowserState?
    private var lastActiveTabId: UUID?

    init() {}

    func attach(to browserState: BrowserState) {
        self.browserState = browserState
        startMonitoring()
    }

    func dismiss() {
        selectedText = nil
        selectionScreenPosition = nil
        sourceURL = nil
    }

    func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Private

    private func startMonitoring() {
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseUp(event)
            }
            return event
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard let browserState else { return }

        // Dismiss on tab switch
        let currentTabId = browserState.activeTab?.id
        if currentTabId != lastActiveTabId {
            lastActiveTabId = currentTabId
            dismiss()
        }

        guard let activeTab = browserState.activeTab, activeTab.tabType == .web else {
            // Not on a web tab -- clear any stale selection
            if selectedText != nil { dismiss() }
            return
        }

        let pageId: UUID
        if activeTab.stackModeEnabled, let activePage = activeTab.activePage {
            pageId = activePage.browserId
        } else {
            guard let firstPage = activeTab.pages.first else { return }
            pageId = firstPage.browserId
        }

        guard let browserView = BrowserManager.shared.existingBrowser(for: pageId),
              let handle = browserView.cefBrowserHandle
        else { return }

        let mouseLocation = NSEvent.mouseLocation
        let capturedURL = activeTab.url
        let savedChangeCount = NSPasteboard.general.changeCount

        cef_copy(handle)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard let self else { return }

            let pb = NSPasteboard.general
            if pb.changeCount == savedChangeCount {
                // Pasteboard unchanged -- cef_copy found no selection. Clear stale popup.
                if self.selectedText != nil { self.dismiss() }
                return
            }

            if let newString = pb.string(forType: .string), !newString.isEmpty {
                self.selectedText = newString
                self.selectionScreenPosition = mouseLocation
                self.sourceURL = capturedURL
            } else {
                // cef_copy changed the pasteboard but with empty/non-string content
                if self.selectedText != nil { self.dismiss() }
            }
        }
    }
}
