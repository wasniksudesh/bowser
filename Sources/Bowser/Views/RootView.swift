// RootView.swift - Top-level composition root
// Gates the app behind license verification, then switches between
// HomescreenView and AppShellView based on AppNavigationState

import SwiftUI

// =============================================================================
// MARK: - Root View
// =============================================================================

/// The top-level view hosted by the main window.
/// First verifies the license, then switches between the homescreen and browser.
struct RootView: View {

    @Bindable var appNav: AppNavigationState
    @Bindable var browserState: BrowserState

    @State private var licenseState: LicenseCheckState = .checking

    /// Tracks whether the browser shell has been instantiated at least once.
    /// Keeps AppShellView alive after first open so subsequent transitions are
    /// a simple opacity crossfade with no view-construction cost.
    @State private var hasBrowserBeenOpened = false

    var body: some View {
        Group {
            switch licenseState {
            case .checking:
                ZStack {
                    UnifiedBackdropView()
                        .ignoresSafeArea()
                    ProgressView("Verifying license...")
                        .controlSize(.large)
                }

            case .needsLicense:
                LicenseView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        licenseState = .verified
                    }
                }

            case .verified:
                browserContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            licenseState = await LicenseService.shared.initialCheckState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .licenseRevoked)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                licenseState = .needsLicense
            }
        }
    }

    // MARK: - Browser Content (post-license)

    private var browserContent: some View {
        let isHome = appNav.isShowingHomescreen
        return ZStack {
            HomescreenView(appNav: appNav, browserState: browserState)
                .opacity(isHome ? 1 : 0)
                .allowsHitTesting(isHome)
                .zIndex(isHome ? 1 : 0)

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
// MARK: - License Notification
// =============================================================================

extension Notification.Name {
    static let licenseRevoked = Notification.Name("bowser.licenseRevoked")
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
