import AppKit  // Required for NSWorkspace
import CoreServices  // Required for LSSetDefaultHandlerForURLScheme
// GeneralSettingsView.swift
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
  @Bindable var manager: SettingsManager

  @State private var isDefault: Bool = false

  var body: some View {
    // Using a Form to contain sections is common practice in Settings views
    // Standard macOS form layout provided by parent View
    Group {
      Section("Startup") {
        Picker("On startup", selection: $manager.onStartup) {
          ForEach(StartupBehavior.allCases, id: \.self) { behavior in
            Text(behavior.rawValue).tag(behavior)
          }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
      }

      Section("Default Browser") {
        HStack {
          if isDefault {
            Text("Bowser is your default browser")
              .font(.system(size: 13))
              .foregroundStyle(.green)
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
          } else {
            Text("Make Bowser your default browser")
              .font(.system(size: 13))
          }

          Spacer()

          if !isDefault {
            Button("Make Default") {
              setAsDefaultBrowser()
            }
          }
        }
      }

      Section("Downloads") {
        LabeledContent {
          HStack {
            Text(manager.downloadLocation)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Change...") {
              let panel = NSOpenPanel()
              panel.canChooseFiles = false
              panel.canChooseDirectories = true
              panel.canCreateDirectories = true
              panel.allowsMultipleSelection = false

              if panel.runModal() == .OK {
                if let url = panel.url {
                  manager.downloadLocation = url.path
                }
              }
            }
          }
        } label: {
          Text("Download location")
            .font(.system(size: 13))
        }

        Toggle("Ask where to save each file before downloading", isOn: $manager.askDownloadSave)
          .font(.system(size: 13))
      }
    }
    .onAppear {
      checkDefaultBrowser()
    }
  }

  private func checkDefaultBrowser() {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.company.Bowser"  // Fallback bundle ID
    // Check if we are the handler for http
    if let defaultApp = NSWorkspace.shared.urlForApplication(
      toOpen: URL(string: "http://www.google.com")!)
    {
      let defaultBundleID = Bundle(url: defaultApp)?.bundleIdentifier
      isDefault = (defaultBundleID == bundleID)
    }
  }

  private func setAsDefaultBrowser() {
    // Method to prompt user is deprecated in newer macOS, but open URL scheme approach is standard
    // For sandbox apps, this might be tricky, but let's try the modern way
    if let bundleID = Bundle.main.bundleIdentifier {
      let httpResult = LSSetDefaultHandlerForURLScheme("http" as CFString, bundleID as CFString)
      let httpsResult = LSSetDefaultHandlerForURLScheme("https" as CFString, bundleID as CFString)
      let htmlResult = LSSetDefaultRoleHandlerForContentType(
        UTType.html.identifier as CFString, LSRolesMask.all, bundleID as CFString)

      print(
        "[Settings] Set default browser result: http=\(httpResult), https=\(httpsResult), html=\(htmlResult)"
      )

      // Check again after a short delay as it might not be immediate and user needs to approve prompt
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        checkDefaultBrowser()
      }
    }
  }
}
