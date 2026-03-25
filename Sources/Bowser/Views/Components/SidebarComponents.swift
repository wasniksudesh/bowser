// SidebarComponents.swift - Reusable Sidebar View Components
// Extracted from SidebarView.swift during codebase cleanup
// Contains PinnedTabView, TabRowView, and Tab Preview support types

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// =============================================================================
// MARK: - NSImage Transparency Detection
// =============================================================================

extension NSImage {
    /// Detect if image has transparent pixels (PNG with alpha)
    var hasTransparency: Bool {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return true // Assume transparency if we can't check
        }
        
        // Check if the image has an alpha channel
        let alphaInfo = cgImage.alphaInfo
        switch alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        default:
            // Has alpha channel - sample corners to check for actual transparency
            return sampleForTransparency(cgImage: cgImage)
        }
    }
    
    /// Sample image corners and center for transparent pixels
    private func sampleForTransparency(cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0, height > 0,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        // Only check if we have alpha channel (4 bytes per pixel typically)
        guard bytesPerPixel >= 4 else { return false }
        
        // Sample points: corners + center
        let samplePoints = [
            (0, 0), (width - 1, 0),           // Top corners
            (0, height - 1), (width - 1, height - 1), // Bottom corners
            (width / 2, height / 2)            // Center
        ]
        
        for (x, y) in samplePoints {
            let offset = y * bytesPerRow + x * bytesPerPixel
            // Alpha is typically the last byte in RGBA or first in ARGB
            let alphaOffset = cgImage.alphaInfo == .premultipliedFirst || cgImage.alphaInfo == .first ? 0 : bytesPerPixel - 1
            let alpha = bytes[offset + alphaOffset]
            
            if alpha < 250 { // Some transparency detected
                return true
            }
        }
        
        return false
    }
}

// =============================================================================
// MARK: - Pinned Tab View
// =============================================================================

/// Compact pinned tab icon (Arc-style)
struct PinnedTabView: View {
    
    let tab: Tab
    let isActive: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? ArcTheme.highlightColor.opacity(0.2) : Color.primary.opacity(0.05))
                    .frame(width: 36, height: 36)
                
                // Favicon with fallback to globe icon
                faviconView
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: tab.icon != nil)
                
                // Loading indicator overlay
                if tab.isLoading {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(ArcTheme.highlightColor, lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: tab.isLoading)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? ArcTheme.highlightColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isHovering ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tab.title)
    }
    
    @ViewBuilder
    private var faviconView: some View {
        if tab.tabType == .note {
            Image(systemName: "note.text")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .primary : .secondary)
        } else if let icon = tab.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else if let faviconData = tab.favicon,
                  let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}

// =============================================================================
// MARK: - Tab Hover Preference Key (Global Overlay Architecture)
// =============================================================================

/// Data structure for tab hover telemetry
/// Transmitted from TabRowView to AppShellView for global overlay rendering
struct TabHoverData: Equatable {
    let tabId: UUID
    let tab: Tab
    let globalFrame: CGRect  // Position in "GlobalShell" coordinate space
    
    static func == (lhs: TabHoverData, rhs: TabHoverData) -> Bool {
        lhs.tabId == rhs.tabId && lhs.globalFrame == rhs.globalFrame
    }
}

/// PreferenceKey for transmitting hover state from TabRowView to root AppShellView
/// This enables the preview card to render at the root level, above all content
struct TabHoverPreferenceKey: PreferenceKey {
    static let defaultValue: TabHoverData? = nil
    
    static func reduce(value: inout TabHoverData?, nextValue: () -> TabHoverData?) {
        // Latest hover wins (only one preview shown at a time)
        if let next = nextValue() {
            value = next
        }
    }
}

// =============================================================================
// MARK: - Tab Row View
// =============================================================================

/// Individual tab row in the vertical list (Arc-style)
/// Uses PreferenceKey to transmit hover position to root for global overlay rendering
struct TabRowView: View {
    
    let tab: Tab
    let isActive: Bool
    let isInSplit: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onPin: () -> Void
    var onOpenChildTab: (() -> Void)? = nil
    
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>? = nil
    
    /// Delay before showing preview (ms) - matches Edge behavior
    private let previewDelay: UInt64 = 400_000_000 // 400ms in nanoseconds
    
    var body: some View {
        // GeometryReader to measure position in GlobalShell coordinate space
        GeometryReader { geometry in
            let globalFrame = geometry.frame(in: .named("GlobalShell"))
            
            tabContent
                // Transmit hover telemetry to root via preference
                .preference(
                    key: TabHoverPreferenceKey.self,
                    value: showPreview && !isActive ? TabHoverData(
                        tabId: tab.id,
                        tab: tab,
                        globalFrame: globalFrame
                    ) : nil
                )
        }
        // Fixed height to prevent GeometryReader from collapsing
        .frame(height: 36)
    }
    
