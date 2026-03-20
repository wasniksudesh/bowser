// DropOverlayView.swift - VS Code-Style Drop Indicator Overlay
// Bowser - Swift 6.2
// Visual "ghost" overlay showing where dropped tab will land

import AppKit

// =============================================================================
// MARK: - Drop Overlay View
// =============================================================================

/// Overlay view that displays the VS Code-style drop indicator during drag operations.
/// Shows a semi-transparent grey highlight indicating where the tab will be placed.
///
/// Visual Design:
/// - Semi-transparent grey fill matching VS Code
/// - Rounded corners for polished appearance
/// - Subtle border for definition
/// - Smooth animations for zone transitions
final class DropOverlayView: NSView {
    
    // MARK: - Configuration
    
    /// Fill color for the drop zone highlight
    private let fillColor = NSColor.systemGray.withAlphaComponent(0.25)
    
    /// Border color for the drop zone
    private let borderColor = NSColor.systemGray.withAlphaComponent(0.6)
    
    /// Border width
    private let borderWidth: CGFloat = 2.0
    
    /// Corner radius
    private let cornerRadius: CGFloat = 8.0
    
    // MARK: - State
    
    /// Current drop zone being highlighted
    private(set) var currentZone: SplitDropZone?
    
    /// Bounds of the target pane
    private var targetBounds: NSRect = .zero
    
    /// The CAShapeLayer for drawing
    private var highlightLayer: CAShapeLayer?
    
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create the highlight layer
        let shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = fillColor.cgColor
        shapeLayer.strokeColor = borderColor.cgColor
        shapeLayer.lineWidth = borderWidth
        shapeLayer.opacity = 0
        layer?.addSublayer(shapeLayer)
        highlightLayer = shapeLayer
        
        // Make the view non-interactive (clicks pass through)
        // This is critical - the overlay should not intercept drag events
    }
    
    // MARK: - Public Interface
    
    /// Show the drop indicator for a specific zone
    /// - Parameters:
    ///   - zone: The drop zone to highlight
    ///   - targetBounds: The bounds of the target pane (in this view's coordinates)
    ///   - animated: Whether to animate the transition
    func showDropIndicator(zone: SplitDropZone, targetBounds: NSRect, animated: Bool = true) {
        print("[DropOverlayView] showDropIndicator zone=\(zone) bounds=\(targetBounds)")
        currentZone = zone
        self.targetBounds = targetBounds
        
        let highlightRect = DropZoneDetector.highlightRect(for: zone, in: targetBounds)
        updateHighlightPath(to: highlightRect, animated: animated)
        
        // Show the layer using CABasicAnimation for proper animation
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        highlightLayer?.opacity = 1
        CATransaction.commit()
    }
    
    /// Update the drop indicator for a new zone (during drag movement)
    /// - Parameters:
    ///   - zone: The new drop zone
    ///   - targetBounds: The bounds of the target pane
    func updateDropIndicator(zone: SplitDropZone, targetBounds: NSRect) {
        guard zone != currentZone || targetBounds != self.targetBounds else { return }
        
        currentZone = zone
        self.targetBounds = targetBounds
        
        let highlightRect = DropZoneDetector.highlightRect(for: zone, in: targetBounds)
        updateHighlightPath(to: highlightRect, animated: true)
    }
    
    /// Hide the drop indicator
    /// - Parameter animated: Whether to animate the hide
    func hideDropIndicator(animated: Bool = true) {
        print("[DropOverlayView] hideDropIndicator")
        currentZone = nil
        
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.15)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        highlightLayer?.opacity = 0
        CATransaction.commit()
    }
    
    // MARK: - Private Helpers
    
    /// Update the highlight layer's path
    private func updateHighlightPath(to rect: NSRect, animated: Bool) {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        
        if animated {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = highlightLayer?.path
            animation.toValue = path
            animation.duration = 0.15
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            highlightLayer?.add(animation, forKey: "pathAnimation")
        }
        
        highlightLayer?.path = path
    }
    
    // MARK: - NSView Overrides
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Return nil to make the overlay non-interactive
        // This allows drag events to pass through to underlying views
        return nil
    }
    
    override var acceptsFirstResponder: Bool {
        false
    }
    
    override func layout() {
        super.layout()
        
        // Update layer frame
        highlightLayer?.frame = bounds
        
        // Recalculate highlight if we have a current zone
        if let zone = currentZone {
            let highlightRect = DropZoneDetector.highlightRect(for: zone, in: targetBounds)
            updateHighlightPath(to: highlightRect, animated: false)
        }
    }
}

