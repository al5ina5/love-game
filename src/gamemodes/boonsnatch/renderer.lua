-- src/gamemodes/boonsnatch/renderer.lua
-- Boon Snatch game mode specific rendering

local BoonSnatchRenderer = {}

function BoonSnatchRenderer.drawChest(chest)
    if chest.opened then
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
    else
        if chest.rarity == "legendary" then
            love.graphics.setColor(1, 0.84, 0, 1)
        elseif chest.rarity == "epic" then
            love.graphics.setColor(0.6, 0.2, 1, 1)
        elseif chest.rarity == "rare" then
            love.graphics.setColor(0.2, 0.6, 1, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
        end
    end
    
    love.graphics.rectangle("fill", chest.x - 8, chest.y - 8, 16, 16)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", chest.x - 8, chest.y - 8, 16, 16)
    love.graphics.setColor(1, 1, 1, 1)
end

function BoonSnatchRenderer.drawProjectile(proj)
    if not proj or not proj.x or not proj.y then
        return
    end
    
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.circle("fill", proj.x, proj.y, 10)
    love.graphics.setColor(1, 0, 0, 1)
    love.graphics.circle("line", proj.x, proj.y, 10)
    love.graphics.setColor(1, 1, 1, 1)
end

function BoonSnatchRenderer.drawExtractionZone(zone)
    if not zone or not zone.x or not zone.y then
        return
    end
    
    local radius = zone.radius or 50
    local pulse = 0.5 + 0.3 * math.sin(love.timer.getTime() * 2)
    
    love.graphics.setColor(0, 1, 0, pulse * 0.3)
    love.graphics.circle("fill", zone.x, zone.y, radius)
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", zone.x, zone.y, radius)
    love.graphics.setLineWidth(1)
    
    love.graphics.setColor(1, 1, 1, 1)
    local font = love.graphics.getFont()
    local text = "EXTRACT"
    local textWidth = font:getWidth(text)
    local textHeight = font:getHeight()
    love.graphics.print(text, zone.x - textWidth / 2, zone.y - textHeight / 2)
    
    love.graphics.setColor(1, 1, 1, 1)
end

function BoonSnatchRenderer.drawGameState(gameState, game)
    if not gameState then return end
    
    if gameState.chests then
        for chestId, chest in pairs(gameState.chests) do
            BoonSnatchRenderer.drawChest(chest)
        end
    end
    
    if gameState.extractionZones then
        for _, zone in ipairs(gameState.extractionZones) do
            BoonSnatchRenderer.drawExtractionZone(zone)
        end
    end
    
    if gameState.projectiles then
        for projId, proj in pairs(gameState.projectiles) do
            BoonSnatchRenderer.drawProjectile(proj)
        end
    end
end

return BoonSnatchRenderer
