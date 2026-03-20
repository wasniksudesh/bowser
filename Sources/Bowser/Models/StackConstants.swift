// StackConstants.swift - Constants for Stacked Page Navigation
// Defines geometry and lifecycle thresholds for the stack feature

import Foundation
import CoreGraphics

// =============================================================================
// MARK: - Stack Constants
// =============================================================================

enum StackConstants {
    
    // MARK: - Geometry
    
    /// Maximum width for all stacked page spines (5% of tab width)
    static let kSpineMaxWidth: CGFloat = 0.05
    
    // MARK: - Page Limits
    
    /// Maximum number of pages in a stack (excluding starred pages)
    static let maxPages: Int = 7
    
    // MARK: - Lifecycle Tiers
    
    /// Percentage of oldest pages that are always frozen (30%)
    static let frozenTierPercentage: Double = 0.30
    
    /// Percentage range for hibernating pages (31%-60%)
    static let hibernatingTierStart: Double = 0.31
    static let hibernatingTierEnd: Double = 0.60
    
    // MARK: - Gesture Thresholds
    
    /// Minimum horizontal swipe distance to trigger page change (points)
    static let swipeThreshold: CGFloat = 50.0
    
    /// Velocity threshold for fling gesture (points per second)
    static let flingVelocityThreshold: CGFloat = 1000.0
    
    /// Animation duration for page transitions (seconds)
    static let pageTransitionDuration: Double = 0.3
    
    // MARK: - Visual
    
    /// Opacity for frozen page curtain overlay
    static let frozenCurtainOpacity: Double = 0.85
    
    /// Duration for wake-up animation (top-to-bottom curtain reveal)
    static let wakeUpAnimationDuration: Double = 0.4
}
