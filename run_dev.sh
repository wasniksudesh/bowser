#!/bin/zsh
# =============================================================================
# Bowser Development Workflow Script
# =============================================================================
#
# This script handles the complete development workflow:
# 1. Checks and installs required build tools (cmake, ninja)
# 2. Downloads CEF binaries if not present (auto-detects Intel/Apple Silicon)
# 3. Builds the CEF wrapper library (libcef_dll_wrapper)
# 4. Sets up Python virtual environment
# 5. Starts the AI sidecar in background
# 6. Builds and runs the Swift application
# 7. Shows all logs in terminal
# 8. Cleans up processes on exit
#
# Usage: ./run_dev.sh
#
# Prerequisites (auto-installed via Homebrew if missing):
# - Xcode Command Line Tools
# - CMake
# - Ninja (optional, for faster builds)
# - Python 3
#
# =============================================================================

set -e  # Exit on error

# Configuration
SIDECAR_PORT=8765
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect architecture and set CEF platform
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    CEF_PLATFORM="macosarm64"
else
    CEF_PLATFORM="macosx64"
fi

# CEF version - URL encoded (+ becomes %2B)
CEF_VERSION_RAW="143.0.13+g30cb3bd+chromium-143.0.7499.170"
CEF_VERSION_ENCODED="143.0.13%2Bg30cb3bd%2Bchromium-143.0.7499.170"
CEF_BUILD_TYPE="minimal"  # Use 'standard' for full debugging symbols

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Command line options
SKIP_SIDECAR=false
CLEAN_BUILD=false
BUILD_ONLY=false

# Log functions
log_info() { echo "${BLUE}[Bowser]${NC} $1"; }
log_success() { echo "${GREEN}[Bowser]${NC} $1"; }
log_warn() { echo "${YELLOW}[Bowser]${NC} $1"; }
log_error() { echo "${RED}[Bowser]${NC} $1"; }
log_step() { echo "${CYAN}[Bowser]${NC} ▶ $1"; }

# =============================================================================
# Help
# =============================================================================

show_help() {
    echo "Bowser Development Script"
    echo ""
    echo "Usage: ./run_dev.sh [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h       Show this help message"
    echo "  --skip-sidecar   Skip starting the AI sidecar"
    echo "  --clean          Clean build (rebuild CEF wrapper and Swift app)"
    echo "  --build-only     Only build, don't run the application"
    echo ""
    echo "This script will:"
    echo "  1. Install required build tools (cmake, ninja) via Homebrew"
    echo "  2. Download CEF binaries if not present"
    echo "  3. Build the CEF wrapper library (libcef_dll_wrapper)"
    echo "  4. Set up Python virtual environment (smart caching - only installs when needed)"
    echo "  5. Start the AI sidecar (unless --skip-sidecar, auto-restarts if files change)"
    echo "  6. Build and run the Swift application"
    echo ""
    echo "Performance Tips:"
    echo "  - Install 'uv' for 10-100x faster Python package installation:"
    echo "    brew install uv"
    echo "  - The script caches Python dependencies and only reinstalls when requirements.txt changes"
    echo "  - Sidecar automatically restarts when Python files are modified"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                ;;
            --skip-sidecar)
                SKIP_SIDECAR=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --build-only)
                BUILD_ONLY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# =============================================================================
# Build Tools Installation
# =============================================================================

check_xcode_tools() {
    log_step "Checking Xcode Command Line Tools..."
    
    if ! xcode-select -p &> /dev/null; then
        log_warn "Xcode Command Line Tools not found. Installing..."
        xcode-select --install
        log_info "Please complete the Xcode Command Line Tools installation and re-run this script."
        exit 1
    fi
    
    log_success "Xcode Command Line Tools found"
}

