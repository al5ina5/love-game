#!/bin/bash
# build/desktop/build.sh
# Builds Pixel Raiders for Windows, macOS, and Linux
#
# Usage:
#   ./build/desktop/build.sh          # Build all platforms
#   ./build/desktop/build.sh windows  # Build Windows only
#   ./build/desktop/build.sh macos    # Build macOS only
#   ./build/desktop/build.sh linux    # Build Linux only
#   ./build/desktop/build.sh love     # Create .love file only
#
# Requirements:
#   - zip (for creating .love file)
#   - curl or wget (for downloading LÖVE binaries)
#   - unzip (for extracting LÖVE binaries)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
GAME_NAME="PIXELRAIDERS"
GAME_DISPLAY_NAME="Pixel Raiders"
LOVE_VERSION="11.5"
BUILD_DIR="$PROJECT_ROOT/dist/desktop"
CACHE_DIR="$PROJECT_ROOT/build/desktop/.cache"

# LÖVE download URLs
LOVE_WIN64_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-win64.zip"
LOVE_MACOS_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-macos.zip"
LOVE_LINUX_URL="https://github.com/love2d/love/releases/download/${LOVE_VERSION}/love-${LOVE_VERSION}-x86_64.AppImage"

# Icon source (optional - will use default LÖVE icon if not found)
ICON_SOURCE="$PROJECT_ROOT/assets/img/icon.png"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect download tool
get_downloader() {
    if command -v curl &> /dev/null; then
        echo "curl"
    elif command -v wget &> /dev/null; then
        echo "wget"
    else
        print_error "Neither curl nor wget found. Please install one of them."
        exit 1
    fi
}

# Download file with progress
download_file() {
    local url="$1"
    local dest="$2"
    local downloader=$(get_downloader)
    
    if [ -f "$dest" ]; then
        print_warning "Using cached: $(basename "$dest")"
        return 0
    fi
    
    print_step "Downloading $(basename "$dest")..."
    
    if [ "$downloader" = "curl" ]; then
        curl -L --progress-bar -o "$dest" "$url"
    else
        wget --show-progress -q -O "$dest" "$url"
    fi
    
    if [ $? -eq 0 ] && [ -f "$dest" ]; then
        print_success "Downloaded $(basename "$dest")"
    else
        print_error "Failed to download $(basename "$dest")"
        exit 1
    fi
}

# Generate macOS .icns icon
generate_macos_icon() {
    if [ ! -f "$ICON_SOURCE" ]; then
        print_warning "Icon source not found: $ICON_SOURCE"
        return 1
    fi
    
    print_step "Generating macOS icon..."
    
    local iconset_dir="$CACHE_DIR/${GAME_NAME}.iconset"
    local icns_file="$CACHE_DIR/${GAME_NAME}.icns"
    
    # Skip if already generated and newer than source
    if [ -f "$icns_file" ] && [ "$icns_file" -nt "$ICON_SOURCE" ]; then
        print_warning "Using cached icon"
        return 0
    fi
    
    rm -rf "$iconset_dir"
    mkdir -p "$iconset_dir"
    
    # Check for ImageMagick (preferred - creates proper RGBA PNGs)
    if command -v magick &> /dev/null; then
        # Create base image with alpha channel
        magick "$ICON_SOURCE" -define png:color-type=6 -strip "PNG32:$CACHE_DIR/icon_base.png"
        
        # Generate all required sizes
        local sizes=("16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x")
        for entry in "${sizes[@]}"; do
            local size="${entry%%:*}"
            local name="${entry##*:}"
            magick "$CACHE_DIR/icon_base.png" -resize "${size}x${size}" -strip -define png:color-type=6 "PNG32:$iconset_dir/icon_${name}.png"
            # Set correct DPI (72 for standard, 144 for @2x)
            sips -s dpiWidth 72 -s dpiHeight 72 "$iconset_dir/icon_${name}.png" > /dev/null 2>&1
        done
        rm -f "$CACHE_DIR/icon_base.png"
    else
        # Fallback to sips (may not work if source lacks alpha)
        print_warning "ImageMagick not found, trying sips (may fail without alpha channel)"
        local sizes=("16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" "512:512x512" "1024:512x512@2x")
        for entry in "${sizes[@]}"; do
            local size="${entry%%:*}"
            local name="${entry##*:}"
            sips -z "$size" "$size" "$ICON_SOURCE" --out "$iconset_dir/icon_${name}.png" > /dev/null 2>&1
            sips -s dpiWidth 72 -s dpiHeight 72 "$iconset_dir/icon_${name}.png" > /dev/null 2>&1
        done
    fi
    
    # Clear any extended attributes
    xattr -cr "$iconset_dir" 2>/dev/null || true
    
    # Convert iconset to icns
    if iconutil -c icns "$iconset_dir" -o "$icns_file" 2>/dev/null; then
        print_success "Generated ${GAME_NAME}.icns"
        rm -rf "$iconset_dir"
        return 0
    else
        print_warning "iconutil failed - will use default LÖVE icon"
        print_warning "Try: brew install imagemagick"
        rm -rf "$iconset_dir"
        return 1
    fi
}

