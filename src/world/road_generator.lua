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

    -- Inner Corners (Inverse)
    INNER_NW = 10,
    INNER_NE = 11,
    INNER_SW = 13,
    INNER_SE = 14
}

local TILE_SIZE = 16
local ROAD_THICKNESS = 3 -- Radius. 1 = 3x3 brush (Center + 1 neighbor each side)

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
        table.insert(queue, {item = item, priority = priority})
        table.sort(queue, function(a, b) return a.priority < b.priority end) -- Low priority first
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
            for _, node in ipairs(path) do
                -- "Thicken" the road: Brush of size ROAD_THICKNESS
                -- Range: -1 to +1 (3x3)
                for dy = -ROAD_THICKNESS, ROAD_THICKNESS do
                    for dx = -ROAD_THICKNESS, ROAD_THICKNESS do
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
            local n = isMarked(x, y - 1)
            local s = isMarked(x, y + 1)
            local e = isMarked(x + 1, y)
            local w = isMarked(x - 1, y)
            
            -- Logic for 3x3 Perfect Square transitions
            -- Prioritize Corners first, then Edges
            
            local tileID = ROAD_TILES.CENTER
            
            if not n and not w then
                tileID = ROAD_TILES.CORNER_NW -- 105
            elseif not n and not e then
                tileID = ROAD_TILES.CORNER_NE -- 108
            elseif not s and not w then
                tileID = ROAD_TILES.CORNER_SW -- 141
            elseif not s and not e then
                tileID = ROAD_TILES.CORNER_SE -- 144
            elseif not n then
                tileID = ROAD_TILES.EDGE_N -- 107
            elseif not s then
                tileID = ROAD_TILES.EDGE_S -- 142
            elseif not w then
                tileID = ROAD_TILES.EDGE_W -- 117
            elseif not e then
                tileID = ROAD_TILES.EDGE_E -- 132
            else
                tileID = ROAD_TILES.CENTER -- 130
            end
            
            self:setRoadTile(x, y, tileID)
        end
    end

    -- 3. Decorate Inner Corners (Concave)
    -- Iterate the roadMap again (or just neighbors of road tiles) to find empty spots that should be corners
    -- We need to check neighbors of road tiles: if a neighbor is empty but has 2 road neighbors forming an L...
    local innerCorners = {}
    
    for x, col in pairs(roadMap) do
        for y, _ in pairs(col) do
            -- Check 4 diagonal neighbors if they are empty
            local diagonals = {
                {dx = -1, dy = -1}, {dx = 1, dy = -1}, {dx = -1, dy = 1}, {dx = 1, dy = 1}
            }
            
            for _, d in ipairs(diagonals) do
                local nx, ny = x + d.dx, y + d.dy
                if not isMarked(nx, ny) then
                    -- This neighbor is Empty (Grass). Should it be an Inner Corner?
                    -- Check IT'S neighbors.
                    -- If we successfully identify it, add to list (don't modify roadMap while iterating)
                    
                    local n = isMarked(nx, ny - 1)
                    local s = isMarked(nx, ny + 1)
                    local e = isMarked(nx + 1, ny)
                    local w = isMarked(nx - 1, ny)
                    
                    if w and n then
                        -- Inner NW Niche (Neighbors West and North are Road). We need Dirt TL.
                        innerCorners[nx .. "," .. ny] = {x = nx, y = ny, id = ROAD_TILES.INNER_NW}
                    elseif e and n then
                         -- Inner NE Niche (Neighbors East and North). We need Dirt TR.
                        innerCorners[nx .. "," .. ny] = {x = nx, y = ny, id = ROAD_TILES.INNER_NE}
                    elseif w and s then
                        -- Inner SW Niche (Neighbors West and South). We need Dirt BL.
                        innerCorners[nx .. "," .. ny] = {x = nx, y = ny, id = ROAD_TILES.INNER_SW}
                    elseif e and s then
                        -- Inner SE Niche (Neighbors East and South). We need Dirt BR.
                        innerCorners[nx .. "," .. ny] = {x = nx, y = ny, id = ROAD_TILES.INNER_SE}
                    end
                end
            end
        end
    end
    
    -- Apply Inner Corners
    for _, item in pairs(innerCorners) do
        self:setRoadTile(item.x, item.y, item.id)
    end
    
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
    local chunkKey = math.floor(tileX / (self.world.chunkSize / TILE_SIZE)) .. "," .. math.floor(tileY / (self.world.chunkSize / TILE_SIZE))
    local localTileX = tileX % (self.world.chunkSize / TILE_SIZE)
    local localTileY = tileY % (self.world.chunkSize / TILE_SIZE)

    if not self.world.roads[chunkKey] then
        self.world.roads[chunkKey] = {}
    end

    if not self.world.roads[chunkKey][localTileX] then
        self.world.roads[chunkKey][localTileX] = {}
    end

    self.world.roads[chunkKey][localTileX][localTileY] = tileID
end

function RoadGenerator:getRoadTile(tileX, tileY)
     local chunkKey = math.floor(tileX / (self.world.chunkSize / TILE_SIZE)) .. "," .. math.floor(tileY / (self.world.chunkSize / TILE_SIZE))
    local localTileX = tileX % (self.world.chunkSize / TILE_SIZE)
    local localTileY = tileY % (self.world.chunkSize / TILE_SIZE)

    if not self.world.roads[chunkKey] or not self.world.roads[chunkKey][localTileX] then
        return nil
    end
    return self.world.roads[chunkKey][localTileX][localTileY]
end

return RoadGenerator