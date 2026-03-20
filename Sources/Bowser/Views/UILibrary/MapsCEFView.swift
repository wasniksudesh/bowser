//
//  MapsCEFView.swift
//  Bowser
//
//  Lightweight CEF container for displaying maps
//  Simplified version without tab/page management
//

import AppKit
import CEFWrapper
import SwiftUI

// =============================================================================
// MARK: - Maps CEF View (NSViewRepresentable)
// =============================================================================

/// SwiftUI wrapper for the maps CEF container
struct MapsCEFView: NSViewRepresentable {
    let url: String
    
    func makeNSView(context: Context) -> MapsCEFContainerView {
        let view = MapsCEFContainerView()
        if let url = URL(string: url) {
            view.loadURL(url)
        }
        return view
    }
    
    func updateNSView(_ nsView: MapsCEFContainerView, context: Context) {
        // Update URL if changed
        if nsView.currentURLString != url, let newURL = URL(string: url) {
            nsView.loadURL(newURL)
        }
    }
}

// =============================================================================
// MARK: - Maps CEF Container View (NSView)
// =============================================================================

/// Lightweight CEF container specifically for maps display
/// Does not participate in tab/page management system
@MainActor
class MapsCEFContainerView: NSView {
    
    /// CEF browser handle (opaque pointer from cef_shim)
    /// Marked as nonisolated(unsafe) to allow access from deinit
    private nonisolated(unsafe) var cefBrowserHandle: CefBrowserHandle?
    
    /// Whether the browser has been created
    private var browserCreated: Bool = false
    
    /// Pending URL to load after browser is created
    private var pendingURL: URL?
    
    /// Current URL string (for change detection)
    private(set) var currentURLString: String = ""
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // Configure view for CEF hosting
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Enable layer-backed view for better compositing with CEF
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Note: CEF message loop is handled globally by AppDelegate
        // No need for per-view message loop timer
        
        // Register for frame change notifications (for resize handling)
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: self
        )
        
        print("[MapsCEFView] Container initialized")
    }
    
    deinit {
        // Destroy CEF browser
        if let handle = cefBrowserHandle {
            cef_destroy_browser(handle)
            print("[MapsCEFView] CEF browser destroyed")
        }
        
        NotificationCenter.default.removeObserver(self)
        print("[MapsCEFView] Container deallocated")
    }
    
    // MARK: - URL Loading
    
    /// Load a URL in the CEF browser
    func loadURL(_ url: URL) {
        guard url.absoluteString != currentURLString else {
            print("[MapsCEFView] URL unchanged, skipping load: \(url.absoluteString)")
            return
        }
        
        if browserCreated {
            navigateToURL(url)
        } else {
            pendingURL = url
            createBrowser(with: url)
        }
    }
    
    /// Create the CEF browser instance
    private func createBrowser(with url: URL) {
        guard !browserCreated else {
            print("[MapsCEFView] Browser already created")
            return
        }
        
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else {
            print("[MapsCEFView] Invalid size, deferring browser creation")
            pendingURL = url
            return
        }
        
        print("[MapsCEFView] Creating CEF browser with URL: \(url.absoluteString)")
        print("[MapsCEFView] Size: \(Int(size.width))x\(Int(size.height))")
        
        // Create browser with this view as the parent container
        // CEF will create its own child NSView for rendering
        let handle = url.absoluteString.withCString { urlCString in
            cef_create_browser(
                Unmanaged.passUnretained(self).toOpaque(),
                urlCString,
                Int32(size.width),
                Int32(size.height),
                0  // Enable swipe navigation for maps
            )
        }
        
        if let handle = handle {
            cefBrowserHandle = handle
            browserCreated = true
            currentURLString = url.absoluteString
            
            print("[MapsCEFView] CEF browser created successfully")
            
            // Configure CEF's internal NSView for proper autoresizing
            configureCEFBrowserViewAutoresizing(handle: handle)
            
            // Default zoom to 70% (CEF zoom level is log2 scale: 0 = 100%, log2(0.7) ≈ 70%)
            cef_set_zoom_level(handle, log2(0.7))
        } else {
            print("[MapsCEFView] Failed to create CEF browser")
        }
    }
    
    /// Navigate to a URL in the existing browser
    private func navigateToURL(_ url: URL) {
        guard let handle = cefBrowserHandle else { return }
        
        print("[MapsCEFView] Navigating to: \(url.absoluteString)")
        
        currentURLString = url.absoluteString
        
        url.absoluteString.withCString { urlCString in
            cef_navigate_to_url(handle, urlCString)
        }
    }
    
    // MARK: - Resize Handling
    
    @objc private func frameDidChange(_ notification: Notification) {
        notifyResize()
    }
    
    /// Notify CEF about a resize
    func notifyResize() {
        guard let handle = cefBrowserHandle else { return }
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }
        
        cef_resize_browser(handle, Int32(size.width), Int32(size.height))
    }
    
    override func layout() {
        super.layout()
        
        // If we have a pending URL and valid size, create the browser now
        if !browserCreated, let url = pendingURL, bounds.size.width > 0, bounds.size.height > 0 {
            createBrowser(with: url)
            pendingURL = nil
        }
        
        // Notify CEF of layout changes
        notifyResize()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if window != nil {
            // View added to window - ensure browser is created
            if !browserCreated, let url = pendingURL {
                createBrowser(with: url)
                pendingURL = nil
            }
        }
    }
    
    // MARK: - CEF Browser View Autoresizing
    
    /// Configure autoresizing for CEF's internal browser NSView
    private func configureCEFBrowserViewAutoresizing(handle: CefBrowserHandle) {
        // Get the CEF browser view (CEF creates it as a child of our container)
        guard let browserView = cef_get_browser_view(handle) else {
            print("[MapsCEFView] WARNING: Could not get CEF browser view for autoresizing")
            return
        }
        
        // Convert opaque pointer to NSView
        let nsView = Unmanaged<NSView>.fromOpaque(browserView).takeUnretainedValue()
        
        // Set autoresizing mask to resize with both width and height
        nsView.autoresizingMask = [.width, .height]
        
        print("[MapsCEFView] ✓ CEF browser view autoresizing configured: [.width, .height]")
    }
}
