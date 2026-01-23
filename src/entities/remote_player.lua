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
    self.targetX = self.x
    self.targetY = self.y
    self.lerpSpeed = Constants.MIYOO_REMOTE_LERP_SPEED  -- Miyoo-tuned for optimal smoothness

    -- Enhanced interpolation state
    self.lastUpdateTime = love.timer.getTime()
    self.velocityX = 0
    self.velocityY = 0
    self.lastPositionX = self.x
    self.lastPositionY = self.y
    self.extrapolationTime = 0
    self.maxExtrapolationTime = Constants.MIYOO_MAX_EXTRAPOLATION_TIME  -- Max time to extrapolate before stopping
    self.smoothingFactor = 0.15  -- How much to smooth velocity estimates

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
    local currentTime = love.timer.getTime()
    local dt = currentTime - self.lastUpdateTime

    -- Calculate velocity from position change
    if dt > 0.001 then  -- Avoid division by very small numbers
        local newVelocityX = (x - self.lastPositionX) / dt
        local newVelocityY = (y - self.lastPositionY) / dt

        -- Smooth velocity estimation to reduce jitter
        self.velocityX = self.velocityX * (1 - self.smoothingFactor) + newVelocityX * self.smoothingFactor
        self.velocityY = self.velocityY * (1 - self.smoothingFactor) + newVelocityY * self.smoothingFactor
    end

    -- Update last position and time
    self.lastPositionX = self.x
    self.lastPositionY = self.y
    self.lastUpdateTime = currentTime

    -- Reset extrapolation timer since we got a fresh update
    self.extrapolationTime = 0

    -- Set direction
    if dir then
        self.direction = dir
    else
        local dx = x - self.x
        local dy = y - self.y
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
    local distToTargetSq = (self.targetX - self.x)^2 + (self.targetY - self.y)^2
    local distanceToTarget = math.sqrt(distToTargetSq)

    -- If we're close to target, snap to position and stop moving
    if distanceToTarget < 0.1 then
        self.x = self.targetX
        self.y = self.targetY
        self.moving = false
        self.extrapolationTime = 0
    else
        -- Check if we should interpolate towards target or extrapolate using velocity
        local timeSinceUpdate = love.timer.getTime() - self.lastUpdateTime

        if timeSinceUpdate < 0.1 then
            -- Recent update: interpolate towards target
            local t = math.min(1, self.lerpSpeed * dt)
            self.x = self.x + (self.targetX - self.x) * t
            self.y = self.y + (self.targetY - self.y) * t
            self.extrapolationTime = 0
        else
            -- Older update: extrapolate using velocity
            self.extrapolationTime = self.extrapolationTime + dt

            if self.extrapolationTime < self.maxExtrapolationTime then
                -- Extrapolate position using velocity
                self.x = self.x + self.velocityX * dt
                self.y = self.y + self.velocityY * dt
            else
                -- Stop extrapolating after max time to prevent runaway movement
                self.moving = false
            end
        end

        -- Check if we're still moving (some distance from target)
        self.moving = distToTargetSq > 1.0
    end

    -- Update animation using base class method
    self:updateAnimation(dt, self.moving)
end

return RemotePlayer
