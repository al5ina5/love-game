-- src/world/chunk_manager.lua
-- Chunk-based loading system for efficient world management

local ChunkManager = {}
ChunkManager.__index = ChunkManager

-- Chunk size (in pixels) - should be large enough to reduce overhead but small enough for efficiency
local CHUNK_SIZE = 512  -- 32x32 tiles at 16px per tile

function ChunkManager:new(worldWidth, worldHeight)
    local self = setmetatable({}, ChunkManager)
    
    self.worldWidth = worldWidth
    self.worldHeight = worldHeight
    self.chunkSize = CHUNK_SIZE
    
    -- Calculate chunk grid dimensions
    self.chunksX = math.ceil(worldWidth / CHUNK_SIZE)
    self.chunksY = math.ceil(worldHeight / CHUNK_SIZE)
    
    -- Active chunks (chunks that are currently loaded/visible)
    self.activeChunks = {}  -- Set of chunk keys (cx, cy)
    
    -- Load distance (how many chunks around the player to keep loaded)
    -- Miyoo: Load only current chunk (1x1 = 1 chunk) to prevent freeze
    -- Desktop: Load 3x3 grid (9 chunks) for smooth experience
    local Constants = require('src.constants')
    self.loadDistance = Constants.MIYOO_DEVICE and 0 or 1
    
    return self
end

-- Convert world coordinates to chunk coordinates
function ChunkManager:worldToChunk(x, y)
    local cx = math.floor(x / self.chunkSize)
    local cy = math.floor(y / self.chunkSize)
    return cx, cy
end

-- Get chunk key for hashing
function ChunkManager:getChunkKey(cx, cy)
    return cx .. "," .. cy
end

-- Check if a chunk is active (loaded)
function ChunkManager:isChunkActive(cx, cy)
    local key = self:getChunkKey(cx, cy)
    return self.activeChunks[key] == true
end

-- Mark a chunk as active
function ChunkManager:setChunkActive(cx, cy, active)
    local key = self:getChunkKey(cx, cy)
    if active then
        self.activeChunks[key] = true
    else
        self.activeChunks[key] = nil
    end
end

-- Update active chunks based on player position
function ChunkManager:updateActiveChunks(playerX, playerY)
    local centerCx, centerCy = self:worldToChunk(playerX, playerY)
    
    -- Track which chunks were active before
    local previouslyActive = {}
    for key in pairs(self.activeChunks) do
        previouslyActive[key] = true
    end
    
    -- Clear old active chunks
    self.activeChunks = {}
    
    -- Mark chunks within load distance as active
    for dy = -self.loadDistance, self.loadDistance do
        for dx = -self.loadDistance, self.loadDistance do
            local cx = centerCx + dx
            local cy = centerCy + dy
            
            -- Check bounds
            if cx >= 0 and cx < self.chunksX and cy >= 0 and cy < self.chunksY then
                local key = self:getChunkKey(cx, cy)
                self:setChunkActive(cx, cy, true)
                previouslyActive[key] = nil  -- Remove from previously active (still active)
            end
        end
    end
    
    -- Return list of unloaded chunk keys
    local unloadedChunks = {}
    for key in pairs(previouslyActive) do
        table.insert(unloadedChunks, key)
    end
    
    return unloadedChunks
end

-- Get all active chunk coordinates
function ChunkManager:getActiveChunks()
    local chunks = {}
    for key, _ in pairs(self.activeChunks) do
        local cx, cy = key:match("([^,]+),([^,]+)")
        if cx and cy then
            table.insert(chunks, {cx = tonumber(cx), cy = tonumber(cy)})
        end
    end
    return chunks
end

-- Check if a world position is in an active chunk
function ChunkManager:isPositionActive(x, y)
    local cx, cy = self:worldToChunk(x, y)
    return self:isChunkActive(cx, cy)
end

-- Get world bounds for a chunk
function ChunkManager:getChunkBounds(cx, cy)
    local minX = cx * self.chunkSize
    local minY = cy * self.chunkSize
    local maxX = math.min((cx + 1) * self.chunkSize, self.worldWidth)
    local maxY = math.min((cy + 1) * self.chunkSize, self.worldHeight)
    return minX, minY, maxX, maxY
end

-- Get chunks that intersect with a rectangle (for camera viewport)
function ChunkManager:getChunksInRect(minX, minY, maxX, maxY)
    local chunks = {}
    local startCx, startCy = self:worldToChunk(minX, minY)
    local endCx, endCy = self:worldToChunk(maxX, maxY)
    
    for cy = startCy, endCy do
        for cx = startCx, endCx do
            if cx >= 0 and cx < self.chunksX and cy >= 0 and cy < self.chunksY then
                table.insert(chunks, {cx = cx, cy = cy})
            end
        end
    end
    
    return chunks
end

return ChunkManager
