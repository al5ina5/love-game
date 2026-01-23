#!/bin/bash

# Clear Numbered Tileset Creator - Higher resolution, no black overlay
# Creates a scaled-up version with clear small numbers

TILESET="assets/img/tileset/tileset-v1.png"
OUTPUT="tileset-v1-clear-numbers.png"

if [ ! -f "$TILESET" ]; then
    echo "ERROR: Tileset file not found: $TILESET"
    exit 1
fi

echo "Creating clear numbered tileset..."

# Get tileset dimensions
DIMENSIONS=$(magick identify "$TILESET" | grep -o "[0-9]*x[0-9]*" | head -1)
WIDTH=$(echo $DIMENSIONS | cut -dx -f1)
HEIGHT=$(echo $DIMENSIONS | cut -dx -f2)

TILES_PER_ROW=$((WIDTH / 16))
TILES_PER_COL=$((HEIGHT / 16))

echo "Original: ${WIDTH}x${HEIGHT}"
echo "Scaling to 3x size for better visibility..."

# Scale up the tileset 3x and then add small numbers
magick "$TILESET" \
    -scale 300% \
    "$OUTPUT"

# Now add small numbers in the corner of each tile (no background)
tile_number=1
for ((row=0; row<TILES_PER_COL; row++)); do
    for ((col=0; col<TILES_PER_ROW; col++)); do
        # Scale coordinates by 3 (since we scaled the image 3x)
        x=$((col * 16 * 3 + 2))
        y=$((row * 16 * 3 + 12))

        # Add small white number with subtle shadow for visibility
        magick "$OUTPUT" \
            -fill black -pointsize 8 -draw "text $((x+1)),$((y+1)) '$tile_number'" \
            -fill white -pointsize 8 -draw "text $x,$y '$tile_number'" \
            "$OUTPUT"

        tile_number=$((tile_number + 1))
    done
done

if [ -f "$OUTPUT" ]; then
    FINAL_SIZE=$(magick identify "$OUTPUT" | grep -o "[0-9]*x[0-9]*" | head -1)
    echo "SUCCESS: Clear numbered tileset saved as: $OUTPUT"
    echo "Final size: $FINAL_SIZE"
    echo ""
    echo "🎯 Now you can clearly see both the tiles AND the numbers!"
    echo "📝 Find the road tile numbers and reply with them."
else
    echo "ERROR: Failed to create numbered tileset"
fi