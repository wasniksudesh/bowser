// TrafficLightLayoutConfig.swift - Traffic Light Layout Policy (Data Layer)
// Swift 6.2 with value semantics and single source of truth design
// Separates design constants from implementation logic (Single Responsibility)

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Traffic Light Layout Config (Pure Data / Policy Layer)
// =============================================================================

/// Policy configuration for traffic light positioning and SwiftUI padding synchronization.
///
/// This struct serves as the **single source of truth** for all layout values related to
/// traffic light button positioning and the corresponding SwiftUI spacer/padding values
/// needed to reserve space in the sidebar header.
///
/// ## Architecture (SOLID Principles)
/// - **Single Responsibility**: Only defines layout policy data, no behavior
/// - **Open/Closed**: New presets can be added without modifying existing code
/// - **Dependency Inversion**: High-level SwiftUI views depend on this abstraction
///
/// ## Synchronization Strategy
/// The key challenge in frameless windows is ensuring SwiftUI padding matches AppKit
/// button positioning. This struct solves it by computing both from the same source values:
///
/// 1. AppKit uses `xOffset`, `yOffset`, `buttonSpacing` to position NSButtons
/// 2. SwiftUI uses computed properties (`reservedWidth`, `reservedHeight`) for spacers
/// 3. Both derive from identical base values = guaranteed synchronization
///
/// ## Usage
/// ```swift
/// // AppKit side
/// let config = TrafficLightLayoutConfig.arcBrowser
/// framelessWindow.applyTrafficLightLayout(config)
///
/// // SwiftUI side (same config)
/// SidebarHeaderView(layoutConfig: config)
///     .padding(.leading, config.reservedWidth)
/// ```
public struct TrafficLightLayoutConfig: Equatable, Sendable, Hashable {
    
    // MARK: - Core Positioning Values (Source of Truth)
    
    /// Horizontal offset from window's left edge to the **center** of the first (close) button.
    /// Measured in points from the left edge of the window frame.
    public let xOffset: CGFloat
    
    /// Vertical offset from window's **top** edge to the **center** of the buttons.
    /// Measured in points from the top edge of the window frame.
    public let yOffset: CGFloat
    
    /// Horizontal spacing between adjacent traffic light buttons (edge to edge).
    public let buttonSpacing: CGFloat
    
    // MARK: - Button Dimensions (macOS Standard)
    
    /// Standard macOS traffic light button diameter (14pt circle).
    public static let buttonDiameter: CGFloat = 14
    
    /// Number of traffic light buttons (Close, Minimize, Zoom).
    public static let buttonCount: Int = 3
    
    // MARK: - Computed Layout Values (SwiftUI Synchronization)
    
    /// Total width required for all three traffic light buttons.
    /// `buttonDiameter * 3 + buttonSpacing * 2`
    public var buttonsRowWidth: CGFloat {
        (Self.buttonDiameter * CGFloat(Self.buttonCount)) + (buttonSpacing * CGFloat(Self.buttonCount - 1))
    }
    
    /// Width that SwiftUI should reserve (spacer width) to avoid overlapping traffic lights.
    /// Includes the xOffset plus the full button row width plus comfortable margin.
    public var reservedWidth: CGFloat {
        xOffset + buttonsRowWidth + sidebarToggleSpacing
    }
    
    /// Height that SwiftUI should use for the header area containing traffic lights.
    /// Provides comfortable vertical spacing above and below the buttons.
    public var reservedHeight: CGFloat {
        yOffset + (Self.buttonDiameter / 2) + verticalPaddingBelow
    }
    
    // MARK: - Sidebar Toggle Button Configuration
    
    /// Spacing between the last traffic light button (zoom) and the sidebar toggle button.
    public let sidebarToggleSpacing: CGFloat
    
    /// Size of the sidebar toggle button (square).
    public let sidebarToggleSize: CGFloat
    
    // MARK: - Padding Configuration
    
    /// Vertical padding below the traffic light buttons within the header.
    public let verticalPaddingBelow: CGFloat
    
