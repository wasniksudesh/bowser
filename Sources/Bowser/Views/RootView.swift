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

    var body: some View {
        ZStack {
            switch appNav.currentScreen {
            case .homescreen:
                HomescreenView(appNav: appNav, browserState: browserState)
                    .transition(homescreenTransition)
            case .browser:
                AppShellView(browserState: browserState, appNav: appNav)
                    .transition(browserTransition)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appNav.currentScreen)
    }

    // MARK: - Transitions

    private var homescreenTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.02, anchor: .center))
        )
    }

    private var browserTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 1.02, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
        )
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
