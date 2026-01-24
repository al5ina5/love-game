#!/bin/bash
# build/portmaster/deploy.sh
# Builds and deploys Pixel Raiders to PortMaster devices via SSH
#
# Usage: 
#   ./build/portmaster/deploy.sh       # Deploy with dev API (default)
#   ./build/portmaster/deploy.sh --prod # Deploy with production API

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GAME_NAME="PIXELRAIDERS"
DIST_DIR="$PROJECT_ROOT/dist/portmaster"

# Source .env for deployment configuration
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# --- PortMaster Configuration (from .env) ---
SPRUCE_IP="${PORTMASTER_TARGET_HOST:-10.0.0.94}"
SPRUCE_USER="${PORTMASTER_TARGET_USER:-spruce}"
SPRUCE_PASS="${PORTMASTER_TARGET_PASS:-happygaming}"
SPRUCE_PATH="${PORTMASTER_DEPLOY_PATH:-/mnt/sdcard/Roms/PORTS}"


cd "$PROJECT_ROOT"

# Pass flag to build script (--prod or default to dev)
BUILD_FLAG="${1:---dev}"
if [ "$BUILD_FLAG" = "--prod" ]; then
    echo "=== Building $GAME_NAME (PRODUCTION API) ==="
else
    echo "=== Building $GAME_NAME (DEV API) ==="
    BUILD_FLAG=""  # build.sh uses dev by default
fi

"$SCRIPT_DIR/build.sh" "$BUILD_FLAG"

echo ""
echo "=== Deploying to SpruceOS ($SPRUCE_IP) ==="

# Test SSH connection first
echo "Testing connection..."
if ! sshpass -p "$SPRUCE_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SPRUCE_USER@$SPRUCE_IP" "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot connect to $SPRUCE_IP"
    echo "Make sure device is on and SSH is enabled"
    exit 1
fi
echo "Connected!"

# Clean old files first
echo "Cleaning old files..."
sshpass -p "$SPRUCE_PASS" ssh -o StrictHostKeyChecking=no "$SPRUCE_USER@$SPRUCE_IP" \
    "rm -rf '$SPRUCE_PATH/$GAME_NAME' '$SPRUCE_PATH/$GAME_NAME.sh' '$SPRUCE_PATH/${GAME_NAME}Updater.sh'" 2>/dev/null

# Upload new files
echo "Uploading files..."
sshpass -p "$SPRUCE_PASS" scp -r "$DIST_DIR/$GAME_NAME.sh" "$DIST_DIR/${GAME_NAME}Updater.sh" "$DIST_DIR/$GAME_NAME" "$SPRUCE_USER@$SPRUCE_IP:$SPRUCE_PATH/"

if [ $? -eq 0 ]; then
    echo ""
    echo "=== DEPLOYMENT COMPLETE ==="
else
    echo ""
    echo "=== DEPLOYMENT FAILED ==="
    exit 1
fi
