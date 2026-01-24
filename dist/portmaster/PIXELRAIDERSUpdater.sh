#!/bin/bash
# PIXELRAIDERSUpdater.sh - Updates Pixel Raiders from GitHub
# Place this next to PIXELRAIDERS.sh in your ports folder
#
# Usage: Run from PortMaster menu or: ./PIXELRAIDERSUpdater.sh

REPO="al5ina5/pixel-raiders"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="$SCRIPT_DIR/PIXELRAIDERS"

echo "=== Pixel Raiders Updater ==="
echo "Game directory: $GAME_DIR"
echo ""

# Check game folder exists
if [ ! -d "$GAME_DIR" ]; then
    echo "ERROR: PIXELRAIDERS folder not found at $GAME_DIR"
    echo "Make sure PIXELRAIDERSUpdater.sh is in the same folder as PIXELRAIDERS/"
    exit 1
fi

# Check for curl or wget
if command -v curl &> /dev/null; then
    DOWNLOADER="curl"
elif command -v wget &> /dev/null; then
    DOWNLOADER="wget"
else
    echo "ERROR: Neither curl nor wget found!"
    exit 1
fi

echo "Using  for downloads..."
echo ""

# Download function
download_file() {
    local url="--prod"
    local dest=""
    
    echo "Downloading: "
    
    if [ "" = "curl" ]; then
        curl -L -s -o "" ""
    else
        wget -q -O "" ""
    fi
    
    if [ 0 -eq 0 ] && [ -f "" ] && [ -s "" ]; then
        echo "  OK"
        return 0
    else
        echo "  FAILED"
        return 1
    fi
}

# Base URL for raw files
BASE_URL="https://raw.githubusercontent.com///dist/portmaster"

echo "Downloading updates..."
echo ""

# Backup current .love file
if [ -f "$GAME_DIR/PIXELRAIDERS.love" ]; then
    cp "$GAME_DIR/PIXELRAIDERS.love" "$GAME_DIR/PIXELRAIDERS.love.backup"
    echo "Backed up current PIXELRAIDERS.love"
fi

# Download new files
download_file "$BASE_URL/PIXELRAIDERS/PIXELRAIDERS.love" "$GAME_DIR/PIXELRAIDERS.love"
LOVE_OK=$?

download_file "$BASE_URL/PIXELRAIDERS/PIXELRAIDERS.gptk" "$GAME_DIR/PIXELRAIDERS.gptk"
GPTK_OK=$?

download_file "$BASE_URL/PIXELRAIDERS/port.json" "$GAME_DIR/port.json"
JSON_OK=$?

echo ""

if [ $LOVE_OK -eq 0 ]; then
    # Remove backup on success
    rm -f "$GAME_DIR/PIXELRAIDERS.love.backup"
    echo "=== Update complete! ==="
    echo "Restart the game to use the new version."
else
    # Restore backup on failure
    if [ -f "$GAME_DIR/PIXELRAIDERS.love.backup" ]; then
        mv "$GAME_DIR/PIXELRAIDERS.love.backup" "$GAME_DIR/PIXELRAIDERS.love"
        echo "Update failed - restored previous version."
    fi
    echo "=== Update FAILED ==="
    exit 1
fi
