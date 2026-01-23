-- src/world/world_cache.lua
-- Client-side world data cache for MIYO performance optimization
-- Downloads complete world data upfront and caches it for fast access

local Constants = require('src.constants')
local dkjson = require('src.lib.dkjson')

local WorldCache = {}
WorldCache.__index = WorldCache

function WorldCache:new()
    local self = setmetatable({}, WorldCache)

    self.worldData = nil
    self.isLoaded = false
    self.loadProgress = 0
    self.loadMessage = "Preparing..."

    -- Spatial index for fast object lookups (will be populated after loading)
    self.spatialIndex = {
        trees = {},
        rocks = {},
        npcs = {},
        animals = {}
    }

    return self
end

-- Download complete world data from server
function WorldCache:downloadWorldData()
    self.loadProgress = 0
    self.loadMessage = "Connecting to server..."

    -- Get API URL
    local apiUrl = Constants.API_BASE_URL .. "/api/world-data"

    -- Create HTTP request with timeout for MIYO
    local timeout = Constants.MIYOO_DEVICE and 10 or 30  -- MIYO: 10 seconds, Desktop: 30 seconds
    local startTime = love.timer.getTime()
    local http = require('src.net.simple_http')

    -- For MIYO, try a simpler approach first
    local success
    local httpSuccess, responseData
    if Constants.MIYOO_DEVICE then
        success, httpSuccess, responseData = pcall(function()
            -- Try with shorter timeout
            return http.get(apiUrl, timeout)
        end)
    else
        success, httpSuccess, responseData = pcall(function()
            return http.get(apiUrl)
        end)
    end

    local downloadTime = love.timer.getTime() - startTime

    -- Check for timeout
    if downloadTime > timeout then
        return false
    end

    if not success then
        print("ERROR: Failed to download world data: " .. tostring(httpSuccess))
        return false
    end

    if not httpSuccess then
        print("ERROR: HTTP request failed: " .. tostring(responseData))
        return false
    end

    if not responseData then
        print("ERROR: No response data from server")
        return false
    end

        -- Show first few keys
        local keys = {}
        for k, v in pairs(responseData) do
            table.insert(keys, tostring(k))
            if #keys >= 5 then break end
        end
    -- For table responses, count keys (SimpleHTTP already decoded JSON)
    local responseSize = 0
    if type(responseData) == "table" then
        for k, v in pairs(responseData) do responseSize = responseSize + 1 end
    else
        responseSize = #responseData
    end

    self.loadProgress = 0.3
    self.loadMessage = "Processing world data..."

    -- SimpleHTTP already parsed the JSON, so responseData is ready to use
    -- But we still need to validate it's the expected structure
    if type(responseData) ~= "table" then
        print("ERROR: Expected table response from server, got " .. type(responseData))
        return false
    end

    print("WorldCache: JSON already parsed by SimpleHTTP")

    self.loadProgress = 0.5
    self.loadMessage = "Processing world data..."

    -- Store the world data
    self.worldData = responseData
    self.isLoaded = true

    -- Log world data stats before spatial indexing
    local chunkCount = self:getChunkCount()
    local npcCount = self.worldData.npcs and #self.worldData.npcs or 0
    local animalCount = self.worldData.animals and #self.worldData.animals or 0

    -- Check memory usage before spatial indexing
    local memBefore = collectgarbage("count")

    self.loadProgress = 0.7
    self.loadMessage = "Building spatial index..."

    -- Build spatial index for fast lookups
    local indexStart = love.timer.getTime()
    self:buildSpatialIndex()
    local indexTime = love.timer.getTime() - indexStart

    -- Check memory usage after spatial indexing
    local memAfter = collectgarbage("count")

    self.loadProgress = 1.0
    self.loadMessage = "World ready!"

    local totalTime = love.timer.getTime() - startTime

    return true
end

-- Build spatial index for fast object lookups by position
function WorldCache:buildSpatialIndex()
    -- Reset spatial index
    self.spatialIndex = {
        trees = {},
        rocks = {},
        npcs = {},
        animals = {}
    }

    -- Index NPCs (global entities)
    local npcCount = 0
    if self.worldData.npcs then
        for _, npc in ipairs(self.worldData.npcs) do
            local key = self:getSpatialKey(npc.x, npc.y)
            if not self.spatialIndex.npcs[key] then
                self.spatialIndex.npcs[key] = {}
            end
            table.insert(self.spatialIndex.npcs[key], npc)
            npcCount = npcCount + 1
        end
    end

    -- Index animals (global entities)
    local animalCount = 0
    if self.worldData.animals then
        for _, animal in ipairs(self.worldData.animals) do
            local key = self:getSpatialKey(animal.x, animal.y)
            if not self.spatialIndex.animals[key] then
                self.spatialIndex.animals[key] = {}
            end
            table.insert(self.spatialIndex.animals[key], animal)
            animalCount = animalCount + 1
        end
    end

    -- Index trees and rocks from chunks
    local treeCount = 0
    local rockCount = 0
    local chunkCount = 0

    -- For MIYO devices, limit the number of objects we index to reduce memory usage
    local maxObjects = Constants.MIYOO_DEVICE and 1000 or 10000  -- MIYO: 1000 objects max, Desktop: 10000
    print(string.format("WorldCache: Object limit set to %d for %s device", maxObjects, Constants.MIYOO_DEVICE and "MIYO" or "Desktop"))
    local objectsIndexed = 0

    for chunkKey, chunkData in pairs(self.worldData.chunks) do
        chunkCount = chunkCount + 1

        -- Index trees in this chunk (with limits for MIYO)
        if chunkData.trees and objectsIndexed < maxObjects then
            for _, tree in ipairs(chunkData.trees) do
                if objectsIndexed >= maxObjects then break end

                local key = self:getSpatialKey(tree.x, tree.y)
                if not self.spatialIndex.trees[key] then
                    self.spatialIndex.trees[key] = {}
                end
                table.insert(self.spatialIndex.trees[key], tree)
                treeCount = treeCount + 1
                objectsIndexed = objectsIndexed + 1
            end
        end

        -- Index rocks in this chunk (with limits for MIYO)
        if chunkData.rocks and objectsIndexed < maxObjects then
            for _, rock in ipairs(chunkData.rocks) do
                if objectsIndexed >= maxObjects then break end

                local key = self:getSpatialKey(rock.x, rock.y)
                if not self.spatialIndex.rocks[key] then
                    self.spatialIndex.rocks[key] = {}
                end
                table.insert(self.spatialIndex.rocks[key], rock)
                rockCount = rockCount + 1
                objectsIndexed = objectsIndexed + 1
            end
        end

        -- Force garbage collection to prevent memory buildup during indexing
        collectgarbage("collect")

        -- Break early for MIYO if we've hit the object limit
        if Constants.MIYOO_DEVICE and objectsIndexed >= maxObjects then
            break
        end
    end


    -- Count spatial grid cells
    local gridCells = 0
    for _, cell in pairs(self.spatialIndex.trees) do gridCells = gridCells + 1 end
    for _, cell in pairs(self.spatialIndex.rocks) do gridCells = gridCells + 1 end
    for _, cell in pairs(self.spatialIndex.npcs) do gridCells = gridCells + 1 end
    for _, cell in pairs(self.spatialIndex.animals) do gridCells = gridCells + 1 end

    print("WorldCache: Spatial index uses " .. gridCells .. " grid cells")
