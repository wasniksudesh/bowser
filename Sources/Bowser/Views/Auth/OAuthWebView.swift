import SwiftUI
import WebKit

/// WKWebView that loads the Google OAuth consent page.
///
/// Two completion paths:
///   **Fast path** – `decidePolicyFor` intercepts the redirect to
///     `callbackURLPrefix?code=...&state=...` before it loads.
///     Fires `onCallbackIntercepted(code, state)`.
///
///   **Fallback** – The redirect actually loads on the backend
///     (`GET /api/oauth/gmail/callback`), which exchanges the code and
///     returns HTML that calls `window.webkit.messageHandlers.oauthComplete`.
///     The `WKScriptMessageHandler` fires `onExchangeCompleted()`.
struct OAuthWebView: NSViewRepresentable {

    let authURL: URL
    let callbackURLPrefix: String

    /// Fast path: redirect intercepted, code + state extracted.
    var onCallbackIntercepted: (String, String) -> Void

    /// Fallback: the backend GET callback already exchanged the code.
    var onExchangeCompleted: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "oauthComplete")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Standard Safari user-agent so Google doesn't gate the consent flow
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.load(URLRequest(url: authURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            callbackURLPrefix: callbackURLPrefix,
            onCallbackIntercepted: onCallbackIntercepted,
            onExchangeCompleted: onExchangeCompleted
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        private let callbackURLPrefix: String
        private let onCallbackIntercepted: (String, String) -> Void
        private let onExchangeCompleted: () -> Void
        private var handled = false

        init(
            callbackURLPrefix: String,
            onCallbackIntercepted: @escaping (String, String) -> Void,
            onExchangeCompleted: @escaping () -> Void
        ) {
            self.callbackURLPrefix = callbackURLPrefix
            self.onCallbackIntercepted = onCallbackIntercepted
            self.onExchangeCompleted = onExchangeCompleted
        }

        // MARK: WKNavigationDelegate – fast path

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.absoluteString.hasPrefix(callbackURLPrefix) {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let code = components?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""
                let state = components?.queryItems?.first(where: { $0.name == "state" })?.value ?? ""

                if !code.isEmpty && !handled {
                    handled = true
                    decisionHandler(.cancel)
                    onCallbackIntercepted(code, state)
                    return
                }
            }

            decisionHandler(.allow)
        }

        // MARK: WKScriptMessageHandler – fallback path

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "oauthComplete", !handled else { return }
            handled = true

            if let body = message.body as? [String: Any],
               let status = body["status"] as? String,
               status == "success"
            {
                onExchangeCompleted()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {}
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {}
    }
}
