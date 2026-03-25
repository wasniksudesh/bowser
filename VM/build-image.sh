#!/bin/bash
# =============================================================================
# Alpine Linux VM Image Builder for Bowser Backend
# =============================================================================
#
# This script builds a minimal Alpine Linux image with:
# - Python 3.12 runtime
# - FastAPI backend with frozen dependencies (via uv)
# - vsock HTTP server support
# - LUKS utilities for encrypted storage
# - Init system for proper startup
#
# Output: system.img  (~500MB)
#         vmlinuz     (kernel binary for VZLinuxBootLoader)
#         initramfs   (initial ramdisk for VZLinuxBootLoader)
# =============================================================================

set -e

# Detect host architecture and set matching Alpine arch for native VM execution
if [[ "$(uname -m)" == "arm64" ]]; then
    ALPINE_ARCH="aarch64"
    DOCKER_PLATFORM="linux/arm64"
else
    ALPINE_ARCH="x86_64"
    DOCKER_PLATFORM="linux/amd64"
fi

# Configuration
ALPINE_VERSION="3.19"
IMAGE_SIZE="1G"
OUTPUT_IMAGE="system.img"
OUTPUT_KERNEL="vmlinuz"
OUTPUT_INITRAMFS="initramfs"
MOUNT_POINT="alpine-root"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[Build]${NC} $1"; }
success() { echo -e "${GREEN}[Build]${NC} $1"; }
warn() { echo -e "${YELLOW}[Build]${NC} $1"; }
error() { echo -e "${RED}[Build]${NC} $1"; exit 1; }

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check for required tools
    for cmd in docker qemu-img; do
        if ! command -v $cmd &> /dev/null; then
            error "$cmd not found. Please install: brew install $cmd"
        fi
    done
    
    success "Prerequisites OK"
}

# =============================================================================
# Create Base Alpine Image
# =============================================================================

create_base_image() {
    log "Creating base Alpine Linux image ($ALPINE_ARCH)..."
    
    # Remove old image if exists
    rm -f "$OUTPUT_IMAGE"
    
    # Create empty disk image
    qemu-img create -f raw "$OUTPUT_IMAGE" "$IMAGE_SIZE"
    
    success "Created $IMAGE_SIZE disk image"
}

# =============================================================================
# Build Alpine Root Filesystem using Docker
# =============================================================================

