// FloatingDockViews.swift - SwiftUI Components for Floating Dock
// Main container, dock bar, tab dropdown, and tab preview

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Floating Dock Root View
// =============================================================================

/// Root container for the floating dock widget
/// Manages state transitions between condensed, dropdown, and preview states
struct FloatingDockRootView: View {
  @Bindable var browserState: BrowserState
  @Bindable var dockState: FloatingDockState

  var body: some View {
    VStack(spacing: 0) {
      // Main dock bar (always visible)
      DockBarView(
        browserState: browserState,
        dockState: dockState
      )
      .frame(height: 44)
      .zIndex(1)  // Keep dock above connector

      // Conditional UI below dock
      switch dockState.currentState {
      case .condensed:
        EmptyView()
      case .tabDropdown:
        VStack(spacing: 0) {
          // Connector
          Triangle()
            .fill(.ultraThickMaterial)
            .frame(width: 20, height: 10)
            .offset(y: 1)  // Overlap slightly to avoid gaps
            .zIndex(1)

          TabDropdownView(
            browserState: browserState,
            dockState: dockState
          )
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      case .tabPreview(let tabId):
        VStack(spacing: 0) {
          // Connector
          Triangle()
            .fill(.ultraThickMaterial)
            .frame(width: 20, height: 10)
            .offset(y: 1)  // Overlap slightly to avoid gaps
            .zIndex(1)

          TabPreviewView(
            browserState: browserState,
            dockState: dockState,
            tabId: tabId
          )
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .environment(\.colorScheme, .dark)  // Force dark mode
  }
}

// Simple Triangle Shape for connector
struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

// =============================================================================
// MARK: - Dock Bar View
// =============================================================================

/// Icon bar in condensed state
/// Shows colorful icons for Tabs, Documents, Notes, Settings, and Apps
struct DockBarView: View {
  @Bindable var browserState: BrowserState
  @Bindable var dockState: FloatingDockState

  var body: some View {
    HStack(spacing: 7) {
      // Drag handle button (left side)
      // DockDragButton()

      // Tabs icon (colorful blue when selected)
      DockIconButton(
        icon: "square.stack.3d.up.fill",
        iconColor: .blue,
        label: "Tabs",
        isSelected: dockState.currentState != .condensed && dockState.selectedQuickAccessApp == nil
      ) {
        handleTabsIconClick()
      }

      // Documents/Pages icon
      // DockIconButton(
      //   icon: "doc.fill",
      //   iconColor: .purple,
      //   label: "Documents"
      // ) {
      //   // TODO: Implement documents
      // }

      // Note/Clipboard icon
      // DockIconButton(
      //   icon: "note.text",
      //   iconColor: .orange,
      //   label: "Notes"
      // ) {
      //   // TODO: Implement notes
      // }

      // Settings icon
      // DockIconButton(
      //   icon: "gearshape.fill",
      //   iconColor: .gray,
      //   label: "Settings"
      // ) {
      //   // TODO: Implement settings
      // }

      // YouTube icon
      DockIconButton(
        icon: "icon_youtube",
        isSystemIcon: false,
        iconColor: .red,
        label: "YouTube",
        isSelected: dockState.selectedQuickAccessApp == "YouTube"
      ) {
        openWebsiteInPreview(url: "https://youtube.com", appName: "YouTube")
      }

      // ChatGPT icon
      DockIconButton(
        icon: "icon_chatgpt",
        isSystemIcon: false,
        iconColor: .cyan,
        label: "ChatGPT",
        isSelected: dockState.selectedQuickAccessApp == "ChatGPT"
      ) {
        openWebsiteInPreview(url: "https://chat.openai.com", appName: "ChatGPT")
      }

      // WhatsApp icon
      DockIconButton(
        icon: "icon_whatsapp",
        isSystemIcon: false,
        iconColor: .green,
        label: "WhatsApp",
        isSelected: dockState.selectedQuickAccessApp == "WhatsApp"
      ) {
        openWebsiteInPreview(url: "https://web.whatsapp.com", appName: "WhatsApp")
      }

      // Gmail icon
      DockIconButton(
        icon: "icon_gmail",
        isSystemIcon: false,
        iconColor: .red,
        label: "Gmail",
        isSelected: dockState.selectedQuickAccessApp == "Gmail"
      ) {
        openWebsiteInPreview(url: "https://mail.google.com", appName: "Gmail")
      }

      // Search button (last icon) - expands into search bar
      DockSearchButton(
        dockState: dockState,
        browserState: browserState
      )

      // Close button (right side) - slim chevron
      DockCloseButton(dockState: dockState)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.ultraThickMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func handleTabsIconClick() {
    withAnimation(ArcTheme.springAnimation) {
      switch dockState.currentState {
      case .condensed:
        dockState.selectedQuickAccessApp = nil
        dockState.currentState = .tabDropdown
      case .tabDropdown:
        dockState.selectedQuickAccessApp = nil
        dockState.currentState = .condensed
      case .tabPreview:
        // From any preview (app or tab), switch to tab dropdown
        dockState.selectedQuickAccessApp = nil
        dockState.currentState = .tabDropdown
      }
    }
  }

  private func openWebsiteInPreview(url: String, appName: String) {
    // Toggle off if this app is already selected
    if dockState.selectedQuickAccessApp == appName {
      withAnimation(ArcTheme.springAnimation) {
        dockState.selectedQuickAccessApp = nil
        dockState.currentState = .condensed
      }
      return
    }

    // Reuse existing quick-access tab if it's still registered in tabManager
    if let tabId = dockState.quickAccessTabs[appName],
      browserState.tabManager.tab(for: tabId) != nil
    {
      withAnimation(ArcTheme.springAnimation) {
        dockState.selectedQuickAccessApp = appName
        dockState.currentState = .tabPreview(tabId: tabId)
      }
      return
    }

    guard let websiteURL = URL(string: url),
      let host = websiteURL.host
    else { return }

    let persistence = FolderTabPersistence.shared
    let allFolderIds = browserState.folderManager.folders.map(\.id)

    // Search all folders for an existing tab matching this host
    if let (_, existingTab) = persistence.findTab(matchingHost: host, inFolders: allFolderIds) {
      browserState.tabManager.insertBackgroundTab(existingTab)
      dockState.quickAccessTabs[appName] = existingTab.id
      withAnimation(ArcTheme.springAnimation) {
        dockState.selectedQuickAccessApp = appName
        dockState.currentState = .tabPreview(tabId: existingTab.id)
      }
      return
    }

    // No existing tab — create in the misc folder and register with tabManager
    let newTab = Tab(url: websiteURL, title: appName)
    persistence.appendTab(newTab, toFolder: Folder.miscId)
    browserState.tabManager.insertBackgroundTab(newTab)
    dockState.quickAccessTabs[appName] = newTab.id

    withAnimation(ArcTheme.springAnimation) {
      dockState.selectedQuickAccessApp = appName
      dockState.currentState = .tabPreview(tabId: newTab.id)
    }
  }
}

// =============================================================================
// MARK: - Dock Icon Button
// =============================================================================

/// Individual icon button in the dock bar
/// Supports colorful icons with hover and selection states
struct DockIconButton: View {
  let icon: String
  var isSystemIcon: Bool = true
  var iconColor: Color = .white
  let label: String
  var isSelected: Bool = false
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Group {
        if isSystemIcon {
          Image(systemName: icon)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(iconColor)
        } else {
          Image(icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(2)
        }
      }
      .frame(width: 28, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isSelected || isHovering ? Color.white.opacity(0.15) : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? iconColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
      )
    }
    .buttonStyle(.plain)
    .help(label)
    .onHover { hovering in
      withAnimation(ArcTheme.hoverAnimation) {
        isHovering = hovering
      }
    }
  }
}

// =============================================================================
// MARK: - Dock Drag Button
// =============================================================================

/// Drag handle button on the left side of the dock
/// Visual indicator for where to drag the dock (actual dragging handled by DockDragHandler)
struct DockDragButton: View {
  @State private var isHovering = false

  var body: some View {
    Image(systemName: "line.3.horizontal")
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(Color.white.opacity(isHovering ? 0.6 : 0.3))
      .frame(width: 24, height: 28)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
      )
      .help("Drag to move dock")
      .onHover { hovering in
        withAnimation(ArcTheme.hoverAnimation) {
          isHovering = hovering
        }
      }
  }
}

// =============================================================================
// MARK: - Tab Dropdown View (Finder Column View)
// =============================================================================

/// Finder-style column view: folders on the left, tabs for selected folder on the right
struct TabDropdownView: View {
  @Bindable var browserState: BrowserState
  @Bindable var dockState: FloatingDockState

  @State private var folderTabs: [Tab] = []

  private var folders: [Folder] {
    browserState.folderManager.sortedFolders
  }

  private var filteredTabs: [Tab] {
    if dockState.tabSearchQuery.isEmpty {
      return folderTabs
    }
    return folderTabs.filter {
      $0.title.localizedCaseInsensitiveContains(dockState.tabSearchQuery)
        || $0.url.absoluteString.localizedCaseInsensitiveContains(dockState.tabSearchQuery)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Search bar spans full width
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .font(.system(size: 13))

        TextField("Search tabs...", text: $dockState.tabSearchQuery)
          .textFieldStyle(.plain)
          .font(.system(size: 13))

        if !dockState.tabSearchQuery.isEmpty {
          Button {
            dockState.tabSearchQuery = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .font(.system(size: 13))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(10)
      .background(Color.white.opacity(0.08))

      Divider()
        .background(Color.white.opacity(0.1))

      // Two-column layout: folders | tabs
      HStack(spacing: 0) {
        // Left column: folder list
        folderColumn
          .frame(width: 160)

        Divider()
          .background(Color.white.opacity(0.1))

        // Right column: tabs for selected folder
        tabColumn
          .frame(maxWidth: .infinity)
      }
      .frame(maxHeight: 280)
    }
    .frame(maxWidth: .infinity)
    .background(.ultraThickMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .environment(\.colorScheme, .dark)
    .onAppear {
      if dockState.selectedDropdownFolderId == nil, let first = folders.first {
        dockState.selectedDropdownFolderId = first.id
      }
      loadTabsForSelectedFolder()
    }
    .onChange(of: dockState.selectedDropdownFolderId) { _, _ in
      loadTabsForSelectedFolder()
    }
  }

  // MARK: - Folder Column

  private var folderColumn: some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(spacing: 0) {
        ForEach(folders) { folder in
          FolderColumnRow(
            folder: folder,
            isSelected: dockState.selectedDropdownFolderId == folder.id
          ) {
            dockState.selectedDropdownFolderId = folder.id
          }
        }
      }
      .padding(.vertical, 4)
    }
  }

  // MARK: - Tab Column

  private var tabColumn: some View {
    Group {
      if filteredTabs.isEmpty {
        VStack(spacing: 6) {
          Image(systemName: "tray")
            .font(.system(size: 20))
            .foregroundStyle(.tertiary)
          Text(dockState.tabSearchQuery.isEmpty ? "No tabs" : "No matches")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(spacing: 0) {
            ForEach(filteredTabs) { tab in
              TabDropdownRow(
                tab: tab,
                onSelect: {
                  withAnimation(ArcTheme.springAnimation) {
                    dockState.selectedQuickAccessApp = nil
                    dockState.currentState = .tabPreview(tabId: tab.id)
                  }
                }
              )
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  // MARK: - Data Loading

  private func loadTabsForSelectedFolder() {
    guard let folderId = dockState.selectedDropdownFolderId else {
      folderTabs = []
      return
    }

    // If this is the currently active folder, use live tabs
    if folderId == browserState.currentFolderId {
      folderTabs = browserState.tabs
    } else {
      folderTabs = FolderTabPersistence.shared.loadTabs(forFolder: folderId) ?? []
    }
  }
}

// =============================================================================
// MARK: - Folder Column Row
// =============================================================================

/// Row in the folder column of the dropdown
struct FolderColumnRow: View {
  let folder: Folder
  let isSelected: Bool
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 8) {
        Image(systemName: folder.icon)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(folder.color)
          .symbolRenderingMode(.hierarchical)
          .frame(width: 16)

        Text(folder.name)
          .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? .primary : .secondary)
          .lineLimit(1)

        Spacer()

        if isSelected {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isSelected ? folder.color.opacity(0.18) : (isHovering ? Color.white.opacity(0.06) : Color.clear))
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 4)
    .onHover { hovering in
      withAnimation(ArcTheme.hoverAnimation) {
        isHovering = hovering
      }
    }
  }
}

// =============================================================================
// MARK: - Tab Dropdown Row
// =============================================================================

/// Individual tab row in the dropdown
struct TabDropdownRow: View {
  let tab: Tab
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 10) {
        if let icon = tab.icon {
          Image(nsImage: icon)
            .resizable()
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
          Image(systemName: "globe")
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
        }

        Text(tab.title.isEmpty ? "New Tab" : tab.title)
          .font(.system(size: 12))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.tail)

        Spacer()

        Text(tab.url.host ?? "")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isHovering ? Color.white.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 4)
    .onHover { hovering in
      withAnimation(ArcTheme.hoverAnimation) {
        isHovering = hovering
      }
    }
  }
}

// =============================================================================
// MARK: - Tab Preview View
// =============================================================================

/// Live CEF browser preview for selected tab
struct TabPreviewView: View {
  @Bindable var browserState: BrowserState
  @Bindable var dockState: FloatingDockState
  let tabId: UUID

  private var resolvedTab: Tab? {
    browserState.tabManager.tab(for: tabId)
  }

  var body: some View {
    VStack(spacing: 0) {
      if let tab = resolvedTab {
        let previewPageId = tab.stackModeEnabled ? (tab.activePage?.browserId ?? tabId) : tabId
        BrowserCanvas(
          browserState: browserState,
          pageId: previewPageId,
          parentTabId: tabId,
          url: tab.url
        )
        .frame(maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThickMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .environment(\.colorScheme, .dark)
  }
}

// Extension to allow cursor modifier (available in newer SwiftUI but good helper)
extension View {
  func cursor(_ cursor: NSCursor) -> some View {
    onHover { hovering in
      if hovering {
        cursor.push()
      } else {
        cursor.pop()
      }
    }
  }
}

// =============================================================================
// MARK: - Dock Close Button
// =============================================================================

/// Slim chevron button to close/hide the dock
struct DockCloseButton: View {
  @Bindable var dockState: FloatingDockState
  @State private var isHovering = false

  var body: some View {
    Button {
      withAnimation(ArcTheme.springAnimation) {
        dockState.isVisible = false
      }
    } label: {
      Image(systemName: "chevron.left")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.white.opacity(isHovering ? 0.8 : 0.4))
        .frame(width: 20, height: 36)
    }
    .buttonStyle(.plain)
    .help("Close Dock")
    .onHover { hovering in
      withAnimation(ArcTheme.hoverAnimation) {
        isHovering = hovering
      }
    }
  }
}

// =============================================================================
// MARK: - Dock Search Button
// =============================================================================

/// Search button that expands into a full search bar
struct DockSearchButton: View {
  @Bindable var dockState: FloatingDockState
  @Bindable var browserState: BrowserState
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    Group {
      if dockState.isSearchExpanded {
        // Expanded search bar
        DockSearchBar(
          dockState: dockState,
          browserState: browserState,
          isSearchFocused: _isSearchFocused
        )
        .transition(.scale.combined(with: .opacity))
      } else {
        // Collapsed search button
        Button {
          withAnimation(ArcTheme.springAnimation) {
            dockState.selectedQuickAccessApp = nil  // Clear app selection when searching
            dockState.isSearchExpanded = true
            isSearchFocused = true
          }
        } label: {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help("Search")
        .transition(.scale.combined(with: .opacity))
      }
    }
  }
}

// =============================================================================
// MARK: - Dock Search Bar
// =============================================================================

/// Inline search bar with plugin support
struct DockSearchBar: View {
  @Bindable var dockState: FloatingDockState
  @Bindable var browserState: BrowserState
  @FocusState var isSearchFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      // Search icon or plugin icon
      if let plugin = dockState.dockActivePlugin {
        Image(systemName: plugin.icon)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.purple)
      } else {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
      }

      // Plugin chip when active
      if let plugin = dockState.dockActivePlugin {
        HStack(spacing: 4) {
          Text(plugin.name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.purple)
        )
      }

      // Text field with autocomplete
      ZStack(alignment: .leading) {
        // Autocomplete hint
        if let plugin = dockState.dockAutocompletePlugin, !dockState.dockSearchText.isEmpty {
          Text(plugin.trigger)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.tertiary)
        }

        TextField(
          dockState.dockActivePlugin != nil ? "Enter query..." : "Search or URL...",
          text: $dockState.dockSearchText
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .focused($isSearchFocused)
        .onSubmit {
          submitSearch()
        }
        .onChange(of: dockState.dockSearchText) { oldValue, newValue in
          handleTextChange(oldValue: oldValue, newValue: newValue)
        }
      }
      .frame(width: 180)

      // Tab hint for autocomplete
      if dockState.dockAutocompletePlugin != nil {
        Text("Tab")
          .font(.system(size: 9, weight: .medium, design: .rounded))
          .foregroundStyle(.white)
          .padding(.horizontal, 4)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 3)
              .fill(Color.purple.opacity(0.8))
          )
      }

      // Close search button
      Button {
        withAnimation(ArcTheme.springAnimation) {
          dockState.isSearchExpanded = false
          dockState.dockSearchText = ""
          dockState.dockActivePlugin = nil
          dockState.dockShowPluginList = false
          dockState.dockAutocompletePlugin = nil
        }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white.opacity(0.1))
    )
    .onKeyPress(.tab) {
      handleTabPress()
      return .handled
    }
    .onAppear {
      // Auto-focus search field when search bar appears
      isSearchFocused = true
    }
  }

  // MARK: - Search Logic

  private func handleTextChange(oldValue: String, newValue: String) {
    // Only process plugin triggers when no plugin is active
    guard dockState.dockActivePlugin == nil else {
      dockState.dockShowPluginList = false
      dockState.dockAutocompletePlugin = nil
      return
    }

    // Check for configured AI trigger (e.g. "/autourl")
    let trigger = browserState.settingsManager.autoUrlTrigger
    if newValue == trigger {
      if let plugin = availablePlugins.first(where: { $0.id == "autourl" }) {
        selectPlugin(plugin)
        return
      }
    }

    // Check for "/" at start to show plugin list
    if newValue == "/" {
      dockState.dockShowPluginList = true
      dockState.dockAutocompletePlugin = nil
      return
    }

    // Check for partial plugin trigger match (autocomplete)
    if newValue.hasPrefix("/") && newValue.count > 1 {
      let lowercased = newValue.lowercased()
      if let match = availablePlugins.first(where: {
        $0.trigger.lowercased().hasPrefix(lowercased)
      }) {
        dockState.dockAutocompletePlugin = match
        dockState.dockShowPluginList = false
      } else if trigger.lowercased().hasPrefix(lowercased) {
        // Also match vs the custom trigger in settings
        if let autoUrlPlugin = availablePlugins.first(where: { $0.id == "autourl" }) {
          dockState.dockAutocompletePlugin = autoUrlPlugin
          dockState.dockShowPluginList = false
        }
      } else {
        dockState.dockAutocompletePlugin = nil
        dockState.dockShowPluginList = false
      }
      return
    }

    // No plugin trigger
    dockState.dockShowPluginList = false
    dockState.dockAutocompletePlugin = nil
  }

  private func handleTabPress() {
    // If autocomplete is available, select that plugin
    if let plugin = dockState.dockAutocompletePlugin {
      selectPlugin(plugin)
      return
    }

    // If plugin list is showing, select first plugin
    if dockState.dockShowPluginList, let firstPlugin = availablePlugins.first {
      selectPlugin(firstPlugin)
      return
    }
  }

  private func selectPlugin(_ plugin: CommandBarPlugin) {
    dockState.dockActivePlugin = plugin
    dockState.dockSearchText = ""
    dockState.dockShowPluginList = false
    dockState.dockAutocompletePlugin = nil
    isSearchFocused = true
  }

  private func submitSearch() {
    let input = dockState.dockSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return }

    navigateToInput(input)
  }

  private func navigateToInput(_ input: String) {
    Task {
      let (url, _) = await browserState.settingsManager.resolveInput(for: input)

      await MainActor.run {
        let newTab = browserState.createTab(url: url)
        transitionToPreview(tabId: newTab.id)
      }
    }
  }

  private func transitionToPreview(tabId: UUID) {
    withAnimation(ArcTheme.springAnimation) {
      // Clear search state
      dockState.isSearchExpanded = false
      dockState.dockSearchText = ""
      dockState.dockActivePlugin = nil
      dockState.dockShowPluginList = false
      dockState.dockAutocompletePlugin = nil
      dockState.selectedQuickAccessApp = nil

      // Transition to preview mode
      dockState.currentState = .tabPreview(tabId: tabId)
    }
  }
}
