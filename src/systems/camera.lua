-- src/systems/camera.lua
-- Smooth camera that follows the player
-- Think of this like a React context that wraps your render

local Camera = {}
Camera.__index = Camera

function Camera:new(target)
    local self = setmetatable({}, Camera)
    
    self.x = 0
    self.y = 0
    self.target = target  -- Entity to follow (usually the player)
    self.smoothness = 2.5 -- Lower = smoother/slower follow (was 5, now gentler)
    
    -- Viewport size (game resolution before scaling)
    self.width = 320
    self.height = 180
    
    -- Dead zone - camera won't move if target is within this distance from center
    -- This prevents micro-jitter when the player is nearly centered
    self.deadZone = 1.0
    
    -- Smoothed position (sub-pixel accurate for interpolation)
    self.smoothX = 0
    self.smoothY = 0
    
    -- Initial position (center on target immediately)
    if target then
        self.x = target.x - self.width / 2
        self.y = target.y - self.height / 2
        self.smoothX = self.x
        self.smoothY = self.y
    end
    
    return self
end

function Camera:update(dt)
    if not self.target then return end
    
    -- Calculate desired camera position (centered on target)
    local targetX = self.target.x + 8 - self.width / 2  -- +8 to center on sprite middle
    local targetY = self.target.y + 8 - self.height / 2
    
    -- Calculate distance to target
    local dx = targetX - self.smoothX
    local dy = targetY - self.smoothY
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Only move camera if outside dead zone (prevents micro-jitter)
    if dist > self.deadZone then
        -- Smooth lerp towards target (exponential ease-out)
        -- Use a frame-rate independent smoothing formula
        local t = 1 - math.exp(-self.smoothness * dt)
        self.smoothX = self.smoothX + dx * t
        self.smoothY = self.smoothY + dy * t
    end
    
    -- Snap to target if very close (prevents endless floating point creep)
    if dist < 0.01 then
        self.smoothX = targetX
        self.smoothY = targetY
    end
    
    -- Round to pixel grid for final render position
    -- This prevents sub-pixel rendering artifacts while keeping smooth motion
    self.x = math.floor(self.smoothX + 0.5)
    self.y = math.floor(self.smoothY + 0.5)
end

-- Call before drawing world content
function Camera:attach()
    love.graphics.push()
    -- Translate by negative camera position (already pixel-snapped in update)
    love.graphics.translate(-self.x, -self.y)
end

-- Call after drawing world content, before drawing HUD
function Camera:detach()
    love.graphics.pop()
end

-- Convert screen coordinates to world coordinates
function Camera:screenToWorld(screenX, screenY)
    return screenX + self.x, screenY + self.y
end

-- Convert world coordinates to screen coordinates
function Camera:worldToScreen(worldX, worldY)
    return worldX - self.x, worldY - self.y
end

return Camera
