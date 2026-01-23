-- src/entities/remote_player.lua
-- Animated sprite for remote players in walking simulator

local RemotePlayer = {}
RemotePlayer.__index = RemotePlayer

function RemotePlayer:new(x, y, spriteName)
    local self = setmetatable({}, RemotePlayer)
    
    self.x = x or 0
    self.y = y or 0
    self.targetX = self.x
    self.targetY = self.y
    self.lerpSpeed = 10
    
    self.direction = "down"
    self.moving = false
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4
    self.frameTime = 0.15
    
    -- Load sprite sheet (will be set from network message or default)
    self.spriteName = spriteName or "Elf Bladedancer"  -- Default fallback
    self:setSprite(self.spriteName)
    
    self.width = 16
    self.height = 16
    self.originY = 12
    
    return self
end

function RemotePlayer:setSprite(spriteName)
    if self.spriteName == spriteName and self.spriteSheet then
        return  -- Already set
    end
    self.spriteName = spriteName
    local spritePath = "assets/img/sprites/humans/" .. spriteName .. "/" .. spriteName:gsub(" ", "") .. ".png"
    self.spriteSheet = love.graphics.newImage(spritePath)
    self.frameWidth = 16
    self.frameHeight = 16
    
    -- Create quads for each frame
    self.quads = {}
    for i = 0, self.frameCount - 1 do
        self.quads[i + 1] = love.graphics.newQuad(
            i * self.frameWidth, 0,
            self.frameWidth, self.frameHeight,
            self.spriteSheet:getDimensions()
        )
    end
end

function RemotePlayer:setTargetPosition(x, y, dir)
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
end

function RemotePlayer:update(dt)
    -- Interpolate position
    local t = math.min(1, self.lerpSpeed * dt)
    self.x = self.x + (self.targetX - self.x) * t
    self.y = self.y + (self.targetY - self.y) * t
    
    -- Detect if moving (for animation)
    local distSq = (self.targetX - self.x)^2 + (self.targetY - self.y)^2
    self.moving = distSq > 0.5
    
    -- Animation
    if self.moving then
        self.animTimer = self.animTimer + dt
        if self.animTimer >= self.frameTime then
            self.animTimer = self.animTimer - self.frameTime
            self.animFrame = (self.animFrame % self.frameCount) + 1
        end
    else
        self.animTimer = 0
        self.animFrame = 1
    end
end

function RemotePlayer:draw()
    -- Round positions to pixels to prevent blur
    local drawX = math.floor(self.x + 0.5)
    local drawY = math.floor(self.y + 0.5)
    
    -- Draw shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", drawX + 8, drawY + 14, 6, 3)
    
    -- Draw sprite
    love.graphics.setColor(1, 1, 1)
    
    -- Flip sprite based on direction
    local scaleX = 1
    local offsetX = 0
    if self.direction == "left" then
        scaleX = -1
        offsetX = self.frameWidth
    end
    
    love.graphics.draw(
        self.spriteSheet,
        self.quads[self.animFrame],
        drawX + offsetX,
        drawY,
        0,
        scaleX, 1
    )
end

return RemotePlayer
