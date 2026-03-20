// CommandBarView.swift - Arc-Style Floating Command Bar
// Spotlight-like search/navigation overlay with persistent history

import AppKit
import SwiftUI

// =============================================================================
// MARK: - CommandBar Plugin
// =============================================================================

/// Represents a plugin that can be activated in the CommandBar
struct CommandBarPlugin: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let trigger: String
    let description: String
}

/// Available plugins for the CommandBar
let availablePlugins: [CommandBarPlugin] = [
    CommandBarPlugin(
        id: "autourl",
        name: "AutoURL",
        icon: "wand.and.stars",
        trigger: "/autourl",
        description: "AI resolves your query to a direct URL"
    ),
    CommandBarPlugin(
        id: "plan",
        name: "Search Plans",
        icon: "lightbulb.fill",
        trigger: "/plan",
        description: "Search and open your plans"
    )
]

// =============================================================================
// MARK: - Command Bar View (Main Overlay)
// =============================================================================

/// Arc-style floating Command Bar for search and URL navigation.
/// Presented as a modal overlay when user clicks '+' or presses CMD+T.
///
/// ## Visual Design
/// - Centered floating panel with ultra-thin material background
/// - Rounded corners (16pt) with subtle drop shadow
/// - Auto-focused text field with search icon
/// - Keyboard-navigable history list below
///
/// ## Workflow
/// 1. User triggers ('+' button or CMD+T)
/// 2. Command Bar appears with dimmed background
/// 3. Text field auto-focuses
/// 4. User types → history filters in real-time
/// 5. User presses Enter or selects suggestion
/// 6. Command Bar dismisses → new tab created with URL
struct CommandBarView: View {

    // MARK: - Environment & State

    /// Browser state for tab creation
    @Bindable var browserState: BrowserState

    /// Search history store
    private let historyStore = SearchHistoryStore.shared

    /// Dismiss callback
    var onDismiss: () -> Void

    /// Callback when navigation is confirmed (creates tab)
    var onNavigate: (URL) -> Void

    /// Search/URL input text
    @State private var searchText: String = ""

    /// Focus state for the text field
    @FocusState private var isTextFieldFocused: Bool

    /// Currently selected index in history list (for keyboard navigation)
    @State private var selectedIndex: Int = -1

    // MARK: - Plugin State

    /// Currently active plugin (when user has selected one)
    @State private var activePlugin: CommandBarPlugin? = nil

    /// Whether to show the plugin list dropdown
    @State private var showPluginList: Bool = false

    /// Plugin that matches current autocomplete (for Tab completion)
    @State private var autocompletePlugin: CommandBarPlugin? = nil

    /// Filtered history based on current search text
    private var filteredHistory: [SearchHistoryItem] {
        // Don't show history when plugin list is visible or when plan plugin is active
        if showPluginList || activePlugin?.id == "plan" { return [] }
        return historyStore.filter(by: searchText)
    }
    
    /// Filtered plans based on current search text
    private var filteredPlans: [PlanMetadata] {
        let plans = browserState.planState.availablePlans
        
        // When plan plugin is active, show all plans if search is empty
        if activePlugin?.id == "plan" {
            if searchText.isEmpty {
                return plans
            }
        } else if searchText.isEmpty {
            // Don't show plans in integrated search when search is empty
            return []
        }
        
        // Filter by search text
        let lowercasedSearch = searchText.lowercased()
        return plans.filter { plan in
            plan.name.lowercased().contains(lowercasedSearch) ||
            plan.intent.lowercased().contains(lowercasedSearch)
        }
    }
    
    /// Whether to show plan results
    private var shouldShowPlans: Bool {
        return !filteredPlans.isEmpty && !showPluginList
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // ═══════════════════════════════════════════════════════════════
            // MARK: Dimmed Backdrop
            // Semi-transparent overlay that dims the background
            // ═══════════════════════════════════════════════════════════════
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissCommandBar()
                }

