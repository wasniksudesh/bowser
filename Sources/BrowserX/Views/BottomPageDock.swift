// BottomPageDock.swift - Bottom Dock for Stacked Pages
// Fixed-size pill with dots, hover previews, no magnification

import SwiftUI
import AppKit

// =============================================================================
// MARK: - Bottom Page Dock
// =============================================================================

/// Bottom dock that shows dots for each page in the stack
/// Appears only when stack mode is enabled
/// Hovering over a dot shows a preview popup above the dock
struct BottomPageDock: View {
    
    @Bindable var browserState: BrowserState
    let tabId: UUID
    
    @State private var hoveredPageIndex: Int? = nil
    
    var body: some View {
        GeometryReader { geometry in
            if let tab = browserState.tabManager.tab(for: tabId), tab.stackModeEnabled, !tab.pages.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Preview popup
                    if let hoveredIndex = hoveredPageIndex,
                       tab.pages.indices.contains(hoveredIndex) {
                        pagePreviewPopup(for: tab.pages[hoveredIndex])
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .padding(.bottom, 8)
                    }
                    
                    // Dock pill
                    dockPill(for: tab)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(true)
    }
    
    // MARK: - Dock Pill
    
    @ViewBuilder
    private func dockPill(for tab: Tab) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(tab.pages.enumerated()), id: \.element.id) { index, page in
                pageDot(for: page, at: index, isActive: index == tab.activePageIndex)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        )
    }
    
    // MARK: - Page Dot
    
    @ViewBuilder
    private func pageDot(for page: Page, at index: Int, isActive: Bool) -> some View {
        Button(action: {
            switchToPage(at: index)
        }) {
            ZStack {
                // Dot background
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                
                // Star indicator for starred pages
                if page.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredPageIndex = hovering ? index : nil
            }
        }
    }
    
    // MARK: - Preview Popup
    
    @ViewBuilder
    private func pagePreviewPopup(for page: Page) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Snapshot
            if let snapshot = page.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 125)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 200, height: 125)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                    )
            }
            
            // Title and URL
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(page.url.host ?? page.url.absoluteString)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        )
        .frame(width: 216)
    }
    
    // MARK: - Actions
    
    private func switchToPage(at index: Int) {
        guard var tab = browserState.tabManager.tab(for: tabId),
              tab.pages.indices.contains(index) else { return }
        
        // Suspend old active page
        let oldActiveIndex = tab.activePageIndex
        if oldActiveIndex != index && tab.pages.indices.contains(oldActiveIndex) {
            tab.pages[oldActiveIndex].suspend()
        }
        
        // Update active page index
        tab.activePageIndex = index
        
        // Resume new active page (if not frozen)
        if tab.pages[index].lifecycleState != .frozen {
            tab.pages[index].resume()
        }
        
        // Update tab in manager
        browserState.tabManager.replaceTab(id: tabId, with: tab)
        
        // Update address bar
        if let page = tab.activePage {
            browserState.addressBarText = page.url.absoluteString
        }
        
        // Wake up frozen pages
        if tab.pages[index].lifecycleState == .frozen {
            // Trigger reload for the specific page's browser
            BrowserManager.shared.reload(pageId: tab.pages[index].browserId)
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct BottomPageDock_Previews: PreviewProvider {
    static var previews: some View {
        let state = BrowserState()
        if let tabId = state.activeTab?.id {
            BottomPageDock(browserState: state, tabId: tabId)
                .frame(width: 1200, height: 800)
                .background(Color.gray.opacity(0.2))
        }
    }
}
#endif
