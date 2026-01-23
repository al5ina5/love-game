-- src/entities/player.lua
-- Animated sprite player for walking simulator

local Input = require('src.systems.input')
local BaseEntity = require('src.entities.base_entity')

local Player = {}
Player.__index = Player
setmetatable(Player, {__index = BaseEntity})

function Player:new(x, y)
    local self = setmetatable(BaseEntity:new(), Player)
    
    -- Position and movement
    self.x = x or 0
    self.y = y or 0
    self.speed = 60
    
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
    self:loadSprite(spritePath)
    
    return self
end

function Player:update(dt)
    -- Get movement vector from keyboard or gamepad
    local dx, dy = Input:getMovementVector()
    
    -- Check for sprint (shift key or gamepad trigger/shoulder)
    local isSprinting = Input:isSprintDown()
    self.isSprinting = isSprinting  -- Store for network sync
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
    
    -- Update animation using base class method
    self:updateAnimation(dt, self.moving)
end

return Player
