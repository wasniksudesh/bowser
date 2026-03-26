//
//  CarouselComponent.swift
//  Bowser
//
//  Product/image carousel component with skeleton loader.
//  Each card shows an image (if available) or an iframe of the product page URL as fallback.
//

import SwiftUI
import WebKit

// =============================================================================
// MARK: - Carousel Card Data Model
// =============================================================================

/// Data model for a carousel card. Supports rich product cards as well as
/// the legacy image-only shape (url + caption).
struct CarouselCardData: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    /// Direct image URL (shown as AsyncImage when non-empty)
    let image: String?
    /// Product / page URL (used as iframe fallback when image is absent)
    let url: String?
    /// Backward-compat caption (used as title fallback)
    let caption: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        image: String? = nil,
        url: String? = nil,
        caption: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.image = image
        self.url = url
        self.caption = caption
    }

    /// Backward-compatible init from the old CarouselImageData shape.
    init(legacyURL: String, caption: String?) {
        self.id = UUID().uuidString
        self.title = caption ?? ""
        self.description = nil
        self.image = legacyURL
        self.url = nil
        self.caption = caption
    }

    /// Legacy init matching old CarouselImageData(id:, url:, caption:) signature.
    init(id: String = UUID().uuidString, url: String, caption: String? = nil) {
        self.id = id
        self.title = caption ?? ""
        self.description = nil
        self.image = url
        self.url = nil
        self.caption = caption
    }

    /// Whether to render an image card (vs iframe fallback).
    var hasImage: Bool {
        guard let img = image else { return false }
        return !img.isEmpty
    }

    /// Whether there is a URL to use as iframe fallback.
    var hasURL: Bool {
        guard let u = url else { return false }
        return !u.isEmpty
    }
}

// Keep the old type alias so call sites that still use CarouselImageData compile.
typealias CarouselImageData = CarouselCardData

// =============================================================================
// MARK: - Lightweight WKWebView wrapper
// =============================================================================

/// Non-interactive embedded web preview (iframe equivalent).
/// Link clicks are intercepted and discarded so the card acts as a preview only.
private struct EmbeddedWebView: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        // Transparent background so card rounded corners show through
        webView.setValue(false, forKey: "drawsBackground")
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: urlString),
              webView.url?.absoluteString != urlString else { return }
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow only the initial page load; block all link navigations
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// =============================================================================
// MARK: - Carousel Component
// =============================================================================

/// Product/image carousel component with horizontal scrolling.
/// Cards render as image cards when an image URL is present, or as an iframe
/// of the product page URL when the image is absent.
struct CarouselComponent: View {

