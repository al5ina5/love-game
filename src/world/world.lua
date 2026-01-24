-- src/world/world.lua
-- World management: tiles, rocks, collision detection

-- Protocol and Network removed from here to allow clean state
local Constants = require('src.constants')

local World = {}
World.__index = World

-- Constants
local TILE_SIZE = 16

-- Road tile IDs using the perfect dirt square pattern
local ROAD_TILES = {
    CORNER_NE = 108,    -- NE corner (grass TOP+RIGHT)
    CORNER_SE = 144,    -- SE corner (grass BOTTOM+RIGHT)
    CORNER_SW = 141,    -- SW corner (grass BOTTOM+LEFT)
    CORNER_NW = 105,    -- NW corner (grass TOP+LEFT)
    DEAD_END_N = 107,   -- North dead end (grass TOP+LEFT+RIGHT)
    DEAD_END_E = 132,   -- East dead end (grass RIGHT+TOP+BOTTOM)
    DEAD_END_S = 142,   -- South dead end (grass BOTTOM+LEFT+RIGHT)
    DEAD_END_W = 117,   -- West dead end (grass LEFT+TOP+BOTTOM)
    CENTER = 130         -- Full dirt center tile
}

local CHUNK_REQUEST_TIMEOUT = 3.0 -- Retry request after 3 seconds

function World:new(worldWidth, worldHeight)
    local self = setmetatable({}, World)

    self.worldWidth = worldWidth
    self.worldHeight = worldHeight
    self.tileSize = TILE_SIZE
    self.chunkSize = 512  -- Same as ChunkManager CHUNK_SIZE
    
    -- Tiles
    self.tilesetImage = nil
    self.tilesetQuads = {}
    self.tileQuads = {}
    self.tileMap = {}
    
    -- Rocks
    self.rocks = {}
    self.rocksImage = nil
    self.rocksQuads = {}
    self.rocksImageData = nil
    self.validTileToActual = {}

    -- Roads and water are now data-driven from server chunks
    self.roads = {}
    self.water = {}

    -- Chunk Management
    self.loadedChunks = {} -- Track which chunks are loaded [cx,cy] = true
    self.loadingChunks = {}
    self.lastChunkUpdate = 0

    -- Chunk loading
    self.chunkLoadQueue = {}
    self.maxChunksPerFrame = 3  -- Standard 3 chunks/frame

    -- SpriteBatches for performance
    self.grassBatch = nil
    self.spriteBatchDirty = true
    
    -- Grass batch optimization - track last rendered area
    self.lastGrassStartX = nil
    self.lastGrassStartY = nil
    self.lastGrassEndX = nil
    self.lastGrassEndY = nil

    -- Throttle grass batch rebuilding
    self.lastGrassRebuildTime = 0
    self.grassRebuildThrottle = 0.1  -- Standard 0.1s throttle
    
    -- Road/Water SpriteBatches per chunk
    self.roadBatches = {}  -- [chunkKey] = SpriteBatch
    self.waterBatches = {} -- [chunkKey] = SpriteBatch

    return self
end

