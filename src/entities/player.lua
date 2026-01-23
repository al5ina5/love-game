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
    -- Randomly select from available human sprites
    local humanSprites = {
        "Adventurous Adolescent",
        "Boisterous Youth",
        "Elf Bladedancer",
        "Elf Enchanter",
        "Elf Lord",
    }
    -- Use a combination of time and random calls to ensure different selection
    -- The seed should already be set in Game:load(), but add some variation
    local randomIndex = math.random(#humanSprites)
    local spriteName = humanSprites[randomIndex]
    local spritePath = "assets/img/sprites/humans/" .. spriteName .. "/" .. spriteName:gsub(" ", "") .. ".png"
    self.spriteName = spriteName  -- Store for network sync
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
    
    -- Sprite size for collision/positioning
    self.width = 16
    self.height = 16
    
    -- For Y-sorting
    self.originY = 12
    
    return self
end

function Player:update(dt)
    -- Get movement vector from keyboard or gamepad
    local dx, dy = Input:getMovementVector()
    
    -- Check for sprint (shift key or gamepad trigger/shoulder)
    local isSprinting = Input:isSprintDown()
    local sprintMultiplier = isSprinting and 1.5 or 1.0
    local currentSpeed = self.speed * sprintMultiplier
    
    -- Update position
    self.x = self.x + dx * currentSpeed * dt
    self.y = self.y + dy * currentSpeed * dt
    
    -- Update facing direction
    self.moving = (dx ~= 0 or dy ~= 0)
    if dx < 0 then self.direction = "left"
    elseif dx > 0 then self.direction = "right"
    elseif dy < 0 then self.direction = "up"
    elseif dy > 0 then self.direction = "down"
    end
    
    -- Animation with faster frame time when sprinting
    local currentFrameTime = isSprinting and (self.frameTime * 0.7) or self.frameTime
    if self.moving then
        self.animTimer = self.animTimer + dt
        if self.animTimer >= currentFrameTime then
            self.animTimer = self.animTimer - currentFrameTime
            self.animFrame = (self.animFrame % self.frameCount) + 1
        end
    else
        -- Reset to first frame when standing still
        self.animTimer = 0
        self.animFrame = 1
    end
end

function Player:draw()
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
        0,  -- rotation
        scaleX, 1  -- scale
    )
end

return Player
