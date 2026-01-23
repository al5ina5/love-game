#!/bin/bash
# deploy.sh
# Builds the game and deploys to multiple handheld devices via SSH/SSHPass

GAME_NAME="PIXELRAIDERS"

echo "=== Building $GAME_NAME ==="
./build_portmaster.sh

# --- Target 1: SpruceOS (handheld) ---
SPRUCE_IP="10.0.0.93"
SPRUCE_USER="spruce"
SPRUCE_PASS="happygaming"
SPRUCE_PATH="/mnt/sdcard/Roms/PORTS"

echo "=== Deploying to SpruceOS ($SPRUCE_IP) ==="
sshpass -p "$SPRUCE_PASS" scp -r "dist/$GAME_NAME.sh" "dist/$GAME_NAME" "$SPRUCE_USER@$SPRUCE_IP:$SPRUCE_PATH/"

# --- Target 2: muOS (handheld) ---
MUOS_IP="10.0.0.79"
MUOS_USER="muos"
MUOS_PASS="root"
# Deployment to multiple paths as requested
# 1. SD2 Ports path
MUOS_PATH1="/mnt/sdcard/ports" 
# 2. SD2 Roms PORTS path
MUOS_PATH2="/mnt/sdcard/Roms/PORTS"

echo "=== Deploying to muOS ($MUOS_IP) ==="
# Attempt deployment to multiple standard locations on muOS
# MUOS SFTP usually roots at the SD card or main FS.
sshpass -p "$MUOS_PASS" scp -P 2022 -r "dist/$GAME_NAME.sh" "dist/$GAME_NAME" "$MUOS_USER@$MUOS_IP:$MUOS_PATH1/"
sshpass -p "$MUOS_PASS" scp -P 2022 -r "dist/$GAME_NAME.sh" "dist/$GAME_NAME" "$MUOS_USER@$MUOS_IP:$MUOS_PATH2/"

echo "=== ALL DEPLOYMENTS DONE ==="
