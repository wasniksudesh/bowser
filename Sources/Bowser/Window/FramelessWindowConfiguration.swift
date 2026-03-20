// FramelessWindowConfiguration.swift - Frameless Window Protocol & Configuration
// Swift 6.2 with protocol-oriented design for extensibility
// Enables reusable frameless window capability across different window types

import AppKit

// =============================================================================
// MARK: - Frameless Window Protocol
// =============================================================================

/// Protocol defining the requirements for a frameless, edge-to-edge window.
///
/// Implement this protocol to create windows with:
/// - Transparent/invisible title bar
/// - Full-size content view (content extends behind titlebar)
/// - Repositioned traffic lights (Close/Minimize/Zoom)
/// - Custom window chrome
///
/// ## Conforming Types
/// - `FramelessWindow`: Main implementation for browser windows
/// - Could be extended for: SettingsWindow, DevToolsWindow, etc.
@MainActor
public protocol FramelessWindowProtocol: AnyObject {
    
    /// The traffic light state coordinator managing button positions
    var trafficLightCoordinator: TrafficLightStateCoordinator { get }
    
    /// Apply frameless window configuration
    func applyFramelessConfiguration(_ config: FramelessWindowConfiguration)
    
    /// Reposition traffic lights to their configured positions
    func repositionTrafficLights()
    
    /// Set traffic light visibility
    func setTrafficLightsVisible(_ visible: Bool)
}

// =============================================================================
// MARK: - Frameless Window Configuration
// =============================================================================

/// Configuration for frameless window appearance and behavior.
///
/// This struct encapsulates all the settings needed to create an Arc-style
/// frameless window. It can be customized for different window types:
/// - Browser windows (main app)
/// - Settings windows
/// - DevTools windows
/// - Picture-in-picture windows
public struct FramelessWindowConfiguration: Equatable, Sendable {
    
    // MARK: - Appearance
    
    /// Background color for the window
    /// This is the base layer that sits behind vibrancy effects
    public var backgroundColor: NSColor
    
    /// Whether the titlebar should appear transparent
    public var titlebarAppearsTransparent: Bool
    
    /// Whether the window title should be hidden
    public var hideTitlebar: Bool
    
    /// Whether the window is movable by clicking its background
    public var isMovableByWindowBackground: Bool
    
    // MARK: - Size Constraints
    
    /// Minimum window size
    public var minSize: NSSize
    
    /// Initial window size (used when creating new windows)
    public var initialSize: NSSize
    
    // MARK: - Traffic Light Configuration
    
    /// Configuration for traffic light button positioning
    public var trafficLightConfiguration: TrafficLightConfiguration
    
    // MARK: - Behavior
    
    /// Whether the window should be released when closed
    public var isReleasedWhenClosed: Bool
    
    /// Whether to automatically reposition traffic lights on resize
    public var autoRepositionTrafficLights: Bool
    
    // MARK: - Preset Configurations
    
    /// Arc-style browser window configuration.
    /// Full-size content, transparent titlebar, repositioned traffic lights.
    public static let arcBrowser = FramelessWindowConfiguration(
        backgroundColor: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.95, alpha: 1.0),
        titlebarAppearsTransparent: true,
        hideTitlebar: true,
        isMovableByWindowBackground: true,
        minSize: NSSize(width: 800, height: 600),
        initialSize: NSSize(width: 1280, height: 800),
        trafficLightConfiguration: .arcBrowserDefault,
        isReleasedWhenClosed: false,
        autoRepositionTrafficLights: true
    )
    
    /// Settings window configuration.
    /// Smaller window, compact traffic lights.
    public static let settings = FramelessWindowConfiguration(
        backgroundColor: NSColor.windowBackgroundColor,
        titlebarAppearsTransparent: true,
        hideTitlebar: true,
        isMovableByWindowBackground: true,
        minSize: NSSize(width: 600, height: 400),
        initialSize: NSSize(width: 700, height: 500),
        trafficLightConfiguration: .compactUtility,
        isReleasedWhenClosed: true,
        autoRepositionTrafficLights: true
    )
    
    /// DevTools window configuration.
    /// Taller aspect ratio, utility positioning.
    public static let devTools = FramelessWindowConfiguration(
        backgroundColor: NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.16, alpha: 1.0),
        titlebarAppearsTransparent: true,
        hideTitlebar: true,
        isMovableByWindowBackground: true,
        minSize: NSSize(width: 600, height: 500),
        initialSize: NSSize(width: 900, height: 700),
        trafficLightConfiguration: .compactUtility,
        isReleasedWhenClosed: true,
        autoRepositionTrafficLights: true
    )
    
    // MARK: - Initializer
    
    public init(
        backgroundColor: NSColor,
        titlebarAppearsTransparent: Bool,
        hideTitlebar: Bool,
        isMovableByWindowBackground: Bool,
        minSize: NSSize,
        initialSize: NSSize,
        trafficLightConfiguration: TrafficLightConfiguration,
        isReleasedWhenClosed: Bool,
        autoRepositionTrafficLights: Bool
    ) {
        self.backgroundColor = backgroundColor
        self.titlebarAppearsTransparent = titlebarAppearsTransparent
        self.hideTitlebar = hideTitlebar
        self.isMovableByWindowBackground = isMovableByWindowBackground
        self.minSize = minSize
        self.initialSize = initialSize
        self.trafficLightConfiguration = trafficLightConfiguration
        self.isReleasedWhenClosed = isReleasedWhenClosed
        self.autoRepositionTrafficLights = autoRepositionTrafficLights
    }
}

// =============================================================================
// MARK: - Style Mask Builder
// =============================================================================

/// Helper for building NSWindow.StyleMask for frameless windows.
public struct FramelessStyleMaskBuilder {
    
    /// Build the standard style mask for a frameless window with traffic lights.
    ///
    /// The key styles are:
    /// - `.titled`: Required to show traffic lights
    /// - `.closable`, `.miniaturizable`, `.resizable`: Enable standard buttons
    /// - `.fullSizeContentView`: **Critical** - makes content extend behind titlebar
    ///
    /// - Parameter includeFullScreenSupport: Whether to include fullscreen capability
    /// - Returns: The configured style mask
    public static func build(includeFullScreenSupport: Bool = true) -> NSWindow.StyleMask {
        let mask: NSWindow.StyleMask = [
            .titled,              // Required for traffic lights to appear
            .closable,            // Enable close button
            .miniaturizable,      // Enable minimize button
            .resizable,           // Enable window resizing
            .fullSizeContentView  // Content extends behind titlebar (CRITICAL)
        ]
        
        // Note: fullScreen is handled via toggleFullScreen(), not style mask
        // The fullSizeContentView mask enables edge-to-edge content
        
        return mask
    }
}

// =============================================================================
// MARK: - Window Appearance Applicator
// =============================================================================

/// Applies frameless configuration to an NSWindow instance.
///
/// This is a stateless utility that encapsulates the AppKit configuration
/// logic, keeping it separate from the window class itself.
public struct FramelessWindowApplicator {
    
    /// Apply frameless configuration to a window.
    ///
    /// - Parameters:
    ///   - window: The NSWindow to configure
    ///   - configuration: The frameless configuration to apply
    @MainActor
    public static func apply(
        to window: NSWindow,
        configuration: FramelessWindowConfiguration
    ) {
        // Background color (foundation layer)
        window.backgroundColor = configuration.backgroundColor
        
        // Titlebar appearance - make it fully transparent
        window.titlebarAppearsTransparent = configuration.titlebarAppearsTransparent
        window.titleVisibility = configuration.hideTitlebar ? .hidden : .visible
        
        // CRITICAL: Set titlebar separator style to none for seamless Arc-style
        // This removes the line that separates the titlebar from content
        window.titlebarSeparatorStyle = .none
        
        // Window behavior
        window.isMovableByWindowBackground = configuration.isMovableByWindowBackground
        window.isReleasedWhenClosed = configuration.isReleasedWhenClosed
        
        // Size constraints
        window.minSize = configuration.minSize
        
        // Ensure content view has layer backing for visual effects
        window.contentView?.wantsLayer = true
        
        // Ensure fullSizeContentView is in the style mask
        window.styleMask.insert(.fullSizeContentView)
        
        // Remove any existing toolbar for Arc-style frameless appearance
        window.toolbar = nil
    }
}