    /// Horizontal padding from the right edge of the sidebar header.
    public let trailingPadding: CGFloat
    
    // MARK: - Initializer
    
    /// Initialize a traffic light layout configuration.
    ///
    /// - Parameters:
    ///   - xOffset: Horizontal offset from left edge to first button center
    ///   - yOffset: Vertical offset from top edge to button center
    ///   - buttonSpacing: Spacing between adjacent buttons
    ///   - sidebarToggleSpacing: Spacing between zoom button and sidebar toggle
    ///   - sidebarToggleSize: Size of the sidebar toggle button
    ///   - verticalPaddingBelow: Padding below buttons in header
    ///   - trailingPadding: Padding from right edge
    public init(
        xOffset: CGFloat,
        yOffset: CGFloat,
        buttonSpacing: CGFloat,
        sidebarToggleSpacing: CGFloat = 12,
        sidebarToggleSize: CGFloat = 24,
        verticalPaddingBelow: CGFloat = 12,
        trailingPadding: CGFloat = 12
    ) {
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.buttonSpacing = buttonSpacing
        self.sidebarToggleSpacing = sidebarToggleSpacing
        self.sidebarToggleSize = sidebarToggleSize
        self.verticalPaddingBelow = verticalPaddingBelow
        self.trailingPadding = trailingPadding
    }
}

// =============================================================================
// MARK: - Preset Configurations
// =============================================================================

extension TrafficLightLayoutConfig {
    
    /// Arc-style browser window configuration.
    ///
    /// Positions traffic lights at (20, 18) from top-left, matching Arc Browser's aesthetic.
    /// The sidebar toggle button appears immediately after the zoom button.
    ///
    /// Visual Layout (from left edge):
    /// ```
    /// |--20--[●]--8--[●]--8--[●]--12--[≡]--
    ///        Close  Min   Zoom    Toggle
    /// ```
    public static let arcBrowser = TrafficLightLayoutConfig(
        xOffset: 20,
        yOffset: 18,
        buttonSpacing: 8,
        sidebarToggleSpacing: 12,
        sidebarToggleSize: 24,
        verticalPaddingBelow: 14,
        trailingPadding: 12
    )
    
    /// Compact configuration for utility windows (Settings, DevTools).
    ///
    /// Tighter spacing appropriate for smaller windows where space is at a premium.
    public static let compactUtility = TrafficLightLayoutConfig(
        xOffset: 14,
        yOffset: 14,
        buttonSpacing: 6,
        sidebarToggleSpacing: 8,
        sidebarToggleSize: 20,
        verticalPaddingBelow: 10,
        trailingPadding: 10
    )
    
    /// Fullscreen mode configuration.
    ///
    /// When in fullscreen, traffic lights appear slightly higher (closer to top edge)
    /// since there's no system menu bar taking space.
    public static let fullscreen = TrafficLightLayoutConfig(
        xOffset: 20,
        yOffset: 12,
        buttonSpacing: 8,
        sidebarToggleSpacing: 12,
        sidebarToggleSize: 24,
        verticalPaddingBelow: 12,
        trailingPadding: 12
    )
    
    /// System default configuration for reference/fallback.
    ///
    /// Matches standard macOS titlebar traffic light positioning.
    public static let systemDefault = TrafficLightLayoutConfig(
        xOffset: 8,
        yOffset: 12,
        buttonSpacing: 6,
        sidebarToggleSpacing: 8,
        sidebarToggleSize: 20,
        verticalPaddingBelow: 8,
        trailingPadding: 8
    )
}

// =============================================================================
// MARK: - AppKit Button Origin Calculator
// =============================================================================

extension TrafficLightLayoutConfig {
    
