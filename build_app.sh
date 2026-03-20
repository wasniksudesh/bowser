#!/bin/bash

# =============================================================================
# Bowser Standalone App Builder
# =============================================================================
# This script bundles Bowser into a standalone .app structure.
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

# 1. Prerequisites Check
log "Checking prerequisites..."
if ! command -v cmake &> /dev/null; then error "CMake not found. Please install it with 'brew install cmake'"; fi
if ! command -v swift &> /dev/null; then error "Swift not found. Please install Xcode."; fi

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

# 3. Clean and Create Structure
log "Creating app bundle structure..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"

# 4. Build Swift App (Release mode)
log "Building Swift application in Release mode..."
# We use -Xswiftc -O to ensure release optimizations even if -c release fails
swift build -c release

# Find the built executable
BINARY_PATH=$(find .build -name "${APP_NAME}" -type f -perm +111 | grep "release" | head -1)
if [ ! -f "${BINARY_PATH}" ]; then
    error "Could not find built executable for ${APP_NAME} in release mode."
fi

log "Copying binary from ${BINARY_PATH}..."
cp "${BINARY_PATH}" "${MACOS_DIR}/"

# 4b. Build and Bundle Helper App
log "Building Bowser Helper..."
HELPER_NAME="Bowser Helper"
HELPER_BUNDLE="${HELPER_NAME}.app"
HELPER_BUNDLE_PATH="${FRAMEWORKS_DIR}/${HELPER_BUNDLE}"
HELPER_CONTENTS="${HELPER_BUNDLE_PATH}/Contents"
HELPER_MACOS="${HELPER_CONTENTS}/MacOS"

# Find the built helper executable
HELPER_BINARY_PATH=$(find .build -name "${HELPER_NAME}" -type f -perm +111 | grep "release" | head -1)
if [ ! -f "${HELPER_BINARY_PATH}" ]; then
    error "Could not find built executable for ${HELPER_NAME} in release mode."
fi

log "Creating Helper app bundle structure..."
mkdir -p "${HELPER_MACOS}"

log "Copying Helper binary from ${HELPER_BINARY_PATH}..."
cp "${HELPER_BINARY_PATH}" "${HELPER_MACOS}/"

# Create Helper Info.plist with LSUIElement=1 (background-only app)
log "Generating Helper Info.plist with LSUIElement=1..."
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

# Fix RPATH in Helper binary
log "Fixing @rpath in Helper binary..."
install_name_tool -add_rpath "@executable_path/../../../../Frameworks" "${HELPER_MACOS}/${HELPER_NAME}" || true


# 5. Copy CEF Framework
CEF_FRAMEWORK="Vendor/cef/Release/Chromium Embedded Framework.framework"
if [ -d "${CEF_FRAMEWORK}" ]; then
    log "Copying CEF Framework (this may take a moment)..."
    # Note: Copying instead of linking for true standalone portability
    cp -R "${CEF_FRAMEWORK}" "${FRAMEWORKS_DIR}/"
else
    error "CEF Framework not found at ${CEF_FRAMEWORK}"
fi

# 6. Copy GPU Libraries (CEF expects these next to the executable)
log "Copying GPU libraries to main app and Helper app..."
CEF_LIBRARIES="${FRAMEWORKS_DIR}/Chromium Embedded Framework.framework/Libraries"
for lib in "libGLESv2.dylib" "libEGL.dylib" "libvk_swiftshader.dylib" "vk_swiftshader_icd.json"; do
    if [ -f "${CEF_LIBRARIES}/${lib}" ]; then
        # Copy to main app
        cp "${CEF_LIBRARIES}/${lib}" "${MACOS_DIR}/"
        # Copy to Helper app (GPU processes run from Helper)
        cp "${CEF_LIBRARIES}/${lib}" "${HELPER_MACOS}/"
    else
        warn "GPU library $lib not found, UI hardware acceleration might be limited."
    fi
done

# 6b. Compile and Copy Resources
log "Compiling asset catalog..."
# Create a temporary directory for actool output
ACTOOL_DIR=$(mktemp -d)
/usr/bin/actool "${PROJECT_DIR}/Sources/Bowser/Assets.xcassets" \
    --compile "${RESOURCES_DIR}" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
	--output-partial-info-plist "${ACTOOL_DIR}/assets.plist"

# Find and copy the resource bundle generated by SPM
# SPM generated accessor expects it at Bowser.app/Bowser_Bowser.bundle
# (Not in Contents/Resources) based on the resource_bundle_accessor.swift
BUNDLE_PATH=$(find .build -name "Bowser_Bowser.bundle" -type d | grep "release" | head -1)
if [ -d "${BUNDLE_PATH}" ]; then
    log "Found resource bundle at ${BUNDLE_PATH}"
    # Copy to the root of the app bundle so Bundle.module can find it
    cp -R "${BUNDLE_PATH}" "${APP_BUNDLE}/"
    # Also copy to Resources for standard compliance
    cp -R "${BUNDLE_PATH}" "${RESOURCES_DIR}/"
else
    warn "Swift Package resource bundle not found in .build"
fi

# 7. Create Info.plist
log "Generating Info.plist..."
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
</dict>
</plist>
EOF

# 8. Fix RPATH in binary
log "Fixing @rpath in binary..."
# Add rpath to look in the bundle's Frameworks folder
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" || true

# 9. Bundle VM Bootstrap Files
log "Bundling VM bootstrap files..."
VM_RESOURCES_DIR="${RESOURCES_DIR}/VM"
mkdir -p "$VM_RESOURCES_DIR"

# Copy VM configuration (bootstrap will download system.img on first launch)
cat > "${VM_RESOURCES_DIR}/vm-config.json" <<EOF
{
  "version": "1.0.0",
  "system_image_url": "https://downloads.bowser.io/vm/system-1.0.0.img",
  "system_image_sha256": "TBD",
  "cpu_count": 2,
  "memory_gb": 2,
  "data_image_gb": 5
}
EOF

log "VM bootstrap configuration created"

success "Standalone App built at: ${PROJECT_DIR}/${APP_BUNDLE}"
log ""
log "Production Mode:"
log "  - Backend will run in Alpine Linux VM (vsock isolation)"
log "  - VM images downloaded on first launch to ~/Library/Application Support/Bowser/"
log "  - LUKS-encrypted storage for user data"
log ""
log "To run the app: open ${APP_BUNDLE}"
