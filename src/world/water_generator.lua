-- src/world/water_generator.lua
local WaterGenerator = {}
WaterGenerator.__index = WaterGenerator

-- Tile IDs (Matching existing Road/Path Tile Setup)
-- NW=1, N=2, NE=3
-- W=4,  C=5,  E=6
-- SW=7, S=8,  SE=9
-- Inner: NW=14, NE=13, SW=11, SE=10
-- The Narnia tileset usually has specific mappings. 
-- Based on road_generator.lua:
local WATER_TILES = {
    CORNER_NW = 1,
    CORNER_NE = 3,
    CORNER_SW = 7,
    CORNER_SE = 9,
    EDGE_N = 2,
    EDGE_S = 8,
    EDGE_W = 4,
    EDGE_E = 6,
    CENTER = 5, -- Will be swapped with Water_Middle.png logic if needed, or just 5

    -- Inner Corners
    INNER_NW = 14,
    INNER_NE = 13,
    INNER_SW = 11,
    INNER_SE = 10
}

local TILE_SIZE = 16

function WaterGenerator:new(world)
    local self = setmetatable({}, WaterGenerator)
    self.world = world
    return self
end

-- Helper to check if a tile is a road
function WaterGenerator:isRoad(x, y)
    return self.world.roadGenerator:getRoadTile(x, y) ~= nil
end

-- Helper to check if a tile is water
function WaterGenerator:isWater(x, y)
    local chunkScale = self.world.chunkSize / TILE_SIZE
    local chunkX = math.floor(x / chunkScale)
    local chunkY = math.floor(y / chunkScale)
    local chunkKey = chunkX .. "," .. chunkY
    local localTileX = x % chunkScale
    local localTileY = y % chunkScale

    if self.world.water[chunkKey] and 
       self.world.water[chunkKey][localTileX] and 
       self.world.water[chunkKey][localTileX][localTileY] then
        return true
    end
    return false
end

function WaterGenerator:setWaterTile(tileX, tileY, tileID)
    local chunkScale = self.world.chunkSize / TILE_SIZE
    local chunkX = math.floor(tileX / chunkScale)
    local chunkY = math.floor(tileY / chunkScale)
    local chunkKey = chunkX .. "," .. chunkY
    local localTileX = tileX % chunkScale
    local localTileY = tileY % chunkScale

    if not self.world.water[chunkKey] then
        self.world.water[chunkKey] = {}
    end

    if not self.world.water[chunkKey][localTileX] then
        self.world.water[chunkKey][localTileX] = {}
    end

    self.world.water[chunkKey][localTileX][localTileY] = tileID
end

function WaterGenerator:getWaterTile(tileX, tileY)
    local chunkScale = self.world.chunkSize / TILE_SIZE
    local chunkX = math.floor(tileX / chunkScale)
    local chunkY = math.floor(tileY / chunkScale)
    local chunkKey = chunkX .. "," .. chunkY
    local localTileX = tileX % chunkScale
    local localTileY = tileY % chunkScale

    if not self.world.water[chunkKey] or not self.world.water[chunkKey][localTileX] then
        return nil
    end
    return self.world.water[chunkKey][localTileX][localTileY]
end

