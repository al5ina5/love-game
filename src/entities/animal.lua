-- src/entities/animal.lua
-- Animal entity with peaceful wander AI and group behavior

local BaseEntity = require('src.entities.base_entity')

local Animal = {}
Animal.__index = Animal
setmetatable(Animal, {__index = BaseEntity})

-- Animal states
local STATE_IDLE = "idle"           -- Standing still, looking around
local STATE_GRAZING = "grazing"     -- Looking down, staying still
local STATE_WANDERING = "wandering" -- Taking a few steps

function Animal:new(x, y, spritePath, animalName, speed)
    local self = setmetatable(BaseEntity:new(), Animal)
    
    -- Position
    self.x = x or 0
    self.y = y or 0
    
    -- Movement
    self.speed = speed or 30  -- Default speed (slower than player)
    self.moving = false
    
    -- Peaceful behavior state machine
    self.state = STATE_IDLE
    self.stateTimer = 0
    self.nextStateTime = math.random(3, 8)  -- Stay idle for 3-8 seconds initially
    
    -- Wander AI state (for when wandering)
    self.wanderDirection = math.random() * math.pi * 2  -- Random initial direction in radians
    self.wanderStepsRemaining = 0  -- How many steps to take before stopping
    self.wanderStepDistance = 0  -- Distance traveled in current step sequence
    
    -- Look around behavior (for idle state)
    self.lookTimer = 0
    self.lookChangeTime = math.random(1, 3)  -- Change look direction every 1-3 seconds
    self.lastLookDirection = "down"
    
    -- Group behavior
    self.groupCenterX = x  -- Center of the group/area
    self.groupCenterY = y
    self.groupRadius = 150  -- How far from center they can wander
    
    -- Load sprite
    self.animalName = animalName or "Animal"
    self.spritePath = spritePath or ""  -- Store for network sync
    self:loadSprite(spritePath)
    
    -- Set initial direction
    self.direction = "down"
    
    return self
end

function Animal:updateDirectionFromAngle(angle)
    -- Convert angle to direction string
    -- 0 = right, π/2 = down, π = left, -π/2 = up
    if angle >= -math.pi / 4 and angle < math.pi / 4 then
        self.direction = "right"
    elseif angle >= math.pi / 4 and angle < 3 * math.pi / 4 then
        self.direction = "down"
    elseif angle >= 3 * math.pi / 4 or angle < -3 * math.pi / 4 then
        self.direction = "left"
    else
        self.direction = "up"
    end
end

function Animal:update(dt, checkCollision)
    -- Update state timer
    self.stateTimer = self.stateTimer + dt
    
    -- State machine for peaceful behavior
    if self.state == STATE_IDLE then
        self:updateIdle(dt)
    elseif self.state == STATE_GRAZING then
        self:updateGrazing(dt)
    elseif self.state == STATE_WANDERING then
        self:updateWandering(dt, checkCollision)
    end
    
    -- Check if we should transition to a new state
    if self.stateTimer >= self.nextStateTime then
        self:transitionToNewState()
    end
    
    -- Keep within group bounds
    local dx = self.x - self.groupCenterX
    local dy = self.y - self.groupCenterY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > self.groupRadius then
        -- Pull back towards center
        local angle = math.atan2(dy, dx)
        self.x = self.groupCenterX + math.cos(angle) * self.groupRadius
        self.y = self.groupCenterY + math.sin(angle) * self.groupRadius
        -- If too far, go back to idle
        if self.state == STATE_WANDERING then
            self.state = STATE_IDLE
            self.stateTimer = 0
            self.nextStateTime = math.random(2, 5)
        end
    end
    
    -- Update animation
    self:updateAnimation(dt, self.moving)
end

