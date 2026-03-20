// DockSettingsView.swift
import SwiftUI

struct DockSettingsView: View {
  @Bindable var dockState: FloatingDockState

  var body: some View {
    Section("Visibility") {
      Toggle("Show floating dock", isOn: $dockState.isVisible)
      // "Dock stays on top" is not in FloatingDockState yet, verify?
      // Assuming it's not, we can toggle it if added, or skip for now.
    }

    Section("Layout") {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Preview Height")
            .font(.system(size: 13))
          Spacer()
          Text("\(Int(dockState.previewHeight))pt")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        Slider(value: $dockState.previewHeight, in: 300...600, step: 10)
      }
      .padding(.vertical, 4)

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Container Width")
            .font(.system(size: 13))
          Spacer()
          Text("\(Int(dockState.previewWidth))pt")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        Slider(value: $dockState.previewWidth, in: 300...800, step: 10)
      }
      .padding(.vertical, 4)
    }
  }
}
