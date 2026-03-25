// FramelessWindowIntegration.swift - AppKit/SwiftUI Integration Layer
// Swift 6.2 demonstrating how to wire FramelessWindow with SwiftUI views
// This file shows the recommended integration patterns

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Window Host Controller
// =============================================================================

/// A hosting controller that integrates FramelessWindow with SwiftUI content.
///
/// This controller:
/// 1. Creates and manages a FramelessWindow
/// 2. Injects the TrafficLightStateCoordinator into the SwiftUI environment
/// 3. Handles coordinator lifecycle
///
/// ## Usage in AppDelegate
/// ```swift
/// let host = FramelessWindowHostController(
///     rootView: AppShellView(browserState: browserState),
///     configuration: .arcBrowser
/// )
/// host.showWindow()
/// ```
@MainActor
public final class FramelessWindowHostController<Content: View> {
    
    // MARK: - Properties
    
    /// The frameless window
    public let window: FramelessWindow
    
    /// The traffic light coordinator (shared with SwiftUI)
    public let trafficLightCoordinator: TrafficLightStateCoordinator
    
    /// The hosting controller for SwiftUI content
    private let hostingController: NSHostingController<EnvironmentWrappedView<Content>>
    
    // MARK: - Initialization
    
    /// Initialize with SwiftUI content and configuration.
    ///
    /// - Parameters:
    ///   - rootView: The root SwiftUI view
    ///   - configuration: Frameless window configuration
    ///   - coordinator: Optional existing coordinator (creates new if nil)
    public init(
        rootView: Content,
        configuration: FramelessWindowConfiguration = .arcBrowser,
        coordinator: TrafficLightStateCoordinator? = nil
    ) {
        // Create or use provided coordinator
        self.trafficLightCoordinator = coordinator ?? TrafficLightStateCoordinator(
            configuration: configuration.trafficLightConfiguration
        )
        
        // Create the frameless window
        self.window = FramelessWindow.createWindow(
            configuration: configuration,
            contentRect: NSRect(
                x: 0, y: 0,
                width: configuration.initialSize.width,
                height: configuration.initialSize.height
            ),
            coordinator: self.trafficLightCoordinator
        )
        
        // Wrap the root view with environment injection
        let wrappedView = EnvironmentWrappedView(
            content: rootView,
            coordinator: self.trafficLightCoordinator
        )
        
        // Create hosting controller
        self.hostingController = NSHostingController(rootView: wrappedView)
        
        // Set as window's content view controller
        window.contentViewController = hostingController
    }
    
    // MARK: - Window Management
    
    /// Show the window centered on screen.
    public func showWindow() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Close the window.
    public func closeWindow() {
        window.close()
    }
    
    /// Update the root view content.
    /// - Parameter newContent: The new SwiftUI view to display
    public func updateContent(_ newContent: Content) {
        let wrappedView = EnvironmentWrappedView(
            content: newContent,
            coordinator: trafficLightCoordinator
        )
        hostingController.rootView = wrappedView
    }
}

// =============================================================================
// MARK: - Environment Wrapped View
// =============================================================================

/// Internal view wrapper that injects the coordinator into the environment.
struct EnvironmentWrappedView<Content: View>: View {
    let content: Content
    let coordinator: TrafficLightStateCoordinator
    
    var body: some View {
        content
            .trafficLightCoordinator(coordinator)
    }
}

// =============================================================================
// MARK: - Example Integration with Existing AppDelegate
// =============================================================================

/// Example showing how to integrate with an existing AppDelegate.
///
/// Replace the existing `createMainWindow()` method with this pattern:
///
/// ```swift
/// @MainActor
/// final class AppDelegate: NSObject, NSApplicationDelegate {
///
///     private var windowHost: FramelessWindowHostController<AppShellView>?
///     private let browserState = BrowserState()
///
///     func applicationDidFinishLaunching(_ notification: Notification) {
///         // ... other initialization ...
///
///         // Create window using the new integration pattern
///         createMainWindowWithFrameless()
///     }
///
///     private func createMainWindowWithFrameless() {
///         let shellView = AppShellView(browserState: browserState)
///
///         windowHost = FramelessWindowHostController(
///             rootView: shellView,
///             configuration: .arcBrowser
///         )
///
///         windowHost?.showWindow()
///     }
/// }
/// ```

// =============================================================================
// MARK: - Alternative: Direct Window Integration
// =============================================================================

