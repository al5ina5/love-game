-- src/ui/map.lua
-- Lightweight in-game minimap system
-- Displays loaded chunks (roads, water, terrain) and player position

local Map = {}
Map.__index = Map

local TILE_SIZE = 16
local MAP_SIZE = 150  -- Map window size in pixels
local MAP_PADDING = 10  -- Distance from screen edge
local MAP_SCALE = 0.05  -- Scale factor for world to map coordinates (1 world pixel = 0.05 map pixels)

function Map:new(world, player)
    local self = setmetatable({}, Map)
    
    self.world = world
    self.player = player
    self.visible = false
    
    -- Map rendering settings
    self.mapSize = MAP_SIZE
    self.padding = MAP_PADDING
    self.scale = MAP_SCALE
    
    -- Colors
    self.colors = {
        background = {0, 0, 0, 0.7},
        border = {1, 1, 1, 0.8},
        grass = {0.2, 0.6, 0.2, 1},
        road = {0.5, 0.35, 0.2, 1},
        water = {0.2, 0.4, 0.8, 1},
        player = {1, 0.2, 0.2, 1},
        unexplored = {0.1, 0.1, 0.1, 1}
    }
    
    return self
end

function Map:toggle()
    self.visible = not self.visible
end

function Map:show()
    self.visible = true
end

function Map:hide()
    self.visible = false
end

function Map:isVisible()
    return self.visible
end

function Map:update(dt)
    -- Map doesn't need updates currently, but keeping for future features
end

function Map:draw()
    if not self.visible then return end
    if not self.world or not self.player then return end
    
    -- Get screen dimensions
    local screenWidth = love.graphics.getWidth()
    local screenHeight = love.graphics.getHeight()
    
    -- Calculate map position (top-right corner)
    local mapX = screenWidth - self.mapSize - self.padding
    local mapY = self.padding
    
    -- Draw map background
    love.graphics.setColor(self.colors.background)
    love.graphics.rectangle("fill", mapX, mapY, self.mapSize, self.mapSize)
    
    -- Draw border
    love.graphics.setColor(self.colors.border)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", mapX, mapY, self.mapSize, self.mapSize)
    
    -- Calculate world bounds based on loaded chunks
    local minX, minY, maxX, maxY = self:getLoadedChunkBounds()
    
    if not minX then
        -- No chunks loaded, just show player position
        self:drawPlayerDot(mapX, mapY, mapX + self.mapSize/2, mapY + self.mapSize/2)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
    -- Add padding to world bounds
    local worldPadding = 200
    minX = minX - worldPadding
    minY = minY - worldPadding
    maxX = maxX + worldPadding
    maxY = maxY + worldPadding
    
    local worldWidth = maxX - minX
    local worldHeight = maxY - minY
    
    -- Calculate scale to fit the explored area in the map
    local scaleX = self.mapSize / worldWidth
    local scaleY = self.mapSize / worldHeight
    local scale = math.min(scaleX, scaleY) * 0.9  -- 0.9 for some margin
    
    -- Function to convert world coordinates to map coordinates
    local function worldToMap(wx, wy)
        local mx = mapX + (wx - minX) * scale
        local my = mapY + (wy - minY) * scale
        return mx, my
    end
    
    -- Draw terrain (grass background for loaded chunks)
    self:drawLoadedChunks(worldToMap, scale)
    
    -- Draw roads
    self:drawRoads(worldToMap, scale)
    
    -- Draw water
    self:drawWater(worldToMap, scale)
    
    -- Draw player position
    local playerMapX, playerMapY = worldToMap(self.player.x, self.player.y)
    self:drawPlayerDot(mapX, mapY, playerMapX, playerMapY)
    
    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function Map:getLoadedChunkBounds()
    if not self.world.loadedChunks then return nil end
    
    local minX, minY, maxX, maxY = nil, nil, nil, nil
    
    for chunkKey, _ in pairs(self.world.loadedChunks) do
        local cx, cy = chunkKey:match("([^,]+),([^,]+)")
        if cx and cy then
            cx, cy = tonumber(cx), tonumber(cy)
            local chunkSize = self.world.chunkSize or 512
            
            local chunkMinX = cx * chunkSize
            local chunkMinY = cy * chunkSize
            local chunkMaxX = (cx + 1) * chunkSize
            local chunkMaxY = (cy + 1) * chunkSize
            
            minX = minX and math.min(minX, chunkMinX) or chunkMinX
            minY = minY and math.min(minY, chunkMinY) or chunkMinY
            maxX = maxX and math.max(maxX, chunkMaxX) or chunkMaxX
            maxY = maxY and math.max(maxY, chunkMaxY) or chunkMaxY
        end
    end
    
    return minX, minY, maxX, maxY
