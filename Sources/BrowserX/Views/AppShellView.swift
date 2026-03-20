// AppShellView.swift - Arc-Style Application Shell Layout (Composition Root)
// Swift 6.2 with NavigationSplitView for sidebar-first architecture
// Refactored: Composes modular components from Views/Shell, Views/Components

import SwiftUI
import AppKit

// =============================================================================
// MARK: - App Shell View (Composition Root)
// =============================================================================

/// Arc-style application shell using NavigationSplitView.
/// This is a composition root that assembles modular sub-views.
///
/// ## Composed Components
/// - `UnifiedBackdropView` - Full-window vibrant backdrop
/// - `ArcSidebarView` - Complete sidebar with URL bar, favorites, tabs
/// - `FloatingWebCanvasView` - Web content in floating card style
/// - `CommandBarView` - Modal search/navigation overlay
/// - `TabPreviewCard` - Hover preview for tabs
struct AppShellView: View {
    
    @Bindable var browserState: BrowserState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showCommandBar: Bool = false
    @State private var isFullScreen: Bool = false
    
    /// Computed binding to convert NavigationSplitViewVisibility to Bool for sidebar toggle
    private var isSidebarCollapsed: Binding<Bool> {
        Binding(
            get: { columnVisibility == .detailOnly },
            set: { collapsed in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    columnVisibility = collapsed ? .detailOnly : .all
                }
            }
        )
    }
    
    var body: some View {
        ZStack {
            // Unified backdrop behind both sidebar and detail
            UnifiedBackdropView()
                .ignoresSafeArea()
            
            // Main navigation split layout
            mainContent
            
            // Collapsed sidebar toggle button (appears when sidebar is hidden)
            collapsedSidebarToggle
            
            // Command bar overlay
            commandBarOverlay
        }
        .coordinateSpace(name: "GlobalShell")
        .overlayPreferenceValue(TabHoverPreferenceKey.self, tabPreviewOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .openCommandBar)) { _ in presentCommandBar() }
        .onReceive(NotificationCenter.default.publisher(for: .focusAddressBar)) { _ in presentCommandBar() }
        .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in presentCommandBar() }
        .onReceive(fullscreenEnterPublisher) { _ in setFullScreen(true) }
        .onReceive(fullscreenExitPublisher) { _ in setFullScreen(false) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in setFullScreen(true) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in setFullScreen(false) }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ArcSidebarView(
                browserState: browserState,
                showCommandBar: $showCommandBar,
                isFullScreen: isFullScreen,
                isSidebarCollapsed: isSidebarCollapsed
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
            // CRITICAL: Remove the default sidebar toggle from toolbar
            // This allows traffic lights to be positioned in the sidebar area
            .toolbar(removing: .sidebarToggle)
            // Ensure sidebar has no navigation title that could create a header
            .navigationTitle("")
        } detail: {
            FloatingWebCanvasView(
                browserState: browserState,
                isFullScreen: isFullScreen
            )
                // Ensure detail view has no navigation title
                .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .scrollContentBackground(.hidden)
        // Hide all toolbar items for Arc-style frameless look
        .toolbar(.hidden, for: .windowToolbar)
        // Ensure the whole NavigationSplitView has no title
        .navigationTitle("")
    }
    
    // MARK: - Collapsed Sidebar Toggle
    
    /// Floating toggle button that appears when sidebar is collapsed
    /// Allows user to re-expand the sidebar
    @ViewBuilder
    private var collapsedSidebarToggle: some View {
        if columnVisibility == .detailOnly {
            VStack {
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            columnVisibility = .all
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Show Sidebar")
                    .padding(.leading, 12)
                    .padding(.top, isFullScreen ? 12 : 52) // Account for traffic lights in windowed mode
                    
                    Spacer()
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }
    
    // MARK: - Command Bar Overlay
    
    @ViewBuilder
    private var commandBarOverlay: some View {
        if showCommandBar {
            CommandBarView(
                browserState: browserState,
                onDismiss: { dismissCommandBar() },
                onNavigate: { url in browserState.createTab(url: url) }
            )
            .transition(commandBarTransition)
            .zIndex(1000)
        }
    }
    
    private var commandBarTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .center))
        )
    }
    
    // MARK: - Tab Preview Overlay
    
    @ViewBuilder
    private func tabPreviewOverlay(_ hoverData: TabHoverData?) -> some View {
        if let data = hoverData {
            TabPreviewCard(tab: data.tab)
                .position(x: data.globalFrame.maxX + 150, y: data.globalFrame.midY)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .leading)),
                    removal: .opacity
                ))
                .zIndex(999)
                .allowsHitTesting(false)
        }
    }
    
    // MARK: - Actions
    
    private func presentCommandBar() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showCommandBar = true
        }
    }
    
    private func dismissCommandBar() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            showCommandBar = false
        }
    }
    
    private func setFullScreen(_ value: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isFullScreen = value
        }
    }
    
    // MARK: - Publishers
    
    private var fullscreenEnterPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .windowDidEnterFullScreen)
    }
    
    private var fullscreenExitPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .windowDidExitFullScreen)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AppShellView_Previews: PreviewProvider {
    static var previews: some View {
        AppShellView(browserState: BrowserState())
            .frame(width: 1200, height: 800)
    }
}
#endif