check_homebrew() {
    if ! command -v brew &> /dev/null; then
        log_warn "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon
        if [[ "$ARCH" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
}

install_build_tools() {
    log_step "Checking build tools..."
    
    # Check for Xcode Command Line Tools first
    check_xcode_tools
    
    local tools_to_install=()
    
    # Check CMake
    if ! command -v cmake &> /dev/null; then
        log_warn "CMake not found"
        tools_to_install+=("cmake")
    else
        log_success "CMake found: $(cmake --version | head -1)"
    fi
    
    # Check Ninja (optional but faster)
    if ! command -v ninja &> /dev/null; then
        log_warn "Ninja not found (optional, will use make)"
        tools_to_install+=("ninja")
    else
        log_success "Ninja found: $(ninja --version)"
    fi
    
    # Check Python3
    if ! command -v python3 &> /dev/null; then
        log_warn "Python3 not found"
        tools_to_install+=("python3")
    else
        log_success "Python3 found: $(python3 --version)"
    fi
    
    # Check for uv (optional, but much faster for Python package management)
    if ! command -v uv &> /dev/null; then
        log_info "uv not found (optional - install with: brew install uv or curl -LsSf https://astral.sh/uv/install.sh | sh)"
        log_info "  uv is 10-100x faster than pip for package installation"
    else
        log_success "uv found: $(uv --version) (will use for faster Python builds)"
    fi
    
    # Install missing tools via Homebrew
    if [[ ${#tools_to_install[@]} -gt 0 ]]; then
        log_info "Installing missing tools: ${tools_to_install[*]}"
        check_homebrew
        
        for tool in "${tools_to_install[@]}"; do
            log_info "Installing $tool..."
            brew install "$tool" || {
                log_error "Failed to install $tool"
                exit 1
            }
        done
        
        log_success "All build tools installed"
    else
        log_success "All build tools already installed"
    fi
}

# =============================================================================
# CEF Download
# =============================================================================

download_cef() {
    local cef_dir="$PROJECT_DIR/Vendor/cef"
    
    # Check if CEF is already present (look for actual content, not just empty dir)
    if [[ -d "$cef_dir/Release" || -d "$cef_dir/include" ]]; then
        log_info "CEF binaries found at $cef_dir"
        return 0
    fi
    
    log_info "CEF binaries not found. Downloading for $ARCH..."
    
    # Clean and create vendor directory
    rm -rf "$cef_dir"
    mkdir -p "$cef_dir"
    
    # CEF download URL (Spotify CDN) - with URL encoded version
    local cef_filename="cef_binary_${CEF_VERSION_ENCODED}_${CEF_PLATFORM}_${CEF_BUILD_TYPE}"
    local cef_url="https://cef-builds.spotifycdn.com/${cef_filename}.tar.bz2"
    local temp_dir=$(mktemp -d)
    local archive_path="$temp_dir/cef.tar.bz2"
    
    log_info "Architecture: $ARCH -> Platform: $CEF_PLATFORM"
    log_info "Downloading from: $cef_url"
    log_warn "This may take a while (CEF is ~100-300MB)..."
    
    # Download with progress
    if command -v curl &> /dev/null; then
        if ! curl -L --progress-bar --fail -o "$archive_path" "$cef_url"; then
            log_error "Download failed! Check your internet connection."
            log_error "URL: $cef_url"
            rm -rf "$temp_dir"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget --show-progress -O "$archive_path" "$cef_url"; then
            log_error "Download failed!"
            rm -rf "$temp_dir"
            exit 1
        fi
    else
        log_error "Neither curl nor wget found. Please install one."
        exit 1
    fi
    
    # Verify download
    if [[ ! -s "$archive_path" ]]; then
        log_error "Downloaded file is empty!"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    log_info "Download complete. Extracting CEF binaries..."
    
    # Extract with error handling
    if ! tar -xjf "$archive_path" -C "$temp_dir" 2>&1; then
        log_error "Extraction failed! The archive may be corrupted."
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Find extracted directory (name includes version with + not %2B)
    local extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "cef_binary_*" | head -1)
    
    if [[ -n "$extracted_dir" && -d "$extracted_dir" ]]; then
        # Move contents to vendor directory
        cp -R "$extracted_dir"/* "$cef_dir/"
        log_success "CEF binaries installed to $cef_dir"
        log_info "Contents: $(ls "$cef_dir" | tr '\n' ' ')"
    else
        log_error "Failed to find extracted CEF directory"
        log_error "Contents of temp dir: $(ls -la "$temp_dir")"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# =============================================================================
# CEF Wrapper Library Build
# =============================================================================

build_cef_wrapper() {
    local cef_dir="$PROJECT_DIR/Vendor/cef"
    local build_dir="$cef_dir/build"
    local wrapper_lib="$build_dir/libcef_dll_wrapper/libcef_dll_wrapper.a"
    
    log_step "Checking CEF wrapper library..."
    
    # Clean build if requested
    if [[ "$CLEAN_BUILD" == "true" && -d "$build_dir" ]]; then
        log_info "Clean build requested - removing CEF build directory..."
        rm -rf "$build_dir"
    fi
    
    # Check if wrapper library already exists
    if [[ -f "$wrapper_lib" ]]; then
        log_success "CEF wrapper library already built"
        return 0
    fi
    
    log_info "Building CEF wrapper library (libcef_dll_wrapper)..."
    log_info "This is required for CEF C++ API integration"
    
    # Create build directory
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # Determine build system (prefer Ninja if available)
    local cmake_generator=""
    local build_cmd=""
    
    if command -v ninja &> /dev/null; then
        cmake_generator="-G Ninja"
        build_cmd="ninja"
        log_info "Using Ninja build system"
    else
        cmake_generator=""
        build_cmd="make -j$(sysctl -n hw.ncpu)"
        log_info "Using Make build system"
    fi
    
    # Configure with CMake
    log_info "Configuring CMake..."
    if ! cmake $cmake_generator \
        -DCMAKE_BUILD_TYPE=Release \
        -DPROJECT_ARCH="$ARCH" \
        .. 2>&1 | while IFS= read -r line; do
            echo "${BLUE}[CMake]${NC} $line"
        done; then
        log_error "CMake configuration failed!"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Build the wrapper library
    log_info "Building libcef_dll_wrapper..."
    if ! $build_cmd libcef_dll_wrapper 2>&1 | while IFS= read -r line; do
        echo "${BLUE}[Build]${NC} $line"
    done; then
        log_error "Build failed!"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    # Verify the library was built
    if [[ -f "$wrapper_lib" ]]; then
        log_success "CEF wrapper library built successfully"
        log_info "Library: $wrapper_lib"
    else
        log_error "Wrapper library not found after build!"
        cd "$PROJECT_DIR"
        return 1
    fi
    
    cd "$PROJECT_DIR"
}

# =============================================================================
# Python Sidecar
# =============================================================================

check_pip_tool() {
    # Check for uv (ultra-fast Python package installer) or use pip
    if command -v uv &> /dev/null; then
        echo "uv"
        return 0
    fi
    echo "pip"
    return 0
}

needs_requirements_install() {
    local venv_dir="$PROJECT_DIR/Sidecar/.venv"
    local requirements_file="$PROJECT_DIR/Sidecar/requirements.txt"
    local lock_file="$venv_dir/.requirements.lock"
    
    # If venv doesn't exist, we need to install
    if [[ ! -d "$venv_dir" ]]; then
        return 0
    fi
    
    # If lock file doesn't exist, we need to install
    if [[ ! -f "$lock_file" ]]; then
        return 0
    fi
    
    # Compare hash of requirements file with lock file
    local current_hash=$(shasum -a 256 "$requirements_file" 2>/dev/null | cut -d' ' -f1)
    local locked_hash=$(cat "$lock_file" 2>/dev/null | cut -d' ' -f1)
    
    if [[ "$current_hash" != "$locked_hash" ]]; then
        return 0
    fi
    
    # Additional check: verify venv is still valid
    if [[ ! -f "$venv_dir/bin/python" ]]; then
        return 0
    fi
    
    return 1
}

setup_python_env() {
    local venv_dir="$PROJECT_DIR/Sidecar/.venv"
    local requirements_file="$PROJECT_DIR/Sidecar/requirements.txt"
    local lock_file="$venv_dir/.requirements.lock"
    
    log_info "Setting up Python environment..."
    
    # Create venv if not exists
    if [[ ! -d "$venv_dir" ]]; then
        log_info "Creating virtual environment..."
        python3 -m venv "$venv_dir"
    fi
    
    # Activate venv
    source "$venv_dir/bin/activate"
    
    # Check if we need to install/update dependencies
    if needs_requirements_install; then
        local pip_tool=$(check_pip_tool)
        
        if [[ "$pip_tool" == "uv" ]]; then
            log_info "Installing Python dependencies with uv (fast)..."
            # uv is much faster than pip
            uv pip install --python "$venv_dir/bin/python" -r "$requirements_file" || {
                log_warn "uv install failed, falling back to pip..."
                pip install --upgrade-strategy only-if-needed -q -r "$requirements_file"
            }
        else
            log_info "Installing Python dependencies with pip..."
            # Use --upgrade-strategy only-if-needed to avoid unnecessary reinstalls
            # Enable pip cache for faster subsequent installs
            pip install --upgrade-strategy only-if-needed --cache-dir "$venv_dir/.pip-cache" -q -r "$requirements_file"
        fi
        
        # Create/update lock file with requirements hash
        if [[ -f "$requirements_file" ]]; then
            shasum -a 256 "$requirements_file" > "$lock_file" 2>/dev/null || \
            echo "$(stat -f %m "$requirements_file" 2>/dev/null || stat -c %Y "$requirements_file" 2>/dev/null)" > "$lock_file"
        fi
        
        log_success "Python dependencies installed"
    else
        log_success "Python dependencies up to date (skipping install)"
    fi
    
    log_success "Python environment ready"
}

needs_sidecar_rebuild() {
    local venv_dir="$PROJECT_DIR/Sidecar/.venv"
    local sidecar_dir="$PROJECT_DIR/Sidecar"
    local rebuild_marker="$venv_dir/.sidecar_rebuild_marker"
    
    # If marker doesn't exist, we need to check
    if [[ ! -f "$rebuild_marker" ]]; then
        return 0
    fi
    
    local last_build_time=$(cat "$rebuild_marker" 2>/dev/null || echo "0")
    
    # Check if any Python file in Sidecar is newer than last build
    local newest_file=$(find "$sidecar_dir" -name "*.py" -type f -newer "$rebuild_marker" 2>/dev/null | head -1)
    
    if [[ -n "$newest_file" ]]; then
        return 0
    fi
    
    # Check if requirements were updated (which might affect the build)
    local requirements_file="$PROJECT_DIR/Sidecar/requirements.txt"
    if [[ "$requirements_file" -nt "$rebuild_marker" ]]; then
        return 0
    fi
    
    return 1
}

mark_sidecar_built() {
    local venv_dir="$PROJECT_DIR/Sidecar/.venv"
    local rebuild_marker="$venv_dir/.sidecar_rebuild_marker"
    touch "$rebuild_marker"
}

stop_existing_sidecar() {
    # Kill any existing sidecar on our port
    local existing_pid=$(lsof -ti:$SIDECAR_PORT 2>/dev/null)
    if [[ -n "$existing_pid" ]]; then
        log_info "Stopping existing sidecar (PID: $existing_pid)..."
        kill "$existing_pid" 2>/dev/null || true
        sleep 1
        # Force kill if still running
        kill -9 "$existing_pid" 2>/dev/null || true
    fi
    
    # Also kill any orphaned uvicorn processes on our port
    pkill -f "uvicorn.*--port $SIDECAR_PORT" 2>/dev/null || true
}

start_sidecar() {
    log_info "Starting AI Sidecar on port $SIDECAR_PORT..."
    
    # Stop any existing sidecar first
    stop_existing_sidecar
    
    # Activate venv
    source "$PROJECT_DIR/Sidecar/.venv/bin/activate"
    
    # Start uvicorn in background, redirecting output for logging
    cd "$PROJECT_DIR/Sidecar"
    
    # Use exec to replace the subshell so we can track the PID
    # --reload enables auto-reload on file changes for development
    uvicorn app.main:app --host 127.0.0.1 --port $SIDECAR_PORT --reload --log-level info 2>&1 | \
        while IFS= read -r line; do
            echo "${GREEN}[Sidecar]${NC} $line"
        done &
    
    SIDECAR_PID=$!
    
    # Mark sidecar as built (since we're starting it)
    mark_sidecar_built
    
    # Wait for sidecar to be ready
    log_info "Waiting for sidecar to start..."
    for i in {1..30}; do
        if curl -s "http://localhost:$SIDECAR_PORT/health" > /dev/null 2>&1; then
            log_success "AI Sidecar is ready!"
            return 0
        fi
        sleep 0.5
    done
    
    log_error "Sidecar failed to start within 15 seconds"
    return 1
}

# =============================================================================
# Swift Application
# =============================================================================

setup_info_plist() {
    local app_bundle="$PROJECT_DIR/Bowser.app"
    local info_plist="$app_bundle/Contents/Info.plist"
    
    # Also check the build directory location just in case
    if [[ ! -d "$app_bundle" ]]; then
       local arch=$(uname -m)
       if [[ "$arch" == "arm64" ]]; then
           app_bundle="$PROJECT_DIR/.build/arm64-apple-macosx/debug/Bowser.app"
       else
           app_bundle="$PROJECT_DIR/.build/x86_64-apple-macosx/debug/Bowser.app"
       fi
       info_plist="$app_bundle/Contents/Info.plist"
    fi

    if [[ -f "$info_plist" ]]; then
        log_info "Updating Info.plist with permissions..."
        plutil -replace NSCameraUsageDescription -string "Bowser needs camera access to enable video calls and conferencing in websites." "$info_plist"
        plutil -replace NSMicrophoneUsageDescription -string "Bowser needs microphone access to enable voice calls and audio recording in websites." "$info_plist"
        log_success "Permissions added to Info.plist"
    else
        log_warn "Info.plist not found at $info_plist - Permissions might be missing!"
    fi
}

setup_cef_framework_link() {
    # The CEF framework has an install name of @executable_path/../Frameworks/Chromium Embedded Framework.framework/...
    # This means it expects to be in a Frameworks folder relative to the executable.
    # We need to create a symlink so the dynamic linker can find it.
    
    local build_dir="$PROJECT_DIR/.build/arm64-apple-macosx/debug"
    local frameworks_dir="$build_dir/../Frameworks"
    local cef_framework="$PROJECT_DIR/Vendor/cef/Release/Chromium Embedded Framework.framework"
    local cef_libraries="$cef_framework/Libraries"
    
    # Also handle x86_64 builds
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]]; then
        build_dir="$PROJECT_DIR/.build/x86_64-apple-macosx/debug"
        frameworks_dir="$build_dir/../Frameworks"
    fi
    
    log_info "Setting up CEF framework link..."
    
    # Create Frameworks directory if it doesn't exist
    mkdir -p "$frameworks_dir"
    
    # Create symlink to CEF framework (remove existing one first)
    local link_path="$frameworks_dir/Chromium Embedded Framework.framework"
    if [[ -L "$link_path" ]]; then
        rm "$link_path"
    fi
    
    ln -sf "$cef_framework" "$link_path"
    log_success "CEF framework linked to $link_path"
    
    # Create symlinks for CEF GPU libraries in the build directory
    # These are needed by CEF's GPU subprocess which looks for them next to the executable
    log_info "Setting up CEF GPU library symlinks..."
    
    for lib in "libGLESv2.dylib" "libEGL.dylib" "libvk_swiftshader.dylib" "vk_swiftshader_icd.json"; do
        local lib_link="$build_dir/$lib"
        if [[ -L "$lib_link" ]]; then
            rm "$lib_link"
        fi
        if [[ -f "$cef_libraries/$lib" ]]; then
            ln -sf "$cef_libraries/$lib" "$lib_link"
        fi
    done
    
    log_success "CEF GPU libraries linked to $build_dir"
}

build_and_run_swift() {
    cd "$PROJECT_DIR"
    
    # Clean build if requested
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        log_info "Clean build requested - removing Swift build directory..."
        rm -rf "$PROJECT_DIR/.build"
    fi
    
    log_info "Building Swift application..."
    
    # Build with release configuration for better performance
    # Use debug for development: swift build
    if swift build 2>&1 | while IFS= read -r line; do
        echo "${BLUE}[Swift Build]${NC} $line"
    done; then
        log_success "Build successful!"
    else
        log_error "Build failed!"
        return 1
    fi
    
    # Setup CEF framework symlink after build (must be done after build creates directories)
    setup_cef_framework_link
    
    # If build-only mode, exit here
    if [[ "$BUILD_ONLY" == "true" ]]; then
        log_success "Build complete (--build-only mode)"
        return 0
    fi
    
    # Copy the built binary to the App Bundle
    log_info "Updating Bowser.app bundle..."
    
    # Determine binary path
    local binary_path=""
    local arch=$(uname -m)
    if [[ "$arch" == "arm64" ]]; then
        binary_path="$PROJECT_DIR/.build/arm64-apple-macosx/debug/Bowser"
    else
        binary_path="$PROJECT_DIR/.build/x86_64-apple-macosx/debug/Bowser"
    fi
    
    # Ensure bundle structure exists
    mkdir -p "$PROJECT_DIR/Bowser.app/Contents/MacOS"
    mkdir -p "$PROJECT_DIR/Bowser.app/Contents/Resources"
    
    # Copy Info.plist from Sources if available
    if [[ -f "$PROJECT_DIR/Sources/Bowser/Info.plist" ]]; then
        cp "$PROJECT_DIR/Sources/Bowser/Info.plist" "$PROJECT_DIR/Bowser.app/Contents/Info.plist"
    fi

    # Copy binary
    cp "$binary_path" "$PROJECT_DIR/Bowser.app/Contents/MacOS/Bowser"

    # Copy Bowser Helper binary
    local helper_src=""
    if [[ "$arch" == "arm64" ]]; then
        helper_src="$PROJECT_DIR/.build/arm64-apple-macosx/debug/Bowser Helper"
    else
        helper_src="$PROJECT_DIR/.build/x86_64-apple-macosx/debug/Bowser Helper"
    fi

    if [[ -f "$helper_src" ]]; then
        log_info "Updating Bowser Helper binary..."
        mkdir -p "$PROJECT_DIR/Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/MacOS"
        cp "$helper_src" "$PROJECT_DIR/Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/MacOS/Bowser Helper"
        
        # Copy Info.plist for Helper if available
        if [[ -f "$PROJECT_DIR/Sources/BowserHelper/Info.plist" ]]; then
            cp "$PROJECT_DIR/Sources/BowserHelper/Info.plist" "$PROJECT_DIR/Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/Info.plist"
        fi
    fi

    # Update Info.plist with permissions (now that it's in the bundle)
    setup_info_plist
    
    # Copy GPU libraries to MacOS folder (required for CEF GPU process)
    log_info "Copying GPU libraries to bundles..."
    for lib in "libGLESv2.dylib" "libEGL.dylib" "libvk_swiftshader.dylib" "vk_swiftshader_icd.json"; do
        local cef_lib="$PROJECT_DIR/Vendor/cef/Release/Chromium Embedded Framework.framework/Libraries/$lib"
        if [[ -f "$cef_lib" ]]; then
            # Main app
            cp "$cef_lib" "$PROJECT_DIR/Bowser.app/Contents/MacOS/"
            # Helper app
            mkdir -p "$PROJECT_DIR/Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/MacOS"
            cp "$cef_lib" "$PROJECT_DIR/Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/MacOS/"
        fi
    done

    # Ensure Resources directory exists
    mkdir -p "$PROJECT_DIR/Bowser.app/Contents/Resources"

    # Copy Resources Bundle (for Bundle.module support)
    local bundle_path=$(find "$PROJECT_DIR/.build" -name "Bowser_Bowser.bundle" -type d | grep "debug" | head -1)
    if [[ -d "$bundle_path" ]]; then
        log_info "Copying resource bundle for dev..."
        # Remove any misplaced bundle in the root that would break codesigning
        rm -rf "$PROJECT_DIR/Bowser.app/Bowser_Bowser.bundle"
        # Copy to the correct location in Contents/Resources
        cp -R "$bundle_path" "$PROJECT_DIR/Bowser.app/Contents/Resources/"
    fi
    
    # Compile Assets.xcassets to Assets.car in Resources (for Bundle.main support)
    log_info "Compiling asset catalog..."
    # Create temp dir for actool output
    local actool_dir=$(mktemp -d)
    /usr/bin/actool "$PROJECT_DIR/Sources/Bowser/Assets.xcassets" \
        --compile "$PROJECT_DIR/Bowser.app/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$actool_dir/assets.plist" > /dev/null
    rm -rf "$actool_dir"
    
    # Ad-hoc sign the app bundle to ensure permissions work
    log_info "Signing application bundle..."
    codesign --force --deep --sign - "$PROJECT_DIR/Bowser.app"
    
    log_success "App bundle updated and signed"
    
    log_info "Starting Bowser application..."
    log_info "Application logs will appear below. Press Ctrl+C to exit."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Run the app from the bundle to ensure Info.plist is picked up
    "$PROJECT_DIR/Bowser.app/Contents/MacOS/Bowser" 2>&1 | while IFS= read -r line; do
        echo "${YELLOW}[Bowser]${NC} $line"
    done
    
    SWIFT_EXIT_CODE=$?
    return $SWIFT_EXIT_CODE
}

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
    echo ""
    log_info "Shutting down Bowser..."
    
    # Kill sidecar if running
    if [[ -n "$SIDECAR_PID" ]]; then
        log_info "Stopping AI Sidecar (PID: $SIDECAR_PID)..."
        kill $SIDECAR_PID 2>/dev/null || true
        wait $SIDECAR_PID 2>/dev/null || true
    fi
    
    # Stop any existing sidecar processes
    stop_existing_sidecar
    
    # Kill any orphaned Bowser processes
    pkill -f "Bowser" 2>/dev/null || true

    # Clean up session data (only if it exists)
    # defaults delete com.bowser.bowser 2>/dev/null || true
    rm -rf ~/Library/Application\ Support/Bowser/FaviconCache 2>/dev/null || true
    rm -rf ~/Library/Caches/Bowser/CEF 2>/dev/null || true
    
    log_success "Cleanup complete. Goodbye!"
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse command line arguments
    parse_args "$@"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🌐 Bowser Development Environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "Architecture: $ARCH"
    log_info "Project: $PROJECT_DIR"
    [[ "$CLEAN_BUILD" == "true" ]] && log_info "Mode: Clean build"
    [[ "$BUILD_ONLY" == "true" ]] && log_info "Mode: Build only"
    [[ "$SKIP_SIDECAR" == "true" ]] && log_info "Mode: Skip sidecar"
    echo ""
    
    # Step 1: Check and install build tools
    log_step "Step 1/6: Checking build tools..."
    install_build_tools
    echo ""
    
    # Step 2: Download CEF if needed
    log_step "Step 2/6: Setting up CEF binaries..."
    download_cef
    echo ""
    
    # Step 3: Build CEF wrapper library
    log_step "Step 3/6: Building CEF wrapper library..."
    build_cef_wrapper || exit 1
    echo ""
    
    # Step 4: Setup Python environment (skip if not using sidecar and build-only)
    if [[ "$SKIP_SIDECAR" == "false" || "$BUILD_ONLY" == "false" ]]; then
        log_step "Step 4/6: Setting up Python environment..."
        setup_python_env
        echo ""
        
        # Check if sidecar needs rebuild (only if we're going to start it)
        if [[ "$SKIP_SIDECAR" == "false" && "$BUILD_ONLY" == "false" ]]; then
            if needs_sidecar_rebuild; then
                log_info "Sidecar Python files changed - will restart sidecar..."
            else
                log_info "Sidecar is up to date"
            fi
        fi
    else
        log_step "Step 4/6: Skipping Python environment setup..."
        echo ""
    fi
    
    # Step 5: Start sidecar (skip if requested or build-only)
    if [[ "$SKIP_SIDECAR" == "false" && "$BUILD_ONLY" == "false" ]]; then
        log_step "Step 5/6: Starting AI Sidecar..."
        start_sidecar || log_warn "Sidecar failed to start, continuing anyway..."
        echo ""
    else
        log_step "Step 5/6: Skipping AI Sidecar..."
        echo ""
    fi
    
    # Step 6: Build and run Swift app
    log_step "Step 6/6: Building and running Bowser..."
    build_and_run_swift
}

main "$@"
