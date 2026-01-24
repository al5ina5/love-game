-- src/systems/camera.lua
-- Smooth camera that follows the player
-- Think of this like a React context that wraps your render

local Camera = {}
Camera.__index = Camera

-- Calculate dynamic viewport size based on screen dimensions
-- Smaller screens get a smaller viewport (more zoomed in) for better visibility
function Camera.calculateViewport(screenWidth, screenHeight)
    -- Base viewport (default for large screens)
    local baseWidth = 320
    local baseHeight = 180
    local aspectRatio = baseWidth / baseHeight  -- 16:9
    
    -- Determine viewport size based on screen size
    -- Smaller screens = smaller viewport = more zoomed in = larger characters
    local viewportWidth, viewportHeight
    
    if screenWidth and screenHeight then
        -- Use the smaller dimension to determine zoom level
        local minDimension = math.min(screenWidth, screenHeight)
        
        if minDimension < 480 then
            -- Very small screens (like Portmaster Muyoo Flip) - most zoomed in
            viewportWidth = 200
            viewportHeight = 112.5
        elseif minDimension < 640 then
            -- Small screens - moderately zoomed in
            viewportWidth = 240
            viewportHeight = 135
        elseif minDimension < 800 then
            -- Medium-small screens - slightly zoomed in
            viewportWidth = 280
            viewportHeight = 157.5
        else
            -- Large screens - default viewport
            viewportWidth = baseWidth
            viewportHeight = baseHeight
        end
    else
        -- Fallback to default if screen size not provided
        viewportWidth = baseWidth
        viewportHeight = baseHeight
    end
    
    return viewportWidth, viewportHeight
end

function Camera:new(target, worldWidth, worldHeight, viewportWidth, viewportHeight)
    local self = setmetatable({}, Camera)
    
    self.x = 0
    self.y = 0
    self.target = target  -- Entity to follow (usually the player)
    self.smoothness = 2.5 -- Lower = smoother/slower follow (was 5, now gentler)
    
    -- Viewport size (game resolution before scaling)
    -- Use provided viewport or calculate dynamically based on screen size
    if viewportWidth and viewportHeight then
        self.width = viewportWidth
        self.height = viewportHeight
    else
        -- Calculate dynamically if not provided
        local screenWidth = love.graphics and love.graphics.getWidth() or nil
        local screenHeight = love.graphics and love.graphics.getHeight() or nil
        self.width, self.height = Camera.calculateViewport(screenWidth, screenHeight)
    end
    
    -- Store base viewport size for zoom calculations
    self.baseWidth = self.width
    self.baseHeight = self.height
    
    -- Zoom level (1.0 = normal, 0.5 = zoomed out 2x, 2.0 = zoomed in 2x)
    self.zoom = 1.0
    self.minZoom = 0.25  -- Can zoom out to see 4x more area
    self.maxZoom = 4.0   -- Can zoom in to see 4x less area (more detail)
    
    -- World bounds for clamping
    self.worldWidth = worldWidth or nil
    self.worldHeight = worldHeight or nil
    
    -- Dead zone removed - using continuous smooth interpolation for perfect smoothness
    
    -- Smoothed position (sub-pixel accurate for interpolation)
    self.smoothX = 0
    self.smoothY = 0
    
    -- Initial position (center on target immediately)
    if target then
        self.x = target.x - self.width / 2
        self.y = target.y - self.height / 2
        self.smoothX = self.x
        self.smoothY = self.y
        -- Clamp initial position to world bounds
        self:clampToWorld()
    end
    
    return self
end

function Camera:clampToWorld()
    if not self.worldWidth or not self.worldHeight then return end
    
    -- Calculate effective viewport size based on zoom
    local effectiveWidth = self.width
    local effectiveHeight = self.height
    
    -- Clamp camera position so it doesn't go beyond world bounds
    -- If world is smaller than viewport, center the camera
    if self.worldWidth <= effectiveWidth then
        self.smoothX = (self.worldWidth - effectiveWidth) / 2
    else
        self.smoothX = math.max(0, math.min(self.smoothX, self.worldWidth - effectiveWidth))
    end
    
    if self.worldHeight <= effectiveHeight then
        self.smoothY = (self.worldHeight - effectiveHeight) / 2
    else
        self.smoothY = math.max(0, math.min(self.smoothY, self.worldHeight - effectiveHeight))
    end
