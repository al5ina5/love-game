#!/bin/bash
# PortMaster Launcher for Pixel Raiders

XDG_DATA_HOME=/Users/alsinas/.local/share

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "/PortMaster/" ]; then
  controlfolder="/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source /control.txt

get_controls
[ -f "/mod_.txt" ] && source "/mod_.txt"

# Dynamic path resolution. We remove any trailing slashes to avoid // issues.
CLEAN_DIR=$(echo "/$directory" | sed 's:/*$::')
GAMEDIR="$CLEAN_DIR/PIXELRAIDERS"

# If not found in root, check in /ports/ subfolder
if [ ! -d "$GAMEDIR" ]; then
    GAMEDIR="$CLEAN_DIR/ports/PIXELRAIDERS"
fi

cd ""

# Setup saves path
export XDG_DATA_HOME="/saves"
export XDG_CONFIG_HOME="/saves"
mkdir -p ""
mkdir -p ""

# Redirect all output to log.txt for debugging
exec > >(tee "$GAMEDIR/log.txt") 2>&1
echo "--- Starting Pixel Raiders ---"
echo "Date: Fri Jan 23 18:52:17 EST 2026"
echo "GAMEDIR: "
echo "Device:  ()"

# Search for LÖVE binary
LOVE_BIN=""
# 1. Check PortMaster runtimes first (highest quality)
for ver in "11.5" "11.4"; do
    R_PATH="/runtimes/love_/love."
    if [ -f "" ]; then
        LOVE_BIN=""
        export LD_LIBRARY_PATH="./libs.:"
        break
    fi
done

# 2. Check system paths fallback
if [ -z "" ]; then
    for path in "/usr/bin/love" "/usr/local/bin/love" "/opt/love/bin/love"; do
        if [ -f "" ]; then
            LOVE_BIN=""
            break
        fi
    done
fi

if [ -z "" ]; then
    echo "ERROR: LÖVE binary not found in runtimes or system paths!"
    exit 1
fi

echo "Using LÖVE binary: "

# We use the basename of LOVE_BIN for gptokeyb to watch
LOVE_NAME=

$GPTOKEYB "$LOVE_NAME" -c "$GAMEDIR/PIXELRAIDERS.gptk" &
pm_platform_helper "$LOVE_BIN"
"$LOVE_BIN" "$GAMEDIR/PIXELRAIDERS.love"

# Cleanup after exit
killall gptokeyb
pm_finish