build_alpine_rootfs() {
    log "Building Alpine Linux root filesystem (platform: $DOCKER_PLATFORM)..."
    
    # Create temporary Dockerfile
    cat > Dockerfile.alpine-build <<EOF
FROM --platform=${DOCKER_PLATFORM} alpine:${ALPINE_VERSION}

# Install base system + Python + dependencies + kernel for VZLinuxBootLoader
RUN apk add --no-cache \\
    alpine-base \\
    openrc \\
    python3 \\
    py3-pip \\
    cryptsetup \\
    util-linux \\
    e2fsprogs \\
    curl \\
    ca-certificates \\
    tzdata \\
    linux-virt \\
    mkinitfs \\
    gcc \\
    g++ \\
    musl-dev \\
    linux-headers \\
    python3-dev \\
    cmake \\
    make \\
    ninja \\
    patchelf \\
    libffi-dev \\
    openssl-dev

# Install uv for fast Python package management (pip for musl/Alpine compatibility)
RUN pip3 install --break-system-packages uv

# Create app directory
RUN mkdir -p /app /mem0 /data

# Copy backend code
COPY Sidecar /app/

# Install Python dependencies with uv (frozen)
WORKDIR /app
RUN uv venv --clear /app/.venv && \\
    . /app/.venv/bin/activate && \\
    uv pip install -r requirements-vm.txt

# Copy real init and start-backend scripts from repo
COPY VM/alpine/init /init
COPY VM/alpine/start-backend.sh /start-backend.sh
COPY VM/alpine/unlock-storage.sh /unlock-storage.sh
RUN chmod +x /init /start-backend.sh /unlock-storage.sh

# Generate initramfs with vsock module support (use the installed Alpine virt kernel)
RUN KVER=\$(ls /lib/modules/ | head -1) && mkinitfs -o /boot/initramfs "\$KVER"

# Clean up to reduce image size
RUN rm -rf /var/cache/apk/* \\
    /tmp/* \\
    /root/.cache

EOF

    # Build Docker image with correct platform
    log "Building Alpine container (platform: $DOCKER_PLATFORM)..."
    docker build \
        --platform "$DOCKER_PLATFORM" \
        -f Dockerfile.alpine-build \
        -t "bowser-alpine:latest" \
        "$PROJECT_ROOT"
    
    # Export filesystem
    log "Exporting filesystem..."
    CONTAINER_ID=$(docker create --platform "$DOCKER_PLATFORM" bowser-alpine:latest)
    docker export "$CONTAINER_ID" > alpine-rootfs.tar
    docker rm "$CONTAINER_ID"
    
    # Clean up
    rm -f Dockerfile.alpine-build
    
    success "Alpine rootfs built"
}

# =============================================================================
# Extract Kernel and Initramfs for VZLinuxBootLoader
# =============================================================================

extract_boot_files() {
    log "Extracting kernel and initramfs for VZLinuxBootLoader..."

    # Use docker cp to avoid macOS BSD tar wildcard/symlink issues
    TMP_CONTAINER=$(docker create --platform "$DOCKER_PLATFORM" bowser-alpine:latest)
    rm -rf ./boot-extract
    docker cp "$TMP_CONTAINER:/boot/." ./boot-extract/
    docker rm "$TMP_CONTAINER"

    # Find the real kernel file (resolve symlinks, prefer non-symlink)
    KERNEL_FILE=$(find ./boot-extract -name "vmlinuz*" ! -type l | head -1)
    [ -n "$KERNEL_FILE" ] || KERNEL_FILE=$(find ./boot-extract -name "vmlinuz*" | head -1)
    [ -n "$KERNEL_FILE" ] || error "Could not find kernel in Alpine image. Check that linux-virt is installed."
    cp "$KERNEL_FILE" "$OUTPUT_KERNEL"

    # Find initramfs (the one we generated with mkinitfs)
    INITRAMFS_FILE=$(find ./boot-extract -name "initramfs" | head -1)
    [ -n "$INITRAMFS_FILE" ] || INITRAMFS_FILE=$(find ./boot-extract -name "initramfs*" | head -1)
    [ -n "$INITRAMFS_FILE" ] || error "Could not find initramfs in Alpine image."
    cp "$INITRAMFS_FILE" "$OUTPUT_INITRAMFS"

    rm -rf ./boot-extract

    [[ -s "$OUTPUT_KERNEL" ]]    || error "Extracted kernel is empty. Build failed."
    [[ -s "$OUTPUT_INITRAMFS" ]] || error "Extracted initramfs is empty. Build failed."

    success "Kernel extracted:    $(du -h "$OUTPUT_KERNEL" | cut -f1)"
    success "Initramfs extracted: $(du -h "$OUTPUT_INITRAMFS" | cut -f1)"
}

# =============================================================================
# Format and Install to Disk Image
# =============================================================================

install_to_image() {
    log "Installing Alpine to disk image..."
    
    # Create loop device (macOS doesn't have losetup, use hdiutil)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # On macOS, use Docker to format and populate the image
        log "Formatting image with ext4..."
        
        docker run --rm \
            --platform "$DOCKER_PLATFORM" \
            -v "$PWD:/work" \
            -w /work \
            "alpine:${ALPINE_VERSION}" sh -c "
            apk add --no-cache e2fsprogs
            mkfs.ext4 -L Bowser-System /work/$OUTPUT_IMAGE
        "
        
        # Mount using Docker and extract rootfs
        log "Extracting rootfs to image..."
        docker run --rm \
            --platform "$DOCKER_PLATFORM" \
            --privileged \
            -v "$PWD:/work" \
            -w /work \
            "alpine:${ALPINE_VERSION}" sh -c "
            apk add --no-cache e2fsprogs
            mkdir -p /mnt/root
            mount -o loop /work/$OUTPUT_IMAGE /mnt/root
            tar -xf /work/alpine-rootfs.tar -C /mnt/root
            umount /mnt/root
        "
        
    else
        # On Linux
        log "Formatting image with ext4..."
        mkfs.ext4 -L Bowser-System "$OUTPUT_IMAGE"
        
        # Mount and extract
        mkdir -p "$MOUNT_POINT"
        sudo mount -o loop "$OUTPUT_IMAGE" "$MOUNT_POINT"
        sudo tar -xf alpine-rootfs.tar -C "$MOUNT_POINT"
        sudo umount "$MOUNT_POINT"
        rmdir "$MOUNT_POINT"
    fi
    
    # Clean up tarball
    rm -f alpine-rootfs.tar
    
    success "Alpine installed to $OUTPUT_IMAGE"
}

# =============================================================================
# Create requirements-vm.txt (without playwright)
# =============================================================================

create_vm_requirements() {
    log "Creating requirements-vm.txt (removing playwright)..."
    
    grep -v "playwright" "$PROJECT_ROOT/Sidecar/requirements.txt" > "$PROJECT_ROOT/Sidecar/requirements-vm.txt"
    
    # Add vsock-specific dependencies
    cat >> "$PROJECT_ROOT/Sidecar/requirements-vm.txt" <<EOF

# VM-specific dependencies
hypercorn>=0.16.0
EOF
    
    success "Created requirements-vm.txt"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Bowser Alpine Linux VM Image Builder"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log "Host arch: $(uname -m) -> Alpine arch: $ALPINE_ARCH (platform: $DOCKER_PLATFORM)"
    echo ""
    
    check_prerequisites
    create_vm_requirements
    create_base_image
    build_alpine_rootfs
    extract_boot_files
    install_to_image
    
    echo ""
    success "VM image built successfully: $OUTPUT_IMAGE"
    
    # Show output sizes
    log "Output files:"
    log "  system.img:  $(du -h "$OUTPUT_IMAGE" | cut -f1)"
    log "  vmlinuz:     $(du -h "$OUTPUT_KERNEL" | cut -f1)"
    log "  initramfs:   $(du -h "$OUTPUT_INITRAMFS" | cut -f1)"
    log ""
    log "Next steps:"
    log "  1. Copy system.img, vmlinuz, initramfs to CDN or bundle path"
    log "  2. Update VMBootstrap.swift with correct version"
    log "  3. Test with: swift run Bowser"
}

main "$@"