function World:loadTiles()
    -- Load tileset image
    local tilesetPath = "assets/img/tileset/narnia/Path_Tile.png"
    
    local success, err = pcall(function()
        self.tilesetImage = love.graphics.newImage(tilesetPath)
        self.tilesetImage:setFilter("nearest", "nearest")
        
        -- Load Grass Background
        self.grassImage = love.graphics.newImage("assets/img/tileset/narnia/Grass_Middle.png")
        self.grassImage:setFilter("nearest", "nearest")

        -- Load Water Tiles
        self.waterTileset = love.graphics.newImage("assets/img/tileset/narnia/Water_Tile.png")
        self.waterTileset:setFilter("nearest", "nearest")
        
        -- Load Water Middle
        self.waterMiddle = love.graphics.newImage("assets/img/tileset/narnia/Water_Middle.png")
        self.waterMiddle:setFilter("nearest", "nearest")

        -- Initialize Grass SpriteBatch (large enough for viewport + margin)
        -- Normal viewport is 320x180 = 20x12 tiles. With margin, maybe 40x30 = 1200 tiles.
        -- We'll just make it 5000 to be safe for any resize.
        self.grassBatch = love.graphics.newSpriteBatch(self.grassImage, 5000)
    end)
    
    if not success then
        print("ERROR: Failed to load tileset: " .. tilesetPath)
        -- Fallback: create a simple colored tile
        local fallbackData = love.image.newImageData(16, 16)
        for y = 0, 15 do
            for x = 0, 15 do
                fallbackData:setPixel(x, y, 0.2, 0.6, 0.2, 1)  -- Green fallback
            end
        end
        self.tilesetImage = love.graphics.newImage(fallbackData)
        self.tilesetImage:setFilter("nearest", "nearest")
    end
    
    -- Get tileset dimensions
    local tilesetWidth, tilesetHeight = self.tilesetImage:getDimensions()
    local tileWidth = 16
    local tileHeight = 16
    local tilesPerRow = math.floor(tilesetWidth / tileWidth)
    local tilesPerCol = math.floor(tilesetHeight / tileHeight)
    
    -- Create quads for each tile (Path)
    self.tilesetQuads = {}
    if tilesPerRow == 1 or tilesetWidth <= 20 then
        -- Single column layout
        for i = 0, tilesPerCol - 1 do
            local y = i * tileHeight
            self.tilesetQuads[i + 1] = love.graphics.newQuad(
                0, y, tileWidth, tileHeight,
                tilesetWidth, tilesetHeight
            )
        end
    else
        -- Grid layout
        local tileIndex = 1
        for row = 0, tilesPerCol - 1 do
            for col = 0, tilesPerRow - 1 do
                local x = col * tileWidth
                local y = row * tileHeight
                self.tilesetQuads[tileIndex] = love.graphics.newQuad(
                    x, y, tileWidth, tileHeight,
                    tilesetWidth, tilesetHeight
                )
                tileIndex = tileIndex + 1
            end
        end
    end

    -- Generate Water Quads
    self.waterQuads = {}
    if self.waterTileset then
        local w, h = self.waterTileset:getDimensions()
        local cols = math.floor(w / 16)
        local rows = math.floor(h / 16)
        local idx = 1
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                 self.waterQuads[idx] = love.graphics.newQuad(c*16, r*16, 16, 16, w, h)
                 idx = idx + 1
            end
        end
    end
    
    -- Use tile 5 (Center) as fallback
    local BASIC_GRASS_TILE_ID = 5
    if not self.tilesetQuads[BASIC_GRASS_TILE_ID] then
        BASIC_GRASS_TILE_ID = 1
    end
    
    -- Store which quad to use for each tile variation
    self.tileQuads = {
        self.tilesetQuads[BASIC_GRASS_TILE_ID],  -- Index 1: Grass
        self.tilesetQuads[BASIC_GRASS_TILE_ID],  -- Index 2: Reserved
        self.tilesetQuads[BASIC_GRASS_TILE_ID],  -- Index 3: Reserved
        self.tilesetQuads[BASIC_GRASS_TILE_ID],  -- Index 4: Reserved
    }

    -- Don't pre-generate tile map for huge worlds - use procedural generation instead
    -- For a 20,000x20,000 world, that would be 1.56 million tiles in memory!
    -- Instead, we'll generate tiles on-the-fly or use a sparse map
    self.tileMap = nil  -- Use nil to indicate procedural generation
end

-- Configure road quads based on the road tile mapping
-- Get the road quad for a given tile ID
function World:getRoadQuad(tileID)
    if self.tilesetQuads[tileID] then
        return self.tilesetQuads[tileID]
    else
        -- Fallback to grass tile
        return self.tilesetQuads[BASIC_GRASS_TILE_ID]
    end
end

-- Road generation functions (delegated to RoadGenerator)
-- Road generation is now handled server-side via ChunkManager.ts
function World:generateRoadNetwork(pointsOfInterest, seed)
    -- This is now managed by the server and synchronized via chunks
end

