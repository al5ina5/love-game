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
    if not animalsData then return end
    
    local Animal = require('src.entities.animal')
    game.animals = {}
    
    for _, animalData in ipairs(animalsData) do
        local animal = Animal:new(
            animalData.x or 0,
            animalData.y or 0,
            animalData.spritePath or "",
            animalData.name or "Animal",
            animalData.speed or 30
        )
        if animalData.groupCenterX and animalData.groupCenterY and animalData.groupRadius then
            animal:setGroupCenter(animalData.groupCenterX, animalData.groupCenterY, animalData.groupRadius)
        end
        table.insert(game.animals, animal)
    end
end

function EntityDataHandler.handleNPCDataFromState(npcsData, game)
    if not npcsData then return end

    local NPC = require('src.entities.npc')
    game.npcs = {}

    for npcId, npcData in pairs(npcsData) do
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

function EntityDataHandler.handleAnimalsDataFromState(animalsData, game)
    if not animalsData then return end

    local Animal = require('src.entities.animal')
    game.animals = {}

    for animalId, animalData in pairs(animalsData) do
        local animal = Animal:new(
            animalData.x or 0,
            animalData.y or 0,
            animalData.spritePath or "",
            animalData.name or "Animal",
            animalData.speed or 30
        )
        if animalData.groupCenterX and animalData.groupCenterY and animalData.groupRadius then
            animal:setGroupCenter(animalData.groupCenterX, animalData.groupCenterY, animalData.groupRadius)
        end
        table.insert(game.animals, animal)
    end
end

return EntityDataHandler
