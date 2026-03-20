// AISettingsView.swift
import SwiftUI

struct AISettingsView: View {
  @Bindable var manager: SettingsManager

  @State private var isTesting: Bool = false
  @State private var connectionStatus: ConnectionStatus = .none
  @State private var statusMessage: String?

  enum ConnectionStatus {
    case none, success, failure
  }

  var body: some View {
    Section("AI Provider") {
      Picker("Provider", selection: $manager.aiProvider) {
        ForEach(AIProvider.allCases) { provider in
          Text(provider.rawValue).tag(provider)
        }
      }
      .pickerStyle(.menu)

      VStack(alignment: .leading, spacing: 8) {
        Text("API Key")
        HStack {
          SecureField("Enter API Key", text: $manager.aiApiKey)
            .textFieldStyle(.roundedBorder)

          Button {
            testConnection()
          } label: {
            if isTesting {
              ProgressView().controlSize(.small)
            } else {
              Text("Test Connection")
            }
          }
          .disabled(manager.aiApiKey.isEmpty || isTesting)
        }

        if let message = statusMessage {
          Text(message)
            .font(.caption)
            .foregroundStyle(connectionStatus == .success ? .green : .red)
        }
      }

      // Model depending on provider
      Picker("Model", selection: $manager.aiModel) {
        if manager.aiProvider == .openai {
          Text("GPT-4o").tag("gpt-4o")
          Text("GPT-4 Turbo").tag("gpt-4-turbo")
          Text("GPT-3.5 Turbo").tag("gpt-3.5-turbo")
        } else if manager.aiProvider == .anthropic {
          Text("Claude 3 Opus").tag("claude-3-opus")
          Text("Claude 3 Sonnet").tag("claude-3-sonnet")
          Text("Claude 3 Haiku").tag("claude-3-haiku")
        } else {
          Text("Llama 3").tag("llama-3")
          Text("Mistral").tag("mistral")
        }
      }
    }

    Section("AutoURL Plugin") {
      Toggle("Enable AutoURL", isOn: $manager.autoUrlEnabled)
        .font(.system(size: 13))

      if manager.autoUrlEnabled {
        HStack {
          Text("Trigger phrase")
            .font(.system(size: 13))
          Spacer()
          TextField("/autourl", text: $manager.autoUrlTrigger)
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)
            .multilineTextAlignment(.leading)
        }

        Toggle("Fallback to search on error", isOn: $manager.autoUrlFallback)
          .font(.system(size: 13))
      }
    }
  }

  private func testConnection() {
    guard !manager.aiApiKey.isEmpty else { return }

    isTesting = true
    statusMessage = nil
    connectionStatus = .none

    Task {
      do {
        try await AIService.shared.configureAI(
          provider: manager.aiProvider.rawValue.lowercased(),
          apiKey: manager.aiApiKey
        )

        await MainActor.run {
          connectionStatus = .success
          statusMessage = "Connection successful"
          isTesting = false
        }
      } catch {
        await MainActor.run {
          connectionStatus = .failure
          statusMessage = "Connection failed: \(error.localizedDescription)"
          isTesting = false
        }
      }
    }
  }
}
