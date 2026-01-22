-- src/systems/gun.lua
-- Manages bullets and projectiles for Boon Snatch
-- Note: In server-authoritative mode, server owns projectiles
-- This is used for client-side prediction and rendering

local Gun = {
    bullets = {}
}

local BULLET_SPEED = 300

function Gun:newBullet(x, y, dx, dy, ownerId)
    local bullet = {
        x = x,
        y = y,
        dx = dx,
        dy = dy,
        ownerId = ownerId,
        life = 2.0
    }
    table.insert(self.bullets, bullet)
    return bullet
end

-- Create triple shot spread (for boon holder)
-- Angles: -10°, 0°, +10° from base direction
function Gun:newBulletSpread(x, y, dx, dy, ownerId)
    local baseAngle = math.atan2(dy, dx)
    local spread = math.rad(10)
    
    local bullets = {}
    for _, angleOffset in ipairs({-spread, 0, spread}) do
        local angle = baseAngle + angleOffset
        local bullet = {
            x = x,
            y = y,
            dx = math.cos(angle),
            dy = math.sin(angle),
            ownerId = ownerId,
            life = 2.0
        }
        table.insert(self.bullets, bullet)
        table.insert(bullets, bullet)
    end
    
    return bullets
end

function Gun:update(dt)
    for i = #self.bullets, 1, -1 do
        local b = self.bullets[i]
        b.x = b.x + b.dx * BULLET_SPEED * dt
        b.y = b.y + b.dy * BULLET_SPEED * dt
        b.life = b.life - dt
        
        if b.life <= 0 then
            table.remove(self.bullets, i)
        end
    end
end

-- Sync bullets from server state
function Gun:syncFromServer(serverProjectiles)
    -- Replace local bullets with server state
    self.bullets = {}
    for _, p in ipairs(serverProjectiles or {}) do
        table.insert(self.bullets, {
            x = p.x,
            y = p.y,
            dx = p.dx,
            dy = p.dy,
            ownerId = p.ownerId,
            life = 2.0
        })
    end
end

function Gun:draw()
    for _, b in ipairs(self.bullets) do
        self:drawBullet(b)
    end
end

function Gun:drawBullet(b)
    -- Determine color based on owner
    if b.ownerId then
        love.graphics.setColor(0.8, 0.4, 0.4)  -- Red for enemy
    else
        love.graphics.setColor(1, 1, 0.5)  -- Yellow for local
    end
    
    love.graphics.circle("fill", b.x, b.y, 3)
    
    -- Bullet trail
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.line(b.x, b.y, b.x - b.dx * 5, b.y - b.dy * 5)
    
    love.graphics.setColor(1, 1, 1)
end

function Gun:checkCollision(bx, by, px, py, pw, ph)
    return bx > px and bx < px + pw and
           by > py and by < py + ph
end

function Gun:clear()
    self.bullets = {}
end

return Gun