            // ═══════════════════════════════════════════════════════════════
            // MARK: Command Bar Panel
            // Floating card with search field and history list
            // ═══════════════════════════════════════════════════════════════
            VStack(spacing: 0) {
                // ───────────────────────────────────────────────────────────
                // Search Input Field
                // ───────────────────────────────────────────────────────────
                searchFieldSection

                // ───────────────────────────────────────────────────────────
                // Plugin List Dropdown (when "/" is typed)
                // ───────────────────────────────────────────────────────────
                if showPluginList {
                    Divider()
                        .padding(.horizontal, 16)

                    pluginListSection
                }

                // ───────────────────────────────────────────────────────────
                // Plan Results (shown above history)
                // ───────────────────────────────────────────────────────────
                if shouldShowPlans {
                    Divider()
                        .padding(.horizontal, 16)

                    planResultsSection
                }
                
                // ───────────────────────────────────────────────────────────
                // History/Suggestions List
                // ───────────────────────────────────────────────────────────
                if !filteredHistory.isEmpty && !showPluginList {
                    Divider()
                        .padding(.horizontal, 16)

                    historyListSection
                }
            }
            .frame(width: 560)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            // Position in upper-third of window for comfortable reach
            .padding(.bottom, 200)
        }
        .onAppear {
            // Auto-focus the text field immediately
            isTextFieldFocused = true
            selectedIndex = -1
        }
        .onExitCommand {
            // ESC key dismisses
            dismissCommandBar()
        }
        .onKeyPress(.upArrow) {
            navigateHistory(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateHistory(direction: 1)
            return .handled
        }
        .onKeyPress(.tab) {
            handleTabPress()
            return .handled
        }
    }

    // MARK: - Search Field Section

    private var searchFieldSection: some View {
        HStack(spacing: 12) {
            // Search icon (or plugin icon when active)
            if let plugin = activePlugin {
                Image(systemName: plugin.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.purple)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Plugin chip (when active)
            if let plugin = activePlugin {
                HStack(spacing: 4) {
                    Text(plugin.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.purple)
                )
            }

            // Text field with autocomplete overlay
            ZStack(alignment: .leading) {
                // Autocomplete hint (grayed out completion)
                if let plugin = autocompletePlugin, !searchText.isEmpty {
                    Text(plugin.trigger)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                // Actual text field
                TextField(
                    activePlugin != nil ? "Enter your query..." : "Search or enter URL...",
                    text: $searchText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .focused($isTextFieldFocused)
                .onSubmit {
                    submitInput()
                }
                .onChange(of: searchText) { oldValue, newValue in
                    handleTextChange(oldValue: oldValue, newValue: newValue)
                }
            }

            // Clear button (when text is present)
            if !searchText.isEmpty || activePlugin != nil {
                Button {
                    if searchText.isEmpty && activePlugin != nil {
                        // Clear plugin
                        activePlugin = nil
                    } else {
                        searchText = ""
                    }
                    showPluginList = false
                    autocompletePlugin = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            // Keyboard shortcut hint (or Tab hint for autocomplete)
            if autocompletePlugin != nil {
                Text("Tab")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple.opacity(0.8))
                    )
            } else {
                Text("⌘T")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - History List Section

    private var historyListSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, item in
                        HistoryRowView(
                            item: item,
                            isSelected: index == selectedIndex,
                            onSelect: {
                                selectHistoryItem(item)
                            },
                            onDelete: {
                                deleteHistoryItem(item)
                            }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0 {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Plan Results Section
    
    private var planResultsSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    // Section header (only when showing integrated results)
                    if activePlugin?.id != "plan" {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                            
                            Text("PLANS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }
                    
                    ForEach(Array(filteredPlans.enumerated()), id: \.element.id) { index, plan in
                        PlanResultRowView(
                            plan: plan,
                            isSelected: index == selectedIndex && activePlugin?.id == "plan",
                            onSelect: {
                                selectPlan(plan)
                            }
                        )
                        .id("plan-\(index)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) { _, newIndex in
                if newIndex >= 0 && activePlugin?.id == "plan" {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("plan-\(newIndex)", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Plugin List Section

    private var pluginListSection: some View {
        VStack(spacing: 2) {
            ForEach(availablePlugins) { plugin in
                Button {
                    selectPlugin(plugin)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: plugin.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.purple)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.trigger)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)

                            Text(plugin.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text("Tab")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    /// Handle text changes for plugin detection
    private func handleTextChange(oldValue: String, newValue: String) {
        // Reset selection when text changes
        selectedIndex = -1

        // Only process plugin triggers when no plugin is active
        guard activePlugin == nil else {
            showPluginList = false
            autocompletePlugin = nil
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
            showPluginList = true
            autocompletePlugin = nil
            return
        }

        // Check for partial plugin trigger match (autocomplete)
        if newValue.hasPrefix("/") && newValue.count > 1 {
            let lowercased = newValue.lowercased()
            // Check available plugins
            if let match = availablePlugins.first(where: {
                $0.trigger.lowercased().hasPrefix(lowercased)
            }) {
                autocompletePlugin = match
                showPluginList = false
            } else if trigger.lowercased().hasPrefix(lowercased) {
                // Also match vs the custom trigger in settings
                if let autoUrlPlugin = availablePlugins.first(where: { $0.id == "autourl" }) {
                    autocompletePlugin = autoUrlPlugin
                    showPluginList = false
                }
            } else {
                autocompletePlugin = nil
                showPluginList = false
            }
            return
        }

        // No plugin trigger
        showPluginList = false
        autocompletePlugin = nil
    }

    /// Handle Tab key press for plugin selection
    private func handleTabPress() {
        // If autocomplete is available, select that plugin
        if let plugin = autocompletePlugin {
            selectPlugin(plugin)
            return
        }

        // If plugin list is showing, select first plugin
        if showPluginList, let firstPlugin = availablePlugins.first {
            selectPlugin(firstPlugin)
            return
        }
    }

    /// Select a plugin and activate it
    private func selectPlugin(_ plugin: CommandBarPlugin) {
        activePlugin = plugin
        searchText = ""
        showPluginList = false
        autocompletePlugin = nil
        isTextFieldFocused = true
    }

    /// Navigate through history with arrow keys
    private func navigateHistory(direction: Int) {
        // For plan plugin, navigate through plans
        if activePlugin?.id == "plan" {
            let count = filteredPlans.count
            guard count > 0 else { return }
            
            if selectedIndex < 0 {
                selectedIndex = direction > 0 ? 0 : count - 1
            } else {
                selectedIndex = (selectedIndex + direction + count) % count
            }
            return
        }
        
        // For normal search, navigate through history
        let count = filteredHistory.count
        guard count > 0 else { return }

        if selectedIndex < 0 {
            // First navigation
            selectedIndex = direction > 0 ? 0 : count - 1
        } else {
            // Move selection
            selectedIndex = (selectedIndex + direction + count) % count
        }

        // Update text field with selected item
        if selectedIndex >= 0 && selectedIndex < count {
            searchText = filteredHistory[selectedIndex].text
        }
    }

    /// Submit the current input (Enter key)
    private func submitInput() {
        // If a history item is selected, use it
        if selectedIndex >= 0 && selectedIndex < filteredHistory.count {
            selectHistoryItem(filteredHistory[selectedIndex])
            return
        }

        // Otherwise, process the text input
        let input = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            dismissCommandBar()
            return
        }

        // Check if plugin is active
        if let plugin = activePlugin {
            handlePluginSubmit(plugin: plugin, query: input)
            return
        }

        navigateToInput(input)
    }

    /// Handle submit when a plugin is active
    private func handlePluginSubmit(plugin: CommandBarPlugin, query: String) {
        switch plugin.id {
        case "autourl":
            // Use async task for API call
            Task {
                await resolveAutoURL(query: query)
            }
        case "plan":
            // If a plan is selected, open it
            if selectedIndex >= 0 && selectedIndex < filteredPlans.count {
                selectPlan(filteredPlans[selectedIndex])
            }
        default:
            // Unknown plugin, fallback to normal navigation
            navigateToInput(query)
        }
    }
    
    /// Select a plan and switch to Plan mode
    private func selectPlan(_ plan: PlanMetadata) {
        // Switch to Plan mode
        browserState.currentPanelMode = .plan
        
        // Load the plan
        browserState.planState.loadPlan(id: plan.id)
        
        // Dismiss command bar
        dismissCommandBar()
    }

    /// Resolve query using AutoURL plugin
    private func resolveAutoURL(query: String) async {
        do {
            let model = browserState.settingsManager.aiModel
            let resolvedURLString = try await AIService.shared.resolveURL(
                query: query, model: model)

            // Validate URL
            guard let url = URL(string: resolvedURLString) else {
                // Invalid URL, fallback to Google search
                await MainActor.run {
                    navigateToInput(query)
                }
                return
            }

            // Save to history with plugin prefix
            await MainActor.run {
                historyStore.addEntry(
                    text: "[AutoURL] \(query)",
                    resolvedURL: url.absoluteString,
                    isSearchQuery: false
                )

                onNavigate(url)
                dismissCommandBar()
            }
        } catch {
            // API error, fallback to Google search
            print(
                "[CommandBar] AutoURL failed: \(error.localizedDescription), falling back to search"
            )
            await MainActor.run {
                navigateToInput(query)
            }
        }
    }

    /// Process text input and navigate
    private func navigateToInput(_ input: String) {
        Task {
            let (url, isAutoURL) = await browserState.settingsManager.resolveInput(for: input)

            await MainActor.run {
                // Save to history
                historyStore.addEntry(
                    text: isAutoURL ? "[AutoURL] \(input)" : input,
                    resolvedURL: url.absoluteString,
                    isSearchQuery: !isAutoURL && !looksLikeURL(input)
                )

                // Trigger navigation callback
                onNavigate(url)
                dismissCommandBar()
            }
        }
    }

    /// Select a history item
    private func selectHistoryItem(_ item: SearchHistoryItem) {
        if let urlString = item.resolvedURL, let url = URL(string: urlString) {
            // Update history timestamp
            historyStore.touchEntry(item)

            onNavigate(url)
        } else {
            // Re-process the text
            navigateToInput(item.text)
            return
        }

        dismissCommandBar()
    }

    /// Delete a history item
    private func deleteHistoryItem(_ item: SearchHistoryItem) {
        historyStore.deleteEntry(item)
    }

    /// Dismiss the command bar
    private func dismissCommandBar() {
        onDismiss()
    }

    /// Heuristic to detect if input is a URL vs search query
    private func looksLikeURL(_ input: String) -> Bool {
        // Contains no spaces and has a dot (domain-like)
        if !input.contains(" ") && input.contains(".") {
            return true
        }

        // Starts with http/https
        if input.hasPrefix("http://") || input.hasPrefix("https://") {
            return true
        }

        // Localhost
        if input.hasPrefix("localhost") {
            return true
        }

        return false
    }
}

// =============================================================================
// MARK: - History Row View
// =============================================================================

/// Single row in the history suggestion list.
/// Displays icon, text, domain, and supports hover/selection states.
private struct HistoryRowView: View {

    let item: SearchHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Type icon
                Image(systemName: item.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let domain = item.domain, domain != item.text {
                        Text(domain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Delete button (on hover)
                if isHovering || isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                }

                // Return hint when selected
                if isSelected {
                    Text("↩")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return ArcTheme.highlightColor.opacity(0.2)
        } else if isHovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var iconColor: Color {
        switch item.iconName {
        case "lock.fill":
            return .green
        case "magnifyingglass":
            return .secondary
        default:
            return .secondary
        }
    }
}

// =============================================================================
// MARK: - Plan Result Row View
// =============================================================================

/// Single row in the plan results list
private struct PlanResultRowView: View {
    
    let plan: PlanMetadata
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Plan icon
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(plan.intent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Progress
                    HStack(spacing: 4) {
                        Text(plan.progressText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        
                        Text(plan.relativeTimeText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                // Return hint when selected
                if isSelected {
                    Text("↩")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return ArcTheme.highlightColor.opacity(0.2)
        } else if isHovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct CommandBarView_Previews: PreviewProvider {
        static var previews: some View {
            ZStack {
                Color.gray.opacity(0.3)
                    .ignoresSafeArea()

                CommandBarView(
                    browserState: BrowserState(),
                    onDismiss: {},
                    onNavigate: { _ in }
                )
            }
            .frame(width: 800, height: 600)
        }
    }
#endif
