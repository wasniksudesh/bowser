---
name: Bowser Bugs and Features
overview: Fix copy/paste keyboard shortcuts in the CEF browser, redesign homescreen folder icons to be smaller with distinct standard icons, add bottom-bar folder preview popovers with tab/plan/agent lists, center-align and resize the bottom bar dock, and implement per-folder browsing history with a sidebar History view.
todos:
  - id: fix-copy-paste
    content: "Bug fix: Remove target=self from Edit menu items, use nil target with standard editing selectors (copy:, paste:, cut:, etc.)"
    status: pending
  - id: folder-icons-smaller
    content: Reduce folder icon size (72->52), update grid sizing, assign distinct SF Symbol icons to default folders
    status: pending
  - id: bottom-bar-popover
    content: Add DockFolderPopover showing tabs/plans/agents as vertical list on folder click in bottom bar
    status: pending
  - id: bottom-bar-center
    content: Center bottom bar, limit max width, make search field flexible-width between folder icons and clock
    status: pending
  - id: history-model
    content: Create BrowsingHistoryItem model and FolderHistoryPersistence service for per-folder history storage
    status: pending
  - id: history-recording
    content: Record browsing history entries in Coordinator when pages finish loading
    status: pending
  - id: history-view
    content: Create HistoryView (Chrome-like) grouped by date with search, clear, and click-to-navigate
    status: pending
  - id: history-sidebar
    content: Add History button to ArcSidebarView bottom bar, wire up to show HistoryView
    status: pending
isProject: false
---

# Bowser Bugs and Features

## 1. Fix Copy/Paste Keyboard Shortcuts in Browser

**Root cause:** In [AppDelegate.swift](Sources/Bowser/AppDelegate.swift), the Edit menu items (Copy, Paste, Cut, Select All, Undo, Redo) all set `target = self`, which hard-wires them to AppDelegate's custom handlers. This bypasses the standard macOS responder chain. CEF's internal Chromium NSView never gets a chance to handle these editing operations natively.

**Fix:** Remove `target = self` from the Edit menu items and use `nil` target with **standard editing action selectors** (`copy:`, `paste:`, `cut:`, `selectAll:`, `undo:`, `redo:`). This lets the standard NSResponder chain handle them:

- When CEF has focus, Chromium's internal NSView handles copy/paste natively
- When a SwiftUI TextField is focused, its NSTextField backing handles them natively

**Files to change:**

- [AppDelegate.swift](Sources/Bowser/AppDelegate.swift) ~lines 380-460: Change `action: #selector(handleCopy)` to `action: #selector(NSText.copy(_:))` (and similar for cut/paste/selectAll), remove `target = self` (set to `nil`). The `handleUndo`/`handleRedo` items should use `Selector(("undo:"))` / `Selector(("redo:"))` with `nil` target.
- Remove (or keep as utilities) the custom `handleCopy`, `handlePaste`, `handleCut`, `handleSelectAll` methods since the responder chain handles it now.

---

## 2. Homescreen Folder Icons: Distinct Icons, Smaller Size

**Current state:** All folders use `"folder.fill"` icon, 72x72 size, `minimum: 110` grid columns. Colors vary but the visual is repetitive.

**Changes:**

- [Folder.swift](Sources/Bowser/Models/Folder.swift) ~line 87-96: Update `Folder.defaults` to assign **distinct SF Symbol icons** per default folder (e.g., `"doc.text.fill"`, `"checkmark.circle.fill"`, `"airplane"`, `"book.fill"`, `"tray.fill"`, `"number.circle.fill"`) -- standard macOS-style icons. Keep `folder.fill` as the default for new user-created folders.
- [FolderIconView.swift](Sources/Bowser/Views/Homescreen/FolderIconView.swift): Reduce icon box from **72x72 to 52x52**, icon font from 32pt to 22pt, corner radius from 16 to 12. Reduce label width from 90 to 72.
- [HomescreenView.swift](Sources/Bowser/Views/Homescreen/HomescreenView.swift) ~line 54: Reduce grid `minimum` from 110 to 80, `maximum` from 130 to 100, and spacing from 20/24 to 16/18.
- [FolderIconView.swift](Sources/Bowser/Views/Homescreen/FolderIconView.swift) `NewFolderButton`: Reduce to match (52x52, same radius).

---

## 3. Bottom Bar Folder Popover: Tabs / Agents / Plans

