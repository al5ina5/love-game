-- src/entities/npc.lua
-- Static NPC with idle animation and dialogue

local NPC = {}
NPC.__index = NPC

function NPC:new(x, y, spritePath, name, dialogueLines)
    local self = setmetatable({}, NPC)
    
    -- Position
    self.x = x or 0
    self.y = y or 0
    
    -- Interaction
    self.name = name or "???"
    self.dialogueLines = dialogueLines or {"..."}
    self.interactionRadius = 24  -- pixels
    
    -- Store sprite path for network sync
    self.spritePath = spritePath or ""
    
    -- Animation state
    self.direction = "down"
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4  -- 4 frames in the sprite sheet
    self.frameTime = 0.2  -- seconds per frame (slightly slower for idle)
    
    -- Load sprite sheet (16x16 per frame, 4 frames horizontal)
    self:loadSprite(spritePath)
    
    -- Sprite size for collision/positioning
    self.width = 16
    self.height = 16
    
    -- For Y-sorting
    self.originY = 12
    
    return self
end

function NPC:loadSprite(spritePath)
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

function NPC:update(dt)
    -- Animate idle
    self.animTimer = self.animTimer + dt
    if self.animTimer >= self.frameTime then
        self.animTimer = self.animTimer - self.frameTime
        self.animFrame = (self.animFrame % self.frameCount) + 1
    end
end

function NPC:isPlayerInRange(player)
    local dx = (self.x + 8) - (player.x + 8)  -- center to center
    local dy = (self.y + 8) - (player.y + 8)
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= self.interactionRadius
end

function NPC:getDialogue()
    return self.name, self.dialogueLines
end

function NPC:draw()
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

return NPC