function World:sendRoadsToClients(network, isHost)
    if not isHost or not network or not self.roads then
        return
    end

    -- Count total road tiles
    local totalRoadTiles = 0
    for chunkKey, chunkData in pairs(self.roads) do
        for localTileX, tileRow in pairs(chunkData) do
            for localTileY, tileID in pairs(tileRow) do
                if tileID then
                    totalRoadTiles = totalRoadTiles + 1
                end
            end
        end
    end

    if totalRoadTiles == 0 then
        -- Send empty roads data
        network:send(Protocol.MSG.ROADS_DATA, {0})
        return
    end

    -- Prepare road data for network transmission
    local roadData = {}
    for chunkKey, chunkData in pairs(self.roads) do
        for localTileX, tileRow in pairs(chunkData) do
            for localTileY, tileID in pairs(tileRow) do
                if tileID then
                    -- Convert chunk key back to coordinates
                    local chunkX, chunkY = chunkKey:match("([^,]+),([^,]+)")
                    chunkX, chunkY = tonumber(chunkX), tonumber(chunkY)
                    local worldTileX = chunkX * (self.chunkSize / TILE_SIZE) + localTileX
                    local worldTileY = chunkY * (self.chunkSize / TILE_SIZE) + localTileY

                    table.insert(roadData, worldTileX)
                    table.insert(roadData, worldTileY)
                    table.insert(roadData, tileID)
                end
            end
        end
    end

    -- Send road data to client
    network:send(Protocol.MSG.ROADS_DATA, roadData)
end

function World:sendRocksToClients(network, isHost)
    if not isHost or not network or not self.rocks then
        return
    end
    
    -- Send rocks data
    -- Protocol expects: { rocks = { {x=, y=, tileId=}, ... } }
    network:send(Protocol.MSG.ROCKS_DATA, { rocks = self.rocks })
end

function World:update(dt, playerX, playerY, network, chunkManager)
    if not playerX or not playerY or not network then return end

    self.lastChunkUpdate = self.lastChunkUpdate + dt
    -- Standard 0.5s check interval
    local checkInterval = 0.5
    if self.lastChunkUpdate < checkInterval then return end
    self.lastChunkUpdate = 0

    local cx = math.floor(playerX / self.chunkSize)
    local cy = math.floor(playerY / self.chunkSize)

    -- Get load distance from chunkManager if available
    local loadDistance = chunkManager and chunkManager.loadDistance or 1

    -- Request chunks around player based on load distance
    for dy = -loadDistance, loadDistance do
        for dx = -loadDistance, loadDistance do
            local tx = cx + dx
            local ty = cy + dy
            local key = tx .. "," .. ty

            local currentTime = love.timer.getTime()
            local status = self.loadedChunks[key]
            local loadingTime = self.loadingChunks[key]

            if not status then 
                if not loadingTime or (currentTime - loadingTime > CHUNK_REQUEST_TIMEOUT) then
                    -- Request chunk (initial or retry)
                    if network.send then
                        network:send("chunk", tx, ty) -- Protocol.MSG.REQUEST_CHUNK
                        self.loadingChunks[key] = currentTime
                        -- print("Requesting chunk " .. key .. (loadingTime and " (RETRY)" or ""))
                    end
                end
            end
        end
    end
end

function World:clearChunks()
    print("World: Clearing all chunks for room join")
    self.loadedChunks = {}
    self.loadingChunks = {}
    self.roads = {}
    self.water = {}
    self.trees = {}
    self.rocks = {}
    self.spriteBatchDirty = true
    if self.roadBatches then
        for _, batch in pairs(self.roadBatches) do batch:release() end
        self.roadBatches = {}
    end
    if self.waterBatches then
        for _, batch in pairs(self.waterBatches) do batch:release() end
        self.waterBatches = {}
    end
end

function World:loadChunkData(chunkX, chunkY, data)
    local chunkKey = chunkX .. "," .. chunkY
    if self.loadedChunks[chunkKey] then return end -- Already loaded

    -- Load immediately
    self:loadChunkDataImmediate(chunkKey, chunkX, chunkY, data)
end

function World:loadChunkDataImmediate(chunkKey, chunkX, chunkY, data)
    local startTime = love.timer.getTime()
    -- print("World: Loading chunk data for " .. chunkKey)

    -- data contains { roads={}, water={}, rocks={}, trees={} }

    -- 1. Load Roads
    if data.roads then
        for key, tileID in pairs(data.roads) do
            local lx, ly = key:match("([^,]+),([^,]+)")
            lx, ly = tonumber(lx), tonumber(ly)
            -- Map to correct chunk storage
            if not self.roads[chunkKey] then self.roads[chunkKey] = {} end
            if not self.roads[chunkKey][lx] then self.roads[chunkKey][lx] = {} end
            self.roads[chunkKey][lx][ly] = tileID
        end
    end

    -- 2. Load Water
    if data.water then
        for key, tileID in pairs(data.water) do
            local lx, ly = key:match("([^,]+),([^,]+)")
            lx, ly = tonumber(lx), tonumber(ly)
            if not self.water[chunkKey] then self.water[chunkKey] = {} end
            if not self.water[chunkKey][lx] then self.water[chunkKey][lx] = {} end
            self.water[chunkKey][lx][ly] = tileID
        end
    end

    -- 3. Load Rocks
    if data.rocks then
        for _, rock in ipairs(data.rocks) do
            table.insert(self.rocks, rock)
        end
    end

    -- 4. Load Trees
    if data.trees then
        for _, tree in ipairs(data.trees) do
            table.insert(self.trees, tree)
        end
    end

    self.loadedChunks[chunkKey] = true
    self.loadingChunks[chunkKey] = nil -- Clear loading flag
    self.spriteBatchDirty = true -- Trigger redraw of floor

    local duration = (love.timer.getTime() - startTime) * 1000
    -- print(string.format("World: Loaded chunk %s in %.2fms", chunkKey, duration))
