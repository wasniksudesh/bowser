//
//  WidgetsSettingsView.swift
//  Bowser
//
//  Settings panel for discovering and managing homescreen widgets.
//

import SwiftUI

// =============================================================================
// MARK: - Widgets Settings View
// =============================================================================

struct WidgetsSettingsView: View {

    @Bindable var widgetManager: WidgetManager
    @State private var search = ""
    @State private var addedIds: Set<String> = []

    private var registry: BuiltinWidgetRegistry { widgetManager.builtinRegistry }

    private var filteredDescriptors: [BuiltinWidgetDescriptor] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return registry.allDescriptors() }
        return registry.allDescriptors().filter {
            $0.displayName.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private var placedBuiltinWidgets: [HomescreenWidgetInstance] {
        widgetManager.widgets.filter { $0.kind == .builtin }
    }

    var body: some View {
        Group {
            Section("Available Widgets") {
                if filteredDescriptors.isEmpty {
                    Text("No widgets match \"\(search)\"")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(filteredDescriptors) { descriptor in
                        widgetRow(descriptor)
                    }
                }
            }

            if !placedBuiltinWidgets.isEmpty {
                Section("On Homescreen") {
                    ForEach(placedBuiltinWidgets) { widget in
                        placedRow(widget)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search widgets")
    }

    // MARK: - Available Widget Row

    private func widgetRow(_ descriptor: BuiltinWidgetDescriptor) -> some View {
        LabeledContent {
            Button("Add to Homescreen") {
                widgetManager.addBuiltinWidget(typeId: descriptor.typeId)
                addedIds.insert(descriptor.typeId)
                // Brief feedback reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    addedIds.remove(descriptor.typeId)
                }
            }
            .disabled(false)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(addedIds.contains(descriptor.typeId) ? .green : .accentColor)
            .overlay {
                if addedIds.contains(descriptor.typeId) {
                    Label("Added", systemImage: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                        .allowsHitTesting(false)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: descriptor.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Text(descriptor.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Placed Widget Row

    private func placedRow(_ widget: HomescreenWidgetInstance) -> some View {
        LabeledContent {
            Button("Remove") {
                withAnimation {
                    widgetManager.removeWidget(widget.id)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        } label: {
            HStack(spacing: 10) {
                let desc = registry.descriptor(for: widget.outputComponentType)
                Image(systemName: desc?.icon ?? "square.grid.2x2")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(desc?.displayName ?? widget.query)
                        .font(.system(size: 13))
                    Text("Grid position: \(widget.gridOrder + 1)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
