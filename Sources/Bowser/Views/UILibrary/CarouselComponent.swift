//
//  CarouselComponent.swift
//  Bowser
//
//  Image carousel component with skeleton loader
//

import SwiftUI

// =============================================================================
// MARK: - Carousel Data Model
// =============================================================================

/// Data model for carousel images
struct CarouselImageData: Codable, Identifiable {
    let id: String
    let url: String
    let caption: String?
    
    init(id: String = UUID().uuidString, url: String, caption: String? = nil) {
        self.id = id
        self.url = url
        self.caption = caption
    }
}

// =============================================================================
// MARK: - Carousel Component
// =============================================================================

/// Image carousel component with horizontal scrolling
struct CarouselComponent: View {
    
    let images: [CarouselImageData]
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
            // Image skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 240)
                .overlay(
                    ProgressView()
                        .controlSize(.large)
                )
                .shimmer()
            
            // Caption skeleton
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
            // Image viewer
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    imageView(for: image)
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                // Left navigation button - ALWAYS VISIBLE when applicable
                if images.count > 1 && selectedIndex > 0 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedIndex -= 1
                        }
                    }) {
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
                // Right navigation button - ALWAYS VISIBLE when applicable
                if images.count > 1 && selectedIndex < images.count - 1 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedIndex += 1
                        }
                    }) {
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
            
            // Caption and page indicator
            HStack {
                if let caption = images[safe: selectedIndex]?.caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<min(images.count, 5), id: \.self) { index in
                        Circle()
                            .fill(index == selectedIndex ? Color.blue : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
    
    // MARK: - Image View
    
    private func imageView(for image: CarouselImageData) -> some View {
        AsyncImage(url: URL(string: image.url)) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Failed to load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                
            @unknown default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No images available")
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
                    gradient: Gradient(colors: [
                        .clear,
                        Color.white.opacity(0.3),
                        .clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .frame(width: 300)
            )
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
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
            // Loading state
            VStack(alignment: .leading) {
                Text("Loading State")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CarouselComponent(images: [], isLoading: true)
            }
            .padding()
            
            // Loaded state with mock data
            VStack(alignment: .leading) {
                Text("Loaded State")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CarouselComponent(
                    images: [
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=1",
                            caption: "Beautiful sunset in Matera"
                        ),
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=2",
                            caption: "Ancient cave dwellings"
                        ),
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=3",
                            caption: "Historic architecture"
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