end

-- Process queued chunk loading (called every frame)
function World:processChunkLoadingQueue()
    if #self.chunkLoadQueue == 0 then return end
    -- Standard implementation for processing queue
    -- (Keeping logic for potential future use, but standardized)
    local chunksProcessed = 0
    while chunksProcessed < self.maxChunksPerFrame and #self.chunkLoadQueue > 0 do
        local chunkInfo = table.remove(self.chunkLoadQueue, 1)
        self:loadChunkDataImmediate(chunkInfo.chunkKey, chunkInfo.chunkX, chunkInfo.chunkY, chunkInfo.data)
        chunksProcessed = chunksProcessed + 1
    end
end

-- Unload a chunk and clean up its resources
function World:unloadChunk(chunkKey)
    if not self.loadedChunks[chunkKey] then
        return -- Not loaded
    end
    
    -- Remove roads for this chunk
    if self.roads[chunkKey] then
        self.roads[chunkKey] = nil
    end
    
    -- Remove water for this chunk
    if self.water[chunkKey] then
        self.water[chunkKey] = nil
    end
    
    -- Remove road/water batches if they exist
    if self.roadBatches and self.roadBatches[chunkKey] then
        self.roadBatches[chunkKey]:release()
        self.roadBatches[chunkKey] = nil
    end
    
    if self.waterBatches and self.waterBatches[chunkKey] then
        self.waterBatches[chunkKey]:release()
        self.waterBatches[chunkKey] = nil
    end
    
    -- Remove trees and rocks for this chunk
    -- Note: trees and rocks are stored as flat arrays, so we need to filter them
    local chunkX, chunkY = chunkKey:match("([^,]+),([^,]+)")
    chunkX, chunkY = tonumber(chunkX), tonumber(chunkY)
    local minX = chunkX * self.chunkSize
    local minY = chunkY * self.chunkSize
    local maxX = (chunkX + 1) * self.chunkSize
    local maxY = (chunkY + 1) * self.chunkSize
    
    -- Filter trees
    if self.trees then
        local newTrees = {}
        for _, tree in ipairs(self.trees) do
            if tree.x < minX or tree.x >= maxX or tree.y < minY or tree.y >= maxY then
                table.insert(newTrees, tree)
            end
        end
        self.trees = newTrees
    end
    
    -- Filter rocks
    if self.rocks then
        local newRocks = {}
        for _, rock in ipairs(self.rocks) do
            if rock.x < minX or rock.x >= maxX or rock.y < minY or rock.y >= maxY then
                table.insert(newRocks, rock)
            end
        end
        self.rocks = newRocks
    end
    
    self.loadedChunks[chunkKey] = nil
    self.spriteBatchDirty = true
    
    -- print("World: Unloaded chunk " .. chunkKey)
end



function World:loadRoadsFromData(encodedData)
    -- Deprecated / Legacy support if needed, but we rely on chunk loading now.
end

function World:isOnRoad(x, y)
    return self:getRoadTileAtWorldPos(x, y) ~= nil
end

function World:getRoadTileAtWorldPos(x, y)
    local tileX = math.floor(x / TILE_SIZE)
    local tileY = math.floor(y / TILE_SIZE)
    
    local chunkScale = self.chunkSize / TILE_SIZE
    local cx = math.floor(tileX / chunkScale)
    local cy = math.floor(tileY / chunkScale)
    local key = cx .. "," .. cy
    
    if self.roads[key] then
        local lx = tileX % chunkScale
        local ly = tileY % chunkScale
        if self.roads[key][lx] then
            return self.roads[key][lx][ly]
        end
    end
    return nil
