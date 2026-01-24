#!/bin/bash
# PortMaster Launcher for Pixel Raiders

# Create a temporary log file first (before we know GAMEDIR)
TEMP_LOG="/tmp/pixelraiders_launch_$$.log"
echo "=== Pixel Raiders Launch Log ===" > "$TEMP_LOG"
echo "Timestamp: $(date)" >> "$TEMP_LOG"
echo "PID: $$" >> "$TEMP_LOG"
echo "" >> "$TEMP_LOG"

log() {
    echo "$1" | tee -a "$TEMP_LOG"
}

log_error() {
    echo "ERROR: $1" | tee -a "$TEMP_LOG" >&2
}

log "Starting launch script..."
log "Script path: $0"
log "Working directory: $(pwd)"
log "User: $(whoami)"
log ""

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
log "XDG_DATA_HOME: $XDG_DATA_HOME"

# Find PortMaster control folder
log "Searching for PortMaster control folder..."
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
  log "Found: /opt/system/Tools/PortMaster/"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
  log "Found: /opt/tools/PortMaster/"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
  log "Found: $XDG_DATA_HOME/PortMaster/"
else
  controlfolder="/roms/ports/PortMaster"
  log "Using default: /roms/ports/PortMaster/"
fi

if [ ! -d "$controlfolder" ]; then
    log_error "PortMaster control folder not found: $controlfolder"
    exit 1
fi

log "Control folder: $controlfolder"
log ""

# Source control.txt
if [ ! -f "$controlfolder/control.txt" ]; then
    log_error "control.txt not found at $controlfolder/control.txt"
    exit 1
fi

log "Sourcing control.txt..."
source "$controlfolder/control.txt"
log "CFW_NAME: ${CFW_NAME:-not set}"
log "DEVICE_NAME: ${DEVICE_NAME:-not set}"
log "DEVICE_ARCH: ${DEVICE_ARCH:-not set}"
log "directory: ${directory:-not set}"
log ""

get_controls
log "Controls configured"

# Source mod file if it exists
MOD_FILE="${controlfolder}/mod_${CFW_NAME}.txt"
if [ -f "$MOD_FILE" ]; then
    log "Sourcing mod file: $MOD_FILE"
    source "$MOD_FILE"
else
    log "No mod file found: $MOD_FILE"
fi
log ""

# Dynamic path resolution - remove trailing slashes, handle leading slash
log "Resolving game directory..."
GAMEDIR="${directory%/}/PIXELRAIDERS"
log "Initial GAMEDIR: $GAMEDIR"