/// For cases where you want more control, you can integrate directly.
///
/// This approach is useful when:
/// - You need to reuse an existing NSHostingController
/// - You want to manage the coordinator lifecycle separately
/// - You're integrating with legacy code
///
/// ```swift
/// // In AppDelegate
/// private var mainWindow: FramelessWindow?
/// private var trafficLightCoordinator: TrafficLightStateCoordinator?
///
/// private func createMainWindow() {
///     // 1. Create coordinator
///     let coordinator = TrafficLightStateCoordinator()
///     self.trafficLightCoordinator = coordinator
///
///     // 2. Create frameless window
///     let window = FramelessWindow.arcStyleWindow(coordinator: coordinator)
///     self.mainWindow = window
///
///     // 3. Create SwiftUI view with coordinator injected
///     let shellView = AppShellView(browserState: browserState)
///         .trafficLightCoordinator(coordinator)
///
///     let hostingController = NSHostingController(rootView: shellView)
///     window.contentViewController = hostingController
///
///     // 4. Show window
///     window.center()
///     window.makeKeyAndOrderFront(nil)
/// }
/// ```

// =============================================================================
// MARK: - Sidebar Integration Example
// =============================================================================

/// Example showing how to use SidebarHeaderView with TrafficLightLayoutConfig.
///
/// The key to synchronized layout is using the same `TrafficLightLayoutConfig`
/// instance for both AppKit (window) and SwiftUI (header view):
///
/// ```swift
/// struct ArcSidebarView: View {
///     @Bindable var browserState: BrowserState
///     @Binding var showCommandBar: Bool
///     var isFullScreen: Bool
///     
///     @State private var isSidebarCollapsed = false
///     
///     /// Layout config - single source of truth
///     private var layoutConfig: TrafficLightLayoutConfig {
///         isFullScreen ? .fullscreen : .arcBrowser
///     }
///
///     var body: some View {
///         VStack(spacing: 0) {
///             // Header uses same config as FramelessWindow
///             SidebarHeaderView(
///                 browserState: browserState,
///                 layoutConfig: layoutConfig,
///                 isSidebarCollapsed: $isSidebarCollapsed
///             )
///             
///             // Rest of sidebar content
///             sidebarURLBarSection
///             tabListSection
///             Spacer()
///         }
///         .trafficLightLayoutConfig(layoutConfig)
///     }
/// }
/// ```

// =============================================================================
// MARK: - TrafficLightLayoutConfig Integration
// =============================================================================

/// The TrafficLightLayoutConfig serves as the **single source of truth** for layout:
///
/// ## Creating a Window with Config
/// ```swift
/// let layoutConfig = TrafficLightLayoutConfig.arcBrowser
/// let window = FramelessWindow.arcStyleWindow(layoutConfig: layoutConfig)
/// ```
///
/// ## Applying Config to Existing Window
/// ```swift
/// window.applyTrafficLightLayout(.fullscreen)  // For fullscreen mode
/// window.applyTrafficLightLayout(.arcBrowser)  // For normal mode
/// ```
///
/// ## Using Config in SwiftUI
/// ```swift
/// @Environment(\.trafficLightLayoutConfig) var layoutConfig
///
/// var body: some View {
///     // Reserved space matches AppKit traffic light positions
///     Color.clear.frame(width: layoutConfig.reservedWidth)
/// }
/// ```

// =============================================================================
// MARK: - Coordinator Communication Patterns
// =============================================================================

/// The TrafficLightStateCoordinator enables two-way communication:
///
/// ## SwiftUI → AppKit (Position Updates)
/// ```swift
/// // In a SwiftUI view
/// @Environment(\.trafficLightCoordinator) var coordinator
///
/// Button("Compact Mode") {
///     coordinator?.applyPreset(.compactUtility)
/// }
/// ```
///
/// ## AppKit → SwiftUI (State Observation)
/// ```swift
/// // In a SwiftUI view
/// @Environment(\.trafficLightCoordinator) var coordinator
///
/// var body: some View {
///     // Read current spacer height
///     let height = coordinator?.reservedSpacerHeight ?? 52
///
///     Spacer()
///         .frame(height: height)
/// }
/// ```
///
/// ## Fullscreen Coordination
/// The coordinator automatically handles fullscreen transitions:
/// 1. FramelessWindow detects fullscreen entry/exit
/// 2. Applies appropriate TrafficLightLayoutConfig (.fullscreen or .arcBrowser)
/// 3. Posts notification for SwiftUI views to update
/// 4. SwiftUI views observe layout config via environment and adjust
