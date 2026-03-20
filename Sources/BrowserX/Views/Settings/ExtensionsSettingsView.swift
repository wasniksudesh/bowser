// ExtensionsSettingsView.swift - Extensions Management UI
// Provides UI for managing browser extensions

import SwiftUI

struct ExtensionsSettingsView: View {
    @Bindable var manager: ExtensionManager

    @State private var showingFilePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Load button
            HStack {
                Text("Manage your browser extensions")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Load Unpacked Extension...") {
                    showFilePicker()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 16)

            // Extensions list
            if manager.extensions.isEmpty {
                emptyStateView
            } else {
                extensionsList
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Extensions Installed")
                .font(.system(size: 16, weight: .medium))

            Text("Click \"Load Unpacked Extension...\" to install an extension from a folder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Extensions List

    private var extensionsList: some View {
        List {
            ForEach(manager.extensions) { ext in
                ExtensionRowView(
                    extensionInfo: ext,
                    onToggle: { isEnabled in
                        toggleExtension(ext, enabled: isEnabled)
                    },
                    onOptions: {
                        manager.openOptionsPage(for: ext)
                    },
                    onRemove: {
                        removeExtension(ext)
                    }
                )
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Actions

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an unpacked extension folder containing manifest.json"

        if panel.runModal() == .OK {
            if let url = panel.url {
                Task {
                    await manager.loadExtension(from: url)
                }
            }
        }
    }

    private func toggleExtension(_ ext: ExtensionInfo, enabled: Bool) {
        // For now, we don't support enabling/disabling without unloading
        // In a full implementation, this would call CEF APIs to enable/disable
        print("[ExtensionsSettings] Toggle extension \(ext.name): \(enabled)")
    }

    private func removeExtension(_ ext: ExtensionInfo) {
        manager.unloadExtension(id: ext.id)
    }
}

// MARK: - Extension Row View

struct ExtensionRowView: View {
    let extensionInfo: ExtensionInfo
    let onToggle: (Bool) -> Void
    let onOptions: () -> Void
    let onRemove: () -> Void

    @State private var isEnabled: Bool

    init(
        extensionInfo: ExtensionInfo, onToggle: @escaping (Bool) -> Void,
        onOptions: @escaping () -> Void, onRemove: @escaping () -> Void
    ) {
        self.extensionInfo = extensionInfo
        self.onToggle = onToggle
        self.onOptions = onOptions
        self.onRemove = onRemove
        self._isEnabled = State(initialValue: extensionInfo.isEnabled)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Extension icon
            extensionIcon
                .frame(width: 48, height: 48)

            // Extension info
            VStack(alignment: .leading, spacing: 4) {
                Text(extensionInfo.name)
                    .font(.system(size: 14, weight: .medium))

                Text(extensionInfo.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("Version \(extensionInfo.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Controls
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, newValue in
                        onToggle(newValue)
                    }

                HStack(spacing: 8) {
                    if extensionInfo.optionsUrl != nil {
                        Button("Options") {
                            onOptions()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("Remove") {
                        onRemove()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var extensionIcon: some View {
        Group {
            if let iconPath = extensionInfo.iconPath,
                let image = NSImage(contentsOfFile: iconPath)
            {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct ExtensionsSettingsView_Previews: PreviewProvider {
        static var previews: some View {
            ExtensionsSettingsView(
                manager: ExtensionManager()
            )
            .frame(width: 700, height: 500)
        }
    }
#endif
