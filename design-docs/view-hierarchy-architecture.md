# Design One-Pager: Bowser View Hierarchy & Layering Architecture

## Overview
Bowser is built using a hybrid **SwiftUI + AppKit** architecture designed to emulate the "Arc Browser" aesthetic: a floating web canvas, a persistent vibrant sidebar, and smooth, hardware-accelerated transitions. This document outlines the structural hierarchy and the layering strategy used to show native UI components over web content.

## Success Criteria
- **Native-at-the-Edges**: UI overlays (buttons, menus, command bars) must feel integrated and performant.
- **Hardware-Accelerated Webview**: Use CEF (Chromium Embedded Framework) for rendering without sacrificing UI responsiveness.
- **Arc-Style Depth**: Implement a card metaphor where web content floats over a unified backdrop.

## Architecture Detail

### 1. Composition Root: App Shell
The entry point is `AppShellView`, which uses a `NavigationSplitView` to manage the primary layout states (Sidebar vs. Detail).

- **Unified Surface**: A `UnifiedBackdropView` (vibrancy material) sits at the bottom of a `ZStack`, showing through the transparent sidebar and the gaps around the floating canvas.
- **Global Overlays**: Components like the `CommandBarView` and `TabPreviewCard` are injected into the top-level `ZStack` to ensure they render above both the sidebar and the browser.

### 2. The Multi-Layer Split Engine (AppKit)
The core of the browsing experience is managed by `SplitCanvasViewController` (AppKit). Each tab is wrapped in a `SplitPaneViewController`, which implements a precise 3-layer stack:

| Layer | Component | Responsibility |
| :--- | :--- | :--- |
| **Top (UI)** | `PaneControlsView` | Hosts native `NSButton` instances for closing and expanding panes. |
| **Middle (Logic)** | `DropTargetView` | An invisible overlay that intercepts drag events (for split creation) and passes through others via `hitTest` tunneling. |
| **Bottom (Content)** | `CEFContainerView` | The host for the Chromium process rendering surface. |

### 3. Browser Canvas & Reparenting (`BrowserView.swift`)
The system uses a **View Reparenting Pattern** to keep CEF browser instances alive even when their SwiftUI containers are dismantled (e.g., during tab switches).

- **`BrowserCanvas` (SwiftUI)**: An `NSViewRepresentable` bridge that acts as a persistent viewport.
- **`BrowserContainerView` (AppKit)**: The physical `NSView` that provides the parent layer for Chromium.
- **`CEFContainerView` (AppKit)**: The actual rendering surface that interacts with the CEF C++ wrapper.

| Component | Role | Relation to CEF |
| :--- | :--- | :--- |
| `BrowserCanvas` | State Coordination | Manages updates and lifecycle between SwiftUI and `BrowserManager`. |
| `BrowserContainerView` | Layer Host | Maintains `wantsLayer = true` and base styling. |
| `CEFContainerView` | Rendering Surface | The `NSView` handle passed to CEF's `SetAsChild` method. |

### 4. Sidebar Tree Logic
The `ArcSidebarView` manages navigation state. It switches between two modes:
- **Tree Mode**: Uses `TabTreeView` to show nested parent/child tab relationships.
- **Split Mode**: Uses `ActiveSplitGroupView` to highlight a group of tabs that are currently visible in the split canvas.

## Technical Implementation Details
- **SwiftUI -> AppKit Bridge**: Uses `NSViewControllerRepresentable` (`SplitCanvasView`) or `NSViewRepresentable` (`BrowserCanvas`) to embed native browser views.
- **View Reparenting**: `BrowserManager` holds a dictionary of `CEFContainerView` instances keyed by `tabId`. When a tab is selected, its view is detached from its previous parent and attached to the current `BrowserContainerView` or `SplitPaneViewController`.
- **Event Tunneling**: `DropTargetView` uses custom `hitTest` logic to ensure that while it "captures" drags, standard clicks are passed down to Chromium's internal `NSView`.
- **Telemetry**: Uses SwiftUI `PreferenceKey` (`TabHoverPreferenceKey`) to transmit local tab positions from deeply nested sidebar rows up to the root shell for preview rendering.

## View Hierarchy Tree
```text
AppShellView (Root)
├── UnifiedBackdropView (Bottom Z-Order)
├── NavigationSplitView
│   ├── Sidebar: ArcSidebarView
│   │   ├── SidebarHeaderView (Traffic Lights Sync)
│   │   ├── Favorites Grid (FavoriteItemView)
│   │   └── Tab List (TabTreeView / ActiveSplitGroupView)
│   └── Detail: FloatingWebCanvasView (Card Layout)
│       └── SplitCanvasView (NSViewController Bridge)
│           └── SplitCanvasViewController (AppKit Master)
│               └── RecursiveSplitViewController
│                   └── SplitPaneViewController (Tab Pane)
│                       ├── PaneControlsView (Native Buttons - TOP)
│                       ├── DropTargetView (Invisible Interceptor)
│                       └── [Reparented Content]
│                           └── CEFContainerView (Chromium Host)
│                               └── CEF Internal View (Renderer)
└── Overlays (Z-Order Top)
    ├── CommandBarView
    └── TabPreviewCard

Note: BrowserCanvas (NSViewRepresentable) acts as an alternative 
SwiftUI-direct viewport for the same [Reparented Content] stack.
```
