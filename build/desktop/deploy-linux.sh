#!/bin/bash
# build/desktop/deploy-linux.sh
# Builds and deploys Pixel Raiders Linux version to target via SSH
#
# Usage: 
#   ./build/desktop/deploy-linux.sh       # Deploy with dev API (default)
#   ./build/desktop/deploy-linux.sh --prod # Deploy with production API

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

# --- Linux Target Configuration (from .env) ---
TARGET_HOST="${LINUX_TARGET_HOST:-imac.local}"
TARGET_USER="${LINUX_TARGET_USER:-$USER}"
DEPLOY_PATH="${LINUX_DEPLOY_PATH:-~/Desktop/${GAME_NAME}-linux}"



cd "$PROJECT_ROOT"

# Pass flag to build script (--prod or default to dev)
BUILD_FLAG="${1}"
if [ "$BUILD_FLAG" = "--prod" ]; then
    echo "=== Building $GAME_NAME for Linux (PRODUCTION API) ==="
    "$SCRIPT_DIR/build.sh" --prod linux
else
    echo "=== Building $GAME_NAME for Linux (DEV API) ==="
    "$SCRIPT_DIR/build.sh" linux
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
    echo "  1. The target machine is on and reachable"
    echo "  2. SSH is enabled on the target"
    echo "  3. You have SSH access (try: ssh $TARGET_USER@$TARGET_HOST)"
    exit 1
fi
echo "Connected!"

# Expand the deploy path on the remote machine (handles ~ properly)
REMOTE_DEPLOY_PATH=$(ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" "echo $DEPLOY_PATH")
echo "Remote deploy path: $REMOTE_DEPLOY_PATH"

# Clean old deployment
echo "Cleaning old deployment..."
ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" \
    "rm -rf '$REMOTE_DEPLOY_PATH'" 2>/dev/null

# Create deployment directory
echo "Creating deployment directory..."
ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" \
    "mkdir -p '$REMOTE_DEPLOY_PATH'"

# Upload files
echo "Uploading files..."
scp -r "$DIST_DIR/${GAME_NAME}-linux/"* "$TARGET_USER@$TARGET_HOST:$REMOTE_DEPLOY_PATH/"

if [ $? -eq 0 ]; then
    # Make launcher executable
    ssh -o StrictHostKeyChecking=no "$TARGET_USER@$TARGET_HOST" \
        "chmod +x '$REMOTE_DEPLOY_PATH/${GAME_NAME}.sh' '$REMOTE_DEPLOY_PATH'/*.AppImage 2>/dev/null || true"

    
    echo ""
    echo "=== DEPLOYMENT COMPLETE ==="
    echo ""
    echo "Game deployed to: $REMOTE_DEPLOY_PATH"
    echo ""
    echo "To run on $TARGET_HOST:"
    echo "  cd $REMOTE_DEPLOY_PATH"
    echo "  ./${GAME_NAME}.sh"
    echo ""
    echo "Or double-click ${GAME_NAME}.sh from the desktop"
else
    echo ""
    echo "=== DEPLOYMENT FAILED ==="
    exit 1
fi
