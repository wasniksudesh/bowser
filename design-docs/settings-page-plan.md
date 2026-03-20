---
name: Settings Page Design
overview: Comprehensive Settings page structure for Bowser, organized into Phase 1 (Essential), Phase 2 (Advanced), and Phase 3 (Power User), with UX organization following Arc-style design patterns.
todos: []
---

# Bowser Settings Page Design

## Overview

A comprehensive Settings page structure inspired by Arc browser aesthetics, organized into 3 implementation phases. The design follows Arc's clean, category-based approach while incorporating modern browser features from Chrome, Brave, and Vivaldi.

---

## UX Organization Pattern

### Layout Structure

- **Sidebar Navigation** (left): Category list with icons
- **Main Content Area** (right): Settings grouped by subcategories
- **Visual Style**: Arc-style floating card aesthetic with vibrancy material
- **Search**: Global settings search bar at top

### Hierarchy Pattern

```
Category (Sidebar)
  └─ Section Header (Main Area)
      ├─ Setting Group 1
      │   ├─ Toggle/Select Control
      │   └─ Description text
      └─ Setting Group 2
```

---

## Phase 1: Essential Settings (MVP)

### 1. General

**Icon**: `gear` | **Category**: Basic browser behavior

#### Startup

- **On Startup**: Radio buttons
  - Open new tab
  - Continue where you left off
  - Open specific pages (list editor)

#### Default Browser

- **Make Bowser your default browser**: Action button with status indicator

#### Downloads

- **Download location**: Path picker with "Browse" button
- **Ask where to save each file before downloading**: Toggle

---

### 2. Search

**Icon**: `magnifyingglass` | **Category**: Search behavior

#### Search Engine

- **Default search engine**: Dropdown
  - Google
  - DuckDuckGo
  - Bing
  - Brave Search
  - Custom (URL template field)

#### Command Bar

- **Show search suggestions**: Toggle
- **Max history items**: Stepper (5-20)

---

### 3. Privacy & Security

**Icon**: `lock.shield` | **Category**: Privacy controls

#### Browsing Data

- **Clear browsing data**: Action button → Modal with:
  - Time range selector
  - Checkboxes: History, Cookies, Cache, Passwords, Autofill
  - "Clear Data" action button

#### Cookies

- **Cookie settings**: Dropdown
  - Allow all cookies
  - Block third-party cookies
  - Block all cookies

#### Site Permissions

- **Default permissions**: List of permission types with dropdown (Ask / Allow / Block)
  - Camera
  - Microphone
  - Location
  - Notifications
  - Pop-ups

---

### 4. AI Features

**Icon**: `sparkles` | **Category**: AI integration

#### AI Provider

- **Provider**: Dropdown (OpenAI / Anthropic / Local)
- **API Key**: Secure field with "Test Connection" button
- **Model**: Dropdown (populated based on provider)

#### AutoURL Plugin

- **Enable AutoURL**: Toggle
- **Trigger phrase**: Text field (default: "/autourl")
- **Fallback to search on error**: Toggle

---

### 5. Floating Dock

**Icon**: `dock.rectangle` | **Category**: Dock widget

#### Visibility

- **Show floating dock**: Toggle
- **Dock stays on top**: Toggle

#### Layout

- **Preview height**: Slider (300-600pt)
- **Container width**: Slider (300-500pt)

---

### 6. Keyboard Shortcuts

**Icon**: `command` | **Category**: Shortcuts

#### Core Actions (Read-only list with shortcut badges)

- New Tab: `⌘T`
- Close Tab: `⌘W`
- Next Tab: `⌘⌥→`
- Previous Tab: `⌘⌥←`
- Command Bar: `⌘T`
- Settings: `⌘,`
- New Space: `⌘⇧N`

**Note**: Phase 1 shows shortcuts but doesn't allow customization

---

## Phase 2: Advanced Settings

### 7. Appearance

**Icon**: `paintpalette` | **Category**: Visual customization

#### Theme

- **Theme**: Segmented control
  - Light
  - Dark
  - Auto (system)

#### Sidebar

- **Sidebar position**: Segmented control (Left / Right)
- **Show sidebar on startup**: Toggle
- **Sidebar width**: Slider (220-400pt)

#### Web Content

- **Default zoom level**: Dropdown (50% - 200%)
- **Font size**: Dropdown (Small / Medium / Large / Extra Large)
- **Show full URLs in address bar**: Toggle

---

### 8. Spaces & Tabs

**Icon**: `square.grid.2x2` | **Category**: Workspace management

#### Spaces

- **Default space on startup**: Dropdown (list of spaces)
- **Show space indicator in sidebar**: Toggle

