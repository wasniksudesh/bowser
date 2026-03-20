// Page.swift - Page Model for Stacked Navigation
// Represents a single page within a tab's stack

import Foundation
import AppKit
import CEFWrapper

// =============================================================================
// MARK: - Page Lifecycle State
// =============================================================================

/// Lifecycle state for pages in the stack
enum PageLifecycleState: String, Codable {
    /// Page is active and fully loaded
    case alive
    
    /// Page is suspended but can be quickly resumed
    case hibernating
    
    /// Page is frozen with a snapshot overlay
    case frozen
}

// =============================================================================
// MARK: - Page Model
// =============================================================================

/// Represents a single page in a tab's horizontal stack
/// Each page has its own URL, title, snapshot, and lifecycle state
struct Page: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    
    /// Unique identifier for this page's browser instance
    /// Used to key the CEF browser in BrowserManager
    let browserId: UUID
    
    /// The URL of this page
    var url: URL
    
    /// The page title
    var title: String
    
    /// Cached snapshot for frozen state and dock preview
    var snapshot: NSImage?
    
    /// Whether this page is starred (exempt from 7-page limit)
    var isStarred: Bool
    
    /// Current lifecycle state (alive, hibernating, frozen)
    var lifecycleState: PageLifecycleState
    
    /// Favicon data
    var favicon: Data?
    
    /// Favicon image
    var icon: NSImage?
    
    /// Loading state
    var isLoading: Bool
    
    /// Loading progress (0.0 to 1.0) for wake-up curtain animation
    var loadingProgress: Double
    
    /// Navigation state
    var canGoBack: Bool
    var canGoForward: Bool
    
    /// Timestamp when page was last visited (for hibernation logic)
    var lastVisitedAt: Date
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        browserId: UUID = UUID(),
        url: URL,
        title: String = "New Page",
        snapshot: NSImage? = nil,
        isStarred: Bool = false,
        lifecycleState: PageLifecycleState = .alive,
        favicon: Data? = nil,
        icon: NSImage? = nil,
        isLoading: Bool = false,
        loadingProgress: Double = 0.0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        lastVisitedAt: Date = Date()
    ) {
        self.id = id
        self.browserId = browserId
        self.url = url
        self.title = title
        self.snapshot = snapshot
        self.isStarred = isStarred
        self.lifecycleState = lifecycleState
        self.favicon = favicon
        self.icon = icon
        self.isLoading = isLoading
        self.loadingProgress = loadingProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.lastVisitedAt = lastVisitedAt
    }
    
    // MARK: - Equatable
    
    static func == (lhs: Page, rhs: Page) -> Bool {
        lhs.id == rhs.id &&
        lhs.browserId == rhs.browserId &&
        lhs.url == rhs.url &&
        lhs.title == rhs.title &&
        lhs.snapshot === rhs.snapshot &&
        lhs.isStarred == rhs.isStarred &&
        lhs.lifecycleState == rhs.lifecycleState &&
        lhs.favicon == rhs.favicon &&
        lhs.icon === rhs.icon &&
        lhs.isLoading == rhs.isLoading &&
        lhs.loadingProgress == rhs.loadingProgress &&
        lhs.canGoBack == rhs.canGoBack &&
        lhs.canGoForward == rhs.canGoForward
    }
    
    // MARK: - Media Control Methods
    
    /// Suspend media playback and block interactions
    @MainActor
    mutating func suspend() {
        guard let browserView = BrowserManager.shared.existingBrowser(for: browserId) else { return }
        
        // JavaScript to pause all media and block pointer events
        let suspendScript = """
        (function() {
            // Pause all standard media tags
            document.querySelectorAll('video, audio').forEach(m => {
                m.pause();
                m.muted = true;
            });
            // Suspend Web Audio API contexts
            if (window.AudioContext || window.webkitAudioContext) {
                [window.AudioContext, window.webkitAudioContext].forEach(ctx => {
                    if (ctx && ctx.state === 'running') {
                        ctx.suspend();
                    }
                });
            }
            // Block pointer events
            document.body.style.pointerEvents = 'none';
        })();
        """
        
        if let handle = browserView.cefBrowserHandle {
            cef_execute_javascript(handle, suspendScript)
        }
    }
    
    /// Resume media playback and enable interactions
    @MainActor
    mutating func resume() {
        guard let browserView = BrowserManager.shared.existingBrowser(for: browserId) else { return }
        
        // JavaScript to unmute media and restore pointer events
        let resumeScript = """
        (function() {
            document.querySelectorAll('video, audio').forEach(m => {
                m.muted = false;
            });
            // Re-enable pointer events
            document.body.style.pointerEvents = 'auto';
        })();
        """
        
        if let handle = browserView.cefBrowserHandle {
            cef_execute_javascript(handle, resumeScript)
        }
    }
}
