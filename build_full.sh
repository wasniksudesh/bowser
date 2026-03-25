#!/bin/bash

# =============================================================================
# Bowser Full Builder  (Build Type 3: Full Build — macOS app + VM backend)
# =============================================================================
# Produces a fully self-contained Bowser.app where the Python AI backend runs
# inside an Alpine Linux VM via Apple Virtualization.framework.
#
# What this script does:
#   1. Builds the Alpine Linux VM image (system.img, vmlinuz, initramfs)
#   2. Builds the macOS Swift app in release mode
#   3. Bundles the VM image + kernel into the app's Resources/VM/
#   4. Writes BowserBackendMode = production into Info.plist
#   5. Codesigns with the com.apple.security.virtualization entitlement
#
# Prerequisites:
#   - Docker (for building Alpine image)
#   - qemu-img: brew install qemu
#   - cmake, swift, ninja (same as build_app.sh)
#
# Usage:
#   ./build_full.sh [--skip-vm-build]
#
#   --skip-vm-build   Skip rebuilding the VM image if system.img/vmlinuz/
#                     initramfs already exist in VM/ (useful during iteration).
#
# For a quick dev run without building the .app:   ./run_dev.sh
# For a .app that uses the TCP sidecar:            ./build_app.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Configuration
APP_NAME="Bowser"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
VM_RESOURCES_DIR="${RESOURCES_DIR}/VM"
ARCH=$(uname -m)

VM_BUILD_DIR="${PROJECT_DIR}/VM"
VM_SYSTEM_IMG="${VM_BUILD_DIR}/system.img"
VM_KERNEL="${VM_BUILD_DIR}/vmlinuz"
VM_INITRAMFS="${VM_BUILD_DIR}/initramfs"

SKIP_VM_BUILD=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${BLUE}[Build]${NC} $1"; }
warn()    { echo -e "${YELLOW}[Warn]${NC} $1"; }
error()   { echo -e "${RED}[Error]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[Build]${NC} $1"; }
step()    { echo -e "${CYAN}[Build]${NC} ▶ $1"; }

# =============================================================================
# Parse arguments
# =============================================================================

for arg in "$@"; do
    case $arg in
        --skip-vm-build)
            SKIP_VM_BUILD=true
            shift
            ;;
        --help|-h)
            echo "Usage: ./build_full.sh [--skip-vm-build]"
            echo ""
            echo "  --skip-vm-build   Reuse existing VM/system.img, VM/vmlinuz, VM/initramfs"
            exit 0
            ;;
    esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bowser Full Build  (backend mode: production / VM)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log "Host arch: $ARCH"
echo ""

# =============================================================================
# Step 1 — Prerequisites
# =============================================================================

step "Step 1/8: Checking prerequisites..."
if ! command -v cmake &> /dev/null; then error "CMake not found. Install: brew install cmake"; fi
if ! command -v swift &> /dev/null; then error "Swift not found. Install Xcode."; fi
if ! command -v docker &> /dev/null; then error "Docker not found. Install Docker Desktop."; fi
if ! command -v qemu-img &> /dev/null; then error "qemu-img not found. Install: brew install qemu"; fi

ENTITLEMENTS_PATH="${PROJECT_DIR}/Bowser.entitlements"
if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    error "Bowser.entitlements not found at ${ENTITLEMENTS_PATH}. It should contain com.apple.security.virtualization."
fi
success "Prerequisites OK"
echo ""

# =============================================================================
# Step 2 — Build VM image
# =============================================================================

step "Step 2/8: Building Alpine Linux VM image..."

if [ "$SKIP_VM_BUILD" = true ]; then
    log "--skip-vm-build: checking for existing VM artifacts..."
    [ -f "$VM_SYSTEM_IMG" ]  || error "system.img not found at $VM_SYSTEM_IMG"
    [ -f "$VM_KERNEL" ]      || error "vmlinuz not found at $VM_KERNEL"
    [ -f "$VM_INITRAMFS" ]   || error "initramfs not found at $VM_INITRAMFS"
    success "Using existing VM artifacts"
else
    log "Running VM/build-image.sh..."
    cd "${VM_BUILD_DIR}"
    bash build-image.sh
    cd "${PROJECT_DIR}"

    [ -f "$VM_SYSTEM_IMG" ]  || error "VM build did not produce system.img"
    [ -f "$VM_KERNEL" ]      || error "VM build did not produce vmlinuz"
    [ -f "$VM_INITRAMFS" ]   || error "VM build did not produce initramfs"
    success "VM image built"
fi
echo ""

# =============================================================================
# Step 3 — CEF Wrapper
# =============================================================================

step "Step 3/8: Checking CEF wrapper library..."
CEF_DIR="$PROJECT_DIR/Vendor/cef"
WRAPPER_LIB="$CEF_DIR/build/libcef_dll_wrapper/libcef_dll_wrapper.a"

if [ ! -f "$WRAPPER_LIB" ]; then
    log "CEF wrapper missing. Building..."
    [ -d "$CEF_DIR" ] || error "CEF binaries missing in Vendor/cef. Run ./run_dev.sh first."

    mkdir -p "$CEF_DIR/build"
    cd "$CEF_DIR/build"

    CMAKE_GEN=""
    BUILD_CMD="make -j$(sysctl -n hw.ncpu)"
    if command -v ninja &> /dev/null; then CMAKE_GEN="-G Ninja"; BUILD_CMD="ninja"; fi

    cmake $CMAKE_GEN -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$ARCH" ..
    $BUILD_CMD libcef_dll_wrapper
    cd "$PROJECT_DIR"
