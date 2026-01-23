-- src/game/entity_data_handler.lua
-- Handles syncing NPC and animal data from network

local EntityDataHandler = {}

function EntityDataHandler.handleNPCData(npcsData, game)
    if not npcsData then return end
    
    local NPC = require('src.entities.npc')
    game.npcs = {}
    
    for _, npcData in ipairs(npcsData) do
        local npc = NPC:new(
            npcData.x or 0,
            npcData.y or 0,
            npcData.spritePath or "",
            npcData.name or "NPC",
            npcData.dialogue or {}
        )
        table.insert(game.npcs, npc)
    end
end

function EntityDataHandler.handleAnimalsData(animalsData, game)
    -- Disabled for performance: basically for now just send tiles and trees
    -- if not animalsData then return end
    -- ... (logic removed)
end

function EntityDataHandler.handleNPCDataFromState(npcsData, game)
    if not npcsData then return end

    local NPC = require('src.entities.npc')
    
    -- Index existing NPCs by ID
    local currentNpcsById = {}
    if game.npcs then
        for _, npc in ipairs(game.npcs) do
            if npc.id then
                currentNpcsById[npc.id] = npc
            end
        end
    end
    
    local newNpcList = {}
    
    for npcId, npcData in pairs(npcsData) do
        local existingNpc = currentNpcsById[npcId]
        
        if existingNpc then
            -- Update existing NPC
            existingNpc.x = npcData.x or existingNpc.x
            existingNpc.y = npcData.y or existingNpc.y
            -- Only reload sprite if it changed
            if npcData.spritePath and npcData.spritePath ~= existingNpc.spritePath then
                existingNpc.spritePath = npcData.spritePath
                existingNpc:loadSprite(npcData.spritePath)
            end
            
            if npcData.name then existingNpc.name = npcData.name end
            if npcData.dialogue then existingNpc.dialogueLines = npcData.dialogue end
            
            table.insert(newNpcList, existingNpc)
        else
            -- Create new NPC
            local npc = NPC:new(
                npcData.x or 0,
                npcData.y or 0,
                npcData.spritePath or "",
                npcData.name or "NPC",
                npcData.dialogue or {}
            )
            npc.id = npcId -- Attach ID for future reuse
            table.insert(newNpcList, npc)
        end
    end
    
    game.npcs = newNpcList
end

function EntityDataHandler.handleAnimalsDataFromState(animalsData, game)
    -- Disabled for performance: basically for now just send tiles and trees
    -- if not animalsData then return end
    -- ... (logic removed)
end

return EntityDataHandler
