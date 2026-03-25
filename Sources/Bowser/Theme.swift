// Theme.swift - Arc-Style Design System
// Swift 6.2 with unified colors and materials
// Single source of truth for Bowser visual styling

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Arc Theme (Single Source of Truth)
// =============================================================================

/// Arc-style theme configuration providing unified colors and materials.
///
/// ## Design Philosophy
/// The "Floating Webpage" aesthetic requires a single, continuous surface
/// behind both the sidebar and detail area. The webpage "card" then floats
/// above this unified backdrop with padding and shadows.
///
/// ## Layer Architecture
/// ```
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ Layer 0: NSWindow.backgroundColor (ArcTheme.windowBackgroundColor)      │
/// │ ┌─────────────────────────────────────────────────────────────────────┐ │
/// │ │ Layer 1: UnifiedBackdropView (ArcTheme.backdropMaterial)            │ │
/// │ │ ┌───────────────────────────────────────────────────────────────┐   │ │
/// │ │ │                                                               │   │ │
/// │ │ │  Sidebar (transparent, no background)                         │   │ │
/// │ │ │                                                               │   │ │
/// │ │ └───────────────────────────────────────────────────────────────┘   │ │
/// │ │ ┌───────────────────────────────────────────────────────────────┐   │ │
/// │ │ │ Layer 2: Floating Card (ArcTheme.cardBackgroundColor)         │   │ │
/// │ │ │ ┌───────────────────────────────────────────────────────────┐ │   │ │
/// │ │ │ │                                                           │ │   │ │
/// │ │ │ │             Web Content (CEF)                             │ │   │ │
/// │ │ │ │                                                           │ │   │ │
/// │ │ │ └───────────────────────────────────────────────────────────┘ │   │ │
/// │ │ │              ↑ padding ↑  rounded corners  ↑ shadow ↑        │   │ │
/// │ │ └───────────────────────────────────────────────────────────────┘   │ │
/// │ └─────────────────────────────────────────────────────────────────────┘ │
/// └─────────────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
/// - **Window Level**: Apply `ArcTheme.windowBackgroundColor` to NSWindow
/// - **Backdrop Level**: Use `ArcTheme.backdropMaterial` for NSVisualEffectView
/// - **Sidebar Level**: Make transparent so backdrop shows through
/// - **Card Level**: Use `ArcTheme.cardBackgroundColor` for the floating web card
enum ArcTheme {
    
    // =========================================================================
    // MARK: - Window Background (Layer 0)
    // =========================================================================
    
