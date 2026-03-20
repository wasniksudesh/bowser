---
name: Linux VM Backend Sandbox
overview: Run the Python Flask backend in a lightweight Alpine Linux VM using Apple Virtualization.framework for security sandboxing, with vsock communication, LUKS-encrypted persistent storage, and seamless dev/production mode switching.
todos:
  - id: swift-vm-manager
    content: Create VMManager.swift using Virtualization.framework to manage VM lifecycle
    status: in_progress
  - id: swift-vsock-client
    content: Create VSockClient.swift - HTTP client over vsock replacing URLSession calls
    status: pending
  - id: swift-vm-bootstrap
    content: Create VMBootstrap.swift for first-launch image download flow
    status: pending
  - id: alpine-image-builder
    content: Create VM/build-image.sh to build Alpine Linux system.img with Python + deps
    status: pending
  - id: vsock-transport
    content: Add vsock listener mode to Sidecar/app/main.py (hypercorn or custom ASGI)
    status: pending
  - id: luks-setup
    content: Implement LUKS encryption for mem0.img with key exchange via vsock
    status: pending
  - id: mcp-bridge
    content: Create Swift-side vsock-to-Docker bridge for MCP Gateway
    status: pending
  - id: remove-playwright
    content: Remove playwright from requirements.txt (unused)
    status: pending
  - id: update-build-app
    content: Update build_app.sh to bundle VM bootstrap code
    status: pending
  - id: dev-mode-guard
    content: "Add runtime detection: dev mode uses direct process, release uses VM"
    status: pending
isProject: false
---

# Linux VM Backend Sandbox

## Architecture Overview

```mermaid
graph TB
    subgraph macOS_Host [macOS Host]
        SwiftApp[Bowser Swift App]
        Keychain[macOS Keychain]
        Docker[Docker Desktop]
    end
    
    subgraph VM [Alpine Linux VM]
        FastAPI[FastAPI Backend]
        Qdrant[Qdrant Vector DB]
        MCP_Native[MCP Servers Native]
        Mem0[mem0.img RW Encrypted]
    end
    
    SwiftApp -->|vsock HTTP| FastAPI
    SwiftApp -->|Boot: API keys| FastAPI
    Keychain -->|Retrieve| SwiftApp
    FastAPI -->|vsock| Docker
    FastAPI --> Qdrant
    FastAPI --> MCP_Native
    Qdrant --> Mem0
```



## Design Decisions Summary


| Decision       | Choice                                                                         |
| -------------- | ------------------------------------------------------------------------------ |
| IPC Protocol   | HTTP over vsock (keep FastAPI, change transport)                               |
| Encryption     | LUKS (key from macOS Keychain via vsock at boot)                               |
| VM Lifecycle   | Start with app, stop on quit                                                   |
| API Keys       | User enters in Swift UI -> Keychain -> passed to VM at session start via vsock |
| Python Runtime | uv with frozen lockfile (fast, reproducible)                                   |
| Image Updates  | Full image replacement on app update                                           |
| MCP            | Native in Alpine + Docker MCP Gateway on host via vsock                        |
| Playwright     | Remove (not used)                                                              |
| VM Packaging   | Download on first launch to `~/Library/Application Support/Bowser/`          |


## VM Specification

```yaml
Hypervisor: Apple Virtualization.framework
Guest_OS: Alpine Linux 3.19 (musl-based, minimal)
CPU: 2 vCPUs
RAM: 2-4 GB (configurable)
Disks:
  system.img: 
    size: ~500MB
    mode: read-only
    contents: Alpine + Python + uv venv + app code
  mem0.img:
    size: 1-5GB (growable)
    mode: read-write
    encryption: LUKS2
    mount: /mem0 (rw,noexec)
    contents: Qdrant data, user memories
Mounts:
  /: read-only (system.img)
  /mem0: rw,noexec (mem0.img)
  /tmp: tmpfs (ephemeral)
Network: vsock only (no TCP/IP)
```

## Implementation

### Phase 1: Swift VM Manager

Create `[Sources/Bowser/VM/VMManager.swift](Sources/Bowser/VM/VMManager.swift)`:

```swift
// Key responsibilities:
// - Create/configure VZVirtualMachine with Virtualization.framework
// - Manage vsock device for IPC
// - Handle VM lifecycle (start/stop with app)
// - Pass LUKS key and API keys at boot via vsock
```

Key classes:

- `VMManager`: Singleton managing VM lifecycle
- `VSockConnection`: HTTP client over vsock (port 8765)
- `VMBootstrap`: Handles first-launch image download

### Phase 2: Alpine Linux Image Build

Create `[VM/build-image.sh](VM/build-image.sh)`:

```bash
# Build reproducible Alpine image with:
# - Python 3.12 + uv
# - Frozen venv from Sidecar/requirements.txt (minus playwright)
# - Init system (OpenRC or direct PID 1)
# - vsock HTTP server setup
# - LUKS tools for encrypted mount
```

Output: `system.img` (~500MB)

### Phase 3: vsock HTTP Transport

Modify `[Sidecar/app/main.py](Sidecar/app/main.py)`:

```python
# In VM mode:
# - Listen on vsock instead of TCP
# - Use hypercorn with vsock support or custom ASGI server
# - Receive LUKS key on boot, unlock /mem0
# - Receive API keys, store in memory only
```

### Phase 4: Dev/Production Mode Switch

Update `[run_dev.sh](run_dev.sh)`:

- Keep current behavior (direct Python process on macOS)
- No changes needed for dev workflow

Update `[build_app.sh](build_app.sh)`:

- Bundle VM bootstrap code
- First-launch downloads `system.img` + creates empty `mem0.img`
- Production app uses VM exclusively

### Phase 5: MCP Docker Gateway Bridge

Create vsock proxy for Docker MCP Gateway:

```
[FastAPI in VM] --vsock--> [Swift proxy] --stdio--> [docker mcp gateway run]
```

Swift acts as bridge between VM and Docker on host.

## File Structure

```
Sources/Bowser/
├── VM/
│   ├── VMManager.swift          # VM lifecycle management
│   ├── VSockClient.swift        # HTTP-over-vsock client
│   ├── VMBootstrap.swift        # First-launch image download
│   └── VMConfiguration.swift    # CPU/RAM/disk settings

VM/
├── build-image.sh               # Alpine image builder
├── alpine/
│   ├── init                     # PID 1 init script
│   ├── start-backend.sh         # Launch FastAPI on vsock
│   └── unlock-storage.sh        # LUKS unlock helper
├── Dockerfile.build             # For reproducible builds
└── requirements-vm.txt          # Sidecar deps minus playwright

Sidecar/app/
├── main.py                      # Add vsock listener mode
└── vsock_transport.py           # vsock ASGI transport
```

## Security Model

1. **Network Isolation**: VM has no TCP/IP, only vsock to host
2. **Filesystem Isolation**: Root is read-only, only /mem0 writable
3. **No Exec on Data**: /mem0 mounted with noexec
4. **Encrypted at Rest**: User data in LUKS, key never persists in VM
5. **API Keys in Memory**: Passed at boot, stored in tmpfs only
6. **Process Isolation**: Full VM boundary, not just container

## First-Launch Flow

```mermaid
sequenceDiagram
    participant User
    participant Swift as Bowser Swift
    participant FS as Filesystem
    participant CDN as Download Server
    participant VM as Alpine VM
    
    User->>Swift: Launch app
    Swift->>FS: Check ~/Library/App Support/Bowser/system.img
    alt Image missing
        Swift->>CDN: Download system.img (~500MB)
        Swift->>FS: Save to App Support
        Swift->>FS: Create empty mem0.img (LUKS formatted)
    end
    Swift->>VM: Start VM with images
    VM->>Swift: vsock: Ready, need LUKS key
    Swift->>VM: vsock: LUKS key from Keychain
    VM->>VM: Unlock /mem0
    VM->>Swift: vsock: Ready for API keys
    Swift->>VM: vsock: API keys from Keychain
    VM->>Swift: vsock: Backend ready on port 8765
    Swift->>User: App ready
```



