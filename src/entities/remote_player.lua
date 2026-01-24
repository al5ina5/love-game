-- src/entities/remote_player.lua
-- Animated sprite for remote players in walking simulator

local BaseEntity = require('src.entities.base_entity')
local Constants = require('src.constants')

local RemotePlayer = {}
RemotePlayer.__index = RemotePlayer
setmetatable(RemotePlayer, {__index = BaseEntity})

function RemotePlayer:new(x, y, spriteName)
    local self = setmetatable(BaseEntity:new(), RemotePlayer)

    self.x = x or 0
    self.y = y or 0
    
    -- Snapshot Buffer
    self.snapshots = {}
    self:addSnapshot(love.timer.getTime(), self.x, self.y)
    
    -- Interpolation Settings
    -- 100ms buffering means we render the player where they were 100ms ago.
    -- This allows us to smoothly interpolate between packets even if they arrive with jitter.
    -- Server sends at 20Hz (50ms interval). 100ms = 2 packets buffer.
    self.interpolationDelay = 0.1 

    -- Fallback for lag
    self.lastUpdateTime = love.timer.getTime()
    self.lastKnownDirection = "down"

    -- Load sprite sheet
    self.spriteName = spriteName or "Elf Bladedancer"
    self:setSprite(self.spriteName)

    return self
end

function RemotePlayer:setSprite(spriteName)
    if self.spriteName == spriteName and self.spriteSheet then
        return  -- Already set
    end
    self.spriteName = spriteName
    local spritePath = "assets/img/sprites/humans/" .. spriteName .. "/" .. spriteName:gsub(" ", "") .. ".png"
    self:loadSprite(spritePath)
end

function RemotePlayer:addSnapshot(timestamp, x, y)
    -- Insert new snapshot sorted by time (usually just append)
    table.insert(self.snapshots, {
        time = timestamp,
        x = x,
        y = y
    })
    
    -- Keep buffer finite (e.g. keep last 20 snapshots ~ 1 second)
    if #self.snapshots > 20 then
        table.remove(self.snapshots, 1)
    end
end

function RemotePlayer:setTargetPosition(x, y, dir, isSprinting)
    local now = love.timer.getTime()
    
    -- Add the authoritative position update to our snapshot history
    self:addSnapshot(now, x, y)

    if dir then self.lastKnownDirection = dir end
    if isSprinting ~= nil then self.isSprinting = isSprinting end
    
    self.lastUpdateTime = now
end

function RemotePlayer:update(dt)
    local now = love.timer.getTime()
    local renderTime = now - self.interpolationDelay
    
    -- Find the two snapshots surrounding renderTime
    -- snapshots[i].time <= renderTime < snapshots[i+1].time
    
    local prev, next = nil, nil
    
    for i = 1, #self.snapshots - 1 do
        if self.snapshots[i].time <= renderTime and self.snapshots[i+1].time >= renderTime then
            prev = self.snapshots[i]
            next = self.snapshots[i+1]
            break
        end
    end
    
    if prev and next then
        -- INTERPOLATION: We are within our buffered history
        local totalTime = next.time - prev.time
        local timeIntoFrame = renderTime - prev.time
        local alpha = 0
        if totalTime > 0.0001 then
            alpha = timeIntoFrame / totalTime
        end
        
        -- Linear interpolation
        local newX = prev.x + (next.x - prev.x) * alpha
        local newY = prev.y + (next.y - prev.y) * alpha
        
        -- Determine direction based on movement
        local dx = newX - self.x
        local dy = newY - self.y
        if math.abs(dx) > 0.01 or math.abs(dy) > 0.01 then
            if math.abs(dx) > math.abs(dy) then
                self.direction = dx > 0 and "right" or "left"
            else
                self.direction = dy > 0 and "down" or "up"
            end
            self.moving = true
        else
            self.moving = false
            -- Keep last direction if stopped
        end
        
        self.x = newX
        self.y = newY
        
    elseif #self.snapshots >= 1 then
        -- EXTRAPOLATION / FALLBACK
        -- If renderTime is newer than our newest snapshot (running dry / lag)
        -- OR renderTime is older than our oldest snapshot (shouldn't happen with sufficient buffer)
        
        local newest = self.snapshots[#self.snapshots]
        
        if renderTime > newest.time then
            -- We ran out of future packets. Snap to latest or extrapolate?
            -- Safe bet: Snap to latest (maybe slide slightly).
            -- For now, just slide towards it or stay there.
            
            -- Simple lerp to catch up if we are behind real-time
            local dx = newest.x - self.x
            local dy = newest.y - self.y
            
             -- If very close, just snap
            if dx*dx + dy*dy < 1 then
                self.x = newest.x
                self.y = newest.y
                self.moving = false
            else
                -- Eased catchup
                self.x = self.x + dx * 10 * dt
                self.y = self.y + dy * 10 * dt
                self.moving = true
                
                 -- Direction
                if math.abs(dx) > math.abs(dy) then
                    self.direction = dx > 0 and "right" or "left"
                else
                    self.direction = dy > 0 and "down" or "up"
                end
            end
        else
            -- We are way behind history? Just snap to oldest.
            self.x = self.snapshots[1].x
            self.y = self.snapshots[1].y
        end
    end

    -- Update animation using base class method
    self:updateAnimation(dt, self.moving)
end

return RemotePlayer
