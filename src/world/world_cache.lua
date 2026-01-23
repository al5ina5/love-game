-- src/world/world_cache.lua
-- Client-side world data cache for MIYO performance optimization
-- Downloads complete world data upfront and caches it for fast access

local Constants = require('src.constants')
local dkjson = require('src.lib.dkjson')
local NPC = require('src.entities.npc')
local Animal = require('src.entities.animal')

local WorldCache = {}
WorldCache.__index = WorldCache

function WorldCache:new()
    local self = setmetatable({}, WorldCache)

    self.worldData = nil
    self.isLoaded = false
    self.loadProgress = 0
    self.loadMessage = "Preparing..."
    self.loadingAsync = false
    self.processingAsync = false
    self.processingStep = 0
    self.processingIndex = 0

    -- Spatial index for fast object lookups (will be populated after loading)
    self.spatialIndex = {
        trees = {},
        rocks = {},
        npcs = {},
        animals = {}
    }

    return self
end

-- Download complete world data from server SYNCHRONOUSLY
function WorldCache:downloadWorldData()
    self.loadProgress = 0
    self.loadMessage = "Connecting..."
    
    local OnlineClient = require('src.net.online_client')
    local onlineClient = nil
    local success, err = pcall(function()
        onlineClient = OnlineClient:new()
    end)
    
    if not success or not onlineClient then
        print("WorldCache: Failed to init OnlineClient: " .. tostring(err))
        return false
    end

    local apiUrl = Constants.API_BASE_URL .. "/api/world-data"
    print("WorldCache: Requesting world data (SYNC): " .. apiUrl)
    
    local ok, data = onlineClient:httpRequest("GET", apiUrl, nil)
    
    if not ok then
        print("WorldCache: Sync download failed: " .. tostring(data))
        return false
    end
    
    self.worldData = data
    
    -- Log chunk data stats
    if data and data.chunks then
        local totalRoads = 0
        local totalWater = 0
        local chunkCount = 0
        for chunkKey, chunkData in pairs(data.chunks) do
            chunkCount = chunkCount + 1
            if chunkData.roads then
                for _ in pairs(chunkData.roads) do totalRoads = totalRoads + 1 end
            end
            if chunkData.water then
                for _ in pairs(chunkData.water) do totalWater = totalWater + 1 end
            end
        end
        print(string.format("WorldCache: Received %d chunks with %d roads, %d water tiles", chunkCount, totalRoads, totalWater))
    end
    
    -- Hydrate NPCs immediately (not async)
    if self.worldData.npcs then
        local NPC = require('src.entities.npc')
        local hydratedNpcs = {}
        for i, npc in ipairs(self.worldData.npcs) do
            local hydratedNpc = NPC:new(
                npc.x or 0,
                npc.y or 0,
                npc.spritePath or "",
                npc.name or "NPC",
                npc.dialogue or {}
            )
            hydratedNpc.id = npc.id or ("npc_" .. i)
            table.insert(hydratedNpcs, hydratedNpc)
        end
        self.worldData.npcs = hydratedNpcs
        print("WorldCache: Hydrated " .. #hydratedNpcs .. " NPCs")
    end
    
    self.isLoaded = true
    self.loadProgress = 1.0
    self.loadMessage = "World ready!"
    
    return true
end


-- Download complete world data from server asynchronously
function WorldCache:downloadWorldDataAsync(callback)
    self.loadProgress = 0
    self.loadMessage = "Connecting..."
    self.loadingAsync = true
    
    local OnlineClient = require('src.net.online_client')
    local onlineClient = nil
    local success, err = pcall(function()
        onlineClient = OnlineClient:new()
    end)
    
    if not success or not onlineClient then
        self.loadingAsync = false
        if callback then callback(false, "Failed to init OnlineClient") end
        return
    end

    local apiUrl = Constants.API_BASE_URL .. "/api/world-data"
    print("WorldCache: Requesting world data asynchronously: " .. apiUrl)
    
    onlineClient:requestAsync("GET", apiUrl, nil, function(ok, data)
        self.loadingAsync = false
        if not ok then
            print("WorldCache: Async download failed: " .. tostring(data))
            if callback then callback(false, data) end
            return
        end
        
        self.worldData = data
        
        -- DEBUG: Log chunk data stats
        if data and data.chunks then
            local totalRoads = 0
            local totalWater = 0
            local chunkCount = 0
            for chunkKey, chunkData in pairs(data.chunks) do
                chunkCount = chunkCount + 1
                if chunkData.roads then
                    for _ in pairs(chunkData.roads) do totalRoads = totalRoads + 1 end
                end
                if chunkData.water then
                    for _ in pairs(chunkData.water) do totalWater = totalWater + 1 end
                end
            end
            print(string.format("WorldCache DEBUG: Received %d chunks with %d roads, %d water tiles", chunkCount, totalRoads, totalWater))
        end
        
        self.processingAsync = true
        self.processingStep = 1 -- Start hydration
        self.processingIndex = 1
        self.onComplete = callback
        self.loadProgress = 0.5
        self.loadMessage = "Processing world data..."
    end)
end

function WorldCache:update(dt)
    if not self.processingAsync then return end
    
    local startTime = love.timer.getTime()
    local maxTime = 0.008 -- Aim for 8ms per frame to keep 60fps
    
    while love.timer.getTime() - startTime < maxTime do
        if self.processingStep == 1 then
            -- Hydration slice
            if self:hydrateSlice() then
                self.processingStep = 2
                self.processingIndex = 1
                self.loadMessage = "Building spatial index..."
            end
        elseif self.processingStep == 2 then
            -- Spatial index slice
            if self:buildSpatialIndexSlice() then
                self.isLoaded = true
                self.processingAsync = false
                self.loadProgress = 1.0
                self.loadMessage = "World ready!"
                if self.onComplete then self.onComplete(true) end
                break
            end
        else
            break
        end
    end
end

function WorldCache:hydrateSlice()
    if not self.worldData then return true end
    
    local sliceSize = 20
    
    -- Initialize hydration state on first call
    if not self.hydratingNpcs then
        self.hydratingNpcs = {}
        self.npcsToHydrate = self.worldData.npcs or {}
        self.processingIndex = 1
    end
    
    -- Hydrate NPCs to separate table (avoids race condition with renderer)
    if self.processingIndex <= #self.npcsToHydrate then
        for i = 1, sliceSize do
            if self.processingIndex > #self.npcsToHydrate then break end
            
            local npc = self.npcsToHydrate[self.processingIndex]
            local hydratedNpc = NPC:new(
                npc.x or 0,
                npc.y or 0,
                npc.spritePath or "",
                npc.name or "NPC",
                npc.dialogue or {}
            )
            hydratedNpc.id = npc.id or ("npc_" .. self.processingIndex)
            table.insert(self.hydratingNpcs, hydratedNpc)
            self.processingIndex = self.processingIndex + 1
        end
        return false
    end
    
    -- All NPCs hydrated - atomic swap to prevent renderer seeing partial data
    if self.hydratingNpcs then
        self.worldData.npcs = self.hydratingNpcs
        self.hydratingNpcs = nil
        self.npcsToHydrate = nil
    end
    
    return true -- Done with hydration
end


function WorldCache:buildSpatialIndexSlice()
    if not self.worldData or not self.worldData.chunks then return true end
    
    -- Collect chunk keys if not done
    if not self.chunkKeys then
        self.chunkKeys = {}
        for k, _ in pairs(self.worldData.chunks) do
            table.insert(self.chunkKeys, k)
        end
    end

    local sliceSize = 5
    for i = 1, sliceSize do
        local idx = self.processingIndex
        if idx > #self.chunkKeys then 
            self.chunkKeys = nil
            return true 
        end
        
        local chunkKey = self.chunkKeys[idx]
        local chunkData = self.worldData.chunks[chunkKey]
        
        -- Index objects in this chunk
        if chunkData.trees then
            for _, tree in ipairs(chunkData.trees) do
                self:addToSpatialIndex("trees", tree.x, tree.y, tree)
            end
        end
        if chunkData.rocks then
            for _, rock in ipairs(chunkData.rocks) do
                self:addToSpatialIndex("rocks", rock.x, rock.y, rock)
            end
        end
        
        self.processingIndex = self.processingIndex + 1
    end
    
    self.loadProgress = 0.6 + (0.3 * (self.processingIndex / #self.chunkKeys))
    return false
end

function WorldCache:hydrateData()
    if not self.worldData then return end
    
    -- Hydrate NPCs
    if self.worldData.npcs then
        local hydratedNpcs = {}
        for i, npc in ipairs(self.worldData.npcs) do
            local hydratedNpc = NPC:new(
                npc.x or 0,
                npc.y or 0,
                npc.spritePath or "",
                npc.name or "NPC",
                npc.dialogue or {}
            )
            hydratedNpc.id = npc.id or ("npc_" .. i)
            table.insert(hydratedNpcs, hydratedNpc)
        end
        self.worldData.npcs = hydratedNpcs
    end

    -- Hydrate Animals (Disabled for performance)
    -- if self.worldData.animals then
    --     local hydratedAnimals = {}
    --     for i, animal in ipairs(self.worldData.animals) do
    --         local hydratedAnimal = Animal:new(
    --             animal.x or 0,
    --             animal.y or 0,
    --             animal.spritePath or "",
    --             animal.name or "Animal",
    --             animal.speed or 30
    --         )
    --         hydratedAnimal.id = animal.id or ("animal_" .. i)
    --         if animal.groupCenterX and animal.groupCenterY and animal.groupRadius then
    --             hydratedAnimal:setGroupCenter(animal.groupCenterX, animal.groupCenterY, animal.groupRadius)
    --         end
    --         table.insert(hydratedAnimals, hydratedAnimal)
    --     end
    --     self.worldData.animals = hydratedAnimals
    -- end
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

-- Add an object to the spatial index
function WorldCache:addToSpatialIndex(objectType, x, y, obj)
    local key = self:getSpatialKey(x, y)
    if not self.spatialIndex[objectType] then
        self.spatialIndex[objectType] = {}
    end
    if not self.spatialIndex[objectType][key] then
        self.spatialIndex[objectType][key] = {}
    end
    table.insert(self.spatialIndex[objectType][key], obj)
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