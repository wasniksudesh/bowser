//
//  MapsComponent.swift
//  Bowser
//
//  Interactive map component with collapsible header and draggable resize
//

import Foundation
import SwiftUI
import AppKit

// =============================================================================
// MARK: - Maps Data Model
// =============================================================================

/// Data model for maps component
struct MapsData: Codable, Identifiable {
    let id: String
    let targetURL: String
    let title: String?
    let searchQuery: String?
    
    init(id: String = UUID().uuidString, targetURL: String, title: String? = nil, searchQuery: String? = nil) {
        self.id = id
        self.targetURL = targetURL
        self.title = title
        self.searchQuery = searchQuery
    }
}

// =============================================================================
// MARK: - Maps Component
// =============================================================================

/// Interactive map component with collapsible header and draggable resize
struct MapsComponent: View {
    
    let data: MapsData?
    let isLoading: Bool
    
    @State private var isExpanded: Bool = true
    @State private var containerHeight: CGFloat = 300
    
    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 600
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                skeletonLoader
            } else if let data = data {
                loadedView(data: data)
            } else {
                emptyState
            }
        }
    }
    
    // MARK: - Skeleton Loader
    
    private var skeletonLoader: some View {
        VStack(spacing: 0) {
            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 120, height: 16)
                    .shimmer()
                
                Spacer()
                
                Image(systemName: "chevron.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .opacity(0.3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Map skeleton
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 300)
                .overlay(
                    ProgressView()
                        .controlSize(.large)
                )
                .shimmer()
        }
    }
    
    // MARK: - Loaded View
    
    private func loadedView(data: MapsData) -> some View {
        VStack(spacing: 0) {
            // Collapsible header
            headerView(data: data)
            
            // Map content (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    // CEF map view
                    MapsCEFView(url: data.targetURL)
                        .frame(height: containerHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // Bottom resize handle
                    ResizeHandleView(height: $containerHeight, minHeight: minHeight, maxHeight: maxHeight)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
    }
    
    private func headerView(data: MapsData) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            HStack {
                // Map icon
                Image(systemName: "map.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 16))
                
                // Title
                Text(data.title ?? "Map")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                // Search query (if available)
                if let query = data.searchQuery, !query.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(query)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Chevron indicator
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 20))
                    .rotationEffect(.degrees(isExpanded ? 0 : 180))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .opacity(0.5)
            
            Text("No map data available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}

// =============================================================================
// MARK: - Resize Handle View
// =============================================================================

/// Draggable resize handle for the bottom of the map container
struct ResizeHandleView: NSViewRepresentable {
    @Binding var height: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    func makeNSView(context: Context) -> ResizeHandleNSView {
        let view = ResizeHandleNSView()
        view.onHeightChange = { delta in
            let newHeight = height + delta
            height = min(max(newHeight, minHeight), maxHeight)
        }
        return view
    }
    
    func updateNSView(_ nsView: ResizeHandleNSView, context: Context) {}
}

/// NSView that handles the drag gesture for resizing
class ResizeHandleNSView: NSView {
    var onHeightChange: ((CGFloat) -> Void)?
    
    private var isDragging = false
    private var dragStartY: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        // Set fixed height for the handle
        let heightConstraint = heightAnchor.constraint(equalToConstant: 8)
        heightConstraint.isActive = true
        
        // Add tracking area for cursor changes
        updateTrackingAreas()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeUpDown.push()
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            NSCursor.pop()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStartY = event.locationInWindow.y
        NSCursor.resizeUpDown.push()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        
        let currentY = event.locationInWindow.y
        let delta = dragStartY - currentY  // Inverted: dragging down increases height
        
        onHeightChange?(delta)
        
        dragStartY = currentY
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        NSCursor.pop()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw subtle grip indicator
        let context = NSGraphicsContext.current?.cgContext
        context?.setFillColor(NSColor.separatorColor.cgColor)
        
        // Draw three horizontal lines (grip dots)
        let lineWidth: CGFloat = 30
        let lineHeight: CGFloat = 2
        let spacing: CGFloat = 2
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        
        for i in -1...1 {
            let rect = CGRect(
                x: centerX - lineWidth / 2,
                y: centerY + CGFloat(i) * (lineHeight + spacing) - lineHeight / 2,
                width: lineWidth,
                height: lineHeight
            )
            context?.fill(rect)
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct MapsComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Loaded state
            MapsComponent(
                data: MapsData(
                    targetURL: "https://www.google.com/maps/search/?api=1&query=Starbucks+near+Times+Square",
                    title: "Nearby Locations",
                    searchQuery: "Starbucks near Times Square"
                ),
                isLoading: false
            )
            
            // Loading state
            MapsComponent(data: nil, isLoading: true)
            
            // Empty state
            MapsComponent(data: nil, isLoading: false)
        }
        .padding()
        .frame(width: 600)
    }
}
#endif
