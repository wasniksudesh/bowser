// SidebarURLBar.swift - Arc-Style Compact Address Bar
// Extracted from AppShellView for modularity and reuse

import SwiftUI

// =============================================================================
// MARK: - Sidebar URL Bar (Compact Address Bar)
// =============================================================================

/// Compact URL bar designed to fit within the sidebar.
/// Tapping opens the full Command Bar modal for detailed navigation.
///
/// This component displays:
/// - Security indicator (lock/globe icon)
/// - Current page domain (truncated)
/// - Subtle capsule background with vibrancy
struct SidebarURLBar: View {
    
    @Bindable var browserState: BrowserState
    var namespace: Namespace.ID
    var onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Security indicator
                Image(systemName: securityIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(securityColor)
                    .frame(width: 16)
                
                // Domain display
                Text(displayDomain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                // Expand indicator
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(urlBarBackground)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Search or enter URL (⌘L)")
    }
    
    // MARK: - URL Bar Background
    
    private var urlBarBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHovering ? ArcTheme.highlightColor.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - Computed Properties
    
    private var currentURL: URL? {
        browserState.activeTab?.url
    }
    
    private var isSecure: Bool {
        currentURL?.scheme == "https"
    }
    
    private var securityIcon: String {
        guard let url = currentURL else { return "globe" }
        
        switch url.scheme {
        case "https": return "lock.fill"
        case "http": return "exclamationmark.triangle.fill"
        case "file": return "doc.fill"
        default: return "globe"
        }
    }
    
    private var securityColor: Color {
        guard let url = currentURL else { return .secondary }
        
        switch url.scheme {
        case "https": return .green
        case "http": return .orange
        default: return .secondary
        }
    }
    
    private var displayDomain: String {
        guard let url = currentURL else { return "New Tab" }
        
        if url.scheme == "about" {
            return "New Tab"
        }
        
        return url.host ?? url.absoluteString
    }
    
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct SidebarURLBar_Previews: PreviewProvider {
    @Namespace static var namespace
    
    static var previews: some View {
        SidebarURLBar(
            browserState: BrowserState(),
            namespace: namespace,
            onTap: {}
        )
        .frame(width: 280)
        .padding()
        .background(Color.gray.opacity(0.2))
    }
}
#endif
