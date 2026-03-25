// LicenseView.swift - License entry screen shown before app access
// Minimal full-screen view with key input and activation

import SwiftUI

// =============================================================================
// MARK: - License View
// =============================================================================

struct LicenseView: View {

    var onVerified: () -> Void

    @State private var licenseKey = ""
    @State private var isVerifying = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            UnifiedBackdropView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    // Icon
                    Image(systemName: "key.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    // Title
                    Text("Enter License Key")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Enter your license key to activate Bowser.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    // Input field
                    VStack(spacing: 12) {
                        TextField("ORGID-XXXX-XXXX-XXXX", text: $licenseKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, design: .monospaced))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(errorMessage != nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                            .frame(maxWidth: 340)
                            .disabled(isVerifying)
                            .onSubmit { activate() }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // Activate button
                    Button(action: activate) {
                        Group {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Activate")
                            }
                        }
                        .frame(width: 120, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isVerifying)
                }
                .padding(40)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: errorMessage != nil)
    }

    // MARK: - Actions

    private func activate() {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isVerifying = true
        errorMessage = nil

        Task { @MainActor in
            do {
                _ = try await LicenseService.shared.verifyLicense(key: key)
                onVerified()
            } catch {
                errorMessage = error.localizedDescription
            }
            isVerifying = false
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct LicenseView_Previews: PreviewProvider {
    static var previews: some View {
        LicenseView(onVerified: {})
            .frame(width: 600, height: 500)
    }
}
#endif
