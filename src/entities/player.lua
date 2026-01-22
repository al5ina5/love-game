-- src/entities/player.lua
-- Animated sprite player for walking simulator

local Input = require('src.systems.input')

local Player = {}
Player.__index = Player

function Player:new(x, y)
    local self = setmetatable({}, Player)
    
    -- Position and movement
    self.x = x or 0
    self.y = y or 0
    self.speed = 60
    
    -- Animation state
    self.direction = "down"
    self.moving = false
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4  -- 4 frames in the sprite sheet
    self.frameTime = 0.15  -- seconds per frame
    
    -- Load sprite sheet (16x16 per frame, 4 frames horizontal)
    self.spriteSheet = love.graphics.newImage("assets/img/sprites/Merfolk Mystic/MerfolkMystic.png")
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
    
    -- Sprite size for collision/positioning
    self.width = 16
    self.height = 16
    
    -- For Y-sorting
    self.originY = 12
    
    return self
end

function Player:update(dt)
    local dx, dy = 0, 0
    
    -- Read input (WASD / arrows)
    if Input:isDown("left") or Input:isDown("a") then dx = -1 end
    if Input:isDown("right") or Input:isDown("d") then dx = 1 end
    if Input:isDown("up") or Input:isDown("w") then dy = -1 end
    if Input:isDown("down") or Input:isDown("s") then dy = 1 end
    
    -- Normalize diagonal movement
    if dx ~= 0 and dy ~= 0 then
        dx = dx * 0.7071
        dy = dy * 0.7071
    end
    
    -- Update position
    self.x = self.x + dx * self.speed * dt
    self.y = self.y + dy * self.speed * dt
    
    -- Update facing direction
    self.moving = (dx ~= 0 or dy ~= 0)
    if dx < 0 then self.direction = "left"
    elseif dx > 0 then self.direction = "right"
    elseif dy < 0 then self.direction = "up"
    elseif dy > 0 then self.direction = "down"
    end
    
    -- Animation
    if self.moving then
        self.animTimer = self.animTimer + dt
        if self.animTimer >= self.frameTime then
            self.animTimer = self.animTimer - self.frameTime
            self.animFrame = (self.animFrame % self.frameCount) + 1
        end
    else
        -- Reset to first frame when standing still
        self.animTimer = 0
        self.animFrame = 1
    end
end

function Player:draw()
    -- Draw shadow
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", self.x + 8, self.y + 14, 6, 3)
    
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
        self.x + offsetX,
        self.y,
        0,  -- rotation
        scaleX, 1  -- scale
    )
end

return Player