# Generate Windows .ico icon
generate_windows_icon() {
    if [ ! -f "$ICON_SOURCE" ]; then
        print_warning "Icon source not found: $ICON_SOURCE"
        return 1
    fi
    
    local ico_file="$CACHE_DIR/${GAME_NAME}.ico"
    
    # Skip if already generated
    if [ -f "$ico_file" ] && [ "$ico_file" -nt "$ICON_SOURCE" ]; then
        print_warning "Using cached icon"
        return 0
    fi
    
    # Check for ImageMagick
    if command -v magick &> /dev/null; then
        print_step "Generating Windows icon with ImageMagick..."
        magick "$ICON_SOURCE" -define icon:auto-resize=256,128,64,48,32,16 "$ico_file" 2>/dev/null
        if [ -f "$ico_file" ]; then
            print_success "Generated ${GAME_NAME}.ico"
            return 0
        fi
    elif command -v convert &> /dev/null; then
        print_step "Generating Windows icon with ImageMagick (legacy)..."
        convert "$ICON_SOURCE" -define icon:auto-resize=256,128,64,48,32,16 "$ico_file" 2>/dev/null
        if [ -f "$ico_file" ]; then
            print_success "Generated ${GAME_NAME}.ico"
            return 0
        fi
    fi
    
    print_warning "ImageMagick not found - Windows build will use default icon"
    print_warning "Install with: brew install imagemagick"
    return 1
}

# Create the .love file
build_love() {
    print_step "Creating ${GAME_NAME}.love..."
    
    mkdir -p "$BUILD_DIR"
    cd "$PROJECT_ROOT"
    
    # Create a production .env file to ensure we use the real server
    # This ensures USE_LOCAL_API is not set to true
    local temp_env="$BUILD_DIR/.env.production"
    echo "# Production build - using real server" > "$temp_env"
    echo "USE_LOCAL_API=false" >> "$temp_env"
    
    # Remove old .love file if exists
    rm -f "$BUILD_DIR/${GAME_NAME}.love"
    
    # Create .love file (it's just a zip)
    # First, temporarily copy the production .env to the project root
    local original_env_exists=false
    if [ -f ".env" ]; then
        original_env_exists=true
        mv ".env" ".env.backup"
    fi
    cp "$temp_env" ".env"
    
    zip -9 -r "$BUILD_DIR/${GAME_NAME}.love" . \
        -x "*.git*" \
        -x "dist/*" \
        -x "build/*" \
        -x "*.DS_Store" \
        -x "relay/*" \
        -x "docs/*" \
        -x "Dockerfile" \
        -x "*.md" \
        -x "raw_udp_test.lua" \
        -x "debug/*" \
        -x ".env.backup" \
        > /dev/null 2>&1
    
    # Restore original .env if it existed
    rm -f ".env"
    if [ "$original_env_exists" = true ]; then
        mv ".env.backup" ".env"
    fi
    
    # Clean up temp file
    rm -f "$temp_env"
    
    print_success "Created ${GAME_NAME}.love ($(du -h "$BUILD_DIR/${GAME_NAME}.love" | cut -f1))"
    print_success "Build configured to use production server"
}

