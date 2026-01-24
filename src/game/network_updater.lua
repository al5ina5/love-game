-- src/game/network_updater.lua
local Constants = require('src.constants')

local NetworkUpdater = {}

local timeSinceLastUpdate = 0
local sendRate = Constants.BASE_SEND_RATE

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
        
        -- Send entire batch of unacknowledged inputs for redundant loss tolerance
        if #player.inputHistory > 0 then
            game.network:sendPosition(
                player.direction,
                player.inputHistory
            )
        end
    end
end

return NetworkUpdater
