// TrafficLightStateCoordinator.swift - Traffic Light Position Logic Layer
// Swift 6.2 with value semantics for configuration management
// Separates positioning logic from raw window code (Single Responsibility Principle)

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Traffic Light Configuration (Value Type)
// =============================================================================

/// Configuration for traffic light (Close/Minimize/Zoom) button positioning.
///
/// This is a value type that encapsulates all positioning parameters,
/// making it easy to:
/// - Create preset configurations (default, compact, settings window, etc.)
/// - Adjust positions without touching window code
/// - Communicate position requirements from SwiftUI to AppKit
///
/// ## Arc Browser Reference
/// Arc positions traffic lights at approximately (20, 18) from top-left,
/// floating inside the sidebar area while web content extends edge-to-edge.
public struct TrafficLightConfiguration: Equatable, Sendable {
    
    /// Horizontal offset from window's left edge to first button center
    public var xPosition: CGFloat
    
    /// Vertical offset from window's TOP edge to button center
    /// (measured downward, not in window coordinates)
    public var yPositionFromTop: CGFloat
    
    /// Horizontal spacing between traffic light buttons
    public var buttonSpacing: CGFloat
    
    /// Standard button width (macOS traffic lights are 14pt wide)
    public let buttonWidth: CGFloat = 14
    
    /// Total width needed for all three buttons + spacing
    /// Close (14) + spacing + Minimize (14) + spacing + Zoom (14)
    public var totalWidthRequired: CGFloat {
        xPosition + (buttonWidth * 3) + (buttonSpacing * 2)
    }
    
    /// Height required in SwiftUI to reserve space for traffic lights
    /// This accounts for button height plus vertical padding
    public var reservedHeight: CGFloat {
        yPositionFromTop + 16 // 16pt padding below buttons
    }
    
    // MARK: - Preset Configurations
    
    /// Arc-style configuration for main browser window.
    /// Positions traffic lights at (20, 18) from top-left.
    public static let arcBrowserDefault = TrafficLightConfiguration(
        xPosition: 20,
        yPositionFromTop: 18,
        buttonSpacing: 8
    )
    
    /// Compact configuration for utility windows (Settings, DevTools).
    /// Positions traffic lights at (12, 14) - tighter spacing.
    public static let compactUtility = TrafficLightConfiguration(
        xPosition: 12,
        yPositionFromTop: 14,
        buttonSpacing: 6
    )
    
    /// Configuration for fullscreen mode.
    /// Traffic lights appear closer to top since no titlebar exists.
    public static let fullscreen = TrafficLightConfiguration(
        xPosition: 20,
        yPositionFromTop: 14,
        buttonSpacing: 8
    )
    
    /// Standard macOS configuration (for comparison/fallback).
    /// Uses system default positioning.
    public static let systemDefault = TrafficLightConfiguration(
        xPosition: 8,
        yPositionFromTop: 8,
        buttonSpacing: 6
    )
}

// =============================================================================
// MARK: - Traffic Light State (Observable State Container)
// =============================================================================

/// Observable state container for traffic light visibility and configuration.
///
/// This class bridges the gap between SwiftUI state management and AppKit
/// window operations. SwiftUI views can observe and modify this state,
/// and the FramelessWindow responds to changes.
///
/// ## Usage Pattern
/// 1. AppDelegate creates a TrafficLightStateCoordinator
/// 2. SwiftUI views receive it via environment or binding
/// 3. SwiftUI updates configuration when layout changes (e.g., sidebar collapse)
/// 4. FramelessWindow observes changes and repositions buttons
@MainActor
public final class TrafficLightStateCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    /// Current traffic light configuration
    @Published public var configuration: TrafficLightConfiguration {
        didSet {
            // Guard against redundant updates
            if oldValue != configuration {
                notifyConfigurationChange()
            }
        }
    }
    
    /// Whether traffic lights are currently visible
    @Published public var isVisible: Bool = true {
        didSet {
            // Guard against redundant updates to prevent infinite recursion
            // when FramelessWindow syncs its state back to the coordinator
            if oldValue != isVisible {
                notifyVisibilityChange()
            }
        }
    }
    
    /// Whether the window is in fullscreen mode
    @Published public var isFullScreen: Bool = false {
        didSet {
            if oldValue != isFullScreen {
                handleFullScreenTransition()
            }
        }
    }
    
    /// Whether the sidebar is collapsed (affects visibility strategy)
    @Published public var isSidebarCollapsed: Bool = false
    
    // MARK: - Callbacks for AppKit Integration
    
    /// Called when configuration changes - FramelessWindow hooks into this
    public var onConfigurationChanged: ((TrafficLightConfiguration) -> Void)?
    
    /// Called when visibility changes - FramelessWindow hooks into this
    public var onVisibilityChanged: ((Bool) -> Void)?
    
    /// Called when fullscreen state changes
    public var onFullScreenChanged: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    /// Initialize with a specific configuration
    /// - Parameter configuration: Initial traffic light configuration
    public init(configuration: TrafficLightConfiguration = .arcBrowserDefault) {
        self.configuration = configuration
    }
    
    // MARK: - Configuration Updates
    
    /// Update the traffic light position.
    /// Use this for programmatic position changes.
    /// - Parameters:
    ///   - x: Horizontal offset from left edge
    ///   - y: Vertical offset from top edge
    public func setPosition(x: CGFloat, y: CGFloat) {
        var newConfig = configuration
        newConfig.xPosition = x
        newConfig.yPositionFromTop = y
        configuration = newConfig
    }
    
    /// Update spacing between buttons
    /// - Parameter spacing: New button spacing value
    public func setSpacing(_ spacing: CGFloat) {
        var newConfig = configuration
        newConfig.buttonSpacing = spacing
        configuration = newConfig
    }
    
    /// Apply a preset configuration
    /// - Parameter preset: The preset configuration to apply
    public func applyPreset(_ preset: TrafficLightConfiguration) {
        configuration = preset
    }
    
    /// Calculate the height that SwiftUI should reserve for traffic lights
    /// This value should be used as a spacer height in sidebar views
    public var reservedSpacerHeight: CGFloat {
        isFullScreen ? configuration.reservedHeight - 10 : configuration.reservedHeight + 18
    }
    
    // MARK: - Private Methods
    
    private func notifyConfigurationChange() {
        onConfigurationChanged?(configuration)
    }
    
    private func notifyVisibilityChange() {
        onVisibilityChanged?(isVisible)
    }
    
    private func handleFullScreenTransition() {
        // Adjust configuration for fullscreen mode
        if isFullScreen {
            configuration = .fullscreen
        } else {
            configuration = .arcBrowserDefault
        }
        onFullScreenChanged?(isFullScreen)
    }
}

