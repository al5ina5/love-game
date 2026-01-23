-- Simple dirt donut generator for testing curves
-- Creates a ring of dirt with grass in the center

-- Tile mappings from road_tile_mappings.txt
local TILES = {
    DIRT = 130,        -- Full dirt center
    CORNER_NE = 108,   -- Grass TOP+RIGHT
    CORNER_SE = 144,   -- Grass BOTTOM+RIGHT
    CORNER_SW = 141,   -- Grass BOTTOM+LEFT
    CORNER_NW = 105,   -- Grass TOP+LEFT
    DEAD_END_N = 107, -- Grass TOP+LEFT+RIGHT
    DEAD_END_E = 132, -- Grass RIGHT+TOP+BOTTOM
    DEAD_END_S = 142, -- Grass BOTTOM+LEFT+RIGHT
    DEAD_END_W = 117, -- Grass LEFT+TOP+BOTTOM
}

-- Function to generate a dirt donut (3-thick ring of dirt with grass center)
function generate_dirt_donut()
    local donut = {}

    -- Top outer edge
    table.insert(donut, {0, 0, TILES.CORNER_NW, TILES.DEAD_END_N, TILES.DEAD_END_N, TILES.DEAD_END_N, TILES.CORNER_NE, 0, 0})

    -- Upper dirt ring (3 thick)
    table.insert(donut, {0, TILES.CORNER_NW, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, TILES.CORNER_NE, 0})
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, 0})
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, 0})

    -- Center area: 3x3 grass with proper dirt transitions
    -- Top of grass center (grass on BOTTOM)
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.CORNER_SE, TILES.DEAD_END_N, TILES.DEAD_END_N, TILES.DEAD_END_N, TILES.CORNER_SW, TILES.DEAD_END_E, 0})
    -- Sides of grass center (grass on LEFT/RIGHT)
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DEAD_END_E, 0, 0, 0, TILES.DEAD_END_W, TILES.DEAD_END_E, 0})
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DEAD_END_E, 0, 0, 0, TILES.DEAD_END_W, TILES.DEAD_END_E, 0})
    -- Bottom of grass center (grass on TOP)
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.CORNER_NE, TILES.DEAD_END_S, TILES.DEAD_END_S, TILES.DEAD_END_S, TILES.CORNER_NW, TILES.DEAD_END_E, 0})

    -- Lower dirt ring (3 thick)
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, 0})
    table.insert(donut, {0, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, 0})
    table.insert(donut, {0, TILES.CORNER_SW, TILES.DEAD_END_W, TILES.DIRT, TILES.DIRT, TILES.DIRT, TILES.DEAD_END_E, TILES.CORNER_SE, 0})

    -- Bottom outer edge
    table.insert(donut, {0, 0, TILES.CORNER_SW, TILES.DEAD_END_S, TILES.DEAD_END_S, TILES.DEAD_END_S, TILES.CORNER_SE, 0, 0})

    return donut
end

-- Function to print donut to console and save to file
function print_and_save_donut(donut, filename)
    local file = io.open(filename, "w")

    print("Generated Dirt Donut:")
    print("====================")

    for y, row in ipairs(donut) do
        local line = ""
        for x, tile in ipairs(row) do
            line = line .. string.format("%3d ", tile)
        end
        print(line)
        file:write(line .. "\n")
    end

    file:close()
    print("\nSaved to: " .. filename)
end

-- Generate the dirt donut
local donut = generate_dirt_donut()
print_and_save_donut(donut, "test_dirt_donut.txt")