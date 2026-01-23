-- src/world/road_generator.lua
-- Procedural Road Generation with 3-thick roads and transition tiles
-- Replaces previous road generation logic

local RoadGenerator = {}
RoadGenerator.__index = RoadGenerator

-- Road tile IDs (from 3x3 Perfect Square pattern)
-- Narnia Tileset Mapping (3x6 Grid)
-- Row 0: NW(0), N(1), NE(2)
-- Row 1: W(3),  C(4),  E(5)
-- Row 2: SW(6), S(7), SE(8)
-- Row 3: InnerNW(9), InnerNE(10), InnerSW(11)? Or maybe 9,10,11 is row 3...
-- Let's try:
-- INNER_SE = 9 (Top Left of Row 3? No, Inner Corner is usually opposite to outer corner).
-- If tile at (0,3) looks like Grass with Bottom-Right Dirt, it is used for Inner NW road niche.
-- Let's enable the inner corner logic with these IDs.

-- Narnia Tileset Mapping (User Provided)
-- 1-based indices
-- NW=1, N=2, NE=3
-- W=4,  C=5,  E=6
-- SW=7, S=8,  SE=9
-- Inner: NW=10, NE=11, SW=13, SE=14

local ROAD_TILES = {
    CORNER_NW = 1,
    CORNER_NE = 3,
    CORNER_SW = 7,
    CORNER_SE = 9,
    EDGE_N = 2,
    EDGE_S = 8,
    EDGE_W = 4,
    EDGE_E = 6,
    CENTER = 5,

    -- Inner Corners (Corrected Mapping)
    INNER_NW = 14,
    INNER_NE = 13,
    INNER_SW = 11,
    INNER_SE = 10
}

local TILE_SIZE = 16
local ROAD_THICKNESS = 4 -- Radius. 1 = 3x3 brush (Center + 1 neighbor each side)

-- Reduce road thickness on Miyoo for performance
local function getRoadThickness()
    local Constants = require('src.constants')
    return Constants.MIYOO_DEVICE and 2 or ROAD_THICKNESS  -- Miyoo: thinner roads (5x5), Desktop: thick roads (9x9)
end

function RoadGenerator:new(world)
    local self = setmetatable({}, RoadGenerator)
    self.world = world
    return self
end

