-- src/entities/base_entity.lua
-- Base class for entities with common sprite animation and drawing functionality

local BaseEntity = {}
BaseEntity.__index = BaseEntity

function BaseEntity:new()
    local self = setmetatable({}, BaseEntity)
    
    -- Position
    self.x = 0
    self.y = 0
    
    -- Animation state
    self.direction = "down"
    self.moving = false
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4
    self.frameTime = 0.15
    
    -- Sprite info
    self.spriteSheet = nil
    self.frameWidth = 16
    self.frameHeight = 16
    self.quads = {}
    
    -- Size for collision/positioning
    self.width = 16
    self.height = 16
    self.originY = 12
    
    self.isSprinting = false
    
    return self
end

function BaseEntity:loadSprite(spritePath)
    local ResourceManager = require('src.game.resource_manager')
    self.spriteSheet = ResourceManager.getImage(spritePath)
    self.frameWidth = 16
    self.frameHeight = 16
    
    -- Create quads for each frame
    self.quads = {}
    if self.spriteSheet then
        for i = 0, self.frameCount - 1 do
            self.quads[i + 1] = love.graphics.newQuad(
                i * self.frameWidth, 0,
                self.frameWidth, self.frameHeight,
                self.spriteSheet:getDimensions()
            )
        end
    end
end

function BaseEntity:updateAnimation(dt, isMoving)
    -- Animation with faster frame time when sprinting
    local currentFrameTime = self.isSprinting and (self.frameTime * 0.7) or self.frameTime
    if isMoving then
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

function BaseEntity:draw()
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

return BaseEntity