# Build Windows version
build_windows() {
    print_step "Building Windows (64-bit)..."
    
    local win_dir="$BUILD_DIR/${GAME_NAME}-win64"
    local cache_file="$CACHE_DIR/love-${LOVE_VERSION}-win64.zip"
    
    mkdir -p "$CACHE_DIR"
    mkdir -p "$win_dir"
    
    # Download LÖVE for Windows
    download_file "$LOVE_WIN64_URL" "$cache_file"
    
    # Extract LÖVE
    print_step "Extracting LÖVE Windows binaries..."
    unzip -q -o "$cache_file" -d "$CACHE_DIR"
    
    # Copy LÖVE files
    cp "$CACHE_DIR/love-${LOVE_VERSION}-win64/"*.dll "$win_dir/"
    cp "$CACHE_DIR/love-${LOVE_VERSION}-win64/license.txt" "$win_dir/love-license.txt"
    
    # Fuse love.exe with .love file to create game executable
    cat "$CACHE_DIR/love-${LOVE_VERSION}-win64/love.exe" "$BUILD_DIR/${GAME_NAME}.love" > "$win_dir/${GAME_NAME}.exe"
    
    # Generate and embed Windows icon
    if generate_windows_icon; then
        local ico_file="$CACHE_DIR/${GAME_NAME}.ico"
        # Copy ico to build folder (users can manually set it)
        cp "$ico_file" "$win_dir/${GAME_NAME}.ico"
        
        # Try to embed icon using rcedit (if available)
        if command -v rcedit &> /dev/null; then
            print_step "Embedding icon in executable..."
            rcedit "$win_dir/${GAME_NAME}.exe" --set-icon "$ico_file" 2>/dev/null && \
                print_success "Embedded icon in ${GAME_NAME}.exe"
        elif command -v rcedit-x64 &> /dev/null; then
            print_step "Embedding icon in executable..."
            rcedit-x64 "$win_dir/${GAME_NAME}.exe" --set-icon "$ico_file" 2>/dev/null && \
                print_success "Embedded icon in ${GAME_NAME}.exe"
        else
            print_warning "rcedit not found - icon included but not embedded in .exe"
            print_warning "Install with: npm install -g rcedit"
        fi
    fi
    
    # Create a simple batch launcher as backup
    cat > "$win_dir/Run ${GAME_DISPLAY_NAME}.bat" << EOF
@echo off
cd /d "%~dp0"
start "" "%~dp0\\${GAME_NAME}.exe"
EOF
    
    print_success "Built Windows version: $win_dir/"
}

