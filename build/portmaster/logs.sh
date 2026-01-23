#!/bin/bash
# build/portmaster/logs.sh
# Downloads logs from PortMaster deployment on Miyoo Flip
#
# Usage: ./build/portmaster/logs.sh [options]
#   -i, --ip IP          Device IP address (default: 10.0.0.94)
#   -u, --user USER       SSH username (default: spruce)
#   -p, --pass PASS       SSH password (default: happygaming)
#   -o, --output DIR      Output directory (default: ./logs)
#   -t, --tail N          Show last N lines from device (default: 50)
#   -h, --help            Show this help message

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default configuration (matches deploy.sh)
SPRUCE_IP="${SPRUCE_IP:-10.0.0.94}"
SPRUCE_USER="${SPRUCE_USER:-spruce}"
SPRUCE_PASS="${SPRUCE_PASS:-happygaming}"
GAME_NAME="PIXELRAIDERS"
OUTPUT_DIR="$PROJECT_ROOT/logs"
TAIL_LINES=50

# Use SPRUCE_* variables for consistency with deploy.sh
DEVICE_IP="$SPRUCE_IP"
DEVICE_USER="$SPRUCE_USER"
DEVICE_PASS="$SPRUCE_PASS"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--ip)
            DEVICE_IP="$2"
            shift 2
            ;;
        -u|--user)
            DEVICE_USER="$2"
            shift 2
            ;;
        -p|--pass)
            DEVICE_PASS="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -t|--tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -i, --ip IP          Device IP address (default: $DEVICE_IP)"
            echo "  -u, --user USER      SSH username (default: $DEVICE_USER)"
            echo "  -p, --pass PASS      SSH password (default: [hidden])"
            echo "  -o, --output DIR     Output directory (default: $OUTPUT_DIR)"
            echo "  -t, --tail N         Show last N lines from device (default: $TAIL_LINES)"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  SPRUCE_IP            Device IP address"
            echo "  SPRUCE_USER          SSH username"
            echo "  SPRUCE_PASS          SSH password"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo "ERROR: sshpass is required but not installed."
    echo "Install it with: brew install hudochenkov/sshpass/sshpass (macOS)"
    echo "                 or: sudo apt-get install sshpass (Linux)"
    exit 1
fi

echo "=== Downloading Logs from $GAME_NAME ==="
echo "Device: $DEVICE_USER@$DEVICE_IP"
echo ""

# Test SSH connection
echo "Testing connection..."
if ! sshpass -p "$DEVICE_PASS" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$DEVICE_USER@$DEVICE_IP" "echo OK" 2>/dev/null; then
    echo "ERROR: Cannot connect to $DEVICE_IP"
    echo "Make sure device is on and SSH is enabled"
    exit 1
fi
echo "Connected!"
echo ""

# Log file is in the game install directory (matches deploy.sh path)
SPRUCE_PATH="/mnt/sdcard/Roms/PORTS"
LOG_FILE="$SPRUCE_PATH/$GAME_NAME/log.txt"

echo "Checking for log file at: $LOG_FILE"
if ! sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no "$DEVICE_USER@$DEVICE_IP" "test -f '$LOG_FILE'" 2>/dev/null; then
    echo "ERROR: Log file not found at $LOG_FILE"
    echo "Make sure the game has been run at least once on the device"
    exit 1
fi

FOUND_LOG="$LOG_FILE"
echo "✓ Found log file"

# Create output directory (relative to project root)
mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_ROOT"

# Generate timestamped filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="$OUTPUT_DIR/${GAME_NAME}_log_${TIMESTAMP}.txt"

# Download the log file
echo ""
echo "Downloading log file..."
if sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no "$DEVICE_USER@$DEVICE_IP:$FOUND_LOG" "$OUTPUT_FILE" 2>/dev/null; then
    echo "✓ Downloaded to: $OUTPUT_FILE"
else
    echo "ERROR: Failed to download log file"
    exit 1
fi

# Show file info
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
LINE_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "  Size: $FILE_SIZE"
echo "  Lines: $LINE_COUNT"
echo ""

# Show last N lines
echo "=== Last $TAIL_LINES lines of log ==="
echo "----------------------------------------"
tail -n "$TAIL_LINES" "$OUTPUT_FILE"
echo "----------------------------------------"
echo ""

# Also create a symlink to latest
LATEST_LINK="$OUTPUT_DIR/${GAME_NAME}_log_latest.txt"
rm -f "$LATEST_LINK"
ln -s "$(basename "$OUTPUT_FILE")" "$LATEST_LINK"
echo "Latest log also available at: $LATEST_LINK"
echo ""

# Check for common errors in the log
echo "=== Quick Error Check ==="
if grep -i "error\|failed\|exception\|timeout\|connection refused" "$OUTPUT_FILE" | tail -5; then
    echo ""
    echo "⚠️  Found potential errors in log (see above)"
else
    echo "✓ No obvious errors found"
fi
echo ""

echo "=== Done ==="
echo "Full log: $OUTPUT_FILE"
echo "Latest: $LATEST_LINK"
