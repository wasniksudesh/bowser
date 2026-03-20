// PrivacySettingsView.swift
import SwiftUI

struct PrivacySettingsView: View {
  @Bindable var manager: SettingsManager

  @State private var showClearDataConfirmation = false

  var body: some View {
    Section("Browsing Data") {
      Button("Clear browsing data...") {
        showClearDataConfirmation = true
      }
      .alert("Clear Browsing Data", isPresented: $showClearDataConfirmation) {
        Button("Clear", role: .destructive) {
          manager.clearBrowsingData()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will clear all cookies and site data. You will be signed out of most websites.")
      }
    }

    Section("Cookies") {
      Picker("Cookie settings", selection: $manager.cookiePolicy) {
        ForEach(CookiePolicy.allCases) { policy in
          Text(policy.rawValue).tag(policy)
        }
      }
    }

    Section("Site Permissions") {
      PermissionRow(title: "Camera", icon: "video.fill", selection: $manager.cameraPermission)
      PermissionRow(title: "Microphone", icon: "mic.fill", selection: $manager.microphonePermission)
      PermissionRow(
        title: "Location", icon: "location.fill", selection: $manager.locationPermission)
      PermissionRow(
        title: "Notifications", icon: "bell.fill", selection: $manager.notificationsPermission)
      PermissionRow(title: "Pop-ups", icon: "app.badge.fill", selection: $manager.popupsPermission)
    }

    Section("Content Redaction") {
      Toggle("Automatically redact sensitive content when pasting", isOn: $manager.redactorEnabled)
      Text("Blurs faces in images and redacts personally identifiable information (PII) such as names, emails, phone numbers, and social security numbers in text.")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }
  }
}

private struct PermissionRow: View {
  let title: String
  let icon: String
  @Binding var selection: PermissionStatus

  var body: some View {
    LabeledContent {
      Picker(title, selection: $selection) {
        ForEach(PermissionStatus.allCases) { status in
          Text(status.rawValue).tag(status)
        }
      }
      .labelsHidden()
      .fixedSize()
    } label: {
      Label(title, systemImage: icon)
        .font(.system(size: 13))
    }
  }
}
