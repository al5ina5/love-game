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
    if not animalsData then return end

    local Animal = require('src.entities.animal')
    
    -- Index existing Animals by ID
    local currentAnimalsById = {}
    if game.animals then
        for _, animal in ipairs(game.animals) do
            if animal.id then
                currentAnimalsById[animal.id] = animal
            end
        end
    end
    
    local newAnimalList = {}
    
    for animalId, animalData in pairs(animalsData) do
        local existingAnimal = currentAnimalsById[animalId]
        
        if existingAnimal then
            -- Update existing Animal
            existingAnimal.x = animalData.x or existingAnimal.x
            existingAnimal.y = animalData.y or existingAnimal.y
            
            -- Only reload sprite if changed
            if animalData.spritePath and animalData.spritePath ~= existingAnimal.spritePath then
                existingAnimal.spritePath = animalData.spritePath
                 existingAnimal:loadSprite(animalData.spritePath)
            end
            
            if animalData.name then existingAnimal.animalName = animalData.name end
            if animalData.speed then existingAnimal.speed = animalData.speed end
            
            if animalData.groupCenterX and animalData.groupCenterY and animalData.groupRadius then
                existingAnimal:setGroupCenter(animalData.groupCenterX, animalData.groupCenterY, animalData.groupRadius)
            end
            
            table.insert(newAnimalList, existingAnimal)
        else
            -- Create new Animal
            local animal = Animal:new(
                animalData.x or 0,
                animalData.y or 0,
                animalData.spritePath or "",
                animalData.name or "Animal",
                animalData.speed or 30
            )
            animal.id = animalId -- Attach ID for future reuse
            if animalData.groupCenterX and animalData.groupCenterY and animalData.groupRadius then
                animal:setGroupCenter(animalData.groupCenterX, animalData.groupCenterY, animalData.groupRadius)
            end
            table.insert(newAnimalList, animal)
        end
    end
    
    game.animals = newAnimalList
end

return EntityDataHandler