    /// The NSColor to apply to NSWindow.backgroundColor.
    /// This is the base layer that sits behind the vibrancy effect.
    ///
    /// Using a subtle warm gray that:
    /// - Works harmoniously with NSVisualEffectMaterial.sidebar
    /// - Provides a neutral backdrop for the vibrancy blend
    /// - Matches Arc Browser's characteristic soft gray aesthetic
    static var windowBackgroundColor: NSColor {
        // Subtle warm gray - the foundation color
        // This shows through where vibrancy doesn't fully obscure
        NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.95, alpha: 1.0)
    }
    
    /// SwiftUI Color equivalent of the window background
    static var windowBackground: Color {
        Color(nsColor: windowBackgroundColor)
    }
    
    // =========================================================================
    // MARK: - Backdrop Material (Layer 1)
    // =========================================================================
    
    /// NSVisualEffectView material for the unified backdrop.
    /// This creates the translucent, vibrant effect that unifies
    /// the sidebar and detail area into a single visual surface.
    ///
    /// Using `.sidebar` material because:
    /// - It provides the characteristic macOS sidebar translucency
    /// - It blends well with desktop wallpapers
    /// - It matches Arc Browser's sidebar aesthetic
    static var backdropMaterial: NSVisualEffectView.Material {
        .sidebar
    }
    
    /// NSVisualEffectView blending mode for the backdrop.
    /// `.behindWindow` allows desktop content to show through.
    static var backdropBlendingMode: NSVisualEffectView.BlendingMode {
        .behindWindow
    }
    
    /// Backdrop color (for areas behind content)
    static var backdropColor: Color {
        Color.secondary.opacity(0.05)
    }
    
    // =========================================================================
    // MARK: - Highlight Color
    // =========================================================================
    
    /// Highlight color (grey instead of blue accent)
    /// Used for tab selections, borders, and other UI highlights
    static var highlightColor: Color {
        Color.gray
    }
    
    /// Section header color
    static var sectionHeaderColor: Color {
        Color.secondary
    }
    
    // =========================================================================
    // MARK: - Floating Card (Layer 2)
    // =========================================================================
    
    /// Background color for the floating web content card.
    /// This must be OPAQUE to create contrast against the translucent backdrop.
    ///
    /// Uses system windowBackgroundColor for automatic light/dark adaptation.
    static var cardBackgroundColor: NSColor {
        NSColor.windowBackgroundColor
    }
    
    /// SwiftUI Color for the card background
    static var cardBackground: Color {
        Color.white
    }
    
    /// Card corner radius matching Arc's aesthetic (~10-12pt)
    static let cardCornerRadius: CGFloat = 10
    
    /// Padding between card edges and window/sidebar boundaries
    static let cardPadding: CGFloat = 10
    
    // =========================================================================
    // MARK: - Shadows
    // =========================================================================
    
    /// Primary shadow for depth perception.
    /// Soft, ambient shadow that lifts the card off the backdrop.
    static let primaryShadow = (
        color: Color.black.opacity(0.15),
        radius: CGFloat(12),
        y: CGFloat(4)
    )
    
    /// Secondary shadow for ground contact.
    /// Tighter shadow that anchors the card and adds realism.
    static let secondaryShadow = (
        color: Color.black.opacity(0.08),
        radius: CGFloat(3),
        y: CGFloat(1)
    )
    
    // =========================================================================
    // MARK: - Sidebar Layout
    // =========================================================================
    
    /// Default sidebar width
    static let sidebarWidth: CGFloat = 280
    
    /// Minimum sidebar width
    static let sidebarMinWidth: CGFloat = 220
    
    /// Maximum sidebar width
    static let sidebarMaxWidth: CGFloat = 400
    
    /// Sidebar section padding
    static let sidebarPadding: CGFloat = 12
    
    // =========================================================================
    // MARK: - Tab Row Styling
    // =========================================================================
    
    /// Tab row corner radius
    static let tabRowCornerRadius: CGFloat = 8
    
    /// Tab row height
    static let tabRowHeight: CGFloat = 36
    
    /// Active tab background color
    static var activeTabBackground: Color {
        highlightColor.opacity(0.12)
    }
    
    /// Hover tab background color
    static var hoverTabBackground: Color {
        Color.primary.opacity(0.04)
    }
    
    // =========================================================================
    // MARK: - Pinned Tabs
    // =========================================================================
    
    /// Pinned tab icon size
    static let pinnedTabSize: CGFloat = 36
    
    /// Pinned tab corner radius
    static let pinnedTabCornerRadius: CGFloat = 8
    
    // =========================================================================
    // MARK: - Typography
    // =========================================================================
    
    /// Section header font
    static var sectionHeaderFont: Font {
        .system(size: 11, weight: .semibold)
    }
    
    /// Tab title font
    static var tabTitleFont: Font {
        .system(size: 13)
    }
    
    // =========================================================================
    // MARK: - Animation
    // =========================================================================
    
    /// Default hover animation
    static var hoverAnimation: Animation {
        .easeInOut(duration: 0.15)
    }
    
    /// Spring animation for interactions
    static var springAnimation: Animation {
        .spring(response: 0.3, dampingFraction: 0.8)
    }
    
    // =========================================================================
    // MARK: - Helper Methods
    // =========================================================================
    
    /// Configure an NSWindow for Arc-style appearance.
    /// Call this from FramelessWindow.configureArcStyleAppearance()
    @MainActor
    static func configureWindow(_ window: NSWindow) {
        // Apply the unified background color
        window.backgroundColor = windowBackgroundColor
        
        // Transparent titlebar for seamless content
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        // Enable dragging from background areas
        window.isMovableByWindowBackground = true
        
        // Ensure layer backing for visual effects
        window.contentView?.wantsLayer = true
    }
}

// =============================================================================
// MARK: - Color Codable Support
// =============================================================================

extension Color: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, opacity
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let opacity = try container.decode(Double.self, forKey: .opacity)
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        
        #if canImport(AppKit)
        if let nsColor = NSColor(self).usingColorSpace(.sRGB) {
            red = nsColor.redComponent
            green = nsColor.greenComponent
            blue = nsColor.blueComponent
            opacity = nsColor.alphaComponent
        }
        #endif
        
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(opacity, forKey: .opacity)
    }
}

// =============================================================================
// MARK: - Theme View Modifiers
// =============================================================================

extension View {
    /// Apply Arc-style card styling
    func arcCardStyle() -> some View {
        self
            .background(ArcTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: ArcTheme.cardCornerRadius))
            .shadow(
                color: ArcTheme.primaryShadow.color,
                radius: ArcTheme.primaryShadow.radius,
                y: ArcTheme.primaryShadow.y
            )
            .shadow(
                color: ArcTheme.secondaryShadow.color,
                radius: ArcTheme.secondaryShadow.radius,
                y: ArcTheme.secondaryShadow.y
            )
    }
    
    /// Apply tab row hover background
    func tabRowBackground(isActive: Bool, isHovering: Bool) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: ArcTheme.tabRowCornerRadius)
                .fill(
                    isActive ? ArcTheme.activeTabBackground :
                    isHovering ? ArcTheme.hoverTabBackground :
                    Color.clear
                )
        )
    }
}
