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

    private var folderManager: FolderManager { browserState.folderManager }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Unified vibrancy backdrop (matches browser backdrop)
            UnifiedBackdropView()
                .ignoresSafeArea()

            // Folder grid canvas
            folderGridCanvas

            // Bottom dock bar
            HomescreenBottomBar(
                browserState: browserState,
                appNav: appNav,
                onCreateFolder: { presentNewFolderPrompt() }
            )
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

    // MARK: - Folder Grid Canvas

    private var folderGridCanvas: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110, maximum: 130), spacing: 20)],
                alignment: .leading,
                spacing: 24
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            browserState.loadFolder(id: folder.id)
            appNav.openFolder(folder.id)
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
