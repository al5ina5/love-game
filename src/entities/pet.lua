-- src/entities/pet.lua
-- Cute floating eye pet that follows the player with smart AI
-- Stays close but not too close, wanders when idle, always nearby

local Pet = {}
Pet.__index = Pet

function Pet:new(owner, isRemote, monsterName)
    local self = setmetatable({}, Pet)
    
    -- Owner reference (the player we follow)
    self.owner = owner
    self.isRemote = isRemote or false  -- If true, position comes from network, not AI
    
    -- Position (start near owner)
    self.x = owner.x + 20
    self.y = owner.y - 10
    self.targetX = self.x
    self.targetY = self.y
    self.lerpSpeed = 10  -- For remote pets
    
    -- Velocity for smooth movement
    self.vx = 0
    self.vy = 0
    
    -- Collision check function (set by game)
    self.checkCollision = nil
    
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
    self.bobAmount = 0           -- Pixels to bob up/down (disabled)
    self.bobSpeed = 3            -- Bob frequency
    
    -- Animation state
    self.animTimer = 0
    self.animFrame = 1
    self.frameCount = 4
    self.frameTime = 0.2         -- Slower animation for idle floating
    
    -- Load sprite sheet - use provided monster name or randomly select
    self.monsterName = monsterName
    if not self.monsterName then
        local monsterSprites = {
            "Blinded Grimlock",
            "Bloodshot Eye",
            "Brawny Ogre",
            "Crimson Slaad",
            "Crushing Cyclops",
            "Death Slime",
            "Fungal Myconid",
            "Humongous Ettin",
            "Murky Slaad",
            "Ochre Jelly",
            "Ocular Watcher",
            "Red Cap",
            "Shrieker Mushroom",
            "Stone Troll",
            "Swamp Troll",
        }
        self.monsterName = monsterSprites[math.random(#monsterSprites)]
    end
    self:setMonster(self.monsterName)
    
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

function Pet:setMonster(monsterName)
    if self.monsterName == monsterName and self.spriteLoaded then
        return  -- Already set and loaded
    end
    self.monsterName = monsterName
    self.spritePath = "assets/img/sprites/monsters/" .. monsterName .. "/" .. monsterName:gsub(" ", "") .. ".png"
    self.spriteLoaded = false
end

function Pet:loadSprite()
    if self.spriteLoaded then return end
    if not self.spritePath or self.spritePath == "" then return end

    local success, err = pcall(function()
        local ResourceManager = require('src.game.resource_manager')
        self.spriteSheet = ResourceManager.getImage(self.spritePath)
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
            self.spriteLoaded = true
        end
    end)
    
    if not success then
        print("Pet: Failed to lazy load sprite: " .. tostring(err))
    end
end

function Pet:update(dt)
    -- Remote pets just interpolate to target position
    if self.isRemote then
        local t = math.min(1, self.lerpSpeed * dt)
        self.x = self.x + (self.targetX - self.x) * t
        self.y = self.y + (self.targetY - self.y) * t
        
        -- Still animate
        self.animTimer = self.animTimer + dt
        if self.animTimer >= self.frameTime then
            self.animTimer = self.animTimer - self.frameTime
            self.animFrame = (self.animFrame % self.frameCount) + 1
        end
        
        -- Bobbing animation
        self.bobTimer = self.bobTimer + dt * self.bobSpeed
        
        return
    end
    
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
    
    -- Apply velocity with obstacle avoidance
    local newX = self.x + self.vx * dt
    local newY = self.y + self.vy * dt
    
    -- Check for collisions before moving
    if self.checkCollision and self.checkCollision(newX, newY, self.width, self.height) then
        -- Collision detected! Try alternative paths
        -- First, try moving only horizontally
        local tryX = self.x + self.vx * dt
        local tryY = self.y
        if not self.checkCollision(tryX, tryY, self.width, self.height) then
            newX = tryX
            newY = tryY
        else
            -- Try moving only vertically
            tryX = self.x
            tryY = self.y + self.vy * dt
            if not self.checkCollision(tryX, tryY, self.width, self.height) then
                newX = tryX
                newY = tryY
            else
                -- Try perpendicular movement (steer around obstacle)
                -- Rotate movement vector 90 degrees
                local perpX = -self.vy * dt * currentSpeed * 0.5
                local perpY = self.vx * dt * currentSpeed * 0.5
                tryX = self.x + perpX
                tryY = self.y + perpY
                if not self.checkCollision(tryX, tryY, self.width, self.height) then
                    newX = tryX
                    newY = tryY
                else
                    -- Try opposite perpendicular
                    perpX = self.vy * dt * currentSpeed * 0.5
                    perpY = -self.vx * dt * currentSpeed * 0.5
                    tryX = self.x + perpX
                    tryY = self.y + perpY
                    if not self.checkCollision(tryX, tryY, self.width, self.height) then
                        newX = tryX
                        newY = tryY
                    else
                        -- Completely blocked, reduce velocity to try to find a way around
                        self.vx = self.vx * 0.5
                        self.vy = self.vy * 0.5
                        newX = self.x
                        newY = self.y
                    end
                end
            end
        end
    end
    
    self.x = newX
    self.y = newY
    
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
    if not self.spriteLoaded then
        self:loadSprite()
    end

    -- Round positions to pixels to prevent blur
    local drawX = math.floor(self.x + 0.5)
    local drawY = math.floor(self.y + 0.5)
    
    -- Calculate bob offset (keep as float for smooth animation, but round final position)
    local bobOffset = math.sin(self.bobTimer) * self.bobAmount
    
    -- Draw shadow (smaller, more transparent since it floats)
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.ellipse("fill", drawX + 8, drawY + 14, 4, 2)
    
    -- Draw sprite
    love.graphics.setColor(1, 1, 1)
    
    -- Flip sprite based on direction
    local scaleX = 1
    local offsetX = 0
    if self.direction == "left" then
        scaleX = -1
        offsetX = self.frameWidth or 16
    end
    
    if self.spriteSheet and self.quads[self.animFrame] then
        love.graphics.draw(
            self.spriteSheet,
            self.quads[self.animFrame],
            drawX + offsetX,
            math.floor(drawY + bobOffset + 0.5),
            0,  -- rotation
            scaleX, 1  -- scale
        )
    end
end

return Pet
