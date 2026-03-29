import SwiftUI

/// Modal sheet that drives the full Gmail OAuth consent flow inside a
/// dedicated WKWebView popup.
///
/// Completion is driven exclusively by polling GET /api/oauth/gmail/status/{state}
/// every second.  All other paths (WKWebView fast intercept, JS message handler)
/// are opportunistic — they attempt the exchange but never cancel the poller or
/// drive the final UI transition themselves.  This avoids race conditions where
/// both the fast path and the fallback GET callback fire for the same code.
struct OAuthSheet: View {

    let sessionId: String
    let authId: String
    var onComplete: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum SheetState {
        case loading
        case ready(authURL: URL, state: String)
        case exchanging
        case failed(String)
    }

    @State private var sheetState: SheetState = .loading
    @State private var pollingTask: Task<Void, Never>? = nil
    /// Guards against finishAuth() being called twice (race between poller and fast path).
    @State private var authCompleted = false

    private let backendBase = "http://localhost:8765"
    private let callbackURLPrefix = "http://localhost:8765/api/oauth/gmail/callback"

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Sign in with Google")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    pollingTask?.cancel()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ZStack {
                switch sheetState {
                case .loading:
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.2)
                        Text("Preparing sign-in…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let authURL, _):
                    OAuthWebView(
                        authURL: authURL,
                        callbackURLPrefix: callbackURLPrefix,
                        onCallbackIntercepted: { code, receivedState in
                            // Opportunistic fast path: try to exchange the code ourselves.
                            // We do NOT cancel the poller here — if the GET callback already
                            // consumed the state, the poller will detect completion regardless.
                            Task { await attemptExchange(code: code, state: receivedState) }
                        },
                        onExchangeCompleted: {
                            // JS message handler signal — backend already exchanged the code.
                            // The poller will detect this within 1 second; nothing to do here.
                        }
                    )

                case .exchanging:
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.2)
                        Text("Completing sign-in…")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.orange)
                        Text("Authentication Failed")
                            .font(.system(size: 16, weight: .semibold))
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Try Again") {
                            authCompleted = false
                            sheetState = .loading
                            Task { await startOAuth() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 520, height: 620)
        .task { await startOAuth() }
        .onDisappear { pollingTask?.cancel() }
    }

    // MARK: - Auth completion (single exit point)

    @MainActor
    private func finishAuth() {
        guard !authCompleted else { return }
        authCompleted = true
        pollingTask?.cancel()
        print("[OAuth Frontend] OAuth completed")
        onComplete(authId, "oauth_token_stored")
        dismiss()
    }

    // MARK: - Network

    @MainActor
    private func startOAuth() async {
        sheetState = .loading
        authCompleted = false
        do {
            guard let url = URL(string: "\(backendBase)/api/oauth/gmail/start") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "session_id": sessionId, "auth_id": authId
            ])

            let (data, _) = try await URLSession.shared.data(for: req)
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let authURLString = json["auth_url"] as? String,
                let authURL = URL(string: authURLString),
                let state = json["state"] as? String
            else {
                sheetState = .failed("Unexpected response from server")
                return
            }

            sheetState = .ready(authURL: authURL, state: state)
            startPolling(state: state)

        } catch {
            sheetState = .failed(error.localizedDescription)
        }
    }

    /// Polls GET /api/oauth/gmail/status/{state} every second.
    /// This is the sole driver of finishAuth() — it fires regardless of which
    /// backend path (fast-path POST /exchange or fallback GET /callback) ran.
    private func startPolling(state: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            guard let url = URL(string: "\(backendBase)/api/oauth/gmail/status/\(state)") else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let completed = json["completed"] as? Bool, completed
                    {
                        await MainActor.run { finishAuth() }
                        return
                    }
                } catch {
                    // Network blip — keep polling
                }
            }
        }
    }

    /// Opportunistically attempt to exchange the code via POST /exchange.
    /// Does NOT cancel the poller or drive the UI transition — the poller does that.
    /// If the state was already consumed by the GET callback, this is a silent no-op.
    @MainActor
    private func attemptExchange(code: String, state: String) async {
        sheetState = .exchanging
        do {
            guard let url = URL(string: "\(backendBase)/api/oauth/gmail/exchange") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "code": code, "state": state
            ])
            let (_, _) = try await URLSession.shared.data(for: req)
            // Whether it succeeds or "state already consumed", the poller will
            // detect _oauth_completed[state] == True and call finishAuth().
        } catch {
            // Network error — poller will still resolve the final state.
        }
    }
}
