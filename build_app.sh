#!/bin/bash

# =============================================================================
# Bowser App Builder  (Build Type 2: App Build — no VM)
# =============================================================================
# Produces a standalone Bowser.app that connects to a separately-running
# Python sidecar over TCP (localhost:8765).  No VM image is needed.
#
# Usage:
#   ./build_app.sh
#
# The resulting app expects the AI sidecar to already be running:
#   cd Sidecar && uvicorn app.main:app --host 127.0.0.1 --port 8765
#
# For a self-contained app with the backend bundled inside a Linux VM, use:
#   ./build_full.sh
# =============================================================================

set -e

# Configuration
APP_NAME="Bowser"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
PROJECT_DIR="$(pwd)"
ARCH=$(uname -m)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[Build]${NC} $1"; }
warn() { echo -e "${YELLOW}[Warn]${NC} $1"; }
error() { echo -e "${RED}[Error]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[Success]${NC} $1"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bowser App Build  (backend mode: development / TCP)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Prerequisites Check
log "Checking prerequisites..."
if ! command -v cmake &> /dev/null; then error "CMake not found. Install: brew install cmake"; fi
if ! command -v swift &> /dev/null; then error "Swift not found. Install Xcode."; fi

# 2. CEF Wrapper Check
CEF_DIR="$PROJECT_DIR/Vendor/cef"
WRAPPER_LIB="$CEF_DIR/build/libcef_dll_wrapper/libcef_dll_wrapper.a"

if [ ! -f "$WRAPPER_LIB" ]; then
    log "CEF wrapper library missing. Attempting to build..."
    if [ ! -d "$CEF_DIR" ]; then error "CEF binaries missing in Vendor/cef. Run ./run_dev.sh first."; fi
    
    mkdir -p "$CEF_DIR/build"
    cd "$CEF_DIR/build"
    
    CMAKE_GEN=""
    BUILD_CMD="make -j$(sysctl -n hw.ncpu)"
    if command -v ninja &> /dev/null; then CMAKE_GEN="-G Ninja"; BUILD_CMD="ninja"; fi
    
    cmake $CMAKE_GEN -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$ARCH" ..
    $BUILD_CMD libcef_dll_wrapper
    cd "$PROJECT_DIR"
fi

# 3. Clean and Create Bundle Structure
log "Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"

# 4. Build Swift App (Release mode)
log "Building Swift application in release mode..."
swift build -c release

BINARY_PATH=$(find .build -name "${APP_NAME}" -type f -perm +111 | grep "release" | head -1)
if [ ! -f "${BINARY_PATH}" ]; then
    error "Could not find built executable for ${APP_NAME}."
fi
log "Copying binary from ${BINARY_PATH}..."
cp "${BINARY_PATH}" "${MACOS_DIR}/"

# 4b. Helper App
HELPER_NAME="Bowser Helper"
HELPER_BUNDLE_PATH="${FRAMEWORKS_DIR}/${HELPER_NAME}.app"
HELPER_CONTENTS="${HELPER_BUNDLE_PATH}/Contents"
HELPER_MACOS="${HELPER_CONTENTS}/MacOS"

HELPER_BINARY_PATH=$(find .build -name "${HELPER_NAME}" -type f -perm +111 | grep "release" | head -1)
if [ ! -f "${HELPER_BINARY_PATH}" ]; then
    error "Could not find built executable for ${HELPER_NAME}."
fi
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

# 5. Copy CEF Framework
CEF_FRAMEWORK="Vendor/cef/Release/Chromium Embedded Framework.framework"
if [ -d "${CEF_FRAMEWORK}" ]; then
    log "Copying CEF Framework..."
    cp -R "${CEF_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
else
    error "CEF Framework not found at ${CEF_FRAMEWORK}"
fi

# 6. Copy GPU Libraries
log "Copying GPU libraries..."
CEF_LIBRARIES="${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework/Libraries"
for lib in "libGLESv2.dylib" "libEGL.dylib" "libvk_swiftshader.dylib" "vk_swiftshader_icd.json"; do
    if [ -f "${CEF_LIBRARIES}/${lib}" ]; then
        cp "${CEF_LIBRARIES}/${lib}" "${MACOS_DIR}/"
        cp "${CEF_LIBRARIES}/${lib}" "${HELPER_MACOS}/"
    else
        warn "GPU library $lib not found."
    fi
done

# 6b. Compile Asset Catalog
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

# 7. Info.plist  — BowserBackendMode = development (TCP sidecar)
log "Generating Info.plist (backend mode: development)..."
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
    <string>development</string>
</dict>
</plist>
EOF

# 8. Fix RPATH
log "Fixing @rpath in binary..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" || true

# 9. Ad-hoc sign (no virtualization entitlement needed — no VM)
log "Signing application bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
success "App build complete: ${PROJECT_DIR}/${APP_BUNDLE}"
log ""
log "Backend mode: development (TCP — localhost:8765)"
log "Start the sidecar before opening the app:"
log "  cd Sidecar && uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload"
log ""
log "Or use the full dev workflow:  ./run_dev.sh"
log "For a VM-backed build:        ./build_full.sh"
log ""
log "To run the app: open ${APP_BUNDLE}"
