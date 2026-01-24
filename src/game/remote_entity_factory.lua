-- src/game/remote_entity_factory.lua
-- Factory for creating remote players and pets

local RemotePlayer = require('src.entities.remote_player')
local Pet = require('src.entities.pet')

local RemoteEntityFactory = {}

function RemoteEntityFactory.createOrUpdateRemotePlayer(game, playerId, posX, posY, skin, direction, sprinting)
    if not playerId or playerId == game.playerId then
        -- Clean up any existing remote player for this ID (ghost player fix)
        if game.remotePlayers[playerId] then
            game.remotePlayers[playerId] = nil
            print("RemoteEntityFactory: Cleaned up ghost remote player for ID: " .. playerId)
        end
        return nil
    end
    
    local remote = game.remotePlayers[playerId]
    if not remote then
        remote = RemotePlayer:new(posX, posY, skin)
        game.remotePlayers[playerId] = remote
        print("Created remote player: " .. playerId .. " at (" .. posX .. ", " .. posY .. ")")
    else
        remote:setTargetPosition(posX, posY, direction or "down", sprinting)
        if skin then
            remote:setSprite(skin)
        end
    end
    
    RemoteEntityFactory.ensureRemotePet(game, playerId, remote)
    
    return remote
end

function RemoteEntityFactory.ensureRemotePet(game, playerId, owner)
    if not game.remotePets then
        game.remotePets = {}
    end
    
    if not game.remotePets[playerId] and owner then
        game.remotePets[playerId] = Pet:new(owner, true, nil)
    end
end

function RemoteEntityFactory.updateRemotePet(game, playerId, x, y, monster)
    if not playerId then
        return
    end
    
    if not game.remotePets then
        game.remotePets = {}
    end
    
    local remotePet = game.remotePets[playerId]
    if remotePet then
        if x and y then
            remotePet.targetX = x
            remotePet.targetY = y
        end
        if monster then
            remotePet:setMonster(monster)
        end
    else
        -- Need to handle creating the pet if it doesn't exist
        -- even if the owner is the local player
        local owner = (playerId == game.playerId) and game.player or game.remotePlayers[playerId]
        if owner then
            game.remotePets[playerId] = Pet:new(owner, true, monster)
            game.remotePets[playerId].targetX = x or owner.x
            game.remotePets[playerId].targetY = y or owner.y
        end
    end
end

function RemoteEntityFactory.removeRemotePlayer(game, playerId)
    if playerId then
        game.remotePlayers[playerId] = nil
        if game.remotePets and game.remotePets[playerId] then
            print("RemoteEntityFactory: Removing pet for " .. tostring(playerId))
            game.remotePets[playerId] = nil
        end
    end
end

return RemoteEntityFactory