# Ensure path starts with /
[[ "$GAMEDIR" != /* ]] && GAMEDIR="/$GAMEDIR"
log "After leading slash check: $GAMEDIR"

# If not found in root, check in /ports/ subfolder
if [ ! -d "$GAMEDIR" ]; then
    log "GAMEDIR not found, trying /ports/ subfolder..."
    GAMEDIR="${directory%/}/ports/PIXELRAIDERS"
    [[ "$GAMEDIR" != /* ]] && GAMEDIR="/$GAMEDIR"
    log "New GAMEDIR: $GAMEDIR"
fi

if [ ! -d "$GAMEDIR" ]; then
    log_error "Game directory not found: $GAMEDIR"
    log "Searched paths:"
    log "  1. ${directory%/}/PIXELRAIDERS"
    log "  2. ${directory%/}/ports/PIXELRAIDERS"
    exit 1
fi

log "Final GAMEDIR: $GAMEDIR"
log "GAMEDIR exists: $(test -d "$GAMEDIR" && echo 'yes' || echo 'no')"
log ""

# Change to game directory
log "Changing to game directory..."
cd "$GAMEDIR" || {
    log_error "Failed to cd to $GAMEDIR"
    exit 1
}
log "Current directory: $(pwd)"
log ""

# Setup saves path
log "Setting up saves directory..."
export XDG_DATA_HOME="$GAMEDIR/saves"
export XDG_CONFIG_HOME="$GAMEDIR/saves"
log "XDG_DATA_HOME: $XDG_DATA_HOME"
log "XDG_CONFIG_HOME: $XDG_CONFIG_HOME"

mkdir -p "$XDG_DATA_HOME" || log_error "Failed to create $XDG_DATA_HOME"
mkdir -p "$XDG_CONFIG_HOME" || log_error "Failed to create $XDG_CONFIG_HOME"
log ""

# Move temp log to final location and redirect all output
FINAL_LOG="$GAMEDIR/log.txt"
log "Moving log to final location: $FINAL_LOG"
cat "$TEMP_LOG" > "$FINAL_LOG"
rm -f "$TEMP_LOG"

# Redirect all output to log.txt for debugging
exec > >(tee -a "$FINAL_LOG") 2>&1

log "=== Launch Process Starting ==="
log "Date: $(date)"
log "GAMEDIR: $GAMEDIR"
log "Device: ${DEVICE_NAME:-unknown} (${DEVICE_ARCH:-unknown})"
log ""

# Check for required files
log "Checking required files..."
LOVE_FILE="$GAMEDIR/PIXELRAIDERS.love"
GPTK_FILE="$GAMEDIR/PIXELRAIDERS.gptk"

if [ ! -f "$LOVE_FILE" ]; then
    log_error "PIXELRAIDERS.love not found at $LOVE_FILE"
    exit 1
fi
log "✓ Found: $LOVE_FILE ($(du -h "$LOVE_FILE" | cut -f1))"

if [ ! -f "$GPTK_FILE" ]; then
    log "⚠ Warning: PIXELRAIDERS.gptk not found at $GPTK_FILE"
else
    log "✓ Found: $GPTK_FILE"
fi
log ""

# Search for LÖVE binary
log "Searching for LÖVE binary..."
LOVE_BIN=""

# 1. Check PortMaster runtimes first (highest quality)
log "Checking PortMaster runtimes..."
for ver in "11.5" "11.4"; do
    R_PATH="$controlfolder/runtimes/love_$ver/love.$DEVICE_ARCH"
    log "  Checking: $R_PATH"
    if [ -f "$R_PATH" ]; then
        LOVE_BIN="$R_PATH"
        export LD_LIBRARY_PATH="$(dirname "$R_PATH")/libs.$DEVICE_ARCH:$LD_LIBRARY_PATH"
        log "  ✓ Found LÖVE $ver at: $LOVE_BIN"
        log "  LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
        break
    else
        log "  ✗ Not found"
    fi
done

# 2. Check system paths fallback
if [ -z "$LOVE_BIN" ]; then
    log "Checking system paths..."
    for path in "/usr/bin/love" "/usr/local/bin/love" "/opt/love/bin/love"; do
        log "  Checking: $path"
        if [ -f "$path" ]; then
            LOVE_BIN="$path"
            log "  ✓ Found at: $LOVE_BIN"
            break
        else
            log "  ✗ Not found"
        fi
    done
fi

if [ -z "$LOVE_BIN" ]; then
    log_error "LÖVE binary not found in runtimes or system paths!"
    log "Searched locations:"
    log "  - $controlfolder/runtimes/love_11.5/love.$DEVICE_ARCH"
    log "  - $controlfolder/runtimes/love_11.4/love.$DEVICE_ARCH"
    log "  - /usr/bin/love"
    log "  - /usr/local/bin/love"
    log "  - /opt/love/bin/love"
    exit 1
fi

log "Using LÖVE binary: $LOVE_BIN"
if [ -x "$LOVE_BIN" ]; then
    log "✓ Binary is executable"
else
    log_error "Binary is not executable!"
    exit 1
fi

# Check binary version if possible
if command -v "$LOVE_BIN" --version &>/dev/null; then
    log "LÖVE version: $("$LOVE_BIN" --version 2>&1 | head -1)"
fi
log ""

# We use the basename of LOVE_BIN for gptokeyb to watch
LOVE_NAME=$(basename "$LOVE_BIN")
log "LOVE_NAME for gptokeyb: $LOVE_NAME"
log ""

# Check for gptokeyb
log "Checking for gptokeyb..."
if [ -z "$GPTOKEYB" ]; then
    log "⚠ GPTOKEYB not set, trying to find it..."
    if [ -f "$controlfolder/gptokeyb" ]; then
        GPTOKEYB="$controlfolder/gptokeyb"
        log "Found: $GPTOKEYB"
    elif command -v gptokeyb &>/dev/null; then
        GPTOKEYB=$(command -v gptokeyb)
        log "Found in PATH: $GPTOKEYB"
    else
        log "⚠ gptokeyb not found, continuing without it"
    fi
fi

# Launch game
log "=== Launching Game ==="
log "Command: \"$LOVE_BIN\" \"$LOVE_FILE\""
log ""

if [ -n "$GPTOKEYB" ] && [ -f "$GPTOKEYB" ] && [ -f "$GPTK_FILE" ]; then
    log "Starting gptokeyb..."
    "$GPTOKEYB" "$LOVE_NAME" -c "$GPTK_FILE" &
    GPTOKEYB_PID=$!
    log "gptokeyb PID: $GPTOKEYB_PID"
    log ""
fi

if command -v pm_platform_helper &>/dev/null; then
    log "Running pm_platform_helper..."
    pm_platform_helper "$LOVE_BIN"
    log ""
fi

log "Executing LÖVE..."
log "--- Game Output Below ---"
log ""

# Execute the game
"$LOVE_BIN" "$LOVE_FILE"
EXIT_CODE=$?

log ""
log "--- Game Exited ---"
log "Exit code: $EXIT_CODE"
log "Timestamp: $(date)"

# Cleanup after exit
log "Cleaning up..."
if [ -n "$GPTOKEYB_PID" ]; then
    kill "$GPTOKEYB_PID" 2>/dev/null || true
    log "Stopped gptokeyb"
fi
killall gptokeyb 2>/dev/null || true

if command -v pm_finish &>/dev/null; then
    pm_finish
    log "Ran pm_finish"
fi

log "=== Launch Process Complete ==="
exit $EXIT_CODE