end

function World:checkRoadCollision(x, y, width, height)
    -- Check if the entity collides with any road tiles
    local left = math.floor(x / TILE_SIZE)
    local right = math.floor((x + width - 1) / TILE_SIZE)
    local top = math.floor(y / TILE_SIZE)
    local bottom = math.floor((y + height - 1) / TILE_SIZE)

    for tileY = top, bottom do
        for tileX = left, right do
            local chunkScale = self.chunkSize / TILE_SIZE
            local cx = math.floor(tileX / chunkScale)
            local cy = math.floor(tileY / chunkScale)
            local key = cx .. "," .. cy
            
            if self.roads[key] then
                local lx = tileX % chunkScale
                local ly = tileY % chunkScale
                if self.roads[key][lx] and self.roads[key][lx][ly] then
                    return true
                end
            end
        end
    end
    return false
end

function World:getNearbyRoadTiles(centerX, centerY, radius)
    local nearbyRoads = {}
    local centerTileX = math.floor(centerX / TILE_SIZE)
    local centerTileY = math.floor(centerY / TILE_SIZE)
    local radiusInTiles = math.ceil(radius / TILE_SIZE)

    for dy = -radiusInTiles, radiusInTiles do
        for dx = -radiusInTiles, radiusInTiles do
            local tileX = centerTileX + dx
            local tileY = centerTileY + dy
            
            local chunkScale = self.chunkSize / TILE_SIZE
            local cx = math.floor(tileX / chunkScale)
            local cy = math.floor(tileY / chunkScale)
            local key = cx .. "," .. cy
            
            local tileID = nil
            if self.roads[key] then
                local lx = tileX % chunkScale
                local ly = tileY % chunkScale
                if self.roads[key][lx] then
                    tileID = self.roads[key][lx][ly]
                end
            end

            if tileID then
                table.insert(nearbyRoads, {
                    x = tileX * TILE_SIZE,
                    y = tileY * TILE_SIZE,
                    tileID = tileID
                })
            end
        end
    end

    return nearbyRoads
end
function World:loadRocks()
    local rocksPath = "assets/img/objects/rocks.png"
    
    local success, err = pcall(function()
        self.rocksImageData = love.image.newImageData(rocksPath)
        self.rocksImage = love.graphics.newImage(self.rocksImageData)
        self.rocksImage:setFilter("nearest", "nearest")
    end)
    
    if not success then
        print("ERROR: Failed to load rocks: " .. rocksPath)
        return
    end
    
    local rocksWidth, rocksHeight = self.rocksImage:getDimensions()
    local tileWidth = 16
    local tileHeight = 16
    local tilesPerRow = 5
    local tilesPerCol = 4
    local totalTiles = tilesPerRow * tilesPerCol
    
    -- Empty tiles
    local emptyTiles = {[10] = true, [13] = true, [14] = true, [15] = true, [18] = true, [19] = true, [20] = true}
    
    -- Create quads for valid tiles
    self.rocksQuads = {}
    self.validTileToActual = {}
    local validTileIndex = 1
    for tileIndex = 1, totalTiles do
        if not emptyTiles[tileIndex] then
            local row = math.floor((tileIndex - 1) / tilesPerRow)
            local col = (tileIndex - 1) % tilesPerRow
            local x = col * tileWidth
            local y = row * tileHeight
            
            self.rocksQuads[validTileIndex] = love.graphics.newQuad(
                x, y, tileWidth, tileHeight,
                rocksWidth, rocksHeight
            )
            self.validTileToActual[validTileIndex] = tileIndex
            validTileIndex = validTileIndex + 1
        end
    end
end

function World:generateRocks()
    -- Local rock generation disabled
    self.rocks = {}
end
    


function World:loadTrees()
    self.treeImages = {}
    local variations = {
        standard = "assets/img/Oak_Tree.png",
        purple = "assets/img/Oak_Tree_Purple.png",
        blue = "assets/img/Oak_Tree_Blue.png",
        alien = "assets/img/Oak_Tree_Alien.png",
        white = "assets/img/Oak_Tree_White.png",
        red_white = "assets/img/Oak_Tree_Red_White.png",
        all_white = "assets/img/Oak_Tree_All_White.png"
    }
    
    for name, path in pairs(variations) do
        local success, err = pcall(function()
            local img = love.graphics.newImage(path)
            img:setFilter("nearest", "nearest")
            self.treeImages[name] = img
        end)
        
        if not success then
            print("ERROR: Failed to load tree: " .. path)
            -- Use first available if possible or leave nil
        end
    end
    
    -- Backward compatibility / fallback
    self.treeImage = self.treeImages.standard
