// FloatingWebCanvasView.swift - Arc-Style Floating Card Web Content
// Extracted from AppShellView for modularity and reuse

import SwiftUI

// =============================================================================
// MARK: - Floating Web Canvas View (Detail)
// =============================================================================

/// Arc-style floating card web content view for the detail column.
///
/// ## Visual Mechanics (Arc Browser Reference)
/// 1. **Unified Backdrop**: The sidebar's vibrant material appears to continue
///    behind this view, creating visual cohesion.
/// 2. **Card Metaphor**: Web content is contained in a distinct rectangular
///    "card" that floats above the backdrop.
/// 3. **Floating Depth**: Achieved through:
///    - Uniform padding separating card from window edges
///    - Subtle rounded corners
///    - Soft drop shadow for depth perception
///
/// ## Fullscreen Mode (Edge-to-Edge)
/// When in fullscreen (Ctrl+Cmd+F), the card metaphor is dropped:
/// - No padding (web content fills entire detail area)
/// - No rounded corners (square edges flush with window)
/// - No shadow (content is flush, not floating)
/// - `.ignoresSafeArea(.all)` ensures no header gap
///
/// ## Split View Support
/// Uses the VS Code-style split editor that supports drag-and-drop tab splitting.
/// Tabs can be dragged to the left or right edge of the canvas to create
/// side-by-side split views.
///
/// ## Modifier Stack (Normal Mode)
/// ```
/// BrowserView (CEF NSViewRepresentable)
///   └─ frame(maxWidth/Height: .infinity)
///   └─ background(cardBackground) ← solid white/theme-aware
///   └─ clipShape(RoundedRectangle)
///   └─ shadow(...) ← depth illusion
///   └─ padding(...) ← separation from edges
///   └─ background(Color.clear) ← transparent detail area
/// ```
struct FloatingWebCanvasView: View {
    
    @Bindable var browserState: BrowserState
    
    /// Whether window is in fullscreen mode (edge-to-edge rendering)
    var isFullScreen: Bool
    
    /// Card corner radius (Arc uses ~10-12pt) - 0 in fullscreen
    private var cardCornerRadius: CGFloat {
        isFullScreen ? 0 : ArcTheme.cardCornerRadius
    }
    
    /// Padding between card and window edges - 0 in fullscreen
    private var cardPadding: CGFloat {
        isFullScreen ? 0 : ArcTheme.cardPadding
    }
    
    /// Top padding accounts for titlebar area - 0 in fullscreen
    private var cardTopPadding: CGFloat {
        isFullScreen ? 0 : ArcTheme.cardPadding
    }
    
    /// Shadow color - clear in fullscreen
    private var shadowColor: Color {
        isFullScreen ? Color.clear : ArcTheme.primaryShadow.color
    }
    
    /// Shadow radius - 0 in fullscreen
    private var shadowRadius: CGFloat {
        isFullScreen ? 0 : ArcTheme.primaryShadow.radius
    }
    
    /// Shadow Y offset - 0 in fullscreen
    private var shadowY: CGFloat {
        isFullScreen ? 0 : ArcTheme.primaryShadow.y
    }
    
