#!/bin/sh
# start-backend.sh
# Startup script for Bowser FastAPI backend in VM

set -e

log() {
    echo "[start-backend] $1"
}

error() {
    echo "[start-backend] ERROR: $1" >&2
    exit 1
}

# Wait for vsock device
log "Waiting for vsock device..."
for i in $(seq 1 30); do
    if [ -c /dev/vsock ]; then
        log "vsock device ready"
        break
    fi
    sleep 0.5
done

if [ ! -c /dev/vsock ]; then
    error "vsock device not available"
fi

# Create vsock listener to receive LUKS key
log "Listening for LUKS key on vsock port 9000..."

# Simple vsock receiver using socat (if available) or nc
# For now, we'll expect the key to be written to /tmp/luks-key by init
# In production, this would be a proper vsock listener

# Wait for key file (set by vsock listener in init)
for i in $(seq 1 60); do
    if [ -f /tmp/luks-key ]; then
        log "LUKS key received"
        break
    fi
    sleep 1
done

if [ ! -f /tmp/luks-key ]; then
    error "LUKS key not received within timeout"
fi

# Unlock storage
log "Unlocking encrypted storage..."
/unlock-storage.sh || error "Failed to unlock storage"

# Change to app directory
cd /app || error "App directory not found"

# Activate Python venv
log "Activating Python virtual environment..."
. .venv/bin/activate || error "Failed to activate venv"

# Set environment variables
export PYTHONUNBUFFERED=1
export LOG_FORMAT=json
export VECTOR_STORE_PATH=/mem0/qdrant

# Wait for API keys via vsock
log "Waiting for API keys on vsock port 9001..."
# In production, receive API keys and export them
# For now, they would be set by the environment

# Start FastAPI backend
log "Starting FastAPI backend on vsock port 8765..."
exec python3 -m app.main --vsock --port 8765
