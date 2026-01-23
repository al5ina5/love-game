#!/bin/bash

# Simple Numbered Tileset - Scale up and add small numbers without background

TILESET="assets/img/tileset/tileset-v1.png"
OUTPUT="tileset-v1-simple-numbers.png"

if [ ! -f "$TILESET" ]; then
    echo "ERROR: Tileset file not found: $TILESET"
    exit 1
fi

echo "Creating simple numbered tileset..."

# Get dimensions
DIMENSIONS=$(magick identify "$TILESET" | grep -o "[0-9]*x[0-9]*" | head -1)
WIDTH=$(echo $DIMENSIONS | cut -dx -f1)
HEIGHT=$(echo $DIMENSIONS | cut -dx -f2)
TILES_PER_ROW=$((WIDTH / 16))
TILES_PER_COL=$((HEIGHT / 16))

echo "Original: ${WIDTH}x${HEIGHT}"
echo "Scaling to 2x for better visibility..."

# Build single command with all draw operations
cmd="magick '$TILESET' -scale 200%"

tile_number=1
for ((row=0; row<TILES_PER_COL; row++)); do
    for ((col=0; col<TILES_PER_ROW; col++)); do
        # Scale coordinates by 2 (since we scaled 200%)
        x=$((col * 16 * 2 + 4))
        y=$((row * 16 * 2 + 14))

        # Add small white number (no background)
        cmd="$cmd -fill white -pointsize 12 -draw \"text $x,$y '$tile_number'\""

        tile_number=$((tile_number + 1))
    done
done

cmd="$cmd '$OUTPUT'"

echo "Running ImageMagick command..."
eval "$cmd"

if [ $? -eq 0 ] && [ -f "$OUTPUT" ]; then
    FINAL_SIZE=$(magick identify "$OUTPUT" | grep -o "[0-9]*x[0-9]*" | head -1)
    echo "SUCCESS: Simple numbered tileset saved as: $OUTPUT"
    echo "Final size: $FINAL_SIZE"
    echo ""
    echo "🎯 Now you can see the tiles clearly with small white numbers!"
    echo "📝 Find your road tile numbers and reply with them."
else
    echo "ERROR: Failed to create numbered tileset"
fi