end

-- Update viewport size dynamically (e.g., on window resize)
function Camera:updateViewport(viewportWidth, viewportHeight)
    if viewportWidth and viewportHeight then
        self.baseWidth = viewportWidth
        self.baseHeight = viewportHeight
        self.width = viewportWidth / self.zoom
        self.height = viewportHeight / self.zoom
        -- Recalculate position to maintain centering on target
        if self.target then
            self.smoothX = self.target.x + 8 - self.width / 2
            self.smoothY = self.target.y + 8 - self.height / 2
            self:clampToWorld()
            self.x = self.smoothX
            self.y = self.smoothY
        end
    end
end

function Camera:update(dt)
    if not self.target then return end
    
    -- Calculate desired camera position (centered on target)
    local targetX = self.target.x + 8 - self.width / 2  -- +8 to center on sprite middle
    local targetY = self.target.y + 8 - self.height / 2
    
    -- Clamp target position to world bounds before calculating distance
    if self.worldWidth and self.worldHeight then
        if self.worldWidth <= self.width then
            targetX = (self.worldWidth - self.width) / 2
        else
            targetX = math.max(0, math.min(targetX, self.worldWidth - self.width))
        end
        
        if self.worldHeight <= self.height then
            targetY = (self.worldHeight - self.height) / 2
        else
            targetY = math.max(0, math.min(targetY, self.worldHeight - self.height))
        end
    end
    
    -- Calculate distance to target
    local dx = targetX - self.smoothX
    local dy = targetY - self.smoothY
    local dist = math.sqrt(dx * dx + dy * dy)
    
    -- Always smoothly interpolate towards target (no dead zone for final pixels)
    -- Use exponential ease-out for perfectly smooth motion
    local t = 1 - math.exp(-self.smoothness * dt)
    self.smoothX = self.smoothX + dx * t
    self.smoothY = self.smoothY + dy * t
    
    -- Clamp to world bounds (after smoothing)
    self:clampToWorld()
    
    -- Use smooth position directly for rendering (no rounding = no stutter)
    -- Sprites will be rounded to pixels when drawn, preventing blur
    self.x = self.smoothX
    self.y = self.smoothY
end

-- Call before drawing world content
function Camera:attach()
    love.graphics.push()
    -- CONTINUOUS RENDERING: Removed math.floor for sub-pixel smoothness.
    -- This may cause slight tile seams or "shimmer" on some hardware for pixel art,
    -- but guarantees smooth scrolling at high refresh rates (144Hz+).
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

-- Adjust zoom level (for mouse wheel)
function Camera:adjustZoom(delta)
    local oldZoom = self.zoom
    
    -- Adjust zoom with exponential scaling for smooth feel
    -- Positive delta = zoom in, negative = zoom out
    self.zoom = self.zoom * (1 + delta * 0.1)
    
    -- Clamp zoom to min/max
    self.zoom = math.max(self.minZoom, math.min(self.maxZoom, self.zoom))
    
    -- Update viewport size based on new zoom
    -- Higher zoom = smaller viewport = more zoomed in
    self.width = self.baseWidth / self.zoom
    self.height = self.baseHeight / self.zoom
    
    -- Recenter on target to maintain focus
    if self.target then
        self.smoothX = self.target.x + 8 - self.width / 2
        self.smoothY = self.target.y + 8 - self.height / 2
        self:clampToWorld()
        self.x = self.smoothX
        self.y = self.smoothY
    end
end

-- Set zoom level directly
function Camera:setZoom(zoom)
    self.zoom = math.max(self.minZoom, math.min(self.maxZoom, zoom))
    self.width = self.baseWidth / self.zoom
    self.height = self.baseHeight / self.zoom
    
    if self.target then
        self.smoothX = self.target.x + 8 - self.width / 2
        self.smoothY = self.target.y + 8 - self.height / 2
        self:clampToWorld()
        self.x = self.smoothX
        self.y = self.smoothY
    end
end

return Camera
