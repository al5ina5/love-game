#!/bin/bash

# Efficient Numbered Tileset Creator using ImageMagick
# Creates a numbered version in a single ImageMagick command

TILESET="assets/img/tileset/tileset-v1.png"
OUTPUT="tileset-v1-numbered.png"

if [ ! -f "$TILESET" ]; then
    echo "ERROR: Tileset file not found: $TILESET"
    exit 1
fi

echo "Processing tileset: $TILESET"

# Get tileset dimensions
DIMENSIONS=$(magick identify "$TILESET" | grep -o "[0-9]*x[0-9]*" | head -1)
WIDTH=$(echo $DIMENSIONS | cut -dx -f1)
HEIGHT=$(echo $DIMENSIONS | cut -dx -f2)

TILES_PER_ROW=$((WIDTH / 16))
TILES_PER_COL=$((HEIGHT / 16))

echo "Tileset: ${WIDTH}x${HEIGHT}"
echo "Grid: ${TILES_PER_ROW}x${TILES_PER_COL} tiles"
echo "Total tiles: $((TILES_PER_ROW * TILES_PER_COL))"

# Build the ImageMagick command with all draw operations
cmd="magick '$TILESET'"

tile_number=1
for ((row=0; row<TILES_PER_COL; row++)); do
    for ((col=0; col<TILES_PER_ROW; col++)); do
        x=$((col * 16 + 2))
        y=$((row * 16 + 14))  # Position at bottom of tile

        # Add draw operation for this tile number
        cmd="$cmd -fill 'rgba(0,0,0,0.8)' -draw 'rectangle $((x-1)),$((y-12)) $((x+13)),$((y+1))'"
        cmd="$cmd -fill yellow -pointsize 10 -draw \"text $x,$y '$tile_number'\""

        tile_number=$((tile_number + 1))
    done
done

# Complete the command
cmd="$cmd '$OUTPUT'"

echo "Running ImageMagick command..."
eval "$cmd"

if [ $? -eq 0 ] && [ -f "$OUTPUT" ]; then
    echo "SUCCESS: Numbered tileset saved as: $OUTPUT"
    echo ""
    echo "🎉 Open '$OUTPUT' to see your tileset with numbers!"
    echo ""
    echo "📋 ROAD TILE IDENTIFICATION GUIDE:"
    echo "Look at the numbered tiles and identify these patterns:"
    echo ""
    echo "STRAIGHT_NS = ?, STRAIGHT_EW = ?, CORNER_NE = ?, CORNER_SE = ?,"
    echo "CORNER_SW = ?, CORNER_NW = ?, T_NORTH = ?, T_EAST = ?, T_SOUTH = ?,"
    echo "T_WEST = ?, CROSS = ?, DEAD_END_N = ?, DEAD_END_E = ?, DEAD_END_S = ?, DEAD_END_W = ?"
    echo ""
    echo "Reply with the numbers you find!"
else
    echo "ERROR: Failed to create numbered tileset"
fi