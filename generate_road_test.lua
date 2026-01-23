-- Simple horizontal road generator for testing
-- Generates a 3-high horizontal road with proper edges and corners

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

-- Function to generate a horizontal road (3 dirt thick)
function generate_horizontal_road(length)
    local road = {}

    -- Top row (grass on top)
    local top_row = {0} -- Start with left grass
    table.insert(top_row, TILES.CORNER_NW) -- NW corner

    -- Add dead ends for the middle
    for i = 1, length - 2 do
        table.insert(top_row, TILES.DEAD_END_N) -- North dead end (grass on TOP)
    end

    table.insert(top_row, TILES.CORNER_NE) -- NE corner
    table.insert(top_row, 0) -- Right grass
    table.insert(road, top_row)

    -- Middle rows (3 rows of full dirt)
    for row = 1, 3 do
        local middle_row = {0} -- Start with left grass
        table.insert(middle_row, TILES.DEAD_END_W) -- West dead end (grass on LEFT)

        -- Add dirt for the middle
        for i = 1, length - 2 do
            table.insert(middle_row, TILES.DIRT) -- Full dirt
        end

        table.insert(middle_row, TILES.DEAD_END_E) -- East dead end (grass on RIGHT)
        table.insert(middle_row, 0) -- Right grass
        table.insert(road, middle_row)
    end

    -- Bottom row (grass on bottom)
    local bottom_row = {0} -- Start with left grass
    table.insert(bottom_row, TILES.CORNER_SW) -- SW corner

    -- Add dead ends for the middle
    for i = 1, length - 2 do
        table.insert(bottom_row, TILES.DEAD_END_S) -- South dead end (grass on BOTTOM)
    end

    table.insert(bottom_row, TILES.CORNER_SE) -- SE corner
    table.insert(bottom_row, 0) -- Right grass
    table.insert(road, bottom_row)

    return road
end

-- Function to print road to console and save to file
function print_and_save_road(road, filename)
    local file = io.open(filename, "w")

    print("Generated Horizontal Road:")
    print("=========================")

    for y, row in ipairs(road) do
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

-- Generate a 7-tile wide road (plus 2 grass padding on each side = 11 total width)
local road = generate_horizontal_road(7)
print_and_save_road(road, "test_horizontal_road.txt")