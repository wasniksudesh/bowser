#!/bin/sh
# unlock-storage.sh
# Unlocks the LUKS-encrypted mem0.img partition and mounts it

set -e

DEVICE="/dev/vdb"  # Second virtio block device (mem0.img)
MAPPER_NAME="mem0"
MOUNT_POINT="/mem0"
LUKS_KEY_FILE="/tmp/luks-key"

log() {
    echo "[unlock-storage] $1"
}

error() {
    echo "[unlock-storage] ERROR: $1" >&2
    exit 1
}

# Check if device exists
if [ ! -b "$DEVICE" ]; then
    error "Device $DEVICE not found"
fi

# Check if LUKS key is available
if [ ! -f "$LUKS_KEY_FILE" ]; then
    error "LUKS key not found at $LUKS_KEY_FILE"
fi

log "Checking if $DEVICE is a LUKS device..."

# Check if already a LUKS device
if cryptsetup isLuks "$DEVICE"; then
    log "Device is already LUKS-encrypted"
else
    log "Device is not LUKS-encrypted, formatting..."
    
    # Format as LUKS2
    cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha256 \
        --pbkdf argon2id \
        --batch-mode \
        "$DEVICE" "$LUKS_KEY_FILE"
    
    log "LUKS formatting complete"
fi

# Open LUKS device
log "Opening LUKS device..."
cryptsetup luksOpen "$DEVICE" "$MAPPER_NAME" --key-file "$LUKS_KEY_FILE"

# Check if filesystem exists
if ! blkid "/dev/mapper/$MAPPER_NAME" | grep -q "TYPE=\"ext4\""; then
    log "Creating ext4 filesystem..."
    mkfs.ext4 -L "Bowser-Data" "/dev/mapper/$MAPPER_NAME"
fi

# Create mount point if needed
mkdir -p "$MOUNT_POINT"

# Mount with noexec for security
log "Mounting to $MOUNT_POINT..."
mount -o rw,noexec,nosuid,nodev "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"

# Set permissions
chmod 755 "$MOUNT_POINT"

# Create required directories
mkdir -p "$MOUNT_POINT/qdrant"
mkdir -p "$MOUNT_POINT/data"

log "Storage unlocked and mounted successfully"

# Clean up key file (security)
rm -f "$LUKS_KEY_FILE"

exit 0