    /// The actual tab row content (extracted for clarity)
    private var tabContent: some View {
        HStack(spacing: 10) {
            // Split indicator (left edge) - shows when tab is in split view
            if isInSplit {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArcTheme.highlightColor.opacity(0.8))
                    .help("This tab is open in the split view")
            }
            
            // Favicon(s) - show multiple for split tabs
            faviconView
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: tab.icon != nil)
            
            // Tab title
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Loading indicator
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
            
            // Hover actions
            if isHovering && !tab.isLoading {
                HStack(spacing: 4) {
                    // Pin button
                    Button(action: onPin) {
                        Image(systemName: tab.isPinned ? "pin.slash.fill" : "pin")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tab.isPinned ? "Unpin" : "Pin")
                    
                    // Close button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
            
            // Handle preview show/hide with delay
            if hovering && !isActive {
                // Start delayed preview show
                hoverTask?.cancel()
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: previewDelay)
                    if !Task.isCancelled {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showPreview = true
                            }
                        }
                    }
                }
            } else {
                // Cancel pending show and hide immediately
                hoverTask?.cancel()
                hoverTask = nil
                withAnimation(.easeInOut(duration: 0.1)) {
                    showPreview = false
                }
            }
        }
        .onTapGesture {
            print("[DEBUG TabRowView] onTapGesture FIRED for tab: \(tab.id) - \(tab.title)")
            onSelect()
        }
        .contextMenu {
            tabContextMenu
        }
    }
    
    @ViewBuilder
    private var faviconView: some View {
        if tab.tabType == .note {
            let size: CGFloat = 16
            Image(systemName: "note.text")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else {
            singleFaviconView(pane: tab.panes.first, isActivePane: true)
        }
    }
    
    @ViewBuilder
    private func singleFaviconView(pane: WebPane?, isActivePane: Bool) -> some View {
        let size: CGFloat = 16
        
        if let icon = pane?.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .opacity(isActivePane ? 1.0 : 0.6)
        } else if let faviconData = pane?.favicon,
                  let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .opacity(isActivePane ? 1.0 : 0.6)
        } else {
            Image(systemName: "globe")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .opacity(isActivePane ? 1.0 : 0.6)
        }
    }
    
    private var backgroundFill: Color {
        if isActive {
            return ArcTheme.highlightColor.opacity(0.12)
        } else if isInSplit {
            // Subtle highlight for tabs in split view
            return ArcTheme.highlightColor.opacity(0.06)
        } else if isHovering {
            return Color.primary.opacity(0.04)
        } else {
            return Color.clear
        }
    }
    
    private var borderColor: Color {
        if isActive {
            return ArcTheme.highlightColor.opacity(0.3)
        } else if isInSplit && !isActive {
            // Subtle border for tabs in split view
            return ArcTheme.highlightColor.opacity(0.15)
        } else {
            return Color.clear
        }
    }
    
    @ViewBuilder
    private var tabContextMenu: some View {
        Button("Pin Tab") { onPin() }
        Button("Duplicate Tab") { /* TODO */ }
        if let onOpenChildTab {
            Button("Open as Child Tab") { onOpenChildTab() }
        }
        Divider()
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        }
        Divider()
        Button("Close Tab", role: .destructive) { onClose() }
        Button("Close Other Tabs", role: .destructive) { /* TODO */ }
    }
}

// =============================================================================
// MARK: - Tab Preview Card (Edge-style)
// =============================================================================

/// Floating preview card shown when hovering over a tab
/// Displays a cached snapshot of the tab content with site info
/// Uses the Cache-on-Exit strategy - snapshot is captured when leaving a tab
struct TabPreviewCard: View {
    
    let tab: Tab
    
    /// Preview card dimensions
    private let previewWidth: CGFloat = 280
    private let previewHeight: CGFloat = 180
    private let cornerRadius: CGFloat = 12
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with site info
            previewHeader
            