#### Tabs

- **Auto-archive inactive tabs**: Toggle + Dropdown (Never / 1 day / 3 days / 1 week / 1 month)
- **Show tab preview on hover**: Toggle
- **Tab tree depth**: Stepper (1-5 levels)
- **Keep pinned tabs on startup**: Toggle

---

### 9. Profiles

**Icon**: `person.2` | **Category**: Multi-profile support

#### Profile Management

- **Current profile**: Display name + edit button
- **Create new profile**: Action button
- **Profile list**: Cards with:
  - Profile name
  - Space count badge
  - Switch / Edit / Delete actions

#### Per-Profile Settings

- **Separate profiles for each space**: Toggle
- **Profile-specific search engine**: Toggle
- **Sync profiles**: Toggle (requires account)

---

### 10. Sync & Account

**Icon**: `arrow.triangle.2.circlepath` | **Category**: Cloud sync

#### Account

- **Sign in with**: OAuth buttons (Google / GitHub / Email)
- **Account status**: Display with user avatar

#### Sync Settings

- **Sync across devices**: Master toggle
- **What to sync**: Checkboxes
  - Spaces
  - Favorites
  - Open tabs
  - History
  - Extensions
  - Passwords
  - Settings

---

### 11. Extensions

**Icon**: `puzzlepiece` | **Category**: Extension management

#### Installed Extensions

- **List view**: Extension cards with:
  - Icon, name, version
  - Enable/disable toggle
  - Configure / Remove buttons

#### Extension Sources

- **Allow Chrome Web Store**: Toggle
- **Developer mode**: Toggle (enables loading unpacked)

---

### 12. Languages & Region

**Icon**: `globe` | **Category**: Localization

#### Display Language

- **Browser language**: Dropdown (English / Spanish / French / etc.)
- **Translate pages not in this language**: Toggle

#### Spell Check

- **Languages to check**: Multi-select list
- **Add custom dictionary words**: Text area

#### Time & Date

- **Time format**: Radio (12-hour / 24-hour)
- **First day of week**: Dropdown

---

### 13. Network

**Icon**: `wifi` | **Category**: Network settings

#### Proxy

- **Proxy configuration**: Dropdown
  - System proxy
  - No proxy
  - Manual proxy (with fields for HTTP/HTTPS/SOCKS)

#### DNS

- **Secure DNS**: Dropdown
  - Use system DNS
  - Cloudflare (1.1.1.1)
  - Google (8.8.8.8)
  - Custom

#### Connection

- **Preload pages for faster browsing**: Toggle
- **Use hardware acceleration**: Toggle

---

### 14. Advanced Privacy

**Icon**: `hand.raised.shield` | **Category**: Enhanced privacy

#### Tracking Protection

- **Block trackers**: Dropdown (Off / Standard / Strict)
- **Block fingerprinting**: Toggle
- **Block cryptominers**: Toggle

#### HTTPS

- **HTTPS-Only Mode**: Toggle
- **Warn about insecure downloads**: Toggle

#### DNT (Do Not Track)

- **Send "Do Not Track" header**: Toggle

---

### 15. History

**Icon**: `clock.arrow.circlepath` | **Category**: Browsing history

#### History Settings

- **Enable browsing history**: Toggle
- **History retention**: Dropdown (Forever / 90 days / 30 days / 7 days)
- **Include in search**: Toggle

#### Command Bar History

- **Save command bar searches**: Toggle
- **Max history items**: Stepper (50-1000)
- **Clear history**: Action button

---

### 16. Autofill

**Icon**: `textformat` | **Category**: Form filling

#### Passwords

- **Save passwords**: Toggle
- **Auto sign-in**: Toggle
- **Password manager**: Action button → Password list view

#### Payment Methods

- **Save and fill payment methods**: Toggle
- **Payment method list**: Cards with edit/delete

#### Addresses

- **Save and fill addresses**: Toggle
- **Address list**: Cards with edit/delete

---

### 17. Notifications

**Icon**: `bell` | **Category**: Browser notifications

#### Desktop Notifications

- **Show notifications**: Toggle
- **Show notification badge**: Toggle

#### Types

- **Download complete**: Toggle
- **Extension updates**: Toggle
- **Tab suspended**: Toggle

---

### 18. System

**Icon**: `gear.circle` | **Category**: System integration

#### Performance

- **Hardware acceleration**: Toggle
- **Continue running background apps when Bowser is closed**: Toggle
- **Memory saver**: Toggle + threshold slider

#### Updates

- **Auto-update Bowser**: Toggle
- **Check for updates**: Action button
- **Update channel**: Dropdown (Stable / Beta / Dev)

