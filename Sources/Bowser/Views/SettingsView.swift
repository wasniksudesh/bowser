// SettingsView.swift - Settings Configuration Window
// Main coordinator for the settings UI
// Phase 1 Implementation

import SwiftUI

// =============================================================================
// MARK: - Settings Category
// =============================================================================

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General"
    case search = "Search"
    case privacy = "Privacy & Security"
    case extensions = "Extensions"
    case ai = "AI Features"
    case widgets = "Widgets"
    case dock = "Floating Dock"
    case shortcuts = "Keyboard Shortcuts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .search: return "magnifyingglass"
        case .privacy: return "lock.shield"
        case .extensions: return "puzzlepiece.extension"
        case .ai: return "sparkles"
        case .widgets: return "square.grid.2x2"
        case .dock: return "dock.rectangle"
        case .shortcuts: return "command"
        }
    }
}

// =============================================================================
// MARK: - Settings View
// =============================================================================

struct SettingsView: View {

    @Bindable var browserState: BrowserState
    @Environment(\.dismiss) private var dismiss

    // Selection state
    @State private var selectedCategory: SettingsCategory? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                NavigationLink(value: category) {
                    Label(category.rawValue, systemImage: category.icon)
                        .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .frame(minWidth: 220)
        } detail: {
            if let category = selectedCategory {
                SettingsDetailView(category: category, browserState: browserState)
            } else {
                Text("Select a category")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 800, height: 600)
    }
}

// =============================================================================
// MARK: - Detail View
// =============================================================================

struct SettingsDetailView: View {
    let category: SettingsCategory
    @Bindable var browserState: BrowserState

    var body: some View {
        Form {
            switch category {
            case .general:
                GeneralSettingsView(manager: browserState.settingsManager)
            case .search:
                SearchSettingsView(manager: browserState.settingsManager)
            case .privacy:
                PrivacySettingsView(manager: browserState.settingsManager)
            case .extensions:
                ExtensionsSettingsView(manager: browserState.extensionManager)
            case .ai:
                AISettingsView(manager: browserState.settingsManager)
            case .widgets:
                WidgetsSettingsView(widgetManager: browserState.widgetManager)
            case .dock:
                DockSettingsView(dockState: browserState.floatingDockState)
            case .shortcuts:
                ShortcutsSettingsView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.rawValue)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct SettingsView_Previews: PreviewProvider {
        static var previews: some View {
            SettingsView(browserState: BrowserState())
        }
    }
#endif
