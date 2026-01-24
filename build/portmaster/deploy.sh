#!/bin/bash
# build/portmaster/deploy.sh
# Builds and deploys Pixel Raiders to PortMaster devices via SSH
#
# Usage: ./build/portmaster/deploy.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GAME_NAME="PIXELRAIDERS"
DIST_DIR="$PROJECT_ROOT/dist/portmaster"

# --- SpruceOS Configuration ---
SPRUCE_IP="10.0.0.94"
SPRUCE_USER="spruce"
SPRUCE_PASS="happygaming"
SPRUCE_PATH="/mnt/sdcard/Roms/PORTS"

cd "$PROJECT_ROOT"

echo "=== Building $GAME_NAME ==="
"$SCRIPT_DIR/build.sh" "$1"

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
