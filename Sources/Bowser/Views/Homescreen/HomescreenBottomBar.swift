// HomescreenBottomBar.swift - macOS-desktop-style dock bar at the bottom of the homescreen

import SwiftUI

// =============================================================================
// MARK: - Homescreen Bottom Bar
// =============================================================================

/// Dock bar pinned to the bottom of the homescreen.
/// Centered and capped at a maximum width like the macOS dock.
/// Contains: folder quick-access icons | + button | search field (flexible) | clock
struct HomescreenBottomBar: View {

    @Bindable var browserState: BrowserState
    @Bindable var appNav: AppNavigationState
    let onCreateFolder: () -> Void
    @Binding var searchText: String
    @Binding var showingHistorySidebar: Bool
    var onSearch: (String) -> Void = { _ in }

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Show up to 8 folders in the dock
    private var dockFolders: [Folder] {
        Array(browserState.folderManager.sortedFolders.prefix(8))
    }

    var body: some View {
        // Centered dock — max width keeps it compact like the macOS dock
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                // Left: Folder quick-access dock icons
                folderDock

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 10)

                // Center: New folder button
                newFolderButton

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 10)

                // Search field — fills remaining space
                searchField

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 10)

                // History & Settings buttons
                historyButton
                settingsButton

                Divider()
                    .frame(height: 24)
                    .padding(.horizontal, 10)

                // Right: Clock
                clockView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
            )
            .frame(maxWidth: 780)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 16)
        .onReceive(timer) { currentTime = $0 }
    }

    // MARK: - Folder Dock

    private var folderDock: some View {
        HStack(spacing: 6) {
            ForEach(dockFolders) { folder in
                DockFolderIcon(
                    folder: folder,
                    browserState: browserState,
                    appNav: appNav
                )
            }
        }
    }

    // MARK: - New Folder Button

    private var newFolderButton: some View {
        Button(action: onCreateFolder) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 28, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("New Folder")
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search Anything", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .onSubmit {
                    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !query.isEmpty { onSearch(query) }
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    // MARK: - History Button

    private var historyButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                showingHistorySidebar.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(showingHistorySidebar
                          ? Color.accentColor.opacity(0.18)
                          : Color.primary.opacity(0.07))
                    .frame(width: 28, height: 28)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(showingHistorySidebar ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help(showingHistorySidebar ? "Hide History" : "Show History")

    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            NotificationCenter.default.post(name: .toggleSettings, object: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 28, height: 28)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Settings")
        .padding(.leading, 4)
    }

    // MARK: - Clock

    private var clockView: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(timeString)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(dateString)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .monospacedDigit()
        .padding(.leading, 8)
    }

    // MARK: - Formatters

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: currentTime)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: currentTime).uppercased()
    }
}

// =============================================================================
// MARK: - Dock Folder Icon (with popover)
// =============================================================================

/// Mini folder icon shown in the bottom dock bar.
/// Clicking shows a popover listing the folder's tabs, plans, and agents.
private struct DockFolderIcon: View {

    let folder: Folder
    @Bindable var browserState: BrowserState
    @Bindable var appNav: AppNavigationState

    @State private var isHovering = false
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(folder.color.opacity(isHovering ? 0.28 : 0.16))
                Image(systemName: folder.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(folder.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 28, height: 28)
            .scaleEffect(isHovering ? 1.1 : 1.0)
            .animation(ArcTheme.hoverAnimation, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(folder.name)
        .popover(isPresented: $showingPopover, arrowEdge: .top) {
            DockFolderPopover(
                folder: folder,
                browserState: browserState,
                appNav: appNav,
                isPresented: $showingPopover
            )
        }
    }
}

// =============================================================================
// MARK: - Dock Folder Popover
// =============================================================================

/// Popover shown when a dock folder icon is clicked.
/// Lists the folder's tabs, plans, and agents as a vertical list.
private struct DockFolderPopover: View {

    let folder: Folder
    @Bindable var browserState: BrowserState
    @Bindable var appNav: AppNavigationState
    @Binding var isPresented: Bool

    @State private var tabs: [Tab] = []
    @State private var plans: [PlanMetadata] = []
    @State private var agentSessions: [AgentSession] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: folder.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(folder.color)
                    .symbolRenderingMode(.hierarchical)
                Text(folder.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                // Open folder directly
                Button {
                    openFolder(panelMode: .tab)
                } label: {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(folder.color)
                }
                .buttonStyle(.plain)
                .help("Open \(folder.name)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Tabs section
                    if !tabs.isEmpty {
                        popoverSection(title: "Tabs", icon: "globe") {
                            ForEach(tabs.prefix(5)) { tab in
                                popoverRow(
                                    icon: "globe",
                                    title: tab.title.isEmpty ? tab.url.absoluteString : tab.title,
                                    subtitle: tab.url.host ?? tab.url.absoluteString
                                ) {
                                    openFolder(panelMode: .tab)
                                }
                            }
                        }
                    }

                    // Plans section
                    if !plans.isEmpty {
                        if !tabs.isEmpty { Divider().padding(.vertical, 4) }
                        popoverSection(title: "Plans", icon: "list.bullet.rectangle") {
                            ForEach(plans.prefix(5)) { plan in
                                popoverRow(
                                    icon: "list.bullet.rectangle",
                                    title: plan.name,
                                    subtitle: plan.intent
                                ) {
                                    openFolder(panelMode: .plan)
                                }
                            }
                        }
                    }

                    // Agents section
                    if !agentSessions.isEmpty {
                        if !tabs.isEmpty || !plans.isEmpty { Divider().padding(.vertical, 4) }
                        popoverSection(title: "Agents", icon: "sparkles") {
                            ForEach(agentSessions.prefix(5)) { session in
                                popoverRow(
                                    icon: "sparkles",
                                    title: session.query,
                                    subtitle: session.status.rawValue.capitalized
                                ) {
                                    openFolder(panelMode: .agent)
                                }
                            }
                        }
                    }

                    // Empty state
                    if tabs.isEmpty && plans.isEmpty && agentSessions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("No items yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 260)
        .task {
            await loadFolderContents()
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func popoverSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .padding(.bottom, 2)
            content()
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func popoverRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(folder.color)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.0))
        )
        .hoverEffect()
    }

    // MARK: - Actions

    private func openFolder(panelMode: PanelMode) {
        isPresented = false
        appNav.openFolder(folder.id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            browserState.loadFolder(id: folder.id)
            browserState.currentPanelMode = panelMode
        }
    }

    // MARK: - Data Loading

    private func loadFolderContents() async {
        // Load tabs
        let loadedTabs = FolderTabPersistence.shared.loadTabs(forFolder: folder.id) ?? []
        tabs = Array(loadedTabs.prefix(5))

        // Load plans via folder-scoped PlanStorageManager
        let planManager = PlanStorageManager(folderId: folder.id)
        plans = Array(planManager.loadAllPlans().prefix(5))

        // Load agent sessions from browserState (in-memory, same folder context)
        agentSessions = Array(browserState.agentState.sessions.prefix(5))
    }
}

// MARK: - Hover Effect Helper

private extension View {
    func hoverEffect() -> some View {
        self.modifier(HoverHighlightModifier())
    }
}

private struct HoverHighlightModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0.0))
            )
            .onHover { isHovering = $0 }
    }
}
