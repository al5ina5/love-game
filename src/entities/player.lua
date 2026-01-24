-- src/entities/player.lua
-- Animated sprite player for walking simulator

local Input = require('src.systems.input')
local BaseEntity = require('src.entities.base_entity')
local Constants = require('src.constants')

local Player = {}
Player.__index = Player
setmetatable(Player, {__index = BaseEntity})

function Player:new(x, y)
    local self = setmetatable(BaseEntity:new(), Player)

    -- Position and movement
    self.x = x or 0
    self.y = y or 0
    self.speed = 60

    -- Client-side prediction state
    self.authoritativeX = self.x
    self.authoritativeY = self.y
    self.predictedX = self.x
    self.predictedY = self.y
    self.lastAuthoritativeTime = love.timer.getTime()
    self.predictionErrorX = 0
    self.predictionErrorY = 0
    self.maxPredictionError = Constants.MIYOO_MAX_PREDICTION_ERROR -- pixels before hard correction
    self.correctionSpeed = Constants.MIYOO_PREDICTION_CORRECTION_SPEED   -- how fast to correct prediction errors
    
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
    
    local sprintMultiplier = 1.0
    if isSprinting then
        if Constants.DEV_MODE then
            sprintMultiplier = Constants.DEV_SPRINT_MULTIPLIER or 1.5
        else
            sprintMultiplier = 1.5
        end
    end
    local currentSpeed = self.speed * sprintMultiplier

    -- Update position directly (disable complex prediction for now to fix movement)
    local oldX, oldY = self.x, self.y
    self.x = self.x + dx * currentSpeed * dt
    self.y = self.y + dy * currentSpeed * dt



    -- Keep prediction state in sync for when we re-enable it
    self.predictedX = self.x
    self.predictedY = self.y
    self.authoritativeX = self.x
    self.authoritativeY = self.y

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

-- Update authoritative position from server
function Player:setAuthoritativePosition(x, y, forceCorrection)
    self.authoritativeX = x
    self.authoritativeY = y
    self.lastAuthoritativeTime = love.timer.getTime()

    if forceCorrection then
        -- Hard correction for large desyncs - snap to server position
        print(string.format("Player: Hard correction - predicted(%.1f,%.1f) -> authoritative(%.1f,%.1f)",
            self.predictedX, self.predictedY, x, y))
        self.predictedX = x
        self.predictedY = y
        self.x = x
        self.y = y
    end
    -- If not forceCorrection, just update authoritative position and let normal correction handle it
end

-- Get current prediction error for debugging
function Player:getPredictionError()
    local errorX = self.predictedX - self.authoritativeX
    local errorY = self.predictedY - self.authoritativeY
    return math.sqrt(errorX*errorX + errorY*errorY)
end

return Player
