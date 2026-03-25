// AppDelegate.swift - AppKit Lifecycle & Window Host
// Swift 6.2 with @MainActor isolation for thread safety
// Uses FramelessWindow for Arc-style chrome and AppShellView for layout

import AppKit
import CEFWrapper
import SwiftUI

// =============================================================================
// MARK: - App Delegate
// =============================================================================

/// Main application delegate handling lifecycle, window creation, and CEF initialization.
/// Uses @MainActor for strict UI thread isolation per Swift 6.2 concurrency model.
///
/// ## Architecture
/// - **FramelessWindow**: Custom NSWindow subclass (in FramelessWindow.swift) that handles
///   transparent titlebar and traffic light repositioning using TrafficLightLayoutConfig.
/// - **AppShellView**: Root SwiftUI view (in AppShellView.swift) implementing Arc-style
///   sidebar-first layout with NavigationSplitView.
/// - **TrafficLightLayoutConfig**: Single source of truth for both AppKit button positioning
///   and SwiftUI spacer sizing, ensuring synchronized layout.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Main application window with custom frameless chrome
    private var mainWindow: NSWindow?

    /// Settings window
    private var settingsWindow: NSWindow?

    /// Reference to the hosting controller for SwiftUI content
    private var hostingController: NSViewController?

    /// Browser state managed by @Observable
    private let browserState = BrowserState()

    /// Top-level navigation state (homescreen vs browser)
    private let appNav = AppNavigationState()

    /// Timer for pumping CEF message loop
    private var cefMessageLoopTimer: Timer?

    /// Task handle for the daily license re-verification loop
    private var licenseCheckTask: Task<Void, Never>?

    /// Whether CEF was successfully initialized
    private var cefInitialized: Bool = false

    /// Browser engine abstraction (wraps CEF)
    private var browserEngine: (any BrowserEngineProtocol)?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Bowser] Application launching...")

        // Initialize browser engine using factory pattern
        // This wraps CEF via the abstraction layer
        browserEngine = BrowserEngineFactory.createDefault()

        // Initialize CEF before creating any browser views
        initializeCEF()

        // Create the main window with Arc-style chrome
        createMainWindow()

        // Initialize floating dock
        FloatingDockManager.shared.initialize(browserState: browserState)

        // Setup settings observer
        setupSettingsObserver()

        // Set up application menu with keyboard shortcuts

        // Set up application menu with keyboard shortcuts
        setupApplicationMenu()

        // Start the Python AI sidecar health check
        Task {
            await checkSidecarHealth()
        }

        // Start daily license re-verification
        startDailyLicenseCheck()

        print("[Bowser] Application ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[Bowser] Application terminating...")

        // Persist current folder tabs before shutdown
        browserState.saveCurrentFolder()

        // Cancel daily license check
        licenseCheckTask?.cancel()
        licenseCheckTask = nil

        // Stop CEF message loop timer first
        cefMessageLoopTimer?.invalidate()
        cefMessageLoopTimer = nil

        // Close all windows to trigger proper view cleanup
        mainWindow?.close()
        settingsWindow?.close()
        
        // Give views time to clean up their event monitors
        Thread.sleep(forTimeInterval: 0.1)

        // Shutdown browser engine abstraction layer
        if let engine = browserEngine {
            // Use a semaphore to wait for async shutdown to complete
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await engine.shutdown()
                semaphore.signal()
            }
            // Wait up to 2 seconds for shutdown to complete
            _ = semaphore.wait(timeout: .now() + 2.0)
        }

        // Clean up CEF resources (backup - engine.shutdown() handles this too)
        shutdownCEF()

        print("[Bowser] Cleanup complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - CEF Initialization

    private func initializeCEF() {
        print("[Bowser] Initializing CEF...")

        // Determine the path to the CEF framework
        let frameworkPath = findCEFFrameworkPath()
        print("[Bowser] CEF Framework path: \(frameworkPath ?? "not found")")

        // Initialize CEF using the C shim
        let result: Int32
        if let path = frameworkPath {
            result = path.withCString { cString in
                cef_simple_initialize_with_path(cString)
            }
        } else {
            result = cef_simple_initialize()
        }

        if result == 1 {
            cefInitialized = true
            print("[Bowser] CEF initialized successfully")

            // Start message loop timer (CEF needs regular message pumping)
            // This integrates CEF's message loop with macOS's run loop
            cefMessageLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true)
            { _ in
                cef_do_message_work()
            }
        } else {
            print("[Bowser] CEF initialization failed!")
            print(
                "[Bowser] Ensure CEF framework is at: Vendor/cef/Release/Chromium Embedded Framework.framework"
            )
        }
    }

    /// Find the CEF framework path
    private func findCEFFrameworkPath() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()

        // Priority 1: Check for bundled framework (for built .app)
        // This is at: Bowser.app/Contents/Frameworks/Chromium Embedded Framework.framework
        let bundledFrameworkPath = executableDir.appendingPathComponent(
            "../Frameworks/Chromium Embedded Framework.framework"
        ).path
        let standardizedBundledPath = (bundledFrameworkPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: standardizedBundledPath) {
            return standardizedBundledPath
        }

        // Priority 2: Check Bundle.main (alternative bundled location)
        if let bundlePath = Bundle.main.path(
            forResource: "Chromium Embedded Framework", ofType: "framework")
        {
            return bundlePath
        }

        // Priority 3: Development paths (for running from Xcode/.build)
        let devPaths = [
            executableDir.appendingPathComponent(
                "../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            executableDir.appendingPathComponent(
                "../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            executableDir.appendingPathComponent(
                "../../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            "./Vendor/cef/Release/Chromium Embedded Framework.framework",
        ]

        for path in devPaths {
            // Convert to absolute path using URL (handles both relative and absolute paths)
            let url = URL(fileURLWithPath: path)
            let absolutePath = url.path

            if FileManager.default.fileExists(atPath: absolutePath) {
                return absolutePath
            }
        }

        return nil
    }

    private func shutdownCEF() {
        guard cefInitialized else { return }

        print("[Bowser] Shutting down CEF...")
        cef_simple_shutdown()
        cefInitialized = false
        print("[Bowser] CEF shutdown complete")
    }

    // MARK: - Window Creation

    /// Create the main browser window with Arc-style frameless chrome.
    ///
    /// Uses `FramelessWindow.arcStyleWindow()` factory method which configures:
    /// - Transparent titlebar with hidden title
    /// - Repositioned traffic lights (Close/Minimize/Zoom) via TrafficLightLayoutConfig
    /// - Full-size content view for edge-to-edge rendering
    ///
    /// ## Traffic Light Synchronization
    /// The `TrafficLightLayoutConfig.arcBrowser` configuration is the **single source
    /// of truth** used by both:
    /// 1. AppKit (`FramelessWindow.applyTrafficLightLayout`) - positions NSButtons
    /// 2. SwiftUI (`SidebarHeaderView`) - reserves spacer width/height
    ///
    /// This ensures the SwiftUI sidebar header reserves exactly the right space
    /// for the AppKit traffic lights to sit without overlap.
    private func createMainWindow() {
        // Define the shared layout configuration (single source of truth)
        let layoutConfig = TrafficLightLayoutConfig.arcBrowser

        // Create Arc-style frameless window using factory method
        let window = FramelessWindow.arcStyleWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            layoutConfig: layoutConfig
        )

        // Create root view: switches between homescreen and browser
        // The AppShellView → ArcSidebarView → SidebarHeaderView chain uses
        // the same TrafficLightLayoutConfig for synchronized spacing
        let shellView = RootView(appNav: appNav, browserState: browserState)
            .trafficLightLayoutConfig(layoutConfig)

        let hostingController = NSHostingController(rootView: shellView)

        // Set the hosting controller's view as window content
        window.contentViewController = hostingController

        // Center and show window
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Activate the application to ensure window is visible
        NSApp.activate(ignoringOtherApps: true)

        // Store references
        self.mainWindow = window
        self.hostingController = hostingController

        print("[Bowser] Main window created with Arc-style frameless sidebar-first layout")
        print(
            "[Bowser] Traffic light config: xOffset=\(layoutConfig.xOffset), yOffset=\(layoutConfig.yOffset)"
        )
    }

    // MARK: - Settings Window

    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(forName: .showSettings, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in
                self?.showSettingsWindow()
            }
        }
        NotificationCenter.default.addObserver(forName: .toggleSettings, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in
                self?.toggleSettingsWindow()
            }
        }
    }

    func toggleSettingsWindow() {
        if let window = settingsWindow, window.isVisible {
            window.close()
            return
        }
        showSettingsWindow()
    }

    @objc func showSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(browserState: browserState)
        let controller = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = controller
        window.center()
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Application Menu

    /// Set up the application menu with keyboard shortcuts
    private func setupApplicationMenu() {
        // Get or create main menu
        let mainMenu = NSApp.mainMenu ?? NSMenu()
        NSApp.mainMenu = mainMenu

        // App Menu (Settings)
        if let appMenu = mainMenu.items.first?.submenu {
            appMenu.addItem(NSMenuItem.separator())
            let settingsItem = NSMenuItem(
                title: "Settings…",
                action: #selector(showSettingsWindow),
                keyEquivalent: ","
            )
            settingsItem.keyEquivalentModifierMask = .command
            settingsItem.target = self
            appMenu.addItem(settingsItem)
        }

        // File Menu
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu

        // New Tab (CMD+T) - Opens Command Bar
        let newTabItem = NSMenuItem(
            title: "New Tab",
            action: #selector(handleNewTab),
            keyEquivalent: "t"
        )
        newTabItem.keyEquivalentModifierMask = .command
        newTabItem.target = self
        fileMenu.addItem(newTabItem)

        // Open Location (CMD+L) - Focus Address Bar / Open Command Bar
        let openLocationItem = NSMenuItem(
            title: "Open Location…",
            action: #selector(handleOpenLocation),
            keyEquivalent: "l"
        )
        openLocationItem.keyEquivalentModifierMask = .command
        openLocationItem.target = self
        fileMenu.addItem(openLocationItem)

        fileMenu.addItem(NSMenuItem.separator())

        // Close Tab (CMD+W)
        let closeTabItem = NSMenuItem(
            title: "Close Tab",
            action: #selector(handleCloseTab),
            keyEquivalent: "w"
        )
        closeTabItem.keyEquivalentModifierMask = .command
        closeTabItem.target = self
        fileMenu.addItem(closeTabItem)

        // Add File menu to main menu if not already present
        if !mainMenu.items.contains(where: { $0.title == "File" }) {
            // Insert after App menu (index 1) or at start
            let insertIndex = mainMenu.items.isEmpty ? 0 : min(1, mainMenu.items.count)
            mainMenu.insertItem(fileMenuItem, at: insertIndex)
        }

        // Edit Menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu

        // Undo (CMD+Z) — nil target lets the responder chain handle it (CEF, TextField, etc.)
        let undoItem = NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = .command
        editMenu.addItem(undoItem)

        // Redo (Shift+CMD+Z)
        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())

        // Cut (CMD+X) — standard selector, nil target → responder chain
        let cutItem = NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        cutItem.keyEquivalentModifierMask = .command
        editMenu.addItem(cutItem)

        // Copy (CMD+C)
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = .command
        editMenu.addItem(copyItem)

        // Paste (CMD+V)
        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = .command
        editMenu.addItem(pasteItem)

        editMenu.addItem(NSMenuItem.separator())

        // Select All (CMD+A)
        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = .command
        editMenu.addItem(selectAllItem)

        editMenu.addItem(NSMenuItem.separator())

        // Find (CMD+F)
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(handleFind),
            keyEquivalent: "f"
        )
        findItem.keyEquivalentModifierMask = .command
        findItem.target = self
        editMenu.addItem(findItem)

        // Add Edit menu to main menu
        mainMenu.addItem(editMenuItem)

        // View Menu
        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewMenuItem.submenu = viewMenu

        // Reload (CMD+R)
        let reloadItem = NSMenuItem(
            title: "Reload Page",
            action: #selector(handleReload),
            keyEquivalent: "r"
        )
        reloadItem.keyEquivalentModifierMask = .command
        reloadItem.target = self
        viewMenu.addItem(reloadItem)

        viewMenu.addItem(NSMenuItem.separator())

        // Zoom In (CMD++)
        let zoomInItem = NSMenuItem(
            title: "Zoom In",
            action: #selector(handleZoomIn),
            keyEquivalent: "+"
        )
        zoomInItem.keyEquivalentModifierMask = .command
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        // Zoom Out (CMD-)
        let zoomOutItem = NSMenuItem(
            title: "Zoom Out",
            action: #selector(handleZoomOut),
            keyEquivalent: "-"
        )
        zoomOutItem.keyEquivalentModifierMask = .command
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        // Actual Size (CMD0)
        let resetZoomItem = NSMenuItem(
            title: "Actual Size",
            action: #selector(handleResetZoom),
            keyEquivalent: "0"
        )
        resetZoomItem.keyEquivalentModifierMask = .command
        resetZoomItem.target = self
        viewMenu.addItem(resetZoomItem)

        // Add View menu to main menu
        mainMenu.addItem(viewMenuItem)

        // History Menu
        let historyMenu = NSMenu(title: "History")
        let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyMenuItem.submenu = historyMenu

        // Back (CMD+[)
        let backItem = NSMenuItem(
            title: "Back",
            action: #selector(handleGoBack),
            keyEquivalent: "["
        )
        backItem.keyEquivalentModifierMask = .command
        backItem.target = self
        historyMenu.addItem(backItem)

        // Forward (CMD+])
        let forwardItem = NSMenuItem(
            title: "Forward",
            action: #selector(handleGoForward),
            keyEquivalent: "]"
        )
        forwardItem.keyEquivalentModifierMask = .command
        forwardItem.target = self
        historyMenu.addItem(forwardItem)

        // Add History menu to main menu
        mainMenu.addItem(historyMenuItem)

        // Window Menu (for Print)
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu

        // Print (CMD+P)
        let printItem = NSMenuItem(
            title: "Print…",
            action: #selector(handlePrint),
            keyEquivalent: "p"
        )
        printItem.keyEquivalentModifierMask = .command
        printItem.target = self
        windowMenu.addItem(printItem)

        // Add Window menu to main menu
        mainMenu.addItem(windowMenuItem)

        print("[Bowser] Application menu configured with keyboard shortcuts")
    }

    // MARK: - Menu Actions

    /// Handle CMD+T - New Tab (opens Command Bar)
    @objc private func handleNewTab() {
        NotificationCenter.default.post(name: .newTab, object: nil)
    }

    /// Handle CMD+L - Open Location (opens Command Bar)
    @objc private func handleOpenLocation() {
        NotificationCenter.default.post(name: .focusAddressBar, object: nil)
    }

    /// Handle CMD+W - Close current tab
    @objc private func handleCloseTab() {
        if let activeTab = browserState.activeTab {
            browserState.closeTab(activeTab)
        }
    }

    // MARK: - Edit Menu Actions

    /// Handle CMD+Z - Undo
    @objc private func handleUndo() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.undo(pageId: activeTab.id)
    }

    /// Handle Shift+CMD+Z - Redo
    @objc private func handleRedo() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.redo(pageId: activeTab.id)
    }

    /// Handle CMD+X - Cut
    @objc private func handleCut() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.cut(pageId: activeTab.id)
    }

    /// Handle CMD+C - Copy
    @objc private func handleCopy() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.copy(pageId: activeTab.id)
    }

    /// Handle CMD+V - Paste
    @objc private func handlePaste() {
        guard let activeTab = browserState.activeTab else { return }
        
        // Check if redactor is enabled
        if browserState.settingsManager.redactorEnabled {
            // Redact clipboard content asynchronously before pasting
            Task { @MainActor in
                _ = await RedactorService.shared.redactClipboardContent()
                // Paste the (potentially redacted) content
                BrowserManager.shared.paste(pageId: activeTab.id)
            }
        } else {
            // Paste directly without redaction
            BrowserManager.shared.paste(pageId: activeTab.id)
        }
    }

    /// Handle CMD+A - Select All
    @objc private func handleSelectAll() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.selectAll(pageId: activeTab.id)
    }

    /// Handle CMD+F - Find
    @objc private func handleFind() {
        // TODO: Implement find in page functionality
        print("[Bowser] Find in page not yet implemented")
    }

    // MARK: - View Menu Actions

    /// Handle CMD+R - Reload
    @objc private func handleReload() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.reload(pageId: activeTab.id)
    }

    /// Handle CMD++ - Zoom In
    @objc private func handleZoomIn() {
        NotificationCenter.default.post(name: .zoomIn, object: nil)
    }

    /// Handle CMD+- - Zoom Out
    @objc private func handleZoomOut() {
        NotificationCenter.default.post(name: .zoomOut, object: nil)
    }

    /// Handle CMD+0 - Reset Zoom
    @objc private func handleResetZoom() {
        NotificationCenter.default.post(name: .resetZoom, object: nil)
    }

    // MARK: - History Menu Actions

    /// Handle CMD+[ - Go Back
    @objc private func handleGoBack() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.goBack(pageId: activeTab.id)
    }

    /// Handle CMD+] - Go Forward
    @objc private func handleGoForward() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.goForward(pageId: activeTab.id)
    }

    // MARK: - Window Menu Actions

    /// Handle CMD+P - Print
    @objc private func handlePrint() {
        guard let activeTab = browserState.activeTab else { return }
        BrowserManager.shared.printPage(pageId: activeTab.id)
    }

    // MARK: - License Re-verification

    private func startDailyLicenseCheck() {
        let interval: TimeInterval = 24 * 60 * 60  // 24 hours
        licenseCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }

                let valid = await LicenseService.shared.checkStoredLicense()
                if !valid {
                    print("[Bowser] Daily license check failed — grace period may have expired")
                    await MainActor.run {
                        NotificationCenter.default.post(name: .licenseRevoked, object: nil)
                    }
                } else {
                    print("[Bowser] Daily license check passed")
                }
            }
        }
    }

    // MARK: - Backend Connection (Dev/Production)

    /// Check backend health and connect (VM in production, TCP in dev)
    private func checkSidecarHealth() async {
        let backendService = BackendService.shared

        do {
            print("[Bowser] Starting backend service in \(backendService.mode) mode...")
            try await backendService.start()

            if backendService.isConnected {
                print("[Bowser] Backend connected successfully")
                browserState.isSidecarConnected = true
            } else {
                print("[Bowser] Backend connection failed")
                if let error = backendService.connectionError {
                    print("[Bowser] Error: \(error)")
                }
            }
        } catch {
            print("[Bowser] Backend start failed: \(error.localizedDescription)")

            // Show helpful message based on mode
            if backendService.mode == .development {
                print("[Bowser] Start the backend with: ./run_dev.sh")
            } else {
                print("[Bowser] Production mode: VM failed to start")
            }
        }
    }
}