    let images: [CarouselCardData]
    let isLoading: Bool

    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                skeletonLoader
            } else if !images.isEmpty {
                loadedCarousel
            } else {
                emptyState
            }
        }
    }

    // MARK: - Skeleton Loader

    private var skeletonLoader: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 240)
                .overlay(ProgressView().controlSize(.large))
                .shimmer()

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 80, height: 12)
                    .shimmer()
                Spacer()
            }
        }
    }

    // MARK: - Loaded Carousel

    private var loadedCarousel: some View {
        VStack(spacing: 12) {
            let currentCard = images[safe: selectedIndex]
            let cardHeight: CGFloat = (currentCard?.hasImage == true) ? 240 : 560

            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, card in
                    cardView(for: card)
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.easeInOut(duration: 0.2), value: cardHeight)
            .overlay(alignment: .leading) {
                if images.count > 1 && selectedIndex > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { selectedIndex -= 1 }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .cursor(.pointingHand)
                }
            }
            .overlay(alignment: .trailing) {
                if images.count > 1 && selectedIndex < images.count - 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { selectedIndex += 1 }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .cursor(.pointingHand)
                }
            }

            // Caption / description + page indicator
            if let card = images[safe: selectedIndex] {
                cardFooter(for: card)
            }
        }
    }

    // MARK: - Card View

    @ViewBuilder
    private func cardView(for card: CarouselCardData) -> some View {
        if card.hasImage, let imageURL = card.image {
            imageCard(urlString: imageURL, card: card)
        } else if card.hasURL, let pageURL = card.url {
            iframeCard(urlString: pageURL, card: card)
        } else {
            placeholderCard(card: card)
        }
    }

    // Image card: AsyncImage filling the card, with title/description overlay at bottom
    private func imageCard(urlString: String, card: CarouselCardData) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))

            case .success(let image):
                ZStack(alignment: .bottom) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    // Gradient overlay with title / description
                    if !card.title.isEmpty || card.description != nil {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.65)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .overlay(alignment: .bottomLeading) {
                            cardTextOverlay(card: card)
                        }
                    }
                }

            case .failure:
                // Image URL failed — fall back to iframe if URL available, else placeholder
                if card.hasURL, let pageURL = card.url {
                    iframeCard(urlString: pageURL, card: card)
                } else {
                    placeholderCard(card: card)
                }

            @unknown default:
                EmptyView()
            }
        }
    }

    // Iframe card: embedded WKWebView preview (bigger card, title/description below)
    private func iframeCard(urlString: String, card: CarouselCardData) -> some View {
        EmbeddedWebView(urlString: urlString)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Fallback placeholder when neither image nor URL is available
    private func placeholderCard(card: CarouselCardData) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if !card.title.isEmpty {
                Text(card.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // Text overlay shown on top of image cards
    private func cardTextOverlay(card: CarouselCardData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !card.title.isEmpty {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            if let desc = card.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // Footer shown below each card (for iframe cards; image cards use overlay instead)
    @ViewBuilder
    private func cardFooter(for card: CarouselCardData) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                // For iframe cards, show title/description below since there's no overlay
                if !card.hasImage {
                    if !card.title.isEmpty {
                        Text(card.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    if let desc = card.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if let caption = card.caption ?? (card.title.isEmpty ? nil : card.title) {
                    // Image cards: show caption/title below image
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Page indicator dots
            HStack(spacing: 6) {
                ForEach(0..<min(images.count, 5), id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No items available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}

// =============================================================================
// MARK: - Shimmer Effect Modifier
// =============================================================================

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, Color.white.opacity(0.3), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .frame(width: 300)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 500
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// =============================================================================
// MARK: - Array Safe Subscript
// =============================================================================

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct CarouselComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            VStack(alignment: .leading) {
                Text("Loading State").font(.caption).foregroundStyle(.secondary)
                CarouselComponent(images: [], isLoading: true)
            }
            .padding()

            VStack(alignment: .leading) {
                Text("Image Cards").font(.caption).foregroundStyle(.secondary)
                CarouselComponent(
                    images: [
                        CarouselCardData(
                            title: "Supabase",
                            description: "Open source Firebase alternative with Postgres.",
                            image: "https://picsum.photos/400/300?random=1",
                            url: "https://supabase.com"
                        ),
                        CarouselCardData(
                            title: "Linear",
                            description: "The issue tracker built for modern software teams.",
                            image: "https://picsum.photos/400/300?random=2",
                            url: "https://linear.app"
                        )
                    ],
                    isLoading: false
                )
            }
            .padding()

            VStack(alignment: .leading) {
                Text("Iframe Fallback Cards").font(.caption).foregroundStyle(.secondary)
                CarouselComponent(
                    images: [
                        CarouselCardData(
                            title: "Vercel",
                            description: "Deploy web projects with zero configuration.",
                            image: nil,
                            url: "https://vercel.com"
                        ),
                        CarouselCardData(
                            title: "Fly.io",
                            description: "Run full-stack apps and databases close to your users.",
                            image: "",
                            url: "https://fly.io"
                        )
                    ],
                    isLoading: false
                )
            }
            .padding()
        }
        .frame(width: 400)
    }
}
#endif
