-- src/systems/particles.lua
-- Simple particle system for movement effects

local Particles = {}
Particles.__index = Particles

function Particles:new()
    local self = setmetatable({}, Particles)
    self.particles = {}
    return self
end

-- Spawn a movement particle
-- intensity: 0.0 to 1.0, affects size and emission rate (1.0 = sprinting, 0.5 = walking)
function Particles:spawnMovementParticle(x, y, intensity)
    intensity = intensity or 0.5
    
    -- Base particle properties (made more visible)
    local baseSize = 3.0  -- Increased for better visibility
    local baseAlpha = 0.6  -- Increased for better visibility
    local baseLifetime = 0.5  -- Longer lifetime
    
    -- Scale based on intensity (sprinting = stronger particles)
    local size = baseSize * (0.8 + intensity * 0.2)  -- 2.4 to 3.0 pixels
    local alpha = baseAlpha * (0.85 + intensity * 0.15)  -- 0.51 to 0.6
    local lifetime = baseLifetime * (0.9 + intensity * 0.1)  -- 0.45 to 0.5
    
    -- Random offset from spawn position (smaller spread)
    local offsetX = (math.random() - 0.5) * 3
    local offsetY = (math.random() - 0.5) * 3
    
    -- Random velocity (slight upward drift for dust effect)
    local vx = (math.random() - 0.5) * 15
    local vy = (math.random() - 0.5) * 8 - 5  -- Slight upward bias
    
    table.insert(self.particles, {
        x = x + offsetX,
        y = y + offsetY,
        vx = vx,
        vy = vy,
        size = size,
        alpha = alpha,
        lifetime = lifetime,
        maxLifetime = lifetime
    })
end

function Particles:update(dt)
    -- Update and remove dead particles
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        
        -- Update position
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        
        -- Apply friction
        p.vx = p.vx * (1 - dt * 3)
        p.vy = p.vy * (1 - dt * 3)
        
        -- Update lifetime
        p.lifetime = p.lifetime - dt
        
        -- Fade out over time
        p.alpha = p.alpha * (p.lifetime / p.maxLifetime)
        
        -- Remove dead particles
        if p.lifetime <= 0 then
            table.remove(self.particles, i)
        end
    end
end

function Particles:draw()
    -- Draw particles as white circles
    -- Use "line" mode with thicker lines for better visibility on pixel art
    love.graphics.setLineWidth(1)
    
    for _, p in ipairs(self.particles) do
        love.graphics.setColor(1, 1, 1, p.alpha)
        -- Draw as filled circle for better visibility
        love.graphics.circle("fill", p.x, p.y, p.size)
        -- Also draw outline for extra visibility
        if p.alpha > 0.3 then
            love.graphics.setColor(1, 1, 1, p.alpha * 0.5)
            love.graphics.circle("line", p.x, p.y, p.size)
        end
    end
    
    -- Reset color and line width
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Clear all particles
function Particles:clear()
    self.particles = {}
end

return Particles
