// StackedCanvasView.swift - Horizontal Page Stacking View
// Renders pages with quadratic left-stacking and handles horizontal swipe gestures

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Stacked Canvas View
// =============================================================================

/// Main view for rendering horizontally stacked pages
/// Pages stack to the left with quadratic distribution (max 5% total width)
/// Active page fills remaining space
struct StackedCanvasView: View {

    @Bindable var browserState: BrowserState
    let tabId: UUID

    @State private var visitedPageIndices: Set<Int> = []
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Render all pages in the stack
                if let tab = browserState.tabManager.tab(for: tabId), tab.stackModeEnabled {
                    ForEach(Array(tab.pages.enumerated()), id: \.element.id) { index, page in
                        pageView(for: page, at: index, in: tab, geometry: geometry)
                    }
                }
            }
            .onAppear {
                // Mark initial page as visited
                if let tab = browserState.tabManager.tab(for: tabId) {
                    visitedPageIndices.insert(tab.activePageIndex)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackGestureChanged)) {
                notification in
                handleGestureChanged(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .stackGestureEnded)) {
                notification in
                handleGestureEnded(notification)
            }
        }
    }

    // MARK: - Page View

    @ViewBuilder
    private func pageView(for page: Page, at index: Int, in tab: Tab, geometry: GeometryProxy)
        -> some View
    {
        let isActive = index == tab.activePageIndex
        let isFuture = index > tab.activePageIndex
        let isPast = index < tab.activePageIndex
        
        // Calculate stack width and page dimensions (from ContentView.swift)
        let stackWidth = calculateStackWidth(
            activeIndex: tab.activePageIndex,
            containerWidth: geometry.size.width
        )
        
        // DYNAMIC WIDTH: Active page is narrower to accommodate the stack
        let pageWidth = isActive ? (geometry.size.width - stackWidth) : geometry.size.width
        
        // Calculate X offset with quadratic distribution
        let xOffset = calculateXOffset(
            index: index,
            activeIndex: tab.activePageIndex,
            stackWidth: stackWidth,
            containerWidth: geometry.size.width
        )

        ZStack(alignment: .topLeading) {
            // Background color for the page card (prevents white flash)
            Color(nsColor: .textBackgroundColor)
            
            // Browser content - ALWAYS render and visible for ALL pages
            BrowserCanvas(
                browserState: browserState, pageId: page.browserId, parentTabId: tabId,
                url: page.url
            )
            .allowsHitTesting(isActive)
            .overlay(
                Group {
                    // Frozen curtain overlay for inactive pages or frozen state
                    if !isActive || page.lifecycleState == .frozen {
                        frozenCurtainView(for: page, geometry: geometry)
                    }
                }
            )
            .overlay(
                // Dimming overlay for non-active pages (like linearbrowser.swift)
                Group {
                    if !isActive && !isFuture {
                        Color.black.opacity(0.2)
                            .allowsHitTesting(true)
                            .onTapGesture {
                                if page.lifecycleState == .frozen {
                                    wakeUpPage(at: index)
                                } else {
                                    switchToPage(at: index)
                                }
                            }
                    }
                }
            )

            // Vertical title on spine (for stacked pages)
            if isPast {
                spineOverlay(for: page)
            }
        }
        .frame(width: pageWidth, height: geometry.size.height)
        .cornerRadius(isPast ? 12 : 0)  // Rounded corners for stacked pages
        .shadow(radius: 10, x: -5, y: 0)  // Shadow to separate layers
        .offset(x: xOffset)
        .zIndex(Double(index))  // Proper stacking order (higher index = on top)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: tab.activePageIndex)
    }
    
    // MARK: - Geometry Calculations (ContentView.swift style)
    
    /// Calculate the total width occupied by the stack of past pages
    /// Uses min to cap at 8% of screen or actual stack size
    private func calculateStackWidth(activeIndex: Int, containerWidth: CGFloat) -> CGFloat {
        guard activeIndex > 0 else { return 0 }
        
        // Cap at 8% of screen width or actual stack size (55pt per page)
        return min(containerWidth * 0.08, CGFloat(activeIndex) * 55.0)
    }
    
    /// Calculate X offset for a page with QUADRATIC distribution (ContentView.swift style)
    /// - Pages at or before activeIndex: stacked on left with quadratic spacing
    /// - Pages after activeIndex: pushed off screen to the right
    /// - Drag offset applied selectively based on gesture direction
    private func calculateXOffset(
        index: Int,
        activeIndex: Int,
        stackWidth: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat {
        let isFuture = index > activeIndex
        let isBottomMost = index == 0
        
        // Base position calculation
        var xOffset: CGFloat
        
        if isFuture {
            // Future pages are off-screen to the right
            xOffset = containerWidth
        } else if index == activeIndex {
            // Active page starts at the end of the stack
            xOffset = stackWidth
        } else {
            // Past pages use QUADRATIC distribution for elegant stacking
            // This creates a compressed stack where older pages are closer together
            let progress = Double(index) / Double(activeIndex)
            xOffset = stackWidth * CGFloat(pow(progress, 1.5))
        }
        
        // Apply drag offset during gesture
        if isDragging {
            // Swiping Right (dragOffset > 0) -> revealing previous page
            // Move the ACTIVE page to the right
            if dragOffset > 0 && index == activeIndex {
                xOffset += dragOffset
            }
            
            // Swiping Left (dragOffset < 0) -> bringing in next page
            // Move the NEXT page (activeIndex + 1) from right to cover current
            if dragOffset < 0 && index == activeIndex + 1 {
                // Next page starts at containerWidth, we pull it left
                xOffset = containerWidth + dragOffset
            }
        }
        
        // CRITICAL: Bottom-most page (index 0) should NEVER leave the left boundary
        // This prevents empty space on the left side
        if isBottomMost && xOffset < 0 {
            xOffset = 0
        }
        
        return xOffset
    }

    // MARK: - Spine Overlay

    @ViewBuilder
    private func spineOverlay(for page: Page) -> some View {
        ZStack(alignment: .topLeading) {
            // Black background for spine
            Color.black

            VStack(alignment: .leading, spacing: 8) {
                // Star button
                Button(action: {
                    toggleStar(for: page)
                }) {
                    Image(systemName: page.isStarred ? "star.fill" : "star")
                        .foregroundStyle(page.isStarred ? .yellow : .white.opacity(0.4))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .padding(.top, 25)

                Spacer()

                // Rotated vertical title
                Text(page.title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 150, alignment: .leading)
                    .rotationEffect(.degrees(-90))
                    .padding(.bottom, 100)
            }
        }
        .frame(width: 50)
    }

    // MARK: - Frozen Curtain

    @ViewBuilder
    private func frozenCurtainView(for page: Page, geometry: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            // Solid background color to prevent white flash
            Color(nsColor: .textBackgroundColor)
            
            // Snapshot background (if available)
            if let snapshot = page.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }

            // Semi-transparent curtain overlay (dimmer for inactive pages)
            Color(nsColor: .windowBackgroundColor)
                .opacity(StackConstants.frozenCurtainOpacity)

            // Top-to-bottom reveal curtain (animated during reload)
            if page.isLoading && page.loadingProgress > 0 {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(height: (1.0 - page.loadingProgress) * geometry.size.height)
                    .offset(y: 0)
                    .animation(.linear(duration: 0.1), value: page.loadingProgress)
            } else if page.lifecycleState == .frozen {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Tap to reload")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipped()
    }


    // MARK: - Gesture Handling

    private func handleGestureChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let notificationTabId = userInfo["tabId"] as? UUID,
            notificationTabId == tabId,
            let translation = userInfo["translation"] as? CGFloat,
            let tab = browserState.tabManager.tab(for: tabId),
            tab.stackModeEnabled
        else {
            return
        }

        isDragging = true

        // Constrain drag based on available pages
        let canGoBack = tab.activePageIndex > 0  // Can go to previous (older) page
        let canGoForward = tab.activePageIndex < tab.pages.count - 1  // Can go to next (newer) page

        if translation > 0 && !canGoBack {
            // Swiping right but at the first page - rubber band effect
            // But NEVER let the bottom-most page leave the left boundary
            dragOffset = translation * 0.2
        } else if translation < 0 && !canGoForward {
            // Swiping left but at the last page - rubber band effect
            dragOffset = translation * 0.2
        } else {
            dragOffset = translation
        }
    }

    private func handleGestureEnded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let notificationTabId = userInfo["tabId"] as? UUID,
            notificationTabId == tabId,
            let translation = userInfo["translation"] as? CGFloat,
            let velocity = userInfo["velocity"] as? CGFloat,
            let tab = browserState.tabManager.tab(for: tabId),
            tab.stackModeEnabled
        else {
            return
        }

        // Mark dragging as finished
        isDragging = false

        // Determine target page based on gesture
        var targetIndex = tab.activePageIndex

        // Check for fling gesture (high velocity)
        let isFling = abs(velocity) > StackConstants.flingVelocityThreshold

        if isFling {
            // Fling: move multiple pages based on velocity
            let pagesToMove = max(1, Int(abs(velocity) / StackConstants.flingVelocityThreshold))
            if velocity > 0 {
                // Fling right (go to previous/older pages)
                targetIndex = max(0, tab.activePageIndex - pagesToMove)
            } else {
                // Fling left (go to next/newer pages)
                targetIndex = min(tab.pages.count - 1, tab.activePageIndex + pagesToMove)
            }
        } else {
            // Latch: move exactly one page if threshold exceeded
            if abs(translation) > StackConstants.swipeThreshold {
                if translation > 0 && tab.activePageIndex > 0 {
                    // Swipe right: go to previous page
                    targetIndex = tab.activePageIndex - 1
                } else if translation < 0 && tab.activePageIndex < tab.pages.count - 1 {
                    // Swipe left: go to next page
                    targetIndex = tab.activePageIndex + 1
                }
            }
        }

        // Reset drag offset with animation FIRST, then switch page
        // This is the key fix - we animate the dragOffset to 0, and the page switch
        // is handled by the activePageIndex change which has its own animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            dragOffset = 0
        }

        // If target changed, switch to the new page
        if targetIndex != tab.activePageIndex {
            switchToPage(at: targetIndex)
        }
    }

    // MARK: - Star Toggle

    private func toggleStar(for page: Page) {
        guard var tab = browserState.tabManager.tab(for: tabId),
            let pageIndex = tab.pages.firstIndex(where: { $0.id == page.id })
        else { return }

        tab.pages[pageIndex].isStarred.toggle()

        // Update tab in manager
        browserState.tabManager.replaceTab(id: tabId, with: tab)
    }

    // MARK: - Page Navigation

    private func switchToPage(at index: Int) {
        guard var tab = browserState.tabManager.tab(for: tabId),
            tab.pages.indices.contains(index)
        else { return }

        // Suspend old active page
        let oldActiveIndex = tab.activePageIndex
        if oldActiveIndex != index && tab.pages.indices.contains(oldActiveIndex) {
            tab.pages[oldActiveIndex].suspend()
        }

        // Update active page index
        tab.activePageIndex = index

        // Resume new active page
        tab.pages[index].resume()

        // Mark as visited
        visitedPageIndices.insert(index)

        // Update lifecycle states
        PageLifecycleManager.updateLifecycleStates(for: &tab, visitedIndices: visitedPageIndices)

        // Update tab in manager
        browserState.tabManager.replaceTab(id: tabId, with: tab)

        // Update address bar
        if let page = tab.activePage {
            browserState.addressBarText = page.url.absoluteString
        }
    }

    private func wakeUpPage(at index: Int) {
        guard var tab = browserState.tabManager.tab(for: tabId),
            tab.pages.indices.contains(index)
        else { return }

        let page = tab.pages[index]

        // Set loading state to trigger curtain animation
        tab.pages[index].isLoading = true
        tab.pages[index].loadingProgress = 0.0
        tab.pages[index].lastVisitedAt = Date()

        // Update tab in manager
        browserState.tabManager.replaceTab(id: tabId, with: tab)

        // Switch to this page and reload
        switchToPage(at: index)

        // Trigger browser reload using page's browserId
        BrowserManager.shared.reload(pageId: page.browserId)

        // The loadingProgress will be updated via CEF callbacks
        // When it reaches 1.0, the curtain will fully reveal
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct StackedCanvasView_Previews: PreviewProvider {
        static var previews: some View {
            let state = BrowserState()
            if let tabId = state.activeTab?.id {
                StackedCanvasView(browserState: state, tabId: tabId)
                    .frame(width: 1200, height: 800)
            }
        }
    }
#endif
