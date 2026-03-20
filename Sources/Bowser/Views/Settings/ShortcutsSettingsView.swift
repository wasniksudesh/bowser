// ShortcutsSettingsView.swift
import SwiftUI

struct ShortcutsSettingsView: View {
  var body: some View {
    Section("Core Actions") {
      ShortcutRow(action: "New Tab", shortcut: "⌘T")
      ShortcutRow(action: "Close Tab", shortcut: "⌘W")
      ShortcutRow(action: "Next Tab", shortcut: "⌘⌥→")
      ShortcutRow(action: "Previous Tab", shortcut: "⌘⌥←")
      ShortcutRow(action: "Command Bar", shortcut: "⌘T")  // Note: Same as New Tab per plan
      ShortcutRow(action: "Settings", shortcut: "⌘,")
      ShortcutRow(action: "New Space", shortcut: "⌘⇧N")
    }
  }
}

struct ShortcutRow: View {
  let action: String
  let shortcut: String

  var body: some View {
    HStack {
      Text(action)
        .font(.system(size: 13))
        .foregroundStyle(.primary)
      Spacer()
      HStack(spacing: 4) {
        // split shortcut keys if possible for better visuals
        Text(shortcut)
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.secondary.opacity(0.1))
          )
      }
    }
    .padding(.vertical, 2)
  }
}