---

## Phase 3: Power User Settings

### 19. Developer Tools

**Icon**: `chevron.left.forwardslash.chevron.right` | **Category**: Developer features

#### DevTools

- **Default DevTools position**: Dropdown (Bottom / Right / Undocked)
- **Enable source maps**: Toggle
- **Dark theme for DevTools**: Toggle

#### Console

- **Log XMLHttpRequests**: Toggle
- **Show timestamps**: Toggle
- **Preserve log upon navigation**: Toggle

#### Experiments

- **Enable experimental features**: Toggle
- **Feature flags**: Expandable list of experimental toggles

---

### 20. Custom CSS/JS

**Icon**: `paintbrush.pointed` | **Category**: Site customization

#### Per-Site Customizations

- **Enable site boosts**: Master toggle
- **Boost list**: Cards showing:
  - Site domain
  - Active customizations badge
  - Edit / Delete

#### Global Styles

- **Custom CSS**: Code editor for global CSS
- **Custom JS**: Code editor for global JS

---

### 21. Command Chains

**Icon**: `link` | **Category**: Automation

#### Command Chains

- **Enable command chains**: Toggle
- **Chain list**: Cards with:
  - Chain name
  - Trigger shortcut
  - Step count
  - Edit / Delete / Duplicate

#### Creation

- **Create chain**: Wizard with:
  - Name
  - Trigger (keyboard shortcut or command bar phrase)
  - Step builder (drag-and-drop actions)

---

### 22. Gestures

**Icon**: `hand.draw` | **Category**: Mouse/trackpad

#### Mouse Gestures

- **Enable mouse gestures**: Toggle
- **Gesture sensitivity**: Slider (Low / Medium / High)
- **Show gesture trail**: Toggle

#### Gesture Mapping

- **Gesture list**: Visual with action mapping
  - Up: New tab
  - Down: Close tab
  - Left: Back
  - Right: Forward
  - Custom gestures: Builder

---

### 23. Tab Management Advanced

**Icon**: `rectangle.stack` | **Category**: Advanced tab features

#### Tab Stacking

- **Enable tab stacking**: Toggle
- **Stack naming**: Toggle (auto-generate or manual)
- **Stack color coding**: Toggle

#### Tab Sleeping

- **Auto-sleep inactive tabs**: Toggle
- **Sleep after**: Stepper (minutes)
- **Exclude pinned tabs**: Toggle
- **Exclude audio tabs**: Toggle

#### Tab Tiling

- **Enable side-by-side tiling**: Toggle
- **Default split ratio**: Slider (1:1 to 3:1)
- **Sync scroll between tiled tabs**: Toggle

---

### 24. Workspace Rules

**Icon**: `arrow.triangle.branch` | **Category**: Space automation

#### Air Traffic Control

- **Enable automatic routing**: Toggle
- **Rule list**: Cards showing:
  - URL pattern
  - Target space
  - Behavior (Open / Switch)
  - Edit / Delete

#### Space Templates

- **Template list**: Cards with:
  - Template name
  - Tab count
  - Create from template button

---

### 25. Import/Export

**Icon**: `arrow.up.arrow.down.square` | **Category**: Data portability

#### Import

- **Import from browser**: Dropdown (Chrome / Firefox / Safari / Edge / Arc / Vivaldi)
- **What to import**: Checkboxes
  - Favorites
  - History
  - Passwords
  - Settings
- **Import** action button

#### Export

- **Export settings**: JSON file download
- **Export favorites**: HTML bookmark file
- **Export passwords**: Encrypted CSV

#### Backup

- **Auto-backup settings**: Toggle
- **Backup frequency**: Dropdown (Daily / Weekly / Monthly)
- **Backup location**: Path picker

---

### 26. Experimental AI

**Icon**: `brain` | **Category**: Experimental AI

#### Smart Suggestions

- **Suggest related tabs**: Toggle
- **Suggest searches based on page content**: Toggle
- **Auto-summarize articles**: Toggle

#### Memory/Context

- **Enable AI memory**: Toggle
- **Memory retention**: Dropdown (Session / 7 days / 30 days / Forever)
- **Clear AI memory**: Action button

#### MCP Servers

- **Enable MCP integration**: Toggle
- **Server list**: Cards with connection status
- **Add MCP server**: Modal with URL/config

---

### 27. Accessibility

**Icon**: `accessibility` | **Category**: Accessibility features

#### Visual

- **High contrast mode**: Toggle
- **Force colors**: Toggle
- **Minimum font size**: Stepper (9-24px)
- **Zoom text only**: Toggle (vs zooming entire page)

