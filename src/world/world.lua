-- src/world/world.lua
-- World management: tiles, rocks, collision detection

local Protocol = require('src.net.protocol')
local NetworkAdapter = require('src.net.network_adapter')

local World = {}
World.__index = World

-- Constants
local TILE_SIZE = 16

function World:new(worldWidth, worldHeight)
    local self = setmetatable({}, World)
    
    self.worldWidth = worldWidth
    self.worldHeight = worldHeight
    self.tileSize = TILE_SIZE
    
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
    
    return self
end

function World:loadTiles()
    -- Load tileset image
    local tilesetPath = "assets/img/tileset/tileset-v1.png"
    
    local success, err = pcall(function()
        self.tilesetImage = love.graphics.newImage(tilesetPath)
        self.tilesetImage:setFilter("nearest", "nearest")
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
    
    -- Use tile 34 (grass tile)
    local BASIC_GRASS_TILE_ID = 34
    if not self.tilesetQuads[BASIC_GRASS_TILE_ID] then
        BASIC_GRASS_TILE_ID = 1
    end
    
    -- Store which quad to use for each tile variation (all use basic grass)
    self.tileQuads = {
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
    }
    
    -- Don't pre-generate tile map for huge worlds - use procedural generation instead
    -- For a 20,000x20,000 world, that would be 1.56 million tiles in memory!
    -- Instead, we'll generate tiles on-the-fly or use a sparse map
    self.tileMap = nil  -- Use nil to indicate procedural generation
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

function World:sendRocksToClients(network, isHost)
    if not isHost or not network or not self.rocks then
        return
    end
    
    local parts = {Protocol.MSG.ROCKS_DATA, #self.rocks}
    for _, rock in ipairs(self.rocks) do
        table.insert(parts, math.floor(rock.x))
        table.insert(parts, math.floor(rock.y))
        table.insert(parts, rock.tileId)
        table.insert(parts, rock.actualTileNum or self.validTileToActual[rock.tileId] or 1)
    end
    
    local encoded = table.concat(parts, "|")
    
    if network.type == NetworkAdapter.TYPE.LAN and network.server then
        if network.server.broadcast then
            network.server:broadcast(encoded, nil, true)
        end
    elseif network.type == NetworkAdapter.TYPE.RELAY and network.client then
        if network.client.send then
            network.client:send(encoded)
        end
    elseif network.sendMessage then
        network:sendMessage(encoded)
    end
end

function World:getRockPixel(x, y, rock)
    if not self.rocksImageData or not rock or not rock.actualTileNum then return false end
    
    local localX = math.floor(x - rock.x)
    local localY = math.floor(y - rock.y)
    
    if localX < 0 or localX >= TILE_SIZE or localY < 0 or localY >= TILE_SIZE then
        return false
    end
    
    local tilesPerRow = 5
    local actualTileNum = rock.actualTileNum
    local row = math.floor((actualTileNum - 1) / tilesPerRow)
    local col = (actualTileNum - 1) % tilesPerRow
    
    local imageX = col * TILE_SIZE + localX
    local imageY = row * TILE_SIZE + localY
    
    local r, g, b, a = self.rocksImageData:getPixel(imageX, imageY)
    return a > 0.5
end

function World:checkRockCollision(x, y, width, height, chunkManager)
    if not self.rocks or not self.rocksImageData then return false end
    
    local charCollisionHeight = 2
    local charCollisionY = y + height - charCollisionHeight
    
    local samplePoints = {}
    for localX = 0, width - 1, 1 do
        table.insert(samplePoints, {x + localX, charCollisionY})
        if charCollisionHeight > 1 then
            table.insert(samplePoints, {x + localX, charCollisionY + 1})
        end
    end
    
    table.insert(samplePoints, {x, charCollisionY})
    table.insert(samplePoints, {x + width - 1, charCollisionY})
    table.insert(samplePoints, {x + math.floor(width * 0.5), charCollisionY})
    
    -- Only check rocks in nearby chunks for efficiency
    local checkRocks = self.rocks
    if chunkManager then
        -- Filter rocks to only those in active chunks
        local nearbyRocks = {}
        for _, rock in ipairs(self.rocks) do
            if chunkManager:isPositionActive(rock.x, rock.y) then
                table.insert(nearbyRocks, rock)
            end
        end
        checkRocks = nearbyRocks
    end
    
    for _, rock in ipairs(checkRocks) do
        local margin = 2
        if x - margin < rock.x + TILE_SIZE and
           x + width + margin > rock.x and
           charCollisionY - margin < rock.y + TILE_SIZE and
           charCollisionY + charCollisionHeight + margin > rock.y then
            
            for _, point in ipairs(samplePoints) do
                if self:getRockPixel(point[1], point[2], rock) then
                    return true
                end
            end
        end
    end
    return false
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
    -- Use procedural tile generation - all tiles are grass (tileIdx = 1)
    -- No need to check tileMap for huge worlds
    local tileIdx = 1
    local quad = self.tileQuads[tileIdx]
    
    if quad and self.tilesetImage then
        -- Batch draw tiles more efficiently
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.draw(
                    self.tilesetImage,
                    quad,
                    tx * TILE_SIZE,
                    ty * TILE_SIZE
                )
            end
        end
    else
        -- Fallback: draw colored rectangles
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