**Current behavior:** Clicking a dock folder icon (`DockFolderIcon`) immediately opens the folder. The user wants a click to show a **vertical popover** listing the folder's contents first.

**Design:**

- Add a new `DockFolderPopover` view that, when a dock folder is clicked, shows a popover anchored above the icon with three sections: **Tabs**, **Plans**, **Agents**.
- Load content from existing persistence:
  - **Tabs:** `FolderTabPersistence.shared.loadTabs(forFolder:)` -- already exists
  - **Plans:** Load from `PlanStorageManager` (plans associated with the folder)
  - **Agents:** Load agent sessions for the folder (from BrowserState/AgentState)
- Each row shows the item title and an icon. Clicking a row opens the folder AND navigates to that specific item (sets `currentPanelMode` to `.tab`/`.plan`/`.agent` and selects the item).

**Files to change:**

- [HomescreenBottomBar.swift](Sources/Bowser/Views/Homescreen/HomescreenBottomBar.swift): Replace the `DockFolderIcon` tap action. Instead of directly calling `appNav.openFolder`, show the popover.
- Add a new `DockFolderPopover` private view inside `HomescreenBottomBar.swift` that renders the vertical list with sections and loads folder data.
- The popover uses `.popover(isPresented:)` anchored to the dock icon.

---

## 4. Bottom Bar: Centered, Shorter Width, Flexible Search

**Current state:** The bar stretches full width with `padding(.horizontal, 24)`. Search field is fixed at `frame(width: 160)`.

**Changes to [HomescreenBottomBar.swift](Sources/Bowser/Views/Homescreen/HomescreenBottomBar.swift):**

- Wrap the `HStack` in a `frame(maxWidth: 720)` (or similar) to limit width, then center it using `.frame(maxWidth: .infinity)` on the parent.
- Remove the fixed `frame(width: 160)` from the search field. Instead, let it stretch to fill the remaining space between the divider (after new-folder button) and the clock using `Spacer` removal -- the search field itself fills. Remove the existing `Spacer()` between search and clock.
- Remove or reduce `padding(.horizontal, 24)` on the outer container since centering handles positioning.

Layout becomes: `[folder icons] | [+] | [---search fills remaining---] | [clock]` -- all within a max-width centered pill.

---

## 5. Per-Folder Browsing History + Sidebar History Button

This is the largest feature. It requires a new data model, persistence, recording, and UI.

### 5a. History Model and Persistence

Create a new file `Sources/Bowser/Models/BrowsingHistoryItem.swift`:

```swift
struct BrowsingHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var timestamp: Date
    var domain: String?
}
```

Create a new file `Sources/Bowser/Services/FolderHistoryPersistence.swift` following the same pattern as [FolderTabPersistence.swift](Sources/Bowser/Services/FolderTabPersistence.swift):

- Stores history as `history.json` in `~/Library/Application Support/Bowser/Folders/{folderId}/`
- Methods: `addEntry(url:title:forFolder:)`, `loadHistory(forFolder:)`, `clearHistory(forFolder:)`, `deleteFolder(_:)`
- Cap at 1000 entries per folder, pruning oldest.

### 5b. Record History on Page Navigation

In [BrowserView.swift](Sources/Bowser/Views/BrowserView.swift), in the Coordinator's `browserDidChangeURL(_:)` and `browserDidChangeTitle(_:)` methods: when a page finishes loading (URL and title are available), call `FolderHistoryPersistence.shared.addEntry(...)` for the current folder (get folderId from `AppNavigationState.activeFolderId`).

### 5c. History View

Create a new view `Sources/Bowser/Views/HistoryView.swift` that displays browsing history for the current folder. It should look like Chrome's history page:

- Grouped by date (Today, Yesterday, older dates)
- Each row shows: favicon placeholder, title, URL domain, relative timestamp
- A "Clear History" button
- Search/filter at the top
- Clicking an entry navigates to that URL

### 5d. Sidebar History Button

In [ArcSidebarView.swift](Sources/Bowser/Views/Shell/ArcSidebarView.swift) ~lines 168-173, add a third button alongside Home and Settings:

```swift
HStack(spacing: 4) {
    homeButton
    historyButton   // NEW
    settingsButton
}
```

Add a `@State private var showingHistory = false` and toggle it on button click. When active, replace the main panel content (tab list area) with `HistoryView`, or present it as a full-page overlay in the sidebar.