-- --- Helper: Distance ---
local function dist(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

-- --- Pathfinding (A*) ---
-- Returns a list of {x, y} tiles
function RoadGenerator:findPath(startX, startY, endX, endY)
    local start = {x = startX, y = startY}
    local goal = {x = endX, y = endY}
    
    -- Heuristic: Euclidean distance (favors straight lines implies diagonal movement?)
    -- Manhattan favors L-shapes. Euclidean favors diagonals if allowed.
    -- We'll use Manhattan for a grid-like feel, or Euclidean for organic.
    -- Let's use Euclidean to get direct paths, but we move in grid steps.
    local function heuristic(a, b)
        return math.abs(a.x - b.x) + math.abs(a.y - b.y)
    end

    local frontier = {}
    local cameFrom = {}
    local costSoFar = {}

    local function push(queue, item, priority)
        local low = 1
        local high = #queue
        local pos = #queue + 1
        
        while low <= high do
            local mid = math.floor((low + high) / 2)
            if queue[mid].priority > priority then
                pos = mid
                high = mid - 1
            else
                low = mid + 1
            end
        end
        table.insert(queue, pos, {item = item, priority = priority})
    end

    local function pop(queue)
        return table.remove(queue, 1)
    end

    push(frontier, start, 0)
    local startKey = start.x .. "," .. start.y
    cameFrom[startKey] = nil
    costSoFar[startKey] = 0

    local count = 0
    local maxIter = 5000 -- Safety break

    while #frontier > 0 and count < maxIter do
        count = count + 1
        local current = pop(frontier).item
        
        if current.x == goal.x and current.y == goal.y then
            break
        end

        local directions = {
            {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0}
        }

        for _, dir in ipairs(directions) do
            local next = {x = current.x + dir.x, y = current.y + dir.y}
            
            -- Bounds check (rough, world is huge, but we can limit to bounding box of start/end + margin)
            if next.x >= 0 and next.y >= 0 and 
               next.x < self.world.worldWidth/TILE_SIZE and next.y < self.world.worldHeight/TILE_SIZE then
                
                local newCost = costSoFar[current.x .. "," .. current.y] + 1
                local nextKey = next.x .. "," .. next.y
                
                if not costSoFar[nextKey] or newCost < costSoFar[nextKey] then
                    costSoFar[nextKey] = newCost
                    local priority = newCost + heuristic(goal, next)
                    push(frontier, next, priority)
                    cameFrom[nextKey] = current
                end
            end
        end
    end

    -- Reconstruct
    local current = goal
    local path = {}
    local key = current.x .. "," .. current.y
    
    if not cameFrom[key] and (start.x ~= goal.x or start.y ~= goal.y) then
        return nil -- No path
    end

    while current do
        table.insert(path, 1, current)
        key = current.x .. "," .. current.y
        current = cameFrom[key]
        if current and current.x == start.x and current.y == start.y then
             table.insert(path, 1, current)
             break
        end
    end

    return path
end

-- --- Main Generation ---
function RoadGenerator:generateRoadNetwork(pointsOfInterest, seed)
    if not pointsOfInterest or #pointsOfInterest == 0 then return end
    
    math.randomseed(seed or 12345)
    self.world.roads = {} -- Clear roads
    
    -- Temporary Grid to mark "Road Candidates" (1) vs Empty (nil)
    -- Using a sparse table: map[x][y] = true
    local roadMap = {}
    
    local function mark(x, y)
        if not roadMap[x] then roadMap[x] = {} end
        roadMap[x][y] = true
    end
    
    local function isMarked(x, y)
        return roadMap[x] and roadMap[x][y]
    end

    -- 1. Connect Points and Draw Thick Lines
    -- Sort points by priority or just chain them
    -- Let's Connect 1 -> 2 -> 3 ... -> N
    -- Also maybe connect some random pairs to make loops?
    -- Current logic just chains.
    
    local keyPoints = {}
    for _, p in ipairs(pointsOfInterest) do
        table.insert(keyPoints, {
            x = math.floor(p.x / TILE_SIZE),
            y = math.floor(p.y / TILE_SIZE)
        })
    end

    -- Create Minimum Spanning Tree or Simple Chain?
    -- Simple Chain is easiest and ensures connectivity.
    for i = 1, #keyPoints - 1 do
        local p1 = keyPoints[i]
        local p2 = keyPoints[i+1]
        
        local path = self:findPath(p1.x, p1.y, p2.x, p2.y)
        if path then
            local thickness = getRoadThickness()
            for _, node in ipairs(path) do
                -- "Thicken" the road: Brush of size based on device
                -- Range: -thickness to +thickness
                for dy = -thickness, thickness do
                    for dx = -thickness, thickness do
                        mark(node.x + dx, node.y + dy)
                    end
                end
            end
        end
    end

    -- 2. Bitmasking / Tile Selection
    -- Iterate all marked tiles and decide their ID
    for x, col in pairs(roadMap) do
        for y, _ in pairs(col) do
            local n = isMarked(x, y - 1) and 1 or 0
            local w = isMarked(x - 1, y) and 1 or 0
            local e = isMarked(x + 1, y) and 1 or 0
            local s = isMarked(x, y + 1) and 1 or 0
            
            local mask = (n * 1) + (w * 2) + (e * 4) + (s * 8)
            
            -- Default to CENTER
            local tileID = ROAD_TILES.CENTER 
            
            -- Map Mask to IDs
            if mask == 12 then tileID = ROAD_TILES.CORNER_NW      -- N=0, W=0, E=1, S=1
            elseif mask == 10 then tileID = ROAD_TILES.CORNER_NE  -- N=0, W=1, E=0, S=1
            elseif mask == 5 then tileID = ROAD_TILES.CORNER_SW   -- N=1, W=0, E=1, S=0
            elseif mask == 3 then tileID = ROAD_TILES.CORNER_SE   -- N=1, W=1, E=0, S=0
            elseif mask == 14 then tileID = ROAD_TILES.EDGE_N     -- N=0, others=1
            elseif mask == 7 then tileID = ROAD_TILES.EDGE_S      -- S=0, others=1
            elseif mask == 11 then tileID = ROAD_TILES.EDGE_E     -- E=0, others=1
            elseif mask == 13 then tileID = ROAD_TILES.EDGE_W     -- W=0, others=1
            elseif mask == 15 then 
                -- Full surround. Check for Inner Corners (diagonals)
                local ne = isMarked(x + 1, y - 1)
                local nw = isMarked(x - 1, y - 1)
                local se = isMarked(x + 1, y + 1)
                local sw = isMarked(x - 1, y + 1)
                
                -- Priority to inner corners if a diagonal is missing
                if not ne then tileID = ROAD_TILES.INNER_NE
                elseif not nw then tileID = ROAD_TILES.INNER_NW
                elseif not se then tileID = ROAD_TILES.INNER_SE
                elseif not sw then tileID = ROAD_TILES.INNER_SW
                else tileID = ROAD_TILES.CENTER
                end
            end
            
            -- Fallback for single-width lines (Optional refinement)
            -- If mask is 6 (W+E) -> Horizontal Line. Use Top/Bottom Edge? 
            -- Given thickness 3, this is rare, but let's handle isolated bits if needed.
            
            self:setRoadTile(x, y, tileID)
        end
    end

    -- 3. Removed old Decorate Inner Corners logic as it is now integrated into the bitmask pass
    
    -- Count
    
    -- Count
    local count = 0
    for k,v in pairs(self.world.roads) do
        for k2, v2 in pairs(v) do
            for k3, v3 in pairs(v2) do count = count + 1 end
        end
    end
    print("New Road Generator: Created " .. count .. " road tiles.")
end

-- Helper to set tile in world sparse array
function RoadGenerator:setRoadTile(tileX, tileY, tileID)
    -- Cache calculations
    local chunkScale = self.world.chunkSize / TILE_SIZE
    local chunkX = math.floor(tileX / chunkScale)
    local chunkY = math.floor(tileY / chunkScale)
    local chunkKey = chunkX .. "," .. chunkY
    local localTileX = tileX % chunkScale
    local localTileY = tileY % chunkScale

    if not self.world.roads[chunkKey] then
        self.world.roads[chunkKey] = {}
    end

    if not self.world.roads[chunkKey][localTileX] then
        self.world.roads[chunkKey][localTileX] = {}
    end

    self.world.roads[chunkKey][localTileX][localTileY] = tileID
end

function RoadGenerator:getRoadTile(tileX, tileY)
    -- Cache calculations
    local chunkScale = self.world.chunkSize / TILE_SIZE
    local chunkX = math.floor(tileX / chunkScale)
    local chunkY = math.floor(tileY / chunkScale)
    local chunkKey = chunkX .. "," .. chunkY
    local localTileX = tileX % chunkScale
    local localTileY = tileY % chunkScale

    if not self.world.roads[chunkKey] or not self.world.roads[chunkKey][localTileX] then
        return nil
    end
    return self.world.roads[chunkKey][localTileX][localTileY]
end

return RoadGenerator