// =============================================================================
// MARK: - Traffic Light Layout Calculator
// =============================================================================

/// Pure function calculator for traffic light button positions.
///
/// This struct contains only pure functions with no side effects,
/// making it easy to test and reason about positioning logic.
public struct TrafficLightLayoutCalculator {
    
    /// Calculate the frame origin for each traffic light button.
    ///
    /// - Parameters:
    ///   - configuration: The traffic light configuration
    ///   - titlebarHeight: Height of the titlebar container view
    ///   - isFlipped: Whether the coordinate system is flipped
    ///   - buttonSize: Size of each button (typically 14x14)
    /// - Returns: Array of CGPoints for [close, minimize, zoom] button origins
    public static func calculateButtonOrigins(
        configuration: TrafficLightConfiguration,
        titlebarHeight: CGFloat,
        isFlipped: Bool,
        buttonSize: CGSize = CGSize(width: 14, height: 14)
    ) -> [CGPoint] {
        // Calculate Y position in titlebar coordinates
        let yPosition: CGFloat
        if isFlipped {
            // Flipped: Y=0 is at top
            yPosition = configuration.yPositionFromTop - (buttonSize.height / 2)
        } else {
            // Non-flipped: Y=0 is at bottom, so calculate from top
            yPosition = titlebarHeight - configuration.yPositionFromTop - (buttonSize.height / 2)
        }
        
        // Calculate X positions for each button
        var xOffset = configuration.xPosition
        var origins: [CGPoint] = []
        
        for _ in 0..<3 {
            let origin = CGPoint(
                x: xOffset - (buttonSize.width / 2),
                y: yPosition
            )
            origins.append(origin)
            xOffset += buttonSize.width + configuration.buttonSpacing
        }
        
        return origins
    }
    
    /// Calculate the minimum sidebar width needed to contain traffic lights.
    ///
    /// - Parameter configuration: The traffic light configuration
    /// - Returns: Minimum sidebar width in points
    public static func minimumSidebarWidth(
        for configuration: TrafficLightConfiguration
    ) -> CGFloat {
        // Total width + 20pt padding for comfortable visual margin
        return configuration.totalWidthRequired + 20
    }
}

// =============================================================================
// MARK: - SwiftUI Environment Key
// =============================================================================

/// Environment key for passing traffic light coordinator to SwiftUI views
private struct TrafficLightCoordinatorKey: EnvironmentKey {
    static let defaultValue: TrafficLightStateCoordinator? = nil
}

extension EnvironmentValues {
    /// The traffic light state coordinator for this view hierarchy
    public var trafficLightCoordinator: TrafficLightStateCoordinator? {
        get { self[TrafficLightCoordinatorKey.self] }
        set { self[TrafficLightCoordinatorKey.self] = newValue }
    }
}

extension View {
    /// Inject a traffic light coordinator into the view hierarchy
    public func trafficLightCoordinator(_ coordinator: TrafficLightStateCoordinator) -> some View {
        environment(\.trafficLightCoordinator, coordinator)
    }
}
