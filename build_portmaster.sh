#!/bin/bash
# build_portmaster.sh
# Creates the exact structure for Miyoo Flip v2 (Spruce OS) PortMaster

set -e

GAME_NAME="WalkingTogether"
BUILD_DIR="dist"

echo "=== Building PortMaster Package for $GAME_NAME ==="

# 1. Clean and create build structure
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$GAME_NAME"

# 2. Package the .love file
echo "Creating $GAME_NAME.love..."
# Zip everything in current dir into the .love file
# Excluding build files and hidden git/system files
zip -9 -r "$BUILD_DIR/$GAME_NAME/$GAME_NAME.love" . \
    -x "*.git*" -x "dist/*" -x "build_portmaster.sh" -x "*.DS_Store" -x "raw_udp_test.lua" -x "debug/*"

# 3. Create the Launcher (.sh)
echo "Creating $GAME_NAME.sh..."
cat > "$BUILD_DIR/$GAME_NAME.sh" << 'EOF'
#!/bin/bash
# PortMaster Launcher for Walking Together

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt

get_controls
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"

# Dynamic path resolution. We remove any trailing slashes to avoid // issues.
CLEAN_DIR=$(echo "/$directory" | sed 's:/*$::')
GAMEDIR="$CLEAN_DIR/WalkingTogether"

# If not found in root, check in /ports/ subfolder
if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR="$CLEAN_DIR/ports/WalkingTogether"
fi

cd "$GAMEDIR"

# Setup saves path
export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
mkdir -p "$XDG_DATA_HOME"
mkdir -p "$XDG_CONFIG_HOME"

# Redirect all output to log.txt for debugging
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "--- Starting Walking Together ---"
echo "Date: $(date)"
echo "GAMEDIR: $GAMEDIR"
echo "Device: $DEVICE_NAME ($DEVICE_ARCH)"

# Search for LÖVE binary
LOVE_BIN=""
# 1. Check PortMaster runtimes first (highest quality)
for ver in "11.5" "11.4"; do
    R_PATH="$controlfolder/runtimes/love_$ver/love.$DEVICE_ARCH"
    if [ -f "$R_PATH" ]; then
        LOVE_BIN="$R_PATH"
        export LD_LIBRARY_PATH="$(dirname "$R_PATH")/libs.$DEVICE_ARCH:$LD_LIBRARY_PATH"
        break
    fi
done

# 2. Check system paths fallback
if [ -z "$LOVE_BIN" ]; then
    for path in "/usr/bin/love" "/usr/local/bin/love" "/opt/love/bin/love"; do
        if [ -f "$path" ]; then
            LOVE_BIN="$path"
            break
        fi
    done
fi

if [ -z "$LOVE_BIN" ]; then
    echo "ERROR: LÖVE binary not found in runtimes or system paths!"
    exit 1
fi

echo "Using LÖVE binary: $LOVE_BIN"

# We use the basename of LOVE_BIN for gptokeyb to watch
LOVE_NAME=$(basename "$LOVE_BIN")

$GPTOKEYB "$LOVE_NAME" -c "$GAMEDIR/WalkingTogether.gptk" &
pm_platform_helper "$LOVE_BIN"
"$LOVE_BIN" "$GAMEDIR/WalkingTogether.love"

# Cleanup after exit
killall gptokeyb
pm_finish
EOF

chmod +x "$BUILD_DIR/$GAME_NAME.sh"

# 4. Create the Controller Mapping (.gptk)
echo "Creating $GAME_NAME.gptk..."
cat > "$BUILD_DIR/$GAME_NAME/WalkingTogether.gptk" << 'EOF'
back = esc
start = enter

up = w
down = s
left = a
right = d

left_analog_up = w
left_analog_down = s
left_analog_left = a
left_analog_right = d

a = enter
b = esc
x = m
y = tab

l1 = tab
r1 = m
EOF

# 5. Create PortMaster metadata (port.json)
echo "Creating port.json..."
cat > "$BUILD_DIR/$GAME_NAME/port.json" << EOF
{
    "version": 1,
    "name": "$GAME_NAME",
    "items": ["$GAME_NAME.sh"],
    "items_opt": [],
    "attr": {
        "title": "Walking Together",
        "desc": "Multiplayer walking simulator boilerplate.",
        "inst": "D-Pad to move. X/Y for Menu. Host on one device, Find on another!",
        "genres": ["multiplayer", "sim"],
        "porter": "Antigravity",
        "runtime": "love-11.4"
    }
}
EOF

echo ""
echo "=== DONE ==="
echo "Your PortMaster files are in the '$BUILD_DIR' folder:"
echo "1. $BUILD_DIR/$GAME_NAME.sh        <-- Move to /roms/ports/"
echo "2. $BUILD_DIR/$GAME_NAME/          <-- Move this whole FOLDER to /roms/ports/"
echo ""
echo "Installation on SD Card should look like this:"
echo "/roms/ports/WalkingTogether.sh"
echo "/roms/ports/WalkingTogether/WalkingTogether.love"
echo "/roms/ports/WalkingTogether/WalkingTogether.gptk"
echo "/roms/ports/WalkingTogether/port.json"