    /// Calculate the frame origin points for each traffic light button in AppKit coordinates.
    ///
    /// AppKit coordinate system has Y=0 at the bottom (non-flipped) or top (flipped).
    /// This method handles both cases for correct positioning within the titlebar container.
    ///
    /// - Parameters:
    ///   - containerHeight: Height of the titlebar container view
    ///   - isFlipped: Whether the container uses flipped coordinates (Y=0 at top)
    /// - Returns: Array of CGPoints for [close, minimize, zoom] button frame origins
    public func calculateButtonOrigins(
        containerHeight: CGFloat,
        isFlipped: Bool
    ) -> [CGPoint] {
        let buttonRadius = Self.buttonDiameter / 2
        
        // Calculate Y position based on coordinate system
        let yPosition: CGFloat
        if isFlipped {
            // Flipped: Y=0 at top, so yOffset directly maps
            yPosition = yOffset - buttonRadius
        } else {
            // Non-flipped: Y=0 at bottom, so invert from container height
            yPosition = containerHeight - yOffset - buttonRadius
        }
        
        // Calculate X positions for each button
        var origins: [CGPoint] = []
        var currentX = xOffset - buttonRadius  // Start at left edge of first button
        
        for _ in 0..<Self.buttonCount {
            origins.append(CGPoint(x: currentX, y: yPosition))
            currentX += Self.buttonDiameter + buttonSpacing
        }
        
        return origins
    }
    
    /// Calculate the X position for the sidebar toggle button.
    ///
    /// The toggle appears immediately after the zoom (last) traffic light button.
    ///
    /// - Returns: X position for the leading edge of the sidebar toggle button
    public var sidebarToggleXPosition: CGFloat {
        let lastButtonRightEdge = xOffset + (Self.buttonDiameter / 2) + 
            (Self.buttonDiameter + buttonSpacing) * CGFloat(Self.buttonCount - 1) +
            (Self.buttonDiameter / 2)
        return lastButtonRightEdge + sidebarToggleSpacing
    }
}

// =============================================================================
// MARK: - SwiftUI Environment Integration
// =============================================================================

/// Environment key for passing traffic light layout config to SwiftUI views.
private struct TrafficLightLayoutConfigKey: EnvironmentKey {
    static let defaultValue: TrafficLightLayoutConfig = .arcBrowser
}

extension EnvironmentValues {
    /// The traffic light layout configuration for this view hierarchy.
    public var trafficLightLayoutConfig: TrafficLightLayoutConfig {
        get { self[TrafficLightLayoutConfigKey.self] }
        set { self[TrafficLightLayoutConfigKey.self] = newValue }
    }
}

extension View {
    /// Inject a traffic light layout configuration into the view hierarchy.
    public func trafficLightLayoutConfig(_ config: TrafficLightLayoutConfig) -> some View {
        environment(\.trafficLightLayoutConfig, config)
    }
}

// =============================================================================
// MARK: - Conversion to TrafficLightConfiguration
// =============================================================================

extension TrafficLightLayoutConfig {
    
    /// Convert to `TrafficLightConfiguration` for use with existing `TrafficLightStateCoordinator`.
    ///
    /// This provides backward compatibility with the existing coordinator-based system.
    public func toTrafficLightConfiguration() -> TrafficLightConfiguration {
        TrafficLightConfiguration(
            xPosition: xOffset,
            yPositionFromTop: yOffset,
            buttonSpacing: buttonSpacing
        )
    }
    
    /// Create from an existing `TrafficLightConfiguration`.
    ///
    /// Useful for migrating existing code to use the new layout config system.
    public init(from configuration: TrafficLightConfiguration) {
        self.init(
            xOffset: configuration.xPosition,
            yOffset: configuration.yPositionFromTop,
            buttonSpacing: configuration.buttonSpacing
        )
    }
}

// =============================================================================
// MARK: - Debug Description
// =============================================================================

extension TrafficLightLayoutConfig: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        TrafficLightLayoutConfig(
            position: (\(xOffset), \(yOffset))
            buttonSpacing: \(buttonSpacing)
            reservedWidth: \(reservedWidth)
            reservedHeight: \(reservedHeight)
            sidebarToggleX: \(sidebarToggleXPosition)
        )
        """
    }
}
