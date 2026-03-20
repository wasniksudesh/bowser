// CardBackgroundView.swift - Theme-Aware Card Background
// Extracted from AppShellView for modularity and reuse

import SwiftUI
import AppKit

// =============================================================================
// MARK: - Card Background View
// =============================================================================

/// Theme-aware opaque background for the floating web content card.
/// Uses NSVisualEffectView for proper light/dark mode adaptation.
/// The card must be OPAQUE to contrast against the translucent backdrop.
struct CardBackgroundView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Use .windowBackground for an opaque, theme-aware surface.
        // This contrasts with the translucent .sidebar backdrop.
        view.material = .windowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = ArcTheme.cardCornerRadius
        view.layer?.masksToBounds = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Material and appearance adapt automatically via system appearance
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct CardBackgroundView_Previews: PreviewProvider {
    static var previews: some View {
        CardBackgroundView()
            .frame(width: 300, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: ArcTheme.cardCornerRadius))
            .padding()
    }
}
#endif