# Build macOS version
build_macos() {
    print_step "Building macOS..."
    
    local mac_dir="$BUILD_DIR/${GAME_NAME}-macos"
    local app_dir="$mac_dir/${GAME_NAME}.app"
    local cache_file="$CACHE_DIR/love-${LOVE_VERSION}-macos.zip"
    
    mkdir -p "$CACHE_DIR"
    rm -rf "$mac_dir"
    mkdir -p "$mac_dir"
    
    # Download LÖVE for macOS
    download_file "$LOVE_MACOS_URL" "$cache_file"
    
    # Extract LÖVE
    print_step "Extracting LÖVE macOS app..."
    unzip -q -o "$cache_file" -d "$CACHE_DIR"
    
    # Copy the app bundle
    cp -R "$CACHE_DIR/love.app" "$app_dir"
    
    # Rename the executable to match our game name
    mv "$app_dir/Contents/MacOS/love" "$app_dir/Contents/MacOS/${GAME_NAME}"
    
    # Update Info.plist
    local plist="$app_dir/Contents/Info.plist"
    
    # Use sed to update the plist (works on both macOS and Linux)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed
        sed -i '' "s/<string>LÖVE<\/string>/<string>${GAME_DISPLAY_NAME}<\/string>/g" "$plist"
        sed -i '' "s/<string>love<\/string>/<string>${GAME_NAME}<\/string>/g" "$plist"
        sed -i '' "s/org\.love2d\.love/com.pixelraider.game/g" "$plist"
    else
        # GNU sed
        sed -i "s/<string>LÖVE<\/string>/<string>${GAME_DISPLAY_NAME}<\/string>/g" "$plist"
        sed -i "s/<string>love<\/string>/<string>${GAME_NAME}<\/string>/g" "$plist"
        sed -i "s/org\.love2d\.love/com.pixelraider.game/g" "$plist"
    fi
    
    # Copy .love file into the app bundle
    cp "$BUILD_DIR/${GAME_NAME}.love" "$app_dir/Contents/Resources/"
    
    # Replace icons with our custom icon
    if generate_macos_icon; then
        local icns_file="$CACHE_DIR/${GAME_NAME}.icns"
        if [ -f "$icns_file" ]; then
            cp "$icns_file" "$app_dir/Contents/Resources/GameIcon.icns"
            cp "$icns_file" "$app_dir/Contents/Resources/OS X AppIcon.icns"
            # Remove Assets.car - it contains LÖVE's icon and takes precedence over .icns
            rm -f "$app_dir/Contents/Resources/Assets.car"
        fi
    fi
    
    print_success "Built macOS version: $app_dir"
    
    # Create a zip for distribution
    print_step "Creating macOS distribution zip..."
    cd "$mac_dir"
    zip -q -r -y "../${GAME_NAME}-macos.zip" "${GAME_NAME}.app"
    cd "$PROJECT_ROOT"
    print_success "Created ${GAME_NAME}-macos.zip"
}