end

function World:generateTrees(seed)
    -- Local tree generation disabled
    self.trees = {}
end



function World:checkTreeCollision(x, y, width, height, chunkManager)
    if not self.trees then return false end

    local entityLeft = x
    local entityRight = x + width
    local entityTop = y
    local entityBottom = y + height

    for _, tree in ipairs(self.trees) do
        -- Trunk collision box from editor: 
        -- P1(27,57), P2(37,58), P3(40,62), P4(33,65), P5(24,63)
        -- Bounding box: X[24, 40], Y[57, 65]
        local trunkWidth = 16
        local trunkHeight = 8
        local trunkX = tree.x + 24
        local trunkY = tree.y + 57

        if entityLeft < trunkX + trunkWidth and entityRight > trunkX and
           entityTop < trunkY + trunkHeight and entityBottom > trunkY then
               
             if not chunkManager or chunkManager:isPositionActive(tree.x, tree.y) then
                return true
            end
        end
    end
    return false
end

function World:getTreesForDrawing(chunkManager, camera, worldCache)
    local drawList = {}

    -- Use world cache if available (MIYO optimization)
    if worldCache and worldCache:isReady() then
        -- Get trees near camera using spatial index
        local cameraCenterX = camera and (camera.x + camera.width/2) or 0
        local cameraCenterY = camera and (camera.y + camera.height/2) or 0
        local viewRadius = 300  -- Draw trees within 300 pixels of camera

        local nearbyTrees = worldCache:getNearbyObjects("trees", cameraCenterX, cameraCenterY, viewRadius)

        -- Draw all nearby trees from cache
        for _, tree in ipairs(nearbyTrees) do
            table.insert(drawList, {
                type = "tree",
                x = tree.x,
                y = tree.y + 64, -- Sort by visual base of trunk (approx 64px down), not image bottom
                originalY = tree.y,
                width = tree.width,
                height = tree.height,
                treeType = tree.type or "standard"
            })
        end
        return drawList
    end

    -- Fallback to old chunk-based system
    if not self.trees then return drawList end

    local visibleTrees = self.trees
    if chunkManager and camera then
        local cameraMinX = camera.x - 200
        local cameraMinY = camera.y - 200
        local cameraMaxX = camera.x + camera.width + 200
        local cameraMaxY = camera.y + camera.height + 200

        visibleTrees = {}
        for _, tree in ipairs(self.trees) do
            if tree.x >= cameraMinX and tree.x <= cameraMaxX and
               tree.y >= cameraMinY and tree.y <= cameraMaxY then
                if chunkManager:isPositionActive(tree.x, tree.y) then
                    table.insert(visibleTrees, tree)
                end
            end
        end
    end

    -- Fallback: Draw visible trees
    if not self.trees then return drawList end

    for _, tree in ipairs(visibleTrees) do
        table.insert(drawList, {
            type = "tree",
            x = tree.x,
            y = tree.y + 64, -- Sort by visual base of trunk (approx 64px down), not image bottom
            originalY = tree.y,
            width = tree.width,
            height = tree.height,
            treeType = tree.type or "standard"
        })
    end
    return drawList
end


