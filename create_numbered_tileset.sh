#!/bin/bash

# Create Numbered Tileset using ImageMagick
# This script overlays tile numbers on your tileset for easy identification

TILESET="assets/img/tileset/tileset-v1.png"
OUTPUT="tileset-v1-numbered.png"

if [ ! -f "$TILESET" ]; then
    echo "ERROR: Tileset file not found: $TILESET"
    exit 1
fi

echo "Processing tileset: $TILESET"

# Get image dimensions
DIMENSIONS=$(convert "$TILESET" -format "%wx%h" info:)
echo "Tileset dimensions: $DIMENSIONS"

# Assuming 16x16 tiles, calculate grid
TILE_SIZE=16
WIDTH=$(echo $DIMENSIONS | cut -dx -f1)
HEIGHT=$(echo $DIMENSIONS | cut -dx -f2)
TILES_PER_ROW=$((WIDTH / TILE_SIZE))
TILES_PER_COL=$((HEIGHT / TILE_SIZE))

echo "Tiles per row: $TILES_PER_ROW, Tiles per column: $TILES_PER_COL"
echo "Total tiles: $((TILES_PER_ROW * TILES_PER_COL))"

# Start with the original tileset
cp "$TILESET" "$OUTPUT"

# Add numbers to each tile
tile_number=1
for ((row=0; row<TILES_PER_COL; row++)); do
    for ((col=0; col<TILES_PER_ROW; col++)); do
        x=$((col * TILE_SIZE + 2))
        y=$((row * TILE_SIZE + 2))

        # Add semi-transparent background and number
        convert "$OUTPUT" \
            -fill "rgba(0,0,0,0.8)" \
            -draw "rectangle $((x-1)),$((y-1)) $((x+13)),$((y+11))" \
            -fill yellow \
            -pointsize 12 \
            -font "DejaVu-Sans-Bold" \
            -draw "text $x,$((y+10)) '$tile_number'" \
            "$OUTPUT"

        tile_number=$((tile_number + 1))
    done
done

echo "SUCCESS: Numbered tileset saved as: $OUTPUT"
echo ""
echo "🎯 ROAD TILE IDENTIFICATION GUIDE:"
echo ""
echo "Open '$OUTPUT' and identify these road patterns:"
echo ""
echo "STRAIGHT ROADS:"
echo "• STRAIGHT_NS (North-South): Vertical straight road"
echo "• STRAIGHT_EW (East-West): Horizontal straight road"
echo ""
echo "CORNER PIECES:"
echo "• CORNER_NE: Corner connecting North and East (└ shape)"
echo "• CORNER_SE: Corner connecting South and East (┌ shape)"
echo "• CORNER_SW: Corner connecting South and West (┐ shape)"
echo "• CORNER_NW: Corner connecting North and West (┘ shape)"
echo ""
echo "T-JUNCTIONS:"
echo "• T_NORTH: T-junction open to North (missing south connection)"
echo "• T_EAST:  T-junction open to East  (missing west connection)"
echo "• T_SOUTH: T-junction open to South (missing north connection)"
echo "• T_WEST:  T-junction open to West  (missing east connection)"
echo ""
echo "SPECIAL:"
echo "• CROSS:    4-way intersection (+ shape)"
echo "• DEAD_END_N/E/S/W: Dead ends pointing in each direction"
echo ""
echo "📝 Reply with mappings like:"
echo "STRAIGHT_NS = 35, STRAIGHT_EW = 36, CORNER_NE = 37, etc."