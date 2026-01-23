-- src/game/network_updater.lua
-- Handles network position updates and server synchronization

local NetworkUpdater = {}

function NetworkUpdater.updateServerSimulation(game, dt)
    if not game.network or not game.isHost then return end
    
    local NetworkAdapter = require('src.net.network_adapter')
    local serverToUpdate = nil
    
    if game.network.type == NetworkAdapter.TYPE.LAN and game.network.server then
        serverToUpdate = game.network.server
    elseif game.network.type == NetworkAdapter.TYPE.RELAY and game.network.localServer then
        serverToUpdate = game.network.localServer
    end
    
    if not serverToUpdate then return end
    
    if serverToUpdate.serverLogic and game.player then
        local hostPlayer = serverToUpdate.serverLogic.state.players["host"]
        if hostPlayer then
            hostPlayer.x = game.player.x
            hostPlayer.y = game.player.y
            hostPlayer.direction = game.player.direction
        end
    end
    
    if serverToUpdate.update then
        serverToUpdate:update(dt)
        
        if serverToUpdate.serverLogic then
            local json = require("src.lib.dkjson")
            local stateJson = serverToUpdate.serverLogic:getStateSnapshot()
            local success, state = pcall(json.decode, stateJson)
            if success and state then
                game.gameState = state
            end
        end
    end
end

function NetworkUpdater.sendPositionUpdates(game)
    if not game.network or not game.network.sendPosition or not game.player then
        return
    end
    
    if not game.lastSentX or not game.lastSentY then
        game.lastSentX = game.player.x - 10
        game.lastSentY = game.player.y - 10
        game.lastSentDir = nil
        local success = game.network:sendPosition(game.player.x, game.player.y, game.player.direction, game.player.spriteName, game.player.isSprinting)
        if success then
            game.lastSentX = game.player.x
            game.lastSentY = game.player.y
            game.lastSentDir = game.player.direction
            game.lastSentSprinting = game.player.isSprinting
        end
        return
    end
    
    local dx = math.abs(game.player.x - game.lastSentX)
    local dy = math.abs(game.player.y - game.lastSentY)
    local dirChanged = (game.player.direction ~= (game.lastSentDir or game.player.direction))
    local sprintChanged = (game.player.isSprinting ~= game.lastSentSprinting)
    
    if dx > 2 or dy > 2 or dirChanged or sprintChanged then
        local success = game.network:sendPosition(game.player.x, game.player.y, game.player.direction, game.player.spriteName, game.player.isSprinting)
        if success then
            game.lastSentX = game.player.x
            game.lastSentY = game.player.y
            game.lastSentDir = game.player.direction
            game.lastSentSprinting = game.player.isSprinting
        end
    end
    
    if game.pet then
        if not game.lastPetSentX or not game.lastPetSentY then
            game.lastPetSentX = game.pet.x - 10
            game.lastPetSentY = game.pet.y - 10
            game.network:sendPetPosition(game.playerId, game.pet.x, game.pet.y, game.pet.monsterName)
        else
            local petDx = math.abs(game.pet.x - game.lastPetSentX)
            local petDy = math.abs(game.pet.y - game.lastPetSentY)
            if petDx > 5 or petDy > 5 then
                game.network:sendPetPosition(game.playerId, game.pet.x, game.pet.y, game.pet.monsterName)
                game.lastPetSentX = game.pet.x
                game.lastPetSentY = game.pet.y
            end
        end
    end
end

function NetworkUpdater.updateFromServerState(game)
    if not game.gameState or not game.gameState.players or not game.playerId then
        return
    end
    
    local serverPlayer = game.gameState.players[game.playerId]
    if serverPlayer then
        -- Don't overwrite local player position with server state - position is client-authoritative
        -- Only update HP and other server-authoritative values
        if serverPlayer.hp then
            game.player.hp = serverPlayer.hp
        end
        
        -- Only update position if there's a huge discrepancy (anti-cheat/desync recovery)
        -- This allows smooth client-side movement while still catching major desyncs
        if serverPlayer.x and serverPlayer.y then
            local dx = math.abs(game.player.x - serverPlayer.x)
            local dy = math.abs(game.player.y - serverPlayer.y)
            -- Only correct if discrepancy is > 50 pixels (likely desync)
            if dx > 50 or dy > 50 then
                print("NetworkUpdater: Large position desync detected, correcting from server")
                game.player.x = serverPlayer.x
                game.player.y = serverPlayer.y
            end
        end
        
        -- Update direction from server (less critical, but helps with sync)
        if serverPlayer.direction then
            game.player.direction = serverPlayer.direction
        end
        
        local EntityManager = require('src.game.entity_manager')
        local worldWidth = game.world and game.world.worldWidth or 5000
        local worldHeight = game.world and game.world.worldHeight or 5000
        EntityManager.clampToBounds(game.player, worldWidth, worldHeight)
    end
end

function NetworkUpdater.update(game, dt)
    NetworkUpdater.updateServerSimulation(game, dt)
    NetworkUpdater.sendPositionUpdates(game)
    NetworkUpdater.updateFromServerState(game)
end

return NetworkUpdater