    var body: some View {
        // Check if we're in agent mode
        let isAgentMode = browserState.currentPanelMode == .agent
        
        // Check if we're in generative UI mode (leaf node selected in Plan Mode)
        let isGenerativeUIMode = browserState.planState.selectedLeafNode != nil
        
        // Check if active tab has stack mode enabled
        let isStackMode = browserState.activeTab?.stackModeEnabled ?? false

        // Check if meeting recorder is active (shows transcript sidebar)
        let isRecording = browserState.meetingRecorderService.isRecording
        let _ = NSLog("[RecordStart] ③ FloatingWebCanvasView body — isRecording=%d", isRecording ? 1 : 0)

        // VS Code-style split editor with drag-and-drop support, or stacked canvas.
        // The recording panel is overlaid (ZStack) so the CEF NSView is never
        // resized — resizing it while audio is playing crashes CEF's internal
        // audio capture pipeline.
        ZStack(alignment: .trailing) {
            Group {
                if isAgentMode {
                    AgentModeMainView(browserState: browserState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isGenerativeUIMode {
                    GenerativeUIView(planState: browserState.planState, browserState: browserState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let activeTab = browserState.activeTab {
                    if activeTab.tabType == .note, let noteId = activeTab.noteId {
                        NoteEditorView(noteId: noteId, browserState: browserState)
                            .id(noteId)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack {
                            if isStackMode {
                                StackedCanvasView(browserState: browserState, tabId: activeTab.id)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                SplitCanvasView(browserState: browserState, isFullScreen: isFullScreen)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            if isStackMode {
                                BottomPageDock(browserState: browserState, tabId: activeTab.id)
                            }

                            ChatBubbleOverlay(
                                chatState: activeTab.chatBubbleState,
                                tabURL: activeTab.url
                            )
                            .zIndex(900)

                            selectionPopupOverlay
                                .zIndex(950)

                            copiedToastOverlay
                                .zIndex(960)
                        }
                    }
                } else {
                    emptyTabView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Recording panel — overlaid on the trailing edge so the CEF
            // NSView keeps its full size and is never resized.
            if isRecording && FeatureFlagService.shared.flags.recordingPanelEnabled {
                let _ = NSLog("[RecordStart] ③ inserting RecordingPanelView into overlay")
                HStack(spacing: 0) {
                    Divider()
                    RecordingPanelView(recorder: browserState.meetingRecorderService)
                        .frame(width: 300)
                        .frame(maxHeight: .infinity)
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)
        // ─────────────────────────────────────────────────────────────
        // Card Background: Solid white (light mode) or dark (dark mode)
        // Uses .background material for proper theme adaptation
        // ─────────────────────────────────────────────────────────────
        .background(CardBackgroundView())
        // ─────────────────────────────────────────────────────────────
        // Rounded Corners: Clip content to rounded rectangle
        // In fullscreen: square corners (cornerRadius = 0)
        // ─────────────────────────────────────────────────────────────
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        // ─────────────────────────────────────────────────────────────
        // Drop Shadow: Multi-layered for realistic depth
        // In fullscreen: no shadow (content is edge-to-edge)
        // ─────────────────────────────────────────────────────────────
        .shadow(
            color: shadowColor,
            radius: shadowRadius,
            x: 0,
            y: shadowY
        )
        .shadow(
            color: isFullScreen ? Color.clear : ArcTheme.secondaryShadow.color,
            radius: isFullScreen ? 0 : ArcTheme.secondaryShadow.radius,
            x: 0,
            y: isFullScreen ? 0 : ArcTheme.secondaryShadow.y
        )
        // ─────────────────────────────────────────────────────────────
        // Padding: Separation from window edges creates "floating" look
        // In fullscreen: no padding (edge-to-edge)
        // ─────────────────────────────────────────────────────────────
        .padding(.top, cardTopPadding)
        .padding(.leading, cardPadding)
        .padding(.trailing, cardPadding)
        .padding(.bottom, cardPadding)
        // ─────────────────────────────────────────────────────────────
        // Transparent Detail Background: Allows unified backdrop to
        // show through, completing the floating card illusion
        // ─────────────────────────────────────────────────────────────
        .background(Color.clear)
        // ─────────────────────────────────────────────────────────────
        // CRITICAL: Ignore safe areas to eliminate header gap
        // This ensures the web content extends fully to window edges,
        // especially in fullscreen mode where no titlebar exists.
        // In normal mode, ignore top and bottom safe areas to achieve
        // consistent padding controlled by cardPadding.
        // ─────────────────────────────────────────────────────────────
        .ignoresSafeArea(.all, edges: isFullScreen ? .all : [.top, .bottom])
        .onChange(of: browserState.activeTabIndex) { _, _ in
            browserState.selectionMonitor.dismiss()
            browserState.snapshotService.dismiss()
        }
    }
    
    // MARK: - Empty Tab View
    
    /// Fallback view when no tab is selected
    private var emptyTabView: some View {
        Text("No tab selected")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(.secondary)
    }

    // MARK: - Selection Popup Overlay

    /// Shows the floating popup bar when text is selected or a snapshot is captured.
    @ViewBuilder
    private var selectionPopupOverlay: some View {
        let hasSelection = browserState.selectionMonitor.selectedText != nil
        let hasSnapshot = browserState.snapshotService.capturedImage != nil

        if hasSelection || hasSnapshot {
            SelectionPopupBar(
                browserState: browserState,
                selectedText: browserState.selectionMonitor.selectedText,
                capturedImage: browserState.snapshotService.capturedImage,
                sourceURL: hasSelection
                    ? browserState.selectionMonitor.sourceURL
                    : browserState.snapshotService.sourceURL,
                screenPosition: hasSelection
                    ? browserState.selectionMonitor.selectionScreenPosition
                    : browserState.snapshotService.snapshotScreenPosition,
                onDismiss: {
                    browserState.selectionMonitor.dismiss()
                    browserState.snapshotService.dismiss()
                }
            )
        }
    }

    // MARK: - Copied Toast Overlay

    @ViewBuilder
    private var copiedToastOverlay: some View {
        CopiedToastView(trigger: browserState.snapshotService.capturedImage != nil)
    }
}

// =============================================================================
// MARK: - Copied Toast View
// =============================================================================

/// Brief "Copied to clipboard" toast that auto-fades and auto-removes.
private struct CopiedToastView: View {
    var trigger: Bool
    @State private var showToast = false

    var body: some View {
        Group {
            if showToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Label("Copied to clipboard", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThickMaterial, in: Capsule())
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                        Spacer()
                    }
                    .padding(.bottom, 60)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.3), value: showToast)
        .onChange(of: trigger) { _, newValue in
            if newValue {
                showToast = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    showToast = false
                }
            }
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct FloatingWebCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FloatingWebCanvasView(
                browserState: BrowserState(),
                isFullScreen: false
            )
            .frame(width: 800, height: 600)
            .background(Color.gray.opacity(0.2))
            .previewDisplayName("Normal")
            
            FloatingWebCanvasView(
                browserState: BrowserState(),
                isFullScreen: true
            )
            .frame(width: 800, height: 600)
            .background(Color.gray.opacity(0.2))
            .previewDisplayName("Fullscreen")
        }
    }
}
#endif
