#!/bin/bash

# Quick Tileset Viewer - Shows tile layout for manual identification

echo "🔍 LOVE GAME TILESET VIEWER"
echo "============================"
echo ""

# Get tileset info
TILESET="assets/img/tileset/tileset-v1.png"
if [ ! -f "$TILESET" ]; then
    echo "❌ ERROR: Tileset not found: $TILESET"
    exit 1
fi

# Get dimensions
DIMENSIONS=$(magick identify "$TILESET" | grep -o "[0-9]*x[0-9]*" | head -1)
WIDTH=$(echo $DIMENSIONS | cut -dx -f1)
HEIGHT=$(echo $DIMENSIONS | cut -dx -f2)

echo "📏 Tileset: $TILESET"
echo "📐 Dimensions: ${WIDTH}x${HEIGHT} pixels"
echo "🔲 Tile size: 16x16 pixels"
echo ""

TILES_PER_ROW=$((WIDTH / 16))
TILES_PER_COL=$((HEIGHT / 16))
TOTAL_TILES=$((TILES_PER_ROW * TILES_PER_COL))

echo "📊 Grid: ${TILES_PER_ROW} tiles per row × ${TILES_PER_COL} tiles per column"
echo "🔢 Total tiles: $TOTAL_TILES"
echo ""

echo "🗺️  TILE NUMBER GRID (1-based indexing):"
echo "   Left to right, top to bottom"
echo ""

tile_number=1
for ((row=1; row<=TILES_PER_COL; row++)); do
    printf "Row %2d: " $row
    for ((col=1; col<=TILES_PER_ROW; col++)); do
        printf "%3d " $tile_number
        tile_number=$((tile_number + 1))
    done
    echo ""
done

echo ""
echo "🎯 ROAD TILE IDENTIFICATION:"
echo "Open your tileset image and find tiles with these patterns:"
echo ""
echo "STRAIGHT ROADS:"
echo "├─── STRAIGHT_NS: Vertical line connecting up/down"
echo "│   └─── Look for tiles with a continuous vertical path"
echo ""
echo "─── STRAIGHT_EW: Horizontal line connecting left/right"
echo "    └─── Look for tiles with a continuous horizontal path"
echo ""
echo "CORNER PIECES:"
echo "└── CORNER_NE: Path turns from North to East (bottom-left corner)"
echo "┌── CORNER_SE: Path turns from South to East (top-left corner)"
echo "┐── CORNER_SW: Path turns from South to West (top-right corner)"
echo "┘── CORNER_NW: Path turns from North to West (bottom-right corner)"
echo ""
echo "T-JUNCTIONS (3-way connections):"
echo "├─ T_NORTH: Connected North, East, West (missing South)"
echo "┬─ T_EAST:  Connected North, South, East (missing West)"
echo "┤─ T_SOUTH: Connected South, East, West (missing North)"
echo "┴─ T_WEST:  Connected North, South, West (missing East)"
echo ""
echo "SPECIAL:"
echo "┼─ CROSS: 4-way intersection (all directions connected)"
echo "╵─ DEAD_END_N: Dead end pointing North"
echo "╶─ DEAD_END_E: Dead end pointing East"
echo "╷─ DEAD_END_S: Dead end pointing South"
echo "╴─ DEAD_END_W: Dead end pointing West"
echo ""
echo "💡 TIP: Look for tiles where the 'road' (usually a different color path)"
echo "        connects in the directions described above."
echo ""
echo "📝 HOW TO RESPOND:"
echo "Reply with your tile mappings, for example:"
echo "STRAIGHT_NS = 35, STRAIGHT_EW = 36, CORNER_NE = 37, CORNER_SE = 38..."
echo ""
echo "Then I'll configure your road generation system! 🛣️"