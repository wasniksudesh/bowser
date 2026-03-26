// HomescreenView.swift
// Two-column homescreen: narrow folder column + scrollable widget grid.
// Widgets are laid out in a grid (no free-form positioning) and support drag-to-reorder.

import SwiftUI
import UniformTypeIdentifiers

// =============================================================================
// MARK: - Homescreen View
// =============================================================================

struct HomescreenView: View {

    @Bindable var appNav: AppNavigationState
    @Bindable var browserState: BrowserState

    @State private var newFolderName = ""
    @State private var newFolderAlertPresented = false
    @State private var showingHistorySidebar = true
    @State private var historySearchText = ""
    @State private var searchState = HomescreenSearchState()

    // Drag-to-reorder state
    @State private var draggingWidgetId: UUID? = nil
    @State private var dropTargetIndex: Int? = nil

    private var folderManager: FolderManager { browserState.folderManager }
    private var widgetManager: WidgetManager { browserState.widgetManager }

    var body: some View {
        ZStack(alignment: .bottom) {
            UnifiedBackdropView()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left sidebar: global history (optional)
                if showingHistorySidebar {
                    historySidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Folder column — three 80pt columns + 2×12pt gaps + 2×16pt padding = 296pt
                folderColumn
                    .frame(width: 296)

                // Widget grid: takes remaining space
                if !widgetManager.orderedVisibleWidgets.isEmpty {
                    widgetGridArea
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Dim scrim when search results are showing
            if searchState.showResults {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            searchState.dismiss()
                        }
                    }
                    .transition(.opacity)
            }

            // Search results card + bottom dock bar
            VStack(spacing: 6) {
                if searchState.showResults {
                    HomescreenSearchResultsView(searchState: searchState, browserState: browserState)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HomescreenBottomBar(
                    browserState: browserState,
                    appNav: appNav,
                    onCreateFolder: { presentNewFolderPrompt() },
                    searchText: $historySearchText,
                    showingHistorySidebar: $showingHistorySidebar,
                    onSearch: { query in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            searchState.submitSearch(query: query)
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("New Folder", isPresented: $newFolderAlertPresented) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Enter a name for the new folder")
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showingHistorySidebar)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: widgetManager.orderedVisibleWidgets.count)
    }

    // MARK: - History Sidebar

    private var historySidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search history", text: $historySearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !historySearchText.isEmpty {
                    Button { historySearchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            GlobalHistoryView(browserState: browserState, appNav: appNav, searchText: $historySearchText)
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }

    // MARK: - Folder Column
    // Three fixed columns (~80pt each) fits the 72pt folder icons with spacing.

    private var folderColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.fixed(80), spacing: 12),
                    GridItem(.fixed(80), spacing: 12),
                    GridItem(.fixed(80), spacing: 12)
                ],
                alignment: .center,
                spacing: 16
            ) {
                ForEach(folderManager.sortedFolders) { folder in
                    FolderIconView(
                        folder: folder,
                        onOpen: { openFolder(folder) },
                        onRename: { folderManager.rename(folder, to: $0) },
                        onSetColor: { folderManager.setColor(folder, to: $0) },
                        onDelete: {
                            folderManager.delete(folder)
                            FolderTabPersistence.shared.deleteFolder(folder.id)
                            FolderHistoryPersistence.shared.deleteFolder(folder.id)
                        },
                        onDuplicate: { folderManager.copyFolder(folder) },
                        hasUnread: widgetManager.hasUnread(forFolder: folder.id)
                    )
                }
                NewFolderButton { presentNewFolderPrompt() }
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
    }

    // MARK: - Widget Grid Area
    // Adaptive columns based on available width. Widgets keep their natural size.
    // Supports drag-to-reorder.

    private var widgetGridArea: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(Array(widgetManager.orderedVisibleWidgets.enumerated()), id: \.element.id) { index, widget in
                    HomescreenWidgetView(
                        browserState: browserState,
                        widget: widget,
                        componentData: widgetManager.cachedData[widget.widgetId],
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                widgetManager.removeWidget(widget.id)
                            }
                        }
                    )
                    .opacity(draggingWidgetId == widget.id ? 0.4 : 1.0)
                    .overlay(alignment: .leading) {
                        // Drop insertion indicator
                        if dropTargetIndex == index && draggingWidgetId != widget.id {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: 3)
                                .padding(.vertical, 8)
                                .offset(x: -10)
                                .transition(.opacity)
                        }
                    }
                    .onDrag {
                        draggingWidgetId = widget.id
                        return NSItemProvider(object: widget.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.plainText], delegate: WidgetDropDelegate(
                        targetIndex: index,
                        draggingWidgetId: $draggingWidgetId,
                        dropTargetIndex: $dropTargetIndex,
                        onDrop: { fromId in
                            widgetManager.moveWidget(fromId: fromId, toIndex: index)
                        }
                    ))
                }
            }
            .padding(.top, 60)
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: widgetManager.orderedVisibleWidgets.map(\.id))
        }
    }

    // MARK: - Actions

    private func openFolder(_ folder: Folder) {
        appNav.openFolder(folder.id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            browserState.loadFolder(id: folder.id)
        }
    }

    private func presentNewFolderPrompt() {
        newFolderName = ""
        newFolderAlertPresented = true
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        let folderName = name.isEmpty ? "New Folder" : name
        let folder = folderManager.createFolder(name: folderName)
        newFolderName = ""
        openFolder(folder)
    }
}

// =============================================================================
// MARK: - Widget Drop Delegate
// =============================================================================

/// Handles drop events for widget drag-to-reorder in the grid.
private struct WidgetDropDelegate: DropDelegate {

    let targetIndex: Int
    @Binding var draggingWidgetId: UUID?
    @Binding var dropTargetIndex: Int?
    let onDrop: (UUID) -> Void

    func dropEntered(info: DropInfo) {
        dropTargetIndex = targetIndex
    }

    func dropExited(info: DropInfo) {
        if dropTargetIndex == targetIndex {
            dropTargetIndex = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetIndex = nil
        guard let draggingId = draggingWidgetId else { return false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            onDrop(draggingId)
        }
        draggingWidgetId = nil
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.plainText])
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct HomescreenView_Previews: PreviewProvider {
    static var previews: some View {
        HomescreenView(appNav: AppNavigationState(), browserState: BrowserState())
            .frame(width: 1280, height: 800)
    }
}
#endif
