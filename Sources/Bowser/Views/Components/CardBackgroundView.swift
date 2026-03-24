// CardBackgroundView.swift - Theme-Aware Card Background
// Extracted from AppShellView for modularity and reuse

import SwiftUI
import AppKit

// =============================================================================
// MARK: - Card Background View
// =============================================================================

/// Solid black background for the floating web content card.
/// Pure black prevents any white flash while pages are loading.
struct CardBackgroundView: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.cornerRadius = ArcTheme.cardCornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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