end

-- Get spatial key for position (grid-based for fast lookups)
function WorldCache:getSpatialKey(x, y)
    -- Use 256x256 pixel grid for spatial indexing (balances speed vs granularity)
    local gridSize = 256
    local gridX = math.floor(x / gridSize)
    local gridY = math.floor(y / gridSize)
    return string.format("%d,%d", gridX, gridY)
end

-- Get chunk data by coordinates
function WorldCache:getChunk(cx, cy)
    if not self.isLoaded then return nil end

    local chunkKey = string.format("%d,%d", cx, cy)
    return self.worldData.chunks[chunkKey]
end

-- Get objects near a position using spatial index
function WorldCache:getNearbyObjects(objectType, centerX, centerY, radius)
    if not self.isLoaded then return {} end

    local objects = {}

    -- Get all grid cells that could contain objects within radius
    local gridSize = 256
    local minGridX = math.floor((centerX - radius) / gridSize)
    local maxGridX = math.floor((centerX + radius) / gridSize)
    local minGridY = math.floor((centerY - radius) / gridSize)
    local maxGridY = math.floor((centerY + radius) / gridSize)

    -- Check all relevant grid cells
    for gridY = minGridY, maxGridY do
        for gridX = minGridX, maxGridX do
            local key = string.format("%d,%d", gridX, gridY)
            local cellObjects = self.spatialIndex[objectType][key]

            if cellObjects then
                for _, obj in ipairs(cellObjects) do
                    -- Check if object is actually within radius
                    local dx = obj.x - centerX
                    local dy = obj.y - centerY
                    local distance = math.sqrt(dx*dx + dy*dy)

                    if distance <= radius then
                        table.insert(objects, obj)
                    end
                end
            end
        end
    end

    return objects
end

-- Get all NPCs (global) - DEPRECATED: Use getNearbyNPCs instead
function WorldCache:getAllNPCs()
    if not self.isLoaded then return {} end
    return self.worldData.npcs
end

-- Get NPCs near a position using spatial index
function WorldCache:getNearbyNPCs(centerX, centerY, radius)
    if not self.isLoaded then return {} end

    local npcs = {}

    -- Get all NPCs since they're static (don't move)
    -- But we still filter by distance for performance
    for _, npc in ipairs(self.worldData.npcs) do
        local dx = npc.x - centerX
        local dy = npc.y - centerY
        local distance = math.sqrt(dx*dx + dy*dy)

        if distance <= radius then
            table.insert(npcs, npc)
        end
    end

    return npcs
end

-- Get all animals (global) - DEPRECATED: Use getNearbyAnimals instead
function WorldCache:getAllAnimals()
    if not self.isLoaded then return {} end
    return self.worldData.animals
end

-- Get animals near a position using spatial index
function WorldCache:getNearbyAnimals(centerX, centerY, radius)
    if not self.isLoaded then return {} end

    local animals = {}

    -- Get all animals since they move dynamically (server updates positions)
    -- But we still filter by distance for performance
    for _, animal in ipairs(self.worldData.animals) do
        local dx = animal.x - centerX
        local dy = animal.y - centerY
        local distance = math.sqrt(dx*dx + dy*dy)

        if distance <= radius then
            table.insert(animals, animal)
        end
    end

    return animals
end

-- Get world dimensions
function WorldCache:getWorldSize()
    if not self.isLoaded then return 5000, 5000 end
    return self.worldData.worldWidth, self.worldData.worldHeight
end

-- Get total number of chunks
function WorldCache:getChunkCount()
    if not self.isLoaded then return 0 end
    local count = 0
    for _ in pairs(self.worldData.chunks) do
        count = count + 1
    end
    return count
end

-- Check if world data is loaded and ready
function WorldCache:isReady()
    return self.isLoaded
end

-- Get loading progress (0-1)
function WorldCache:getLoadProgress()
    return self.loadProgress
end

-- Get loading message
function WorldCache:getLoadMessage()
    return self.loadMessage
end

return WorldCache