function World:drawFloor(camera, worldCache)
    -- Process chunk loading queue
    self:processChunkLoadingQueue()

    local cameraX = math.floor(camera.x + 0.5)
    local cameraY = math.floor(camera.y + 0.5)
    local margin = 3
    local startX = math.floor((cameraX - margin * TILE_SIZE) / TILE_SIZE)
    local startY = math.floor((cameraY - margin * TILE_SIZE) / TILE_SIZE)
    local endX = math.ceil((cameraX + camera.width + margin * TILE_SIZE) / TILE_SIZE)
    local endY = math.ceil((cameraY + camera.height + margin * TILE_SIZE) / TILE_SIZE)
    
    startX = math.max(0, startX)
    startY = math.max(0, startY)
    endX = math.min(math.ceil(self.worldWidth / TILE_SIZE) - 1, endX)
    endY = math.min(math.ceil(self.worldHeight / TILE_SIZE) - 1, endY)

    -- 1. Draw Background Grass EVERYWHERE using SpriteBatch
    if self.grassImage and self.grassBatch then
        -- Only rebuild SpriteBatch if camera moved to new tiles OR throttle time passed
        local currentTime = love.timer.getTime()
        local needsRebuild = self.lastGrassStartX ~= startX or
                             self.lastGrassStartY ~= startY or
                             self.lastGrassEndX ~= endX or
                             self.lastGrassEndY ~= endY or
                             self.spriteBatchDirty or
                             (currentTime - self.lastGrassRebuildTime) >= self.grassRebuildThrottle

        if needsRebuild then
            self.grassBatch:clear()
            for ty = startY, endY do
                for tx = startX, endX do
                    self.grassBatch:add(tx * TILE_SIZE, ty * TILE_SIZE)
                end
            end

            -- Update tracking
            self.lastGrassStartX = startX
            self.lastGrassStartY = startY
            self.lastGrassEndX = endX
            self.lastGrassEndY = endY
            self.spriteBatchDirty = false
            self.lastGrassRebuildTime = currentTime
        end
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.grassBatch)
    else
        -- Fallback green rectangles
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            end
        end
    end

    -- 2. Draw Road and Water on Top
    -- DEBUG: One-time check if roads table has data
    if not self.debugRoadsChecked then
        self.debugRoadsChecked = true
        local roadChunks = 0
        for k, v in pairs(self.roads) do
            roadChunks = roadChunks + 1
        end
        print("DEBUG drawFloor: roads table has " .. roadChunks .. " chunks")
    end
    
    if self.tilesetImage then
        love.graphics.setColor(1, 1, 1, 1)
        for ty = startY, endY do
            for tx = startX, endX do
                local roadTileID = nil
                local waterTileID = nil

                -- Use chunk-loaded road/water data (from worldCache or network)
                local chunkSize = self.chunkSize / TILE_SIZE  -- Convert to tile units (32)
                local chunkX = math.floor(tx / chunkSize)
                local chunkY = math.floor(ty / chunkSize)
                local chunkKey = chunkX .. "," .. chunkY
                local localTileX = tx % chunkSize
                local localTileY = ty % chunkSize
                
                -- Check self.roads table (populated from worldCache or network)
                if self.roads[chunkKey] and self.roads[chunkKey][localTileX] then
                    roadTileID = self.roads[chunkKey][localTileX][localTileY]
                end
                
                -- Check self.water table
                if self.water[chunkKey] and self.water[chunkKey][localTileX] then
                    waterTileID = self.water[chunkKey][localTileX][localTileY]
                end

                -- Draw Road
                if roadTileID then
                    local quad = self:getRoadQuad(roadTileID)
                    if quad then
                        love.graphics.draw(self.tilesetImage, quad, tx * TILE_SIZE, ty * TILE_SIZE)
                    end
                end

                -- Draw Water
                if waterTileID then
                     if waterTileID == 5 and self.waterMiddle then
                        love.graphics.draw(self.waterMiddle, tx * TILE_SIZE, ty * TILE_SIZE)
                     elseif self.waterTileset and self.waterQuads then
                         local quad = self.waterQuads[waterTileID]
                         if quad then
                            love.graphics.draw(self.waterTileset, quad, tx * TILE_SIZE, ty * TILE_SIZE)
                         end
                     end
                end
            end
        end
    end
end

