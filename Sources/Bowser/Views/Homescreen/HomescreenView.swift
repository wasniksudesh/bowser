// HomescreenView.swift - macOS-desktop-style homescreen with folder grid
// Full-screen canvas: folders in auto-layout grid + bottom dock bar

import SwiftUI

// =============================================================================
// MARK: - Homescreen View
// =============================================================================

/// The app's homescreen — a full-window desktop canvas showing project folders
/// in an auto-layout grid with a bottom dock bar, consistent with ArcTheme.
struct HomescreenView: View {

    @Bindable var appNav: AppNavigationState
    @Bindable var browserState: BrowserState

    @State private var showingNewFolderSheet = false
    @State private var newFolderName = ""
    @State private var newFolderAlertPresented = false
    @State private var showingHistorySidebar = true
    @State private var historySearchText = ""
    @State private var searchState = HomescreenSearchState()

    private var folderManager: FolderManager { browserState.folderManager }

    var body: some View {
        ZStack(alignment: .bottom) {
            UnifiedBackdropView()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // Left sidebar: global history
                if showingHistorySidebar {
                    historySidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Main content: folder grid
                folderGridCanvas
            }

            // Dismiss scrim when search results are showing
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

            // Bottom dock bar + attached search card
            VStack(spacing: 6) {
                if searchState.showResults {
                    HomescreenSearchResultsView(
                        searchState: searchState,
                        browserState: browserState
                    )
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
    }

    // MARK: - History Sidebar

    private var historySidebar: some View {
        VStack(spacing: 0) {
            // Search bar inside sidebar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search history", text: $historySearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !historySearchText.isEmpty {
                    Button {
                        historySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            GlobalHistoryView(
                browserState: browserState,
                appNav: appNav,
                searchText: $historySearchText
            )
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }

    // MARK: - Folder Grid Canvas

    private var folderGridCanvas: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 16)],
                alignment: .leading,
                spacing: 18
            ) {
                // Existing folders
                ForEach(folderManager.sortedFolders) { folder in
                    FolderIconView(
                        folder: folder,
                        onOpen: {
                            openFolder(folder)
                        },
                        onRename: { newName in
                            folderManager.rename(folder, to: newName)
                        },
                        onSetColor: { color in
                            folderManager.setColor(folder, to: color)
                        },
                        onDelete: {
                            folderManager.delete(folder)
                            FolderTabPersistence.shared.deleteFolder(folder.id)
                            FolderHistoryPersistence.shared.deleteFolder(folder.id)
                        },
                        onDuplicate: {
                            folderManager.copyFolder(folder)
                        }
                    )
                }

                // New folder button at end of grid
                NewFolderButton {
                    presentNewFolderPrompt()
                }
            }
            .padding(.top, 60)  // clearance for traffic lights
            .padding(.horizontal, 40)
            .padding(.bottom, 100) // clearance for bottom bar
        }
    }

    // MARK: - Actions

    private func openFolder(_ folder: Folder) {
        // Switch screen first so the transition animation can begin immediately,
        // then load folder data after a brief yield to avoid blocking the first frame.
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
        // Immediately open the new folder
        openFolder(folder)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct HomescreenView_Previews: PreviewProvider {
    static var previews: some View {
        HomescreenView(
            appNav: AppNavigationState(),
            browserState: BrowserState()
        )
        .frame(width: 1280, height: 800)
    }
}
#endif
