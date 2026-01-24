#!/bin/bash
# build/desktop/deploy-windows.sh
# Builds and deploys Pixel Raiders Windows version to target via SSH
#
# Usage: 
#   ./build/desktop/deploy-windows.sh       # Deploy with dev API (default)
#   ./build/desktop/deploy-windows.sh --prod # Deploy with production API

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GAME_NAME="PIXELRAIDERS"
DIST_DIR="$PROJECT_ROOT/dist/desktop"

# Source .env for deployment configuration
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# --- Windows Target Configuration (from .env) ---
TARGET_HOST="${WINDOWS_TARGET_HOST:-192.168.1.100}"
TARGET_USER="${WINDOWS_TARGET_USER:-YourUsername}"
DEPLOY_PATH="${WINDOWS_DEPLOY_PATH:-C:/Users/YourUsername/Desktop/${GAME_NAME}-win64}"


cd "$PROJECT_ROOT"

# Pass flag to build script (--prod or default to dev)
BUILD_FLAG="${1}"
if [ "$BUILD_FLAG" = "--prod" ]; then
    echo "=== Building $GAME_NAME for Windows (PRODUCTION API) ==="
    "$SCRIPT_DIR/build.sh" --prod windows
else
    echo "=== Building $GAME_NAME for Windows (DEV API) ==="
    "$SCRIPT_DIR/build.sh" windows
fi

if [ $? -ne 0 ]; then
    echo ""
    echo "=== BUILD FAILED ==="
    exit 1
fi

echo ""
echo "=== Deploying to $TARGET_HOST ===" 

# Test SSH connection first
echo "Testing connection to $TARGET_HOST..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot connect to $TARGET_HOST"
    echo "Make sure:"
    echo "  1. The target Windows machine is on and reachable"
    echo "  2. OpenSSH Server is installed and running on Windows"
    echo "  3. You have SSH access (try: ssh $TARGET_USER@$TARGET_HOST)"
    echo ""
    echo "To set up SSH on Windows, see DEPLOY.md"
    exit 1
fi
echo "Connected!"

# Clean old deployment
echo "Cleaning old deployment..."
ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" \
    "if exist \"$DEPLOY_PATH\" rmdir /s /q \"$DEPLOY_PATH\"" 2>/dev/null

# Create deployment directory
echo "Creating deployment directory..."
ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" \
    "mkdir \"$DEPLOY_PATH\""

# Upload files using scp with Windows path
echo "Uploading files..."
scp -r "$DIST_DIR/${GAME_NAME}-win64/"* "$TARGET_USER@$TARGET_HOST:$(echo $DEPLOY_PATH | sed 's|C:|/c|' | sed 's|\\|/|g')/"

if [ $? -eq 0 ]; then
    echo ""
    echo "=== DEPLOYMENT COMPLETE ==="
    echo ""
    echo "Game deployed to: $DEPLOY_PATH"
    echo ""
    echo "To run on $TARGET_HOST:"
    echo "  1. Navigate to $DEPLOY_PATH"
    echo "  2. Double-click ${GAME_NAME}.exe"
else
    echo ""
    echo "=== DEPLOYMENT FAILED ==="
    exit 1
fi