#### Navigation

- **Always show keyboard focus**: Toggle
- **Tab cycling**: Toggle (include/exclude address bar)

#### Reader Mode

- **Enable reader mode**: Toggle
- **Auto-activate reader mode**: Toggle for article pages
- **Reader theme**: Dropdown (Sepia / White / Gray / Black)
- **Reader font**: Dropdown (Serif / Sans-serif / Dyslexic-friendly)

---

### 28. Performance Monitoring

**Icon**: `chart.bar` | **Category**: Browser performance

#### Metrics

- **Show memory usage in dock**: Toggle
- **Performance dashboard**: Action button → Modal with:
  - Memory usage per tab
  - CPU usage
  - Network activity
  - Extension impact

#### Limits

- **Max tabs before warning**: Stepper
- **Max memory before tab suspension**: Slider (GB)

---

### 29. CEF/Engine

**Icon**: `engine.combustion` | **Category**: Browser engine

#### Chromium Settings

- **CEF version**: Display only (with "Check updates" button)
- **User agent**: Dropdown (Default / Chrome / Safari / Custom)

#### Rendering

- **WebGL**: Toggle
- **WebGPU**: Toggle
- **Force GPU rasterization**: Toggle

#### Debugging

- **Enable CEF debugging**: Toggle
- **Debug port**: Number field (default: 9222)

---

### 30. Policy & Administration

**Icon**: `building.2` | **Category**: Enterprise settings

#### Managed Settings

- **Policy status**: Display (Managed / Unmanaged)
- **Applied policies**: Read-only list

#### Restrictions

- **Allow policy overrides**: Toggle (admin only)
- **Require extension allowlist**: Toggle

---

## Settings Search & Navigation

### Global Search

- **Search bar** at top of Settings window
- Real-time filtering of all settings
- Highlights matching text in results
- Shows breadcrumb path (e.g., "Privacy & Security > Cookies > Block third-party")

### Recently Changed

- Section at top showing last 5 modified settings with "Revert" buttons

### Quick Access

- Pinned settings: Star icon next to any setting to add to "Favorites" tab

---

## Implementation Notes

### Data Storage

- All settings persist to `UserDefaults` with appropriate keys
- Settings sync structure mirrors current patterns (e.g., `FloatingDockState`)
- Create `SettingsManager` observable class similar to existing managers

### UI Components

- Reuse existing Arc-style components (`ArcTheme`, vibrancy materials)
- Settings window as separate window (not sheet) for better multi-tasking
- Sidebar uses `List` with `.listStyle(.sidebar)`
- Main content uses `Form` with grouped sections

### Validation & Defaults

- All settings have sensible defaults
- Validation for text fields (URLs, ports, etc.)
- Confirmation dialogs for destructive actions (clear data, reset settings)

---

## Visual Mockup Structure

```
┌────────────────────────────────────────────────────────────────┐
│  ⚙ Settings                                      [Search...] ×  │
├──────────────┬─────────────────────────────────────────────────┤
│              │                                                  │
│  General     │  ◉ General                                      │
│  Appearance  │  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│  Search      │                                                  │
│  Privacy     │  Startup                                        │
│  Spaces      │  ○ Open new tab                                 │
│  AI          │  ● Continue where you left off                  │
│  Dock        │  ○ Open specific pages                          │
│  Shortcuts   │                                                  │
│              │  Default Browser                                │
│  ─────────   │  Bowser is your default browser     ✓        │
│              │                                                  │
│  [Phase 2]   │  Downloads                                      │
│  Profiles    │  Location: ~/Downloads            [Browse...]  │
│  Sync        │  [ ] Ask where to save each file                │
│  Extensions  │                                                  │
│  Languages   │                                                  │
│  Network     │                                                  │
│  ...         │                                                  │
│              │                                                  │
└──────────────┴─────────────────────────────────────────────────┘
```

---

## Summary

### Phase 1 (Essential): 6 Categories, ~25 Settings

Core functionality for basic browser usage, AI integration, and Bowser's unique features (Dock, Command Bar, Keyboard Shortcuts). Focused on essential privacy, search, and AI settings without appearance or workspace management complexity.

### Phase 2 (Advanced): 12 Categories, ~75 Settings  

Enhanced features including profiles, sync, extensions, network customization, comprehensive privacy controls, appearance customization, and workspace/tab management (Spaces & Tabs and Appearance moved here from Phase 1).

### Phase 3 (Power User): 12 Categories, ~80 Settings

Advanced customization including developer tools, CSS/JS injection, command automation, gestures, performance monitoring, and enterprise features.

**Total**: