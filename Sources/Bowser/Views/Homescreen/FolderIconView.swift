// FolderIconView.swift - A single folder icon on the homescreen desktop grid

import SwiftUI

// =============================================================================
// MARK: - Folder Icon View
// =============================================================================

/// Displays a single folder as a desktop icon: colored rounded rect, SF Symbol, name label.
/// Supports hover effects, click to open, and a context menu for rename/color/delete.
struct FolderIconView: View {

    let folder: Folder
    let onOpen: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (Color) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 6) {
            // Folder icon box
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(folder.color.opacity(isHovering ? 0.28 : 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(folder.color.opacity(isHovering ? 0.45 : 0.25), lineWidth: 1)
                    )

                Image(systemName: folder.icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(folder.color)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(isHovering ? 1.06 : 1.0)
            .shadow(
                color: folder.color.opacity(isHovering ? 0.25 : 0.0),
                radius: 6,
                y: 3
            )
            .animation(ArcTheme.hoverAnimation, value: isHovering)

            // Folder name (editable inline when renaming)
            if isRenaming {
                TextField("Folder name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.ultraThinMaterial)
                    )
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
            } else {
                Text(folder.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .onHover { isHovering = $0 }
        .contextMenu { contextMenuContent }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            renameText = folder.name
            isRenaming = true
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Menu("Color") {
            ForEach(Folder.availableColors, id: \.self) { color in
                Button {
                    onSetColor(color)
                } label: {
                    // SwiftUI doesn't support colored menu items natively;
                    // show the color name as a label
                    Text(colorName(color))
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private func colorName(_ color: Color) -> String {
        switch color {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .green: return "Green"
        case .orange: return "Orange"
        case .pink: return "Pink"
        case .cyan: return "Cyan"
        case .indigo: return "Indigo"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .teal: return "Teal"
        default: return "Custom"
        }
    }
}

// =============================================================================
// MARK: - New Folder Button
// =============================================================================

/// The "New Folder" add button shown at the end of the grid
struct NewFolderButton: View {

    let onCreate: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                Color.primary.opacity(isHovering ? 0.25 : 0.12),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    )

                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(ArcTheme.hoverAnimation, value: isHovering)

            Text("New Folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 72)
        }
        .contentShape(Rectangle())
        .onTapGesture { onCreate() }
        .onHover { isHovering = $0 }
    }
}