# Build Linux version
build_linux() {
    print_step "Building Linux..."
    
    local linux_dir="$BUILD_DIR/${GAME_NAME}-linux"
    local cache_file="$CACHE_DIR/love-${LOVE_VERSION}-x86_64.AppImage"
    
    mkdir -p "$CACHE_DIR"
    rm -rf "$linux_dir"
    mkdir -p "$linux_dir"
    
    # Download LÖVE AppImage
    download_file "$LOVE_LINUX_URL" "$cache_file"
    chmod +x "$cache_file"
    
    # Copy the .love file
    cp "$BUILD_DIR/${GAME_NAME}.love" "$linux_dir/"
    
    # Create a launcher script
    cat > "$linux_dir/${GAME_NAME}.sh" << EOF
#!/bin/bash
# ${GAME_DISPLAY_NAME} Linux Launcher
# This script tries multiple methods to run the game

SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
LOVE_FILE="\$SCRIPT_DIR/${GAME_NAME}.love"

# Method 1: Try system-installed LÖVE
if command -v love &> /dev/null; then
    exec love "\$LOVE_FILE"
fi

# Method 2: Try flatpak
if command -v flatpak &> /dev/null; then
    if flatpak list | grep -q "org.love2d.Love2D"; then
        exec flatpak run org.love2d.Love2D "\$LOVE_FILE"
    fi
fi

# Method 3: Try AppImage in same directory
if [ -f "\$SCRIPT_DIR/love.AppImage" ]; then
    chmod +x "\$SCRIPT_DIR/love.AppImage"
    exec "\$SCRIPT_DIR/love.AppImage" "\$LOVE_FILE"
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
EOF
    chmod +x "$linux_dir/${GAME_NAME}.sh"
    
    # Option: Create a fused AppImage (single-file executable)
    # This requires the AppImage to be extracted and repacked
    # Note: Extraction requires FUSE or --appimage-extract-and-run
    print_step "Attempting to create fused AppImage..."
    
    cd "$CACHE_DIR"
    
    # Try to extract the AppImage (may fail without FUSE)
    local extract_success=false
    if [ ! -d "squashfs-root" ]; then
        if "$cache_file" --appimage-extract > /dev/null 2>&1; then
            extract_success=true
        fi
    else
        extract_success=true
    fi
    
    if [ "$extract_success" = true ] && [ -d "squashfs-root" ]; then
        # Copy our .love file into the extracted AppImage
        cp "$BUILD_DIR/${GAME_NAME}.love" "squashfs-root/${GAME_NAME}.love"
        
        # Modify the AppRun to use our game
        cat > "squashfs-root/AppRun" << EOF
#!/bin/bash
SELF=\$(readlink -f "\$0")
HERE=\${SELF%/*}
export LD_LIBRARY_PATH="\${HERE}/usr/lib/:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/love" "\${HERE}/${GAME_NAME}.love" "\$@"
EOF
        chmod +x "squashfs-root/AppRun"
        
        # Update desktop file
        if [ -f "squashfs-root/love.desktop" ]; then
            sed -i "s/Name=LÖVE/Name=${GAME_DISPLAY_NAME}/" "squashfs-root/love.desktop" 2>/dev/null || true
            sed -i "s/Exec=love/Exec=${GAME_NAME}/" "squashfs-root/love.desktop" 2>/dev/null || true
            mv "squashfs-root/love.desktop" "squashfs-root/${GAME_NAME}.desktop" 2>/dev/null || true
        fi
        
        # Check if appimagetool is available
        if command -v appimagetool &> /dev/null; then
            ARCH=x86_64 appimagetool -n squashfs-root "$linux_dir/${GAME_NAME}.AppImage" > /dev/null 2>&1
            print_success "Created fused AppImage: ${GAME_NAME}.AppImage"
        else
            # Copy unfused AppImage as fallback
            cp "$cache_file" "$linux_dir/love.AppImage"
            print_warning "appimagetool not found - included love.AppImage separately"
        fi
    else
        # Extraction failed (no FUSE) - copy AppImage directly
        cp "$cache_file" "$linux_dir/love.AppImage"
        print_warning "Could not extract AppImage (FUSE not available)"
        print_warning "Included love.AppImage separately - users can run: ./love.AppImage ${GAME_NAME}.love"
    fi
    
    cd "$PROJECT_ROOT"
    
    # Copy icon PNG for Linux desktop integration
    if [ -f "$ICON_SOURCE" ]; then
        cp "$ICON_SOURCE" "$linux_dir/${GAME_NAME}.png"
        print_success "Included icon: ${GAME_NAME}.png"
    fi
    
    print_success "Built Linux version: $linux_dir/"
}

# Clean build directory
clean() {
    print_step "Cleaning build directory..."
    rm -rf "$BUILD_DIR"
    print_success "Cleaned $BUILD_DIR"
}

# Clean cache
clean_cache() {
    print_step "Cleaning cache..."
    rm -rf "$CACHE_DIR"
    print_success "Cleaned $CACHE_DIR"
}

# Print usage
usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  all       Build for all platforms (default)"
    echo "  love      Create .love file only"
    echo "  windows   Build Windows version"
    echo "  macos     Build macOS version"
    echo "  linux     Build Linux version"
    echo "  clean     Remove build output"
    echo "  cleanall  Remove build output and cached downloads"
    echo ""
    echo "Examples:"
    echo "  $0              # Build all platforms"
    echo "  $0 windows      # Build Windows only"
    echo "  $0 love         # Create .love file only"
}

# Main
main() {
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║     ${GAME_NAME} Desktop Build System           ║"
    echo "║     LÖVE ${LOVE_VERSION}                              ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""
    
    local command="${1:-all}"
    
    case "$command" in
        all)
            build_love
            build_windows
            build_macos
            build_linux
            ;;
        love)
            build_love
            ;;
        windows)
            build_love
            build_windows
            ;;
        macos)
            build_love
            build_macos
            ;;
        linux)
            build_love
            build_linux
            ;;
        clean)
            clean
            ;;
        cleanall)
            clean
            clean_cache
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
    
    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║            Build Complete!                ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""
    echo "Output directory: $BUILD_DIR"
    echo ""
    
    if [ -d "$BUILD_DIR" ]; then
        echo "Contents:"
        ls -la "$BUILD_DIR" 2>/dev/null | tail -n +2 | while read line; do
            echo "  $line"
        done
    fi
}

main "$@"