fi
success "CEF wrapper OK"
echo ""

# =============================================================================
# Step 4 — Create app bundle structure
# =============================================================================

step "Step 4/8: Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}" "${VM_RESOURCES_DIR}"
echo ""

# =============================================================================
# Step 5 — Build Swift app
# =============================================================================

step "Step 5/8: Building Swift application (release)..."
swift build -c release

BINARY_PATH=$(find .build -name "${APP_NAME}" -type f -perm +111 | grep "release" | head -1)
[ -f "${BINARY_PATH}" ] || error "Could not find built Bowser executable."
cp "${BINARY_PATH}" "${MACOS_DIR}/"

HELPER_NAME="Bowser Helper"
HELPER_BUNDLE_PATH="${FRAMEWORKS_DIR}/${HELPER_NAME}.app"
HELPER_CONTENTS="${HELPER_BUNDLE_PATH}/Contents"
HELPER_MACOS="${HELPER_CONTENTS}/MacOS"
HELPER_BINARY_PATH=$(find .build -name "${HELPER_NAME}" -type f -perm +111 | grep "release" | head -1)
[ -f "${HELPER_BINARY_PATH}" ] || error "Could not find built Bowser Helper executable."
mkdir -p "${HELPER_MACOS}"
cp "${HELPER_BINARY_PATH}" "${HELPER_MACOS}/"

log "Generating Helper Info.plist..."
cat > "${HELPER_CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${HELPER_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.bowser.mac.helper</string>
    <key>CFBundleName</key>
    <string>${HELPER_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
install_name_tool -add_rpath "@executable_path/../../../../Frameworks" "${HELPER_MACOS}/${HELPER_NAME}" || true
success "Swift app built"
echo ""

# =============================================================================
# Step 6 — CEF framework + GPU libs + assets + resource bundle
# =============================================================================

step "Step 6/8: Copying CEF framework and resources..."
CEF_FRAMEWORK="Vendor/cef/Release/Chromium Embedded Framework.framework"
[ -d "${CEF_FRAMEWORK}" ] || error "CEF Framework not found at ${CEF_FRAMEWORK}"
cp -R "${CEF_FRAMEWORK}" "${FRAMEWORKS_DIR}/"

CEF_LIBRARIES="${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework/Libraries"
for lib in "libGLESv2.dylib" "libEGL.dylib" "libvk_swiftshader.dylib" "vk_swiftshader_icd.json"; do
    if [ -f "${CEF_LIBRARIES}/${lib}" ]; then
        cp "${CEF_LIBRARIES}/${lib}" "${MACOS_DIR}/"
        cp "${CEF_LIBRARIES}/${lib}" "${HELPER_MACOS}/"
    else
        warn "GPU library $lib not found."
    fi
done

log "Compiling asset catalog..."
ACTOOL_DIR=$(mktemp -d)
/usr/bin/actool "${PROJECT_DIR}/Sources/Bowser/Assets.xcassets" \
    --compile "${RESOURCES_DIR}" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "${ACTOOL_DIR}/assets.plist"

BUNDLE_PATH=$(find .build -name "Bowser_Bowser.bundle" -type d | grep "release" | head -1)
if [ -d "${BUNDLE_PATH}" ]; then
    cp -R "${BUNDLE_PATH}" "${RESOURCES_DIR}/"
else
    warn "Swift Package resource bundle not found."
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" || true
success "CEF framework and resources copied"
echo ""

# =============================================================================
# Step 7 — Bundle VM artifacts + Info.plist
# =============================================================================

step "Step 7/8: Bundling VM artifacts and writing Info.plist..."

log "Copying VM images into bundle..."
cp "$VM_SYSTEM_IMG"  "${VM_RESOURCES_DIR}/system.img"
cp "$VM_KERNEL"      "${VM_RESOURCES_DIR}/vmlinuz"
cp "$VM_INITRAMFS"   "${VM_RESOURCES_DIR}/initramfs"

SYSTEM_IMG_SIZE=$(du -h "${VM_RESOURCES_DIR}/system.img"  | cut -f1)
KERNEL_SIZE=$(du -h "${VM_RESOURCES_DIR}/vmlinuz"         | cut -f1)
INITRAMFS_SIZE=$(du -h "${VM_RESOURCES_DIR}/initramfs"    | cut -f1)
log "  system.img:  $SYSTEM_IMG_SIZE"
log "  vmlinuz:     $KERNEL_SIZE"
log "  initramfs:   $INITRAMFS_SIZE"

log "Generating Info.plist (backend mode: production)..."
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.bowser.mac</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>BowserBackendMode</key>
    <string>production</string>
</dict>
</plist>
EOF
success "VM artifacts bundled and Info.plist written"
echo ""

# =============================================================================
# Step 8 — Codesign with Virtualization entitlement
# =============================================================================

step "Step 8/8: Signing with Virtualization entitlement..."
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS_PATH" \
    "${APP_BUNDLE}"
success "Signed with com.apple.security.virtualization"
echo ""

# =============================================================================
# Done
# =============================================================================

TOTAL_SIZE=$(du -sh "${APP_BUNDLE}" | cut -f1)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
success "Full build complete: ${PROJECT_DIR}/${APP_BUNDLE}  (${TOTAL_SIZE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log ""
log "Backend mode: production (Alpine Linux VM via vsock)"
log "  - VM boots on app launch; no separate sidecar needed"
log "  - kernel + rootfs bundled in Resources/VM/"
log "  - LUKS-encrypted data volume at ~/Library/Application Support/Bowser/VM/mem0.img"
log ""
log "To run the app: open ${APP_BUNDLE}"
