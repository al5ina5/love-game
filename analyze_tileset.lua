-- Analyze Tileset - Text-based tile identification
-- This script analyzes your tileset and prints a numbered grid

local function analyzeTileset()
    print("=== TILESET ANALYSIS ===")

    -- Try to load the tileset image data
    local tilesetPath = "assets/img/tileset/tileset-v1.png"

    -- For now, let's assume standard 16x16 tiles and create a reference grid
    -- In a real Love2D environment, we'd load the actual image

    print("Tileset path: " .. tilesetPath)
    print("Assuming 16x16 pixel tiles...")
    print("")

    -- Create a sample grid for a typical 256x256 tileset (16x16 tiles)
    local tilesPerRow = 16  -- This would be calculated from actual image width/16
    local tilesPerCol = 16  -- This would be calculated from actual image height/16

    print("TILE NUMBER REFERENCE GRID:")
    print("Each number represents a tile index (1-based, left to right, top to bottom)")
    print("")

    local tileNumber = 1
    for row = 1, tilesPerCol do
        local rowStr = string.format("Row %2d: ", row)
        for col = 1, tilesPerRow do
            rowStr = rowStr .. string.format("%3d ", tileNumber)
            tileNumber = tileNumber + 1
        end
        print(rowStr)
    end

    print("")
    print("TOTAL TILES: " .. ((tileNumber - 1)))
    print("")
    print("=== ROAD TILE IDENTIFICATION GUIDE ===")
    print("")
    print("Look at your tileset image and identify these road tile types:")
    print("")
    print("STRAIGHT ROADS:")
    print("- STRAIGHT_NS (North-South): Vertical straight road")
    print("- STRAIGHT_EW (East-West): Horizontal straight road")
    print("")
    print("CORNER PIECES:")
    print("- CORNER_NE: Corner connecting North and East (└ shape)")
    print("- CORNER_SE: Corner connecting South and East (┌ shape)")
    print("- CORNER_SW: Corner connecting South and West (┐ shape)")
    print("- CORNER_NW: Corner connecting North and West (┘ shape)")
    print("")
    print("T-JUNCTIONS:")
    print("- T_NORTH: T-junction open to North (missing south connection)")
    print("- T_EAST:  T-junction open to East  (missing west connection)")
    print("- T_SOUTH: T-junction open to South (missing north connection)")
    print("- T_WEST:  T-junction open to West  (missing east connection)")
    print("")
    print("SPECIAL:")
    print("- CROSS:    4-way intersection (+ shape)")
    print("- DEAD_END_N: Dead end pointing North (end of road)")
    print("- DEAD_END_E: Dead end pointing East")
    print("- DEAD_END_S: Dead end pointing South")
    print("- DEAD_END_W: Dead end pointing West")
    print("")
    print("MATERIAL VARIATIONS:")
    print("- DIRT:    Basic brown dirt paths")
    print("- STONE:   Gray formal roads")
    print("- ANCIENT: Purple/mystical roads")
    print("- BRICK:   Red/orange brick roads")
    print("")
    print("INSTRUCTIONS:")
    print("1. Open your tileset-v1.png image")
    print("2. Use the grid above to identify tile numbers")
    print("3. For each road type, note which tile number shows that pattern")
    print("4. Reply with mappings like:")
    print("   STRAIGHT_NS = 35, STRAIGHT_EW = 36, CORNER_NE = 37, etc.")
end

-- Run the analysis
analyzeTileset()