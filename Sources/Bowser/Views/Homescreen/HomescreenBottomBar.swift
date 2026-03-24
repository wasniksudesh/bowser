// HomescreenBottomBar.swift - macOS-desktop-style dock bar at the bottom of the homescreen

import SwiftUI

// =============================================================================
// MARK: - Homescreen Bottom Bar
// =============================================================================

/// Dock bar pinned to the bottom of the homescreen.
/// Contains: folder quick-access icons | + button | search field | clock
struct HomescreenBottomBar: View {

    @Bindable var browserState: BrowserState
    @Bindable var appNav: AppNavigationState
    let onCreateFolder: () -> Void

    @State private var searchText = ""
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Show up to 8 folders in the dock
    private var dockFolders: [Folder] {
        Array(browserState.folderManager.sortedFolders.prefix(8))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Folder quick-access dock icons
            folderDock

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 12)

            // Center: New folder button
            newFolderButton

            Divider()
                .frame(height: 24)
                .padding(.horizontal, 12)

            // Search field
            searchField

            Spacer()

            // Right: Clock
            clockView
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .onReceive(timer) { currentTime = $0 }
    }

    // MARK: - Folder Dock

    private var folderDock: some View {
        HStack(spacing: 8) {
            ForEach(dockFolders) { folder in
                DockFolderIcon(folder: folder) {
                    appNav.openFolder(folder.id)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        browserState.loadFolder(id: folder.id)
                    }
                }
            }
        }
    }

    // MARK: - New Folder Button

    private var newFolderButton: some View {
        Button(action: onCreateFolder) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 32, height: 32)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search Everything", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 160)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - Clock

    private var clockView: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(timeString)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(dateString)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .monospacedDigit()
        .padding(.leading, 12)
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
// MARK: - Dock Folder Icon
// =============================================================================

/// Mini folder icon shown in the bottom dock bar
private struct DockFolderIcon: View {

    let folder: Folder
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(folder.color.opacity(isHovering ? 0.28 : 0.16))
                Image(systemName: folder.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(folder.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 32, height: 32)
            .scaleEffect(isHovering ? 1.1 : 1.0)
            .animation(ArcTheme.hoverAnimation, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(folder.name)
    }
}
