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
# Output: system.img (~500MB)
# =============================================================================

set -e

# Configuration
ALPINE_VERSION="3.19"
ALPINE_ARCH="x86_64"
IMAGE_SIZE="1G"
OUTPUT_IMAGE="system.img"
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
    log "Creating base Alpine Linux image..."
    
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
    log "Building Alpine Linux root filesystem..."
    
    # Create temporary Dockerfile
    cat > Dockerfile.alpine-build <<'EOF'
FROM alpine:3.19

# Install base system + Python + dependencies
RUN apk add --no-cache \
    alpine-base \
    openrc \
    python3 \
    py3-pip \
    cryptsetup \
    util-linux \
    e2fsprogs \
    curl \
    ca-certificates \
    tzdata

# Install uv for fast Python package management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:$PATH"

# Create app directory
RUN mkdir -p /app /mem0 /data

# Copy backend code
COPY Sidecar /app/

# Install Python dependencies with uv (frozen)
WORKDIR /app
RUN uv venv /app/.venv && \
    . /app/.venv/bin/activate && \
    uv pip install -r requirements-vm.txt

# Create init script
RUN cat > /init <<'INIT_SCRIPT'
#!/bin/sh
# Bowser VM Init Script

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mount -t tmpfs -o mode=0755 tmpfs /run
mount -t tmpfs -o mode=1777 tmpfs /tmp

# Setup networking (vsock only)
ip link set lo up

# Wait for vsock to receive LUKS key and unlock /mem0
echo "Waiting for LUKS key via vsock..."
# This will be handled by start-backend.sh

# Start backend
exec /start-backend.sh
INIT_SCRIPT

RUN chmod +x /init

# Create backend startup script
RUN cat > /start-backend.sh <<'START_SCRIPT'
#!/bin/sh
# Start Bowser FastAPI backend on vsock

cd /app

# Activate venv
. .venv/bin/activate

# Set environment
export PYTHONUNBUFFERED=1
export LOG_FORMAT=json

# Start FastAPI with vsock listener
echo "Starting FastAPI backend on vsock..."
exec python3 -m app.main --vsock --port 8765
START_SCRIPT

RUN chmod +x /start-backend.sh

# Clean up to reduce image size
RUN rm -rf /var/cache/apk/* \
    /tmp/* \
    /root/.cache

EOF

    # Build Docker image
    log "Building Alpine container..."
    docker build -f Dockerfile.alpine-build -t bowser-alpine:latest "$PROJECT_ROOT"
    
    # Export filesystem
    log "Exporting filesystem..."
    CONTAINER_ID=$(docker create bowser-alpine:latest)
    docker export "$CONTAINER_ID" > alpine-rootfs.tar
    docker rm "$CONTAINER_ID"
    
    # Clean up
    rm -f Dockerfile.alpine-build
    
    success "Alpine rootfs built"
}

# =============================================================================
# Format and Install to Disk Image
# =============================================================================

install_to_image() {
    log "Installing Alpine to disk image..."
    
    # Create loop device (macOS doesn't have losetup, use hdiutil)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # On macOS, we'll use a different approach
        log "Formatting image with ext4..."
        
        # Use Docker to format and copy
        docker run --rm -v "$PWD:/work" -w /work alpine:3.19 sh -c "
            apk add --no-cache e2fsprogs
            mkfs.ext4 -L Bowser-System /work/$OUTPUT_IMAGE
        "
        
        # Mount using Docker and extract rootfs
        log "Extracting rootfs to image..."
        docker run --rm \
            --privileged \
            -v "$PWD:/work" \
            -w /work \
            alpine:3.19 sh -c "
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
    echo "  🏔️  Bowser Alpine Linux VM Image Builder"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    check_prerequisites
    create_vm_requirements
    create_base_image
    build_alpine_rootfs
    install_to_image
    
    echo ""
    success "✅ VM image built successfully: $OUTPUT_IMAGE"
    
    # Show image size
    SIZE=$(du -h "$OUTPUT_IMAGE" | cut -f1)
    log "Image size: $SIZE"
    log ""
    log "Next steps:"
    log "  1. Upload $OUTPUT_IMAGE to CDN"
    log "  2. Update VMBootstrap.swift with correct version"
    log "  3. Test with: swift run Bowser"
}

main "$@"
