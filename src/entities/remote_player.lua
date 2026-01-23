-- src/entities/remote_player.lua
-- Animated sprite for remote players in walking simulator

local BaseEntity = require('src.entities.base_entity')

local RemotePlayer = {}
RemotePlayer.__index = RemotePlayer
setmetatable(RemotePlayer, {__index = BaseEntity})

function RemotePlayer:new(x, y, spriteName)
    local self = setmetatable(BaseEntity:new(), RemotePlayer)
    
    self.x = x or 0
    self.y = y or 0
    self.targetX = self.x
    self.targetY = self.y
    self.lerpSpeed = 10
    
    -- Load sprite sheet (will be set from network message or default)
    self.spriteName = spriteName or "Elf Bladedancer"  -- Default fallback
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

function RemotePlayer:setTargetPosition(x, y, dir, isSprinting)
    local dx = x - self.targetX
    local dy = y - self.targetY
    
    if dir then
        self.direction = dir
    else
        if math.abs(dx) > math.abs(dy) then
            self.direction = dx > 0 and "right" or "left"
        elseif dy ~= 0 then
            self.direction = dy > 0 and "down" or "up"
        end
    end
    
    self.targetX = x
    self.targetY = y
    if isSprinting ~= nil then
        self.isSprinting = isSprinting
    end
end

function RemotePlayer:update(dt)
    -- Interpolate position
    local t = math.min(1, self.lerpSpeed * dt)
    self.x = self.x + (self.targetX - self.x) * t
    self.y = self.y + (self.targetY - self.y) * t
    
    -- Detect if moving (for animation)
    local distSq = (self.targetX - self.x)^2 + (self.targetY - self.y)^2
    self.moving = distSq > 0.5
    
    -- Update animation using base class method
    self:updateAnimation(dt, self.moving)
end

return RemotePlayer