function Animal:updateIdle(dt)
    -- Not moving, just looking around
    self.moving = false
    
    -- Look around occasionally
    self.lookTimer = self.lookTimer + dt
    if self.lookTimer >= self.lookChangeTime then
        self.lookTimer = 0
        self.lookChangeTime = math.random(1.5, 4)  -- Look around every 1.5-4 seconds
        
        -- Change look direction (look left, right, up, down, or back to last direction)
        local directions = {"up", "down", "left", "right"}
        if math.random() < 0.3 then
            -- 30% chance to look back at last direction
            self.direction = self.lastLookDirection
        else
            -- Otherwise pick a random direction
            self.direction = directions[math.random(#directions)]
            self.lastLookDirection = self.direction
        end
    end
end

function Animal:updateGrazing(dt)
    -- Looking down, staying still
    self.moving = false
    self.direction = "down"  -- Always look down when grazing
end

function Animal:updateWandering(dt, checkCollision)
    -- Take a few steps in a direction
    if self.wanderStepsRemaining <= 0 then
        -- Finished this wandering sequence, stop
        self.moving = false
        return
    end
    
    -- Calculate movement vector (slower, more peaceful)
    local peacefulSpeed = self.speed * 0.6  -- 60% of normal speed for peaceful movement
    local moveX = math.cos(self.wanderDirection) * peacefulSpeed * dt
    local moveY = math.sin(self.wanderDirection) * peacefulSpeed * dt
    
    -- Store old position for collision
    local oldX = self.x
    local oldY = self.y
    
    -- Update position
    self.x = self.x + moveX
    self.y = self.y + moveY
    
    -- Check collision if function provided
    if checkCollision then
        if checkCollision(self.x, self.y, self.width, self.height) then
            -- Collision detected, revert position and stop wandering
            self.x = oldX
            self.y = oldY
            self.wanderStepsRemaining = 0
            self.moving = false
            return
        end
    end
    
    -- Update direction based on movement
    self:updateDirectionFromAngle(self.wanderDirection)
    self.moving = true
    
    -- Track distance traveled
    self.wanderStepDistance = self.wanderStepDistance + math.sqrt(moveX * moveX + moveY * moveY)
    
    -- If we've traveled enough distance (about 20-40 pixels), take one step off
    local maxStepDistance = 30  -- Average distance per "step"
    if self.wanderStepDistance >= maxStepDistance then
        self.wanderStepsRemaining = self.wanderStepsRemaining - 1
        self.wanderStepDistance = 0  -- Reset for next step
        
        -- If we still have steps, maybe change direction slightly for more natural movement
        if self.wanderStepsRemaining > 0 and math.random() < 0.3 then
            -- 30% chance to slightly adjust direction
            self.wanderDirection = self.wanderDirection + (math.random() - 0.5) * math.pi / 4
        end
    end
    
    -- Safety check: if we've been wandering too long, stop
    if self.stateTimer >= self.nextStateTime then
        self.wanderStepsRemaining = 0
        self.moving = false
    end
end

function Animal:transitionToNewState()
    -- Reset state timer
    self.stateTimer = 0
    
    -- Decide next state based on current state
    if self.state == STATE_IDLE then
        -- From idle, can go to grazing or wandering
        if math.random() < 0.4 then
            -- 40% chance to start grazing
            self.state = STATE_GRAZING
            self.nextStateTime = math.random(4, 8)  -- Graze for 4-8 seconds
        else
            -- 60% chance to start wandering
            self.state = STATE_WANDERING
            self:startWandering()
            self.nextStateTime = math.random(2, 4)  -- Wander for 2-4 seconds max
        end
    elseif self.state == STATE_GRAZING then
        -- From grazing, go back to idle or wander
        if math.random() < 0.6 then
            self.state = STATE_IDLE
            self.nextStateTime = math.random(3, 7)  -- Idle for 3-7 seconds
        else
            self.state = STATE_WANDERING
            self:startWandering()
            self.nextStateTime = math.random(2, 4)
        end
    elseif self.state == STATE_WANDERING then
        -- From wandering, go to idle or grazing
        if math.random() < 0.5 then
            self.state = STATE_IDLE
            self.nextStateTime = math.random(4, 8)  -- Idle for 4-8 seconds
        else
            self.state = STATE_GRAZING
            self.nextStateTime = math.random(3, 6)  -- Graze for 3-6 seconds
        end
        self.wanderStepsRemaining = 0
        self.moving = false
    end
end

function Animal:startWandering()
    -- Calculate angle towards group center with some randomness
    local dx = self.groupCenterX - self.x
    local dy = self.groupCenterY - self.y
    local distToCenter = math.sqrt(dx * dx + dy * dy)
    
    -- If too far from center, move back towards it
    if distToCenter > self.groupRadius * 0.8 then
        self.wanderDirection = math.atan2(dy, dx)
    else
        -- Otherwise, wander randomly but stay near center
        local angleToCenter = math.atan2(dy, dx)
        -- Add random variation: -π/3 to π/3 (smaller angle for more peaceful wandering)
        self.wanderDirection = angleToCenter + (math.random() - 0.5) * (math.pi * 2 / 3)
    end
    
    -- Take 2-4 "steps" (each step is about 30 pixels of movement)
    self.wanderStepsRemaining = math.random(2, 4)
    self.wanderStepDistance = 0
end

function Animal:setGroupCenter(x, y, radius)
    self.groupCenterX = x
    self.groupCenterY = y
    self.groupRadius = radius or 150
end

return Animal