            // Preview image or placeholder
            previewContent
        }
        .frame(width: previewWidth)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    /// Header section with favicon, title, and URL
    private var previewHeader: some View {
        HStack(spacing: 8) {
            // Favicon
            Group {
                if tab.tabType == .note {
                    Image(systemName: "note.text")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else if let icon = tab.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let faviconData = tab.favicon,
                          let nsImage = NSImage(data: faviconData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(tab.title.isEmpty ? "New Tab" : tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // URL (domain only)
                Text(tab.url.host ?? tab.url.absoluteString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }
    
    /// Preview image content or fallback placeholder
    @ViewBuilder
    private var previewContent: some View {
        if let preview = tab.cachedPreview {
            // Cached preview snapshot
            Image(nsImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: previewWidth, height: previewHeight)
                .clipped()
        } else {
            // Fallback: Preview unavailable placeholder
            previewPlaceholder
        }
    }
    
    /// Placeholder when no cached preview is available
    private var previewPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            
            Text("Preview unavailable")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            
            Text("Open this tab to capture a preview")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(width: previewWidth, height: previewHeight)
        .background(Color.primary.opacity(0.02))
    }
}

// =============================================================================
// MARK: - Split Group Row View
// =============================================================================

/// Row view for a saved split group in the sidebar
/// Shows grouped tabs with a combined title and icon indicating split layout
struct SplitGroupRowView: View {
    
    let group: SplitGroup
    let tabs: [Tab]
    let onRestore: () -> Void
    let onDismiss: () -> Void
    
    @State private var isHovering = false
    
    /// Tabs in this group
    private var groupTabs: [Tab] {
        group.tabIds.compactMap { tabId in
            tabs.first { $0.id == tabId }
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Split icon indicator
            Image(systemName: group.axis == .horizontal ? "square.split.2x1.fill" : "square.split.1x2.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ArcTheme.highlightColor)
            
            // Stacked favicons
            stackedFavicons
            
            // Combined title
            VStack(alignment: .leading, spacing: 2) {
                Text("Split View")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                
                Text(group.combinedTitle(tabs: tabs))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Hover actions
            if isHovering {
                HStack(spacing: 4) {
                    // Restore button
                    Button(action: onRestore) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Restore split view")
                    
                    // Dismiss button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss group")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ArcTheme.highlightColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onRestore()
        }
    }
    
    /// Stacked favicons showing tabs in the group
    @ViewBuilder
    private var stackedFavicons: some View {
        HStack(spacing: -6) {
            ForEach(Array(groupTabs.prefix(3).enumerated()), id: \.element.id) { index, tab in
                singleFavicon(for: tab)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    .zIndex(Double(3 - index))
            }
        }
    }
    
    @ViewBuilder
    private func singleFavicon(for tab: Tab) -> some View {
        let size: CGFloat = 18
        
        if tab.tabType == .note {
            Image(systemName: "note.text")
                .font(.system(size: size - 4))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else if let icon = tab.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if let faviconData = tab.favicon,
                  let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "globe")
                .font(.system(size: size - 4))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
    
    private var backgroundFill: Color {
        if isHovering {
            return ArcTheme.highlightColor.opacity(0.1)
        } else {
            return ArcTheme.highlightColor.opacity(0.05)
        }
    }
}

// =============================================================================
// MARK: - Active Split Group View
// =============================================================================

/// View showing tabs that are currently in the active split view
/// Groups them together visually to indicate they're part of the split
struct ActiveSplitGroupView: View {
    
    let tabIds: Set<UUID>
    let tabs: [Tab]
    let activeTabId: UUID?
    
    @State private var isExpanded = true
    
    /// Cached tab order to prevent flickering during resize
    /// Only updated when tabIds actually change, not on every render
    @State private var cachedTabOrder: [UUID] = []
    
    /// Tabs currently in the split, maintaining stable order
    private var splitTabs: [Tab] {
        // Use cached order if it matches current tabIds
        if Set(cachedTabOrder) == tabIds {
            return cachedTabOrder.compactMap { tabId in
                tabs.first { $0.id == tabId }
            }
        }
        // Fallback: compute from current tabIds
        return tabIds.compactMap { tabId in
            tabs.first { $0.id == tabId }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header
            HStack {
                Image(systemName: "square.split.2x1.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ArcTheme.highlightColor)
                
                Text("Active Split")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArcTheme.highlightColor)
                
                Text("(\(splitTabs.count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ArcTheme.highlightColor.opacity(0.7))
                
                Spacer()
                
                // Collapse/expand button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            
            // Grouped tabs
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(splitTabs) { tab in
                        SplitTabRowView(
                            tab: tab,
                            isActive: activeTabId == tab.id
                        )
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ArcTheme.highlightColor.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ArcTheme.highlightColor.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .onAppear {
            // Initialize cached order on first appear
            if cachedTabOrder.isEmpty {
                cachedTabOrder = Array(tabIds)
            }
        }
        .onChange(of: tabIds) { oldValue, newValue in
            // Only update cached order when tabs actually change
            // (not during resize operations)
            if oldValue != newValue {
                cachedTabOrder = Array(newValue)
            }
        }
    }
}

/// Simplified tab row for tabs within an active split group
struct SplitTabRowView: View {
    
    let tab: Tab
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Favicon
            faviconView
            
            // Title
            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Active indicator
            if isActive {
                Circle()
                    .fill(ArcTheme.highlightColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? ArcTheme.highlightColor.opacity(0.1) : Color.clear)
        )
    }
    
    @ViewBuilder
    private var faviconView: some View {
        let size: CGFloat = 14
        
        if tab.tabType == .note {
            Image(systemName: "note.text")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        } else if let icon = tab.icon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if let faviconData = tab.favicon,
                  let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "globe")
                .font(.system(size: size - 3))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}
