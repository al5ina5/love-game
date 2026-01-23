# Desktop Build System

Build scripts for packaging Pixel Raiders for Windows, macOS, and Linux.

## Quick Start

```bash
# Build for all platforms
./build/desktop/build.sh

# Build for specific platform
./build/desktop/build.sh windows
./build/desktop/build.sh macos
./build/desktop/build.sh linux

# Create .love file only
./build/desktop/build.sh love
```

## Requirements

- `zip` - for creating .love files
- `unzip` - for extracting LÖVE binaries
- `curl` or `wget` - for downloading LÖVE

Optional (for fused Linux AppImage):
- FUSE - for extracting AppImages
- `appimagetool` - for repacking AppImages

## Output

After building, you'll find the following in `dist/desktop/`:

```
dist/desktop/
├── PixelRaider.love           # Universal LÖVE package
├── PixelRaider-win64/         # Windows 64-bit
│   ├── PixelRaider.exe        # Fused executable
│   ├── *.dll                   # Required libraries
│   └── Run Pixel Raiders.bat    # Backup launcher
├── PixelRaider-macos/
│   └── PixelRaider.app         # macOS application bundle
├── PixelRaider-macos.zip       # Ready for distribution
└── PixelRaider-linux/
    ├── PixelRaider.love        # Game file
    ├── PixelRaider.sh          # Launcher script
    └── love.AppImage           # LÖVE runtime (if fusing unavailable)
```

## Platform Notes

### Windows

The build creates a fused `.exe` by concatenating `love.exe` with the `.love` file. All required DLLs are included. Users can run `PixelRaider.exe` directly - **no dependencies needed, just double-click!**

### macOS

Creates a proper `.app` bundle with the game embedded. The `Info.plist` is updated with the game name. A `.zip` is also created for easy distribution.

**Note:** The app is not signed or notarized. Users may need to right-click → Open on first launch, or you can sign it with your Apple Developer certificate:

```bash
codesign --deep --force --sign "Developer ID Application: Your Name" dist/desktop/PixelRaider-macos/PixelRaider.app
```

### Linux

The build includes:
1. **PixelRaider.sh** - A launcher that tries system LÖVE, Flatpak, or bundled AppImage
2. **PixelRaider.love** - The game file
3. **love.AppImage** - Bundled LÖVE runtime (fallback)

If you have FUSE and `appimagetool` installed, the build will create a single fused AppImage instead.

## Caching

Downloaded LÖVE binaries are cached in `build/desktop/.cache/`. To clear the cache:

```bash
./build/desktop/build.sh cleanall
```

## LÖVE Version

Currently using LÖVE **11.5**. To change the version, edit `LOVE_VERSION` at the top of `build.sh`.

## Distribution Checklist

- [ ] Test on each target platform
- [ ] (macOS) Sign and notarize the app for distribution outside App Store
- [ ] (Windows) Consider signing with a code signing certificate
- [ ] Create release archives (the script creates macOS zip automatically)
- [ ] Add custom icons (replace the LÖVE icons in the builds)
