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
    
    -- Industrial Grade CSP State
    self.inputHistory = {} -- Queue of {seq, dx, dy, sprinting}
    self.nextSeqNum = 1
    self.lastProcessedSeq = 0
    
    -- Visual Smoothing
    self.visualX = self.x
    self.visualY = self.y
    self.smoothingFactor = 0.2 -- Speed to slide visual toward physical (0.1 - 0.5)
    
    self.lastDx = 0
    self.lastDy = 0
    
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

    -- Update position directly (CSP Prediction)
    self.x = self.x + dx * currentSpeed * dt
    self.y = self.y + dy * currentSpeed * dt

    -- Record input in history for reconciliation
    table.insert(self.inputHistory, {
        seq = self.nextSeqNum,
        dx = dx,
        dy = dy,
        sprinting = isSprinting,
        dt = dt
    })
    
    self.lastSeqUsed = self.nextSeqNum
    self.nextSeqNum = self.nextSeqNum + 1
    self.lastDx = dx
    self.lastDy = dy

    -- Update facing direction
    self.moving = (dx ~= 0 or dy ~= 0)
    if dx < 0 then self.direction = "left"
    elseif dx > 0 then self.direction = "right"
    elseif dy < 0 then self.direction = "up"
    elseif dy > 0 then self.direction = "down"
    end

    -- Visual Smoothing: Interpolate visualX/Y toward real x/y
    -- This hides minor snapping during reconciliation
    local smoothDt = math.min(dt * 15, 1.0) -- Adjust 15 for snappiness
    self.visualX = self.visualX + (self.x - self.visualX) * smoothDt
    self.visualY = self.visualY + (self.y - self.visualY) * smoothDt

    -- Update animation using base class method
    self:updateAnimation(dt, self.moving)
end

-- Reconcile authoritative position from server
function Player:setAuthoritativePosition(srvX, srvY, lastProcessedSeq)
    -- 1. Remove processed inputs from history
    while #self.inputHistory > 0 and self.inputHistory[1].seq <= lastProcessedSeq do
        table.remove(self.inputHistory, 1)
    end

    -- 2. Reset position to authoritative server position
    self.x = srvX
    self.y = srvY

    -- 3. Re-simulate unacknowledged inputs
    for _, input in ipairs(self.inputHistory) do
        local multiplier = input.sprinting and 1.5 or 1.0
        local speed = self.speed * multiplier
        self.x = self.x + input.dx * speed * input.dt
        self.y = self.y + input.dy * speed * input.dt
    end
end

-- Get current prediction error for debugging
function Player:getPredictionError()
    local errorX = self.predictedX - self.authoritativeX
    local errorY = self.predictedY - self.authoritativeY
    return math.sqrt(errorX*errorX + errorY*errorY)
end

return Player