end

function Map:drawLoadedChunks(worldToMap, scale)
    if not self.world.loadedChunks then return end
    
    love.graphics.setColor(self.colors.grass)
    
    for chunkKey, _ in pairs(self.world.loadedChunks) do
        local cx, cy = chunkKey:match("([^,]+),([^,]+)")
        if cx and cy then
            cx, cy = tonumber(cx), tonumber(cy)
            local chunkSize = self.world.chunkSize or 512
            
            local worldX = cx * chunkSize
            local worldY = cy * chunkSize
            
            local mapX, mapY = worldToMap(worldX, worldY)
            local mapChunkSize = chunkSize * scale
            
            love.graphics.rectangle("fill", mapX, mapY, mapChunkSize, mapChunkSize)
        end
    end
end

function Map:drawRoads(worldToMap, scale)
    if not self.world.roads then return end
    
    love.graphics.setColor(self.colors.road)
    
    local tileMapSize = TILE_SIZE * scale
    
    for chunkKey, chunkData in pairs(self.world.roads) do
        local cx, cy = chunkKey:match("([^,]+),([^,]+)")
        if cx and cy then
            cx, cy = tonumber(cx), tonumber(cy)
            local chunkSize = self.world.chunkSize or 512
            local tilesPerChunk = chunkSize / TILE_SIZE
            
            for localTileX, tileRow in pairs(chunkData) do
                for localTileY, tileID in pairs(tileRow) do
                    if tileID then
                        local worldX = (cx * tilesPerChunk + localTileX) * TILE_SIZE
                        local worldY = (cy * tilesPerChunk + localTileY) * TILE_SIZE
                        
                        local mapX, mapY = worldToMap(worldX, worldY)
                        love.graphics.rectangle("fill", mapX, mapY, tileMapSize, tileMapSize)
                    end
                end
            end
        end
    end
end

function Map:drawWater(worldToMap, scale)
    if not self.world.water then return end
    
    love.graphics.setColor(self.colors.water)
    
    local tileMapSize = TILE_SIZE * scale
    
    for chunkKey, chunkData in pairs(self.world.water) do
        local cx, cy = chunkKey:match("([^,]+),([^,]+)")
        if cx and cy then
            cx, cy = tonumber(cx), tonumber(cy)
            local chunkSize = self.world.chunkSize or 512
            local tilesPerChunk = chunkSize / TILE_SIZE
            
            for localTileX, tileRow in pairs(chunkData) do
                for localTileY, tileID in pairs(tileRow) do
                    if tileID then
                        local worldX = (cx * tilesPerChunk + localTileX) * TILE_SIZE
                        local worldY = (cy * tilesPerChunk + localTileY) * TILE_SIZE
                        
                        local mapX, mapY = worldToMap(worldX, worldY)
                        love.graphics.rectangle("fill", mapX, mapY, tileMapSize, tileMapSize)
                    end
                end
            end
        end
    end
end

function Map:drawPlayerDot(mapX, mapY, playerMapX, playerMapY)
    -- Clamp player position to map bounds
    playerMapX = math.max(mapX, math.min(mapX + self.mapSize, playerMapX))
    playerMapY = math.max(mapY, math.min(mapY + self.mapSize, playerMapY))
    
    love.graphics.setColor(self.colors.player)
    love.graphics.circle("fill", playerMapX, playerMapY, 3)
    
    -- Draw player direction indicator (small line)
    if self.player.lastDx and self.player.lastDy then
        local dx, dy = self.player.lastDx, self.player.lastDy
        if dx ~= 0 or dy ~= 0 then
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
                dx, dy = dx / len, dy / len
                love.graphics.line(
                    playerMapX, playerMapY,
                    playerMapX + dx * 6, playerMapY + dy * 6
                )
            end
        end
    end
end

return Map
