# Bowser

## DEMO 

Bowser OS Style : 
https://github.com/user-attachments/assets/bf60615c-bfaa-480b-853d-400727383984

Feature Set : 
https://github.com/user-attachments/assets/894bef37-2acb-45af-a98f-8662634050e7

Dock : 
https://github.com/user-attachments/assets/5aab15db-1358-472c-bcd2-5b9879e3346e


A high-performance macOS browser shell built with a native hybrid architecture:

- **Swift 6.2 + SwiftUI** — Modern UI with NavigationSplitView, @Observable, and strict concurrency
- **CEF (Chromium Embedded Framework)** — Industry-standard web engine via Swift C++ interop
- **Python AI Sidecar** — FastAPI server for local AI agent capabilities

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Bowser Application                         │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌──────────────────────────────────────────┐ │
│  │  ArcSidebarView │  │       FloatingWebCanvasView              │ │
│  │  (SwiftUI +     │  │         (NSViewRepresentable +            │ │
│  │   Vibrancy)     │  │           CEF Browser Canvas)             │ │
│  │                 │  │                                           │ │
│  │  • SidebarURLBar│  │  ┌─────────────────────────────────────┐ │ │
│  │  • Pinned Tabs  │  │  │                                     │ │ │
│  │  • Tab List     │  │  │          CEF Web Content            │ │ │
│  │  • Spaces       │  │  │                                     │ │ │
│  └─────────────────┘  │  └─────────────────────────────────────┘ │ │
│                        └──────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│                        CEFBridge (C++ Interop)                      │
├───────────────────────────────┬─────────────────────────────────────┤
│           CEF Runtime         │          Python AI Sidecar          │
│        (Chromium Engine)      │        (FastAPI on :8765)           │
└───────────────────────────────┴─────────────────────────────────────┘
```

## Prerequisites

- **macOS 14+** (Sonoma or later)
- **Xcode Command Line Tools** (auto-installed if missing)
- **Swift 6.2+** (via Xcode 16+ or swift.org toolchain)
- **Python 3.11+** (auto-installed via Homebrew if missing)
- **CMake** (auto-installed via Homebrew if missing)
- **Ninja** (optional, auto-installed for faster builds)

## Quick Start

```bash
# Clone and enter the project
cd bowser-mac

# Run the development environment (handles everything automatically)
./run_dev.sh
```

The script will automatically:
1. ✅ Install required build tools (CMake, Ninja) via Homebrew
2. ✅ Download CEF binaries (~100-300MB) if not present
3. ✅ Build the CEF wrapper library (libcef_dll_wrapper)
4. ✅ Set up GPU library symlinks (libGLESv2, libEGL, etc.)
5. ✅ Create Python virtual environment and install dependencies
6. ✅ Start the AI sidecar on `http://localhost:8765`
7. ✅ Build and launch the Swift application
8. ✅ Stream all logs to the terminal

### Development Script Options

```bash
./run_dev.sh              # Full build and run
./run_dev.sh --help       # Show all options
./run_dev.sh --clean      # Clean rebuild (CEF wrapper + Swift)
./run_dev.sh --build-only # Build without running
./run_dev.sh --skip-sidecar # Run without AI sidecar
```

## Project Structure

