// UnifiedBackdropView.swift - Full-Window Vibrant Backdrop
// Extracted from AppShellView for modularity and reuse

import SwiftUI
import AppKit

// =============================================================================
// MARK: - Unified Backdrop View
// =============================================================================

/// Full-window vibrant backdrop that creates visual continuity between
/// sidebar and detail areas. Uses ArcTheme for consistent material configuration.
///
/// ## Visual Effect
/// The sidebar and detail area share this same backdrop, creating the illusion
/// of a single continuous surface. The floating web card then hovers above it.
struct UnifiedBackdropView: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Use ArcTheme.backdropMaterial for the unified surface
        view.material = ArcTheme.backdropMaterial
        view.blendingMode = ArcTheme.backdropBlendingMode
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Material updates automatically with system appearance
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct UnifiedBackdropView_Previews: PreviewProvider {
    static var previews: some View {
        UnifiedBackdropView()
            .frame(width: 400, height: 300)
            .overlay {
                Text("Unified Backdrop")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}
#endif