function World:drawRock(rockItem)
    if self.rocksImage and self.rocksQuads and self.rocksQuads[rockItem.tileId] then
        love.graphics.setColor(1, 1, 1, 1)
        local drawY = rockItem.originalY or (rockItem.y - 12)
        love.graphics.draw(
            self.rocksImage,
            self.rocksQuads[rockItem.tileId],
            rockItem.x,
            drawY
        )
    else
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", rockItem.x, rockItem.y - 12, 16, 16)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function World:getRocksForDrawing(chunkManager, camera, worldCache)
    local drawList = {}

    -- Use world cache if available (MIYO optimization)
    if worldCache and worldCache:isReady() then
        -- Get rocks near camera using spatial index
        local cameraCenterX = camera and (camera.x + camera.width/2) or 0
        local cameraCenterY = camera and (camera.y + camera.height/2) or 0
        local viewRadius = 200  -- Draw rocks within 200 pixels of camera

        local nearbyRocks = worldCache:getNearbyObjects("rocks", cameraCenterX, cameraCenterY, viewRadius)

        -- Draw all rocks in draw list
        for _, rock in ipairs(nearbyRocks) do
            if rock and rock.x and rock.y and rock.tileId then
                local sortY = math.floor(rock.y) + 16
                table.insert(drawList, {
                    type = "rock",
                    x = rock.x,
                    y = sortY,
                    tileId = rock.tileId,
                    originalY = rock.y
                })
            end
        end
        return drawList
    end

    -- Fallback to old chunk-based system
    if not self.rocks or #self.rocks == 0 then return drawList end

    -- Get visible chunks from camera
    local visibleRocks = self.rocks
    if chunkManager and camera then
        -- Only draw rocks in visible chunks
        local cameraMinX = camera.x - 100  -- Margin for off-screen rendering
        local cameraMinY = camera.y - 100
        local cameraMaxX = camera.x + camera.width + 100
        local cameraMaxY = camera.y + camera.height + 100

        visibleRocks = {}
        for _, rock in ipairs(self.rocks) do
            -- Check if rock is in camera view or nearby chunks
            if rock.x >= cameraMinX and rock.x <= cameraMaxX and
               rock.y >= cameraMinY and rock.y <= cameraMaxY then
                if chunkManager:isPositionActive(rock.x, rock.y) then
                    table.insert(visibleRocks, rock)
                end
            end
        end
    end


    for _, rock in ipairs(visibleRocks) do
        if rock and rock.x and rock.y and rock.tileId then
            local sortY = math.floor(rock.y) + 16
            table.insert(drawList, {
                type = "rock",
                x = rock.x,
                y = sortY,
                tileId = rock.tileId,
                originalY = rock.y
            })
        end
    end
    return drawList
end

function World:checkRockCollision(x, y, width, height, chunkManager)
    if not self.rocks or #self.rocks == 0 then
        return false
    end

    -- Check collision with rocks
    local entityLeft = x
    local entityRight = x + width
    local entityTop = y
    local entityBottom = y + height

    for _, rock in ipairs(self.rocks) do
        if rock and rock.x and rock.y then
            -- Rock bounding box (16x16 pixels typically)
            local rockLeft = rock.x
            local rockRight = rock.x + 16
            local rockTop = rock.y
            local rockBottom = rock.y + 16

            -- Check for bounding box intersection
            if entityLeft < rockRight and entityRight > rockLeft and
               entityTop < rockBottom and entityBottom > rockTop then
                -- Only check collision if rock is in an active chunk (if chunkManager provided)
                if not chunkManager or chunkManager:isPositionActive(rock.x, rock.y) then
                    return true
                end
            end
        end
    end

    return false
end

function World:checkWaterCollision(x, y, width, height)
    local left = math.floor(x / TILE_SIZE)
    local right = math.floor((x + width - 1) / TILE_SIZE)
    local top = math.floor(y / TILE_SIZE)
    local bottom = math.floor((y + height - 1) / TILE_SIZE)

    for tileY = top, bottom do
        for tileX = left, right do
            local chunkScale = self.chunkSize / TILE_SIZE
            local cx = math.floor(tileX / chunkScale)
            local cy = math.floor(tileY / chunkScale)
            local key = cx .. "," .. cy
            
            local tileID = nil
            if self.water[key] then
                local lx = tileX % chunkScale
                local ly = tileY % chunkScale
                if self.water[key][lx] then
                    tileID = self.water[key][lx][ly]
                end
            end

            if tileID then
                local masks = Constants.WATER_COLLISION_MASKS[tileID]
                if masks then
                    for _, mask in ipairs(masks) do
                        local maskX = tileX * TILE_SIZE + mask.x
                        local maskY = tileY * TILE_SIZE + mask.y
                        local maskW = mask.w
                        local maskH = mask.h
                        
                        if x < maskX + maskW and x + width > maskX and
                           y < maskY + maskH and y + height > maskY then
                            return true
                        end
                    end
                else
                    -- Default to full tile collision if no mask defined
                    return true
                end
            end
        end
    end
    return false
end

function World:drawTree(treeItem)
    local img = self.treeImages and self.treeImages[treeItem.treeType or "standard"]
    if not img then img = self.treeImage end -- Fallback

    if img then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(
            img,
            treeItem.x,
            treeItem.originalY
        )
    else
        love.graphics.setColor(0, 0.5, 0, 1)
        love.graphics.rectangle("fill", treeItem.x, treeItem.originalY, treeItem.width, treeItem.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return World