```
bowser-mac/
├── Package.swift              # Swift package with C++ interop
├── Sources/
│   ├── Bowser/
│   │   ├── Main.swift         # App entry point
│   │   ├── AppDelegate.swift  # Window host, CEF lifecycle
│   │   ├── BrowserState.swift # @Observable state
│   │   ├── Views/
│   │   │   ├── AppShellView.swift       # Root NavigationSplitView
│   │   │   ├── BrowserView.swift        # CEF container
│   │   │   ├── CommandBarView.swift     # URL/search modal
│   │   │   ├── Shell/
│   │   │   │   ├── ArcSidebarView.swift       # Arc-style sidebar
│   │   │   │   ├── FloatingWebCanvasView.swift # Web content card
│   │   │   │   └── SidebarURLBar.swift        # Compact URL bar
│   │   │   └── Components/
│   │   │       └── SidebarComponents.swift    # Tab/Sidebar views
│   │   ├── Window/
│   │   │   └── FramelessWindow.swift    # Arc-style window chrome
│   │   ├── CEF/
│   │   │   ├── CEFBridge.swift     # C++ interop wrapper
│   │   │   └── CEFHandler.swift    # Event handlers
│   │   └── Services/
│   │       └── AIService.swift     # Sidecar HTTP client
│   └── CEFWrapper/
│       ├── module.modulemap   # C++ module definition
│       └── cef_shim.h         # Swift-compatible C headers
├── Sidecar/
│   ├── app.py                 # FastAPI server
│   └── requirements.txt
├── Vendor/
│   └── cef/                   # CEF binaries (auto-downloaded)
└── run_dev.sh                 # Development script
```

## IPC Flow

### Swift → Python Sidecar

```
1. User triggers AI action in the UI
2. AIService.shared.analyze(content:) is called
3. AIService sends HTTP POST to http://localhost:8765/analyze
4. Python FastAPI processes request, returns JSON
5. Result displayed in the UI
```

### Swift → CEF (C++ Interop)

```
1. User enters URL in CommandBarView or SidebarURLBar
2. BrowserState.createTab(url:) or navigation triggers update
3. BrowserCanvas.updateNSView() detects URL change
4. BrowserManager reparents CEF view into container
5. CEFBridge.navigate(handle:to:) calls cef_navigate_to_url()
```

## Development

### Using run_dev.sh (Recommended)

The `run_dev.sh` script handles the complete development workflow:

```bash
./run_dev.sh              # Full build and run
./run_dev.sh --clean      # Clean rebuild everything
./run_dev.sh --build-only # Just build, don't run
./run_dev.sh --skip-sidecar # Run without AI sidecar
```

### Manual Setup

#### Swift Only (No CEF)

The application runs in "stub mode" without CEF binaries, allowing UI development:

```bash
swift build  # Builds without CEF
swift run    # Runs with placeholder browser view
```

#### With CEF (Manual)

CEF binaries are auto-downloaded by `run_dev.sh`. For manual setup:

1. Download from [CEF Builds](https://cef-builds.spotifycdn.com/index.html)
2. Extract to `./Vendor/cef/`
3. Ensure the framework is at `./Vendor/cef/Release/Chromium Embedded Framework.framework`
4. Build the CEF wrapper library:
   ```bash
   cd Vendor/cef
   mkdir build && cd build
   cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
   ninja libcef_dll_wrapper
   ```
5. Create GPU library symlinks in `.build/arm64-apple-macosx/debug/`:
   ```bash
   ln -sf ../../../Vendor/cef/Release/Chromium\ Embedded\ Framework.framework/Libraries/libGLESv2.dylib .
   ln -sf ../../../Vendor/cef/Release/Chromium\ Embedded\ Framework.framework/Libraries/libEGL.dylib .
   ln -sf ../../../Vendor/cef/Release/Chromium\ Embedded\ Framework.framework/Libraries/libvk_swiftshader.dylib .
   ```

#### Python Sidecar (Manual)

```bash
cd Sidecar
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --port 8765 --reload
```

Test endpoints:
```bash
curl http://localhost:8765/health
curl -X POST http://localhost:8765/analyze \
  -H "Content-Type: application/json" \
  -d '{"content": "https://example.com"}'
```

## Key Features

- **Edge-to-Edge Design** — Custom NSWindow with transparent title bar
- **Traffic Light Repositioning** — Programmatic control of window buttons
- **Vibrancy Effects** — NSVisualEffectView bridged to SwiftUI
- **Strict Concurrency** — @MainActor isolation, Sendable types
- **@Observable State** — Low-overhead reactive updates

## License

MIT License - See [LICENSE](LICENSE) for details.