function WaterGenerator:generate(seed)
    math.randomseed(seed or os.time())
    self.world.water = {} -- Clear water

    -- 1. Identify potential seeds near roads
    -- We'll scan established road chunks. Since iterating sparse array is tricky without keys,
    -- we rely on self.world.roads structure.
    
    local potentialSeeds = {}
    
    for chunkKey, chunkData in pairs(self.world.roads) do
        local chunkX, chunkY = chunkKey:match("([^,]+),([^,]+)")
        chunkX, chunkY = tonumber(chunkX), tonumber(chunkY)
        local chunksScale = (self.world.chunkSize / TILE_SIZE)

        for localX, row in pairs(chunkData) do
            for localY, _ in pairs(row) do
                local worldX = chunkX * chunksScale + localX
                local worldY = chunkY * chunksScale + localY
                
                -- Look for a spot 2-4 tiles away
                -- Try 4 random directions per road tile to find a valid seed
                for i=1, 2 do 
                    local dx = math.random(-4, 4)
                    local dy = math.random(-4, 4)
                    
                    -- Enforce gap 2-4
                    if (math.abs(dx) >= 2 or math.abs(dy) >= 2) then
                        local targetX = worldX + dx
                        local targetY = worldY + dy
                        
                        -- Check if empty (no road, no water yet)
                        if not self:isRoad(targetX, targetY) and 
                           not self:isWater(targetX, targetY) then
                           
                           -- Spawn Protection: Avoid 2500,2500 (approx 156,156 in tiles)
                           local spawnX, spawnY = 2500, 2500
                           local distToSpawn = math.sqrt((targetX * TILE_SIZE - spawnX)^2 + (targetY * TILE_SIZE - spawnY)^2)
                           
                           if distToSpawn > 150 then
                               -- Double check distance to ANY road to ensure gap
                               local tooClose = false
                               for cx = -1, 1 do
                                   for cy = -1, 1 do
                                       if self:isRoad(targetX + cx, targetY + cy) then
                                           tooClose = true
                                           break
                                       end
                                   end
                               end
                               
                               if not tooClose then
                                   table.insert(potentialSeeds, {x = targetX, y = targetY})
                               end
                           end
                        end
                    end
                end
            end
        end
    end
    
    -- 2. Select seeds and grow
    -- Frequency: Let's pick 5% of potential seeds, but filter for distance between them
    -- to avoid merging too much (or maybe we want merging?)
    
    local waterMap = {} -- Temporary boolean map for generation
    
    local function mark(x, y)
        if not waterMap[x] then waterMap[x] = {} end
        waterMap[x][y] = true
    end
    
    local function isMarked(x, y)
        return waterMap[x] and waterMap[x][y]
    end

    print("WaterGenerator: Found " .. #potentialSeeds .. " potential seeds.")
    
    for _, seed in ipairs(potentialSeeds) do
        -- Chance to spawn a pond
        if math.random() < 0.05 then
            -- Grow pond
            local targetSize = math.random(15, 60) -- 4-10 tiles wide approx area matches this
            local currentSize = 0
            local frontier = {seed}
            local pondTiles = {} 
            
            mark(seed.x, seed.y)
            table.insert(pondTiles, seed)
            currentSize = 1
            
            while currentSize < targetSize and #frontier > 0 do
                local idx = math.random(1, #frontier)
                local current = frontier[idx]
                
                -- Try to expand
                local dirs = {{x=0,y=1}, {x=0,y=-1}, {x=1,y=0}, {x=-1,y=0}}
                local expanded = false
                
                for _, dir in ipairs(dirs) do
                    local nx, ny = current.x + dir.x, current.y + dir.y
                    
                    -- Check constraints:
                    -- 1. Not already water
                    -- 2. Not a road (strictly!)
                    -- 3. Ideally keep 1 tile buffer from road
                    
                    if not isMarked(nx, ny) then
                        local closeToRoad = false
                        for rx = -1, 1 do
                            for ry = -1, 1 do
                                if self:isRoad(nx+rx, ny+ry) then
                                    closeToRoad = true
                                    break
                                end
                            end
                        end
                        
                        if not closeToRoad then
                            mark(nx, ny)
                            table.insert(frontier, {x=nx, y=ny})
                            table.insert(pondTiles, {x=nx, y=ny})
                            currentSize = currentSize + 1
                            expanded = true
                            if currentSize >= targetSize then break end
                        end
                    end
                end
                
                if not expanded then
                    table.remove(frontier, idx)
                end
            end
        end
    end
    
    -- 2.5 Smoothing / Rounding (Cellular Automata)
    -- Reduce noise and make bodies of water more "lake-like"
    
    local function countAliveNeighbors(map, x, y)
        local count = 0
        for i = -1, 1 do
            for j = -1, 1 do
                if not (i == 0 and j == 0) then
                    if map[x+i] and map[x+i][y+j] then
                        count = count + 1
                    end
                end
            end
        end
        return count
    end
    
    -- Determine bounds for smoothing to avoid iterating the whole world
    local minX, maxX, minY, maxY = 999999, -999999, 999999, -999999
    local hasWater = false
    for x, row in pairs(waterMap) do
        for y, _ in pairs(row) do
            if x < minX then minX = x end
            if x > maxX then maxX = x end
            if y < minY then minY = y end
            if y > maxY then maxY = y end
            hasWater = true
        end
    end
    
    if hasWater then
        -- Add padding for expansion
        minX, maxX = minX - 2, maxX + 2
        minY, maxY = minY - 2, maxY + 2
        
        local smoothingIterations = 4 -- Increase iterations for rounder lakes
        for i = 1, smoothingIterations do
            local newMap = {}
            for x, row in pairs(waterMap) do
                 newMap[x] = {}
                 for y, val in pairs(row) do
                     newMap[x][y] = val
                 end
            end
            
            for x = minX, maxX do
                for y = minY, maxY do
                    local nbs = countAliveNeighbors(waterMap, x, y)
                    local isAlive = waterMap[x] and waterMap[x][y]
                    
                    if isAlive then
                        -- Death rule: if too sparse, die (removes thin snakey lines)
                        if nbs < 4 then -- Stricter death rule (was 3) to kill thin edges faster
                            if not newMap[x] then newMap[x] = {} end
                            newMap[x][y] = nil
                        end
                    else
                        -- Birth rule: if crowded, be born (fills gaps, roundness)
                        if nbs >= 5 then
                            -- Check constraints (no road)
                            local roadSafe = true
                            if self:isRoad(x, y) then roadSafe = false end
                            -- Extra buffer from road check?
                             if roadSafe then
                                for rx = -1, 1 do
                                    for ry = -1, 1 do
                                        if self:isRoad(x+rx, y+ry) then
                                            roadSafe = false -- Stay away from roads
                                            break
                                        end
                                    end
                                    if not roadSafe then break end
                                end
                            end
                            
                            if roadSafe then
                                if not newMap[x] then newMap[x] = {} end
                                newMap[x][y] = true
                            end
                        end
                    end
                end
            end
            waterMap = newMap
        end
    end
    for x, col in pairs(waterMap) do
        for y, _ in pairs(col) do
            local n = isMarked(x, y - 1) and 1 or 0
            local w = isMarked(x - 1, y) and 1 or 0
            local e = isMarked(x + 1, y) and 1 or 0
            local s = isMarked(x, y + 1) and 1 or 0
            
            local mask = (n * 1) + (w * 2) + (e * 4) + (s * 8)
            
            local tileID = nil -- Default to nil, effectively removing invalid shapes
            
            if mask == 12 then tileID = WATER_TILES.CORNER_NW
            elseif mask == 10 then tileID = WATER_TILES.CORNER_NE
            elseif mask == 5 then tileID = WATER_TILES.CORNER_SW
            elseif mask == 3 then tileID = WATER_TILES.CORNER_SE
            elseif mask == 14 then tileID = WATER_TILES.EDGE_N
            elseif mask == 7 then tileID = WATER_TILES.EDGE_S
            elseif mask == 11 then tileID = WATER_TILES.EDGE_E
            elseif mask == 13 then tileID = WATER_TILES.EDGE_W
            elseif mask == 15 then 
                -- Inner corners check
                local ne = isMarked(x + 1, y - 1)
                local nw = isMarked(x - 1, y - 1)
                local se = isMarked(x + 1, y + 1)
                local sw = isMarked(x - 1, y + 1)
                
                if not ne then tileID = WATER_TILES.INNER_NE
                elseif not nw then tileID = WATER_TILES.INNER_NW
                elseif not se then tileID = WATER_TILES.INNER_SE
                elseif not sw then tileID = WATER_TILES.INNER_SW
                else tileID = WATER_TILES.CENTER
                end
            end
            
            if tileID then
                self:setWaterTile(x, y, tileID)
            end
        end
    end
    
    local count = 0
    for k,v in pairs(self.world.water) do
        for k2, v2 in pairs(v) do
            for k3, v3 in pairs(v2) do count = count + 1 end
        end
    end
    print("WaterGenerator: Created " .. count .. " water tiles.")
end

return WaterGenerator
