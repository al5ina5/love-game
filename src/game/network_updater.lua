-- src/game/network_updater.lua
local Constants = require('src.constants')

local NetworkUpdater = {}

local timeSinceLastUpdate = 0
local sendRate = Constants.MIYOO_BASE_SEND_RATE

function NetworkUpdater.update(game, dt)
    -- Safety checks
    if not game.network then 
        return 
    end

    -- Run server simulation (if host)
    game.network:update(dt)

    if not game.network:isConnected() then
        return
    end
    
    if not game.player then 
        return 
    end

    -- Update timer
    timeSinceLastUpdate = timeSinceLastUpdate + dt
    
    -- Check if it's time to send an update
    if timeSinceLastUpdate >= sendRate then
        timeSinceLastUpdate = 0
        
        -- Get player state
        local player = game.player
        
        game.network:sendPosition(
            player.x, 
            player.y, 
            player.direction, 
            player.spriteName, 
            player.isSprinting
        )
    end
end

return NetworkUpdater