// =============================================================================
// MARK: - Drop Target Indicator View
// =============================================================================

/// Small indicator showing the exact split direction with an icon
/// Appears at the center of the drop zone for additional clarity
final class DropDirectionIndicator: NSView {
    
    // MARK: - Configuration
    
    private let iconSize: CGFloat = 24
    private let backgroundColor = NSColor.systemGray
    private let iconColor = NSColor.white
    
    // MARK: - State
    
    private var iconImageView: NSImageView?
    private var currentZone: SplitDropZone?
    
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
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 4
        layer?.shadowOpacity = 0.2
        
        // Create icon image view
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = iconColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: iconSize),
            imageView.heightAnchor.constraint(equalToConstant: iconSize)
        ])
        
        iconImageView = imageView
        alphaValue = 0
    }
    
    // MARK: - Public Interface
    
    /// Update the indicator for a drop zone
    func update(for zone: SplitDropZone) {
        guard zone != currentZone else { return }
        currentZone = zone
        
        let symbolName: String
        switch zone {
        case .left:
            symbolName = "arrow.left.to.line"
        case .right:
            symbolName = "arrow.right.to.line"
        case .center:
            symbolName = "plus"
        }
        
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        iconImageView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
    
    /// Show the indicator
    func show(animated: Bool = true) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }
    
    /// Hide the indicator
    func hide(animated: Bool = true) {
        currentZone = nil
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 0
            }
        } else {
            alphaValue = 0
        }
    }
    
    // MARK: - NSView Overrides
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Non-interactive
    }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: 40, height: 40)
    }
}

// =============================================================================
// MARK: - Combined Drop Overlay Manager
// =============================================================================

/// Manages the drop overlay and direction indicator together
@MainActor
final class DropOverlayManager {
    
    /// The overlay view
    let overlayView: DropOverlayView
    
    /// The direction indicator
    let directionIndicator: DropDirectionIndicator
    
    /// Parent view for positioning
    private weak var parentView: NSView?
    
    init() {
        overlayView = DropOverlayView(frame: .zero)
        directionIndicator = DropDirectionIndicator(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    }
    
    /// Install the overlay into a parent view
    func install(in parent: NSView) {
        parentView = parent
        
        // Add overlay
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(overlayView, positioned: .above, relativeTo: nil)
        
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: parent.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
        
        // Add direction indicator (positioned later)
        directionIndicator.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(directionIndicator, positioned: .above, relativeTo: overlayView)
    }
    
    /// Show drop indicator for a zone within target bounds
    func showDrop(zone: SplitDropZone, targetBounds: NSRect) {
        print("[DropOverlay] Showing drop indicator for zone: \(zone) in bounds: \(targetBounds)")
        overlayView.showDropIndicator(zone: zone, targetBounds: targetBounds)
        
        // Position direction indicator at center of highlight
        let highlightRect = DropZoneDetector.highlightRect(for: zone, in: targetBounds)
        directionIndicator.frame.origin = NSPoint(
            x: highlightRect.midX - 20,
            y: highlightRect.midY - 20
        )
        directionIndicator.update(for: zone)
        directionIndicator.show()
    }
    
    /// Update drop indicator
    func updateDrop(zone: SplitDropZone, targetBounds: NSRect) {
        print("[DropOverlay] Updating drop indicator for zone: \(zone)")
        overlayView.updateDropIndicator(zone: zone, targetBounds: targetBounds)
        
        let highlightRect = DropZoneDetector.highlightRect(for: zone, in: targetBounds)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            directionIndicator.animator().frame.origin = NSPoint(
                x: highlightRect.midX - 20,
                y: highlightRect.midY - 20
            )
        }
        directionIndicator.update(for: zone)
    }
    
    /// Hide all drop indicators
    func hideDrop() {
        overlayView.hideDropIndicator()
        directionIndicator.hide()
    }
    
    /// Remove from parent
    func uninstall() {
        overlayView.removeFromSuperview()
        directionIndicator.removeFromSuperview()
        parentView = nil
    }
}
