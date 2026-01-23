-- src/game/world_sync.lua
-- Functions to sync world data (NPCs, animals) from host to clients

local Protocol = require('src.net.protocol')
local NetworkAdapter = require('src.net.network_adapter')
local json = require('src.lib.dkjson')

local WorldSync = {}

-- Send NPCs to clients
function WorldSync.sendNPCsToClients(game)
    if not game.isHost or not game.network or not game.npcs or #game.npcs == 0 then
        return
    end
    
    local parts = {Protocol.MSG.NPC_DATA, #game.npcs}
    for _, npc in ipairs(game.npcs) do
        table.insert(parts, math.floor(npc.x))
        table.insert(parts, math.floor(npc.y))
        table.insert(parts, npc.spritePath or "")
        table.insert(parts, npc.name or "NPC")
        -- Encode dialogue as JSON
        local dialogueJson = "[]"
        if npc.dialogueLines then
            local success, encoded = pcall(json.encode, npc.dialogueLines)
            if success then
                dialogueJson = encoded
            end
        end
        table.insert(parts, dialogueJson)
    end
    
    local encoded = table.concat(parts, "|")
    
    if game.network.type == NetworkAdapter.TYPE.LAN and game.network.server then
        if game.network.server.broadcast then
            game.network.server:broadcast(encoded, nil, true)
        end
    elseif game.network.type == NetworkAdapter.TYPE.RELAY and game.network.client then
        if game.network.client.send then
            game.network.client:send(encoded)
        end
    elseif game.network.sendMessage then
        game.network:sendMessage(encoded)
    end
end

-- Send animals to clients
function WorldSync.sendAnimalsToClients(game)
    if not game.isHost or not game.network or not game.animals or #game.animals == 0 then
        return
    end
    
    local parts = {Protocol.MSG.ANIMALS_DATA, #game.animals}
    for _, animal in ipairs(game.animals) do
        table.insert(parts, math.floor(animal.x))
        table.insert(parts, math.floor(animal.y))
        table.insert(parts, animal.spritePath or "")
        table.insert(parts, animal.animalName or "Animal")
        table.insert(parts, animal.speed or 30)
        table.insert(parts, math.floor(animal.groupCenterX or animal.x or 0))
        table.insert(parts, math.floor(animal.groupCenterY or animal.y or 0))
        table.insert(parts, math.floor(animal.groupRadius or 150))
    end
    
    local encoded = table.concat(parts, "|")
    
    if game.network.type == NetworkAdapter.TYPE.LAN and game.network.server then
        if game.network.server.broadcast then
            game.network.server:broadcast(encoded, nil, true)
        end
    elseif game.network.type == NetworkAdapter.TYPE.RELAY and game.network.client then
        if game.network.client.send then
            game.network.client:send(encoded)
        end
    elseif game.network.sendMessage then
        game.network:sendMessage(encoded)
    end
end

return WorldSync
