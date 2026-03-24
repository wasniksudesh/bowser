// RootView.swift - Top-level composition root
// Switches between HomescreenView and AppShellView based on AppNavigationState

import SwiftUI

// =============================================================================
// MARK: - Root View
// =============================================================================

/// The top-level view hosted by the main window.
/// Switches between the homescreen desktop and the browser interface.
struct RootView: View {

    @Bindable var appNav: AppNavigationState
    @Bindable var browserState: BrowserState

    /// Tracks whether the browser shell has been instantiated at least once.
    /// Keeps AppShellView alive after first open so subsequent transitions are
    /// a simple opacity crossfade with no view-construction cost.
    @State private var hasBrowserBeenOpened = false

    var body: some View {
        let isHome = appNav.isShowingHomescreen
        ZStack {
            // Homescreen is always present — zero construction cost on return
            HomescreenView(appNav: appNav, browserState: browserState)
                .opacity(isHome ? 1 : 0)
                .allowsHitTesting(isHome)
                .zIndex(isHome ? 1 : 0)

            // Browser shell is created on first open and then kept alive so that
            // every subsequent homescreen ↔ browser transition is instantaneous.
            if hasBrowserBeenOpened {
                AppShellView(browserState: browserState, appNav: appNav)
                    .opacity(isHome ? 0 : 1)
                    .allowsHitTesting(!isHome)
                    .zIndex(isHome ? 0 : 1)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isHome)
        .onChange(of: appNav.currentScreen) { _, newValue in
            if case .browser = newValue {
                hasBrowserBeenOpened = true
            }
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(
            appNav: AppNavigationState(),
            browserState: BrowserState()
        )
        .frame(width: 1280, height: 800)
    }
}
#endif
