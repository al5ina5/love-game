-- src/entities/pet.lua
-- Cute floating eye pet that follows the player with smart AI
-- Stays close but not too close, wanders when idle, always nearby

local Pet = {}
Pet.__index = Pet

function Pet:new(owner)
    local self = setmetatable({}, Pet)
    
    -- Owner reference (the player we follow)
    self.owner = owner
    
    -- Position (start near owner)
    self.x = owner.x + 20
    self.y = owner.y - 10
    
    -- Velocity for smooth movement
    self.vx = 0
    self.vy = 0
    
    -- AI behavior parameters
    self.preferredDistance = 25  -- Sweet spot distance from owner
    self.minDistance = 15        -- Too close! Back off
    self.maxDistance = 50        -- Too far! Catch up
    self.wanderRadius = 8        -- How much to wander when idle
    self.speed = 45              -- Base movement speed
    self.catchUpSpeed = 80       -- Speed when catching up
    
    -- Wander state
    self.wanderTimer = 0
    self.wanderTargetX = 0
    self.wanderTargetY = 0
    self.wanderInterval = 1.5    -- New wander target every X seconds
    
    -- Bobbing animation (floating effect)
    self.bobTimer = 0
    self.bobAmount = 2           -- Pixels to bob up/down
    self.bobSpeed = 3            -- Bob frequency
    
    -- Animation state
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4
    self.frameTime = 0.2         -- Slower animation for idle floating
    
    -- Load sprite sheet
    self.spriteSheet = love.graphics.newImage("assets/img/sprites/Ocular Watcher/OcularWatcher.png")
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
    
    -- Sprite info
    self.width = 16
    self.height = 16
    self.originY = 8  -- Center for Y-sorting (floats above ground)
    
    -- Direction facing
    self.direction = "right"
    
    -- State
    self.state = "idle"  -- idle, following, catching_up
    
    return self
end

function Pet:update(dt)
    -- Calculate distance to owner
    local dx = self.owner.x - self.x
    local dy = self.owner.y - self.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Determine behavior state
    if distance > self.maxDistance then
        self.state = "catching_up"
    elseif distance > self.preferredDistance then
        self.state = "following"
    elseif distance < self.minDistance then
        self.state = "backing_off"
    else
        self.state = "idle"
    end
    
    -- Calculate target position based on state
    local targetX, targetY
    local currentSpeed = self.speed
    
    if self.state == "catching_up" then
        -- Move directly toward owner, fast
        targetX = self.owner.x
        targetY = self.owner.y - 10  -- Float slightly above
        currentSpeed = self.catchUpSpeed
        
    elseif self.state == "following" then
        -- Move toward preferred distance from owner
        local angle = math.atan2(dy, dx)
        targetX = self.owner.x - math.cos(angle) * self.preferredDistance
        targetY = self.owner.y - math.sin(angle) * self.preferredDistance - 5
        
    elseif self.state == "backing_off" then
        -- Move away from owner slightly
        local angle = math.atan2(dy, dx)
        targetX = self.owner.x - math.cos(angle) * self.preferredDistance
        targetY = self.owner.y - math.sin(angle) * self.preferredDistance - 5
        currentSpeed = self.speed * 0.5
        
    else -- idle
        -- Gentle wandering near current position
        self.wanderTimer = self.wanderTimer + dt
        if self.wanderTimer >= self.wanderInterval then
            self.wanderTimer = 0
            -- Pick a new wander target near the owner
            local angle = math.random() * math.pi * 2
            local dist = self.preferredDistance + math.random(-5, 5)
            self.wanderTargetX = self.owner.x + math.cos(angle) * dist
            self.wanderTargetY = self.owner.y + math.sin(angle) * dist - 8
        end
        targetX = self.wanderTargetX
        targetY = self.wanderTargetY
        currentSpeed = self.speed * 0.3  -- Slow wandering
    end
    
    -- Move toward target with smooth acceleration
    local toTargetX = targetX - self.x
    local toTargetY = targetY - self.y
    local distToTarget = math.sqrt(toTargetX * toTargetX + toTargetY * toTargetY)
    
    if distToTarget > 1 then
        -- Normalize and apply speed
        local moveX = (toTargetX / distToTarget) * currentSpeed
        local moveY = (toTargetY / distToTarget) * currentSpeed
        
        -- Smooth acceleration (lerp velocity)
        local accel = 5 * dt
        self.vx = self.vx + (moveX - self.vx) * accel
        self.vy = self.vy + (moveY - self.vy) * accel
    else
        -- Slow down when at target
        self.vx = self.vx * 0.9
        self.vy = self.vy * 0.9
    end
    
    -- Apply velocity
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    
    -- Update facing direction based on velocity
    if math.abs(self.vx) > 2 then
        if self.vx < 0 then
            self.direction = "left"
        else
            self.direction = "right"
        end
    else
        -- Face toward owner when mostly idle
        if self.owner.x < self.x then
            self.direction = "left"
        else
            self.direction = "right"
        end
    end
    
    -- Bobbing animation
    self.bobTimer = self.bobTimer + dt * self.bobSpeed
    
    -- Frame animation (always animates - it's a floating eye!)
    self.animTimer = self.animTimer + dt
    if self.animTimer >= self.frameTime then
        self.animTimer = self.animTimer - self.frameTime
        self.animFrame = (self.animFrame % self.frameCount) + 1
    end
end

function Pet:draw()
    -- Calculate bob offset
    local bobOffset = math.sin(self.bobTimer) * self.bobAmount
    
    -- Draw shadow (smaller, more transparent since it floats)
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.ellipse("fill", self.x + 8, self.y + 14, 4, 2)
    
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
        self.y + bobOffset,
        0,  -- rotation
        scaleX, 1  -- scale
    )
end

return Pet
