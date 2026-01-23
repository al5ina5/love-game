#!/bin/bash
# Pixel Raiders Linux Launcher
# This script tries multiple methods to run the game

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOVE_FILE="$SCRIPT_DIR/PIXELRAIDERS.love"

# Method 1: Try system-installed LÖVE
if command -v love &> /dev/null; then
    exec love "$LOVE_FILE"
fi

# Method 2: Try flatpak
if command -v flatpak &> /dev/null; then
    if flatpak list | grep -q "org.love2d.Love2D"; then
        exec flatpak run org.love2d.Love2D "$LOVE_FILE"
    fi
fi

# Method 3: Try AppImage in same directory
if [ -f "$SCRIPT_DIR/love.AppImage" ]; then
    chmod +x "$SCRIPT_DIR/love.AppImage"
    exec "$SCRIPT_DIR/love.AppImage" "$LOVE_FILE"
fi

echo "ERROR: LÖVE not found!"
echo ""
echo "Please install LÖVE using one of these methods:"
echo "  - Ubuntu/Debian: sudo apt install love"
echo "  - Fedora: sudo dnf install love"
echo "  - Arch: sudo pacman -S love"
echo "  - Flatpak: flatpak install flathub org.love2d.Love2D"
echo "  - Or download the AppImage from https://love2d.org"
echo ""
echo "Alternatively, place 'love.AppImage' in this directory."
exit 1
