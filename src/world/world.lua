-- src/world/world.lua
-- World management: tiles, rocks, collision detection

local Protocol = require('src.net.protocol')
local NetworkAdapter = require('src.net.network_adapter')
local RoadGenerator = require('src.world.road_generator')

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

    -- Roads - simple sparse map: [chunkKey][localTileX][localTileY] = tileID
    self.roads = {}

    -- Road generator
    self.roadGenerator = RoadGenerator:new(self)

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
    
    -- Create quads for each tile
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
function World:generateRoadNetwork(pointsOfInterest, seed)
    self.roadGenerator:generateRoadNetwork(pointsOfInterest, seed)
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

function World:loadRoadsFromData(encodedData)
    self.roads = {}

    if not encodedData or #encodedData == 0 then
        return
    end

    -- encodedData is an array of [tileX, tileY, tileID, tileX, tileY, tileID, ...]
    for i = 1, #encodedData, 3 do
        local tileX = encodedData[i]
        local tileY = encodedData[i + 1]
        local tileID = encodedData[i + 2]

        if tileX and tileY and tileID then
            self.roadGenerator:setRoadTile(tileX, tileY, tileID)
        end
    end
end

function World:isOnRoad(x, y)
    local tileX = math.floor(x / TILE_SIZE)
    local tileY = math.floor(y / TILE_SIZE)
    return self.roadGenerator:getRoadTile(tileX, tileY) ~= nil
end

function World:getRoadTileAtWorldPos(x, y)
    local tileX = math.floor(x / TILE_SIZE)
    local tileY = math.floor(y / TILE_SIZE)
    return self.roadGenerator:getRoadTile(tileX, tileY)
end

function World:checkRoadCollision(x, y, width, height)
    -- Check if the entity collides with any road tiles
    local left = math.floor(x / TILE_SIZE)
    local right = math.floor((x + width - 1) / TILE_SIZE)
    local top = math.floor(y / TILE_SIZE)
    local bottom = math.floor((y + height - 1) / TILE_SIZE)

    for tileY = top, bottom do
        for tileX = left, right do
            if self.roadGenerator:getRoadTile(tileX, tileY) then
                return true
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
            local tileID = self.roadGenerator:getRoadTile(tileX, tileY)
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
    if not self.rocksQuads or #self.rocksQuads == 0 then
        print("ERROR: No rock quads available! Cannot generate rocks.")
        return
    end
    
    -- Generate rocks deterministically across the huge world
    local savedSeed = math.random()
    math.randomseed(12345)
    
    self.rocks = {}
    -- Even lower rock density for low-end devices - roughly 1 rock per 100,000 pixels
    -- This gives us ~4,000 rocks for a 20,000x20,000 world (reduced from 8,000)
    local numRocks = math.floor((self.worldWidth * self.worldHeight) / 100000)
    -- Cap at reasonable maximum for low-end devices
    numRocks = math.min(numRocks, 5000)
    -- Generating rocks (optimized for low-end devices)
    local rockTypes = {3, 4}
    
    for i = 1, numRocks do
        local x = math.random(0, self.worldWidth - TILE_SIZE)
        local y = math.random(0, self.worldHeight - TILE_SIZE)
        x = math.floor(math.floor(x / TILE_SIZE) * TILE_SIZE)
        y = math.floor(math.floor(y / TILE_SIZE) * TILE_SIZE)
        local tileId = rockTypes[math.random(1, #rockTypes)]
        
        table.insert(self.rocks, {
            x = x,
            y = y,
            tileId = tileId,
            actualTileNum = self.validTileToActual[tileId] or 1
        })
    end
    
    math.randomseed(savedSeed)
end

function World:drawFloor(camera)
    if not self.tilesetImage or not self.tileQuads then
        -- Draw fallback green rectangles
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
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
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
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
    
    love.graphics.setColor(1, 1, 1, 1)

    if self.tilesetImage then
        -- Draw tiles (grass or roads)
        for ty = startY, endY do
            for tx = startX, endX do
                -- 1. Draw Background Grass EVERYWHERE
                if self.grassImage then
                    love.graphics.draw(self.grassImage, tx * TILE_SIZE, ty * TILE_SIZE)
                end

                -- 2. Draw Road on Top (Narnia Overlay)
                local roadTileID = self.roadGenerator:getRoadTile(tx, ty)

                if roadTileID then
                     local quad = self:getRoadQuad(roadTileID)
                     if quad then
                        -- Apply manual offsets for Inner Corners (User Fix: 1 Tile Offset)
                        local drawX = tx * TILE_SIZE
                        local drawY = ty * TILE_SIZE
                        
                        -- Tile 10 (INNER_NW): Left 1, Up 1
                        if roadTileID == 10 then
                            drawX = drawX - TILE_SIZE
                            drawY = drawY - TILE_SIZE
                        end

                        -- Tile 11 (INNER_NE): Right 1, Up 1
                        if roadTileID == 11 then
                            drawX = drawX + TILE_SIZE
                            drawY = drawY - TILE_SIZE
                        end
                        
                        -- Tile 13 (INNER_SW): Left 1, Down 1
                        if roadTileID == 13 then
                            drawX = drawX - TILE_SIZE
                            drawY = drawY + TILE_SIZE
                        end

                        -- Tile 14 (INNER_SE): Right 1, Down 1
                        if roadTileID == 14 then
                            drawX = drawX + TILE_SIZE
                            drawY = drawY + TILE_SIZE
                        end
                        
                        -- Tile 3 (CORNER_NE, Dirt BL): Left 1, Down 1 (1px alignment)
                        if roadTileID == 3 then
                            drawX = drawX - 1
                            drawY = drawY + 1
                        end

                        love.graphics.draw(
                            self.tilesetImage,
                            quad,
                            drawX,
                            drawY
                        )
                    end
                end
            end
        end
    else
        -- Fallback when no tileset: draw colored rectangles
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function World:getRocksForDrawing(chunkManager, camera)
    local drawList = {}
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
                x = math.floor(rock.x),
                y = sortY,
                tileId = rock.tileId,
                originalY = math.floor(rock.y)
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

return World
