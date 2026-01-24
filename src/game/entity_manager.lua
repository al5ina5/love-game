-- src/game/entity_manager.lua
-- Manages all entities: player, pet, NPCs, animals, remote players

local EntityManager = {}

-- Clamp entity position to world bounds
function EntityManager.clampToBounds(entity, worldWidth, worldHeight)
    if not entity or not entity.x or not entity.y then return end
    
    local width = entity.width or 16
    local height = entity.height or 16
    
    entity.x = math.max(0, math.min(entity.x, worldWidth - width))
    entity.y = math.max(0, math.min(entity.y, worldHeight - height))
end

-- Update local player with collision detection
function EntityManager.updatePlayer(player, dt, world, chunkManager, worldWidth, worldHeight)
    if not player or type(player.update) ~= "function" then
        print("EntityManager.updatePlayer: Player not valid")
        return
    end



    local oldX = player.x
    local oldY = player.y

    player:update(dt)

    EntityManager.clampToBounds(player, worldWidth, worldHeight)

    -- Collision detection (only check bottom 3 pixels for feet, 4px wide centered)
    local collisionWidth = 4
    local collisionHeight = 3
    local collisionX = player.x + (player.width - collisionWidth) / 2
    local collisionY = player.y + player.height - collisionHeight
    if world:checkRockCollision(collisionX, collisionY, collisionWidth, collisionHeight, chunkManager) or 
       world:checkWaterCollision(collisionX, collisionY, collisionWidth, collisionHeight) or
       world:checkTreeCollision(collisionX, collisionY, collisionWidth, collisionHeight, chunkManager) then
        -- print(string.format("Player: Collision detected at (%.1f,%.1f), reverting to (%.1f,%.1f)", player.x, player.y, oldX, oldY))
        player.x = oldX
        player.y = oldY
    end
end

-- updatePet removed - all pets are now remote pets synced from server

-- Update remote players
function EntityManager.updateRemotePlayers(remotePlayers, dt, worldWidth, worldHeight)
    for _, remote in pairs(remotePlayers) do
        remote:update(dt)
        EntityManager.clampToBounds(remote, worldWidth, worldHeight)
    end
end

-- Update remote pets
function EntityManager.updateRemotePets(remotePets, dt, worldWidth, worldHeight)
    if not remotePets then return end
    
    for _, remotePet in pairs(remotePets) do
        remotePet:update(dt)
        EntityManager.clampToBounds(remotePet, worldWidth, worldHeight)
    end
end

-- Update NPCs (only nearby NPCs to prevent lag from hundreds of NPCs)
function EntityManager.updateNPCs(npcs, dt, chunkManager, worldCache, camera)
    -- If we have a world cache, only update nearby NPCs
    -- Otherwise fall back to chunk-based filtering
    local npcsToUpdate = npcs or {}

    if worldCache and worldCache.isReady and worldCache:isReady() and camera then
        -- Get NPCs near camera
        local cameraCenterX = camera.x + camera.width/2
        local cameraCenterY = camera.y + camera.height/2
        local updateRadius = 400  -- Standard 400 pixels

        npcsToUpdate = worldCache:getNearbyNPCs(cameraCenterX, cameraCenterY, updateRadius)

        -- Standard limit for NPC updates
        local maxNPCs = 20
        if #npcsToUpdate > maxNPCs then
            table.sort(npcsToUpdate, function(a, b)
                local distA = (a.x - cameraCenterX)^2 + (a.y - cameraCenterY)^2
                local distB = (b.x - cameraCenterX)^2 + (b.y - cameraCenterY)^2
                return distA < distB
            end)
            -- Keep only the closest NPCs
            local limitedNPCs = {}
            for i = 1, math.min(maxNPCs, #npcsToUpdate) do
                limitedNPCs[i] = npcsToUpdate[i]
            end
            npcsToUpdate = limitedNPCs
        end
    else
        -- Fallback: filter by chunks (legacy behavior)
        local filteredNPCs = {}
        for _, npc in ipairs(npcs) do
            if not chunkManager or chunkManager:isPositionActive(npc.x, npc.y) then
                table.insert(filteredNPCs, npc)
            end
        end
        npcsToUpdate = filteredNPCs
    end

    -- Update the filtered NPCs
    for _, npc in ipairs(npcsToUpdate) do
        if type(npc.update) == "function" then
            npc:update(dt)
        end
    end
end

-- Update animals (only nearby animals to prevent lag from thousands of animals)
function EntityManager.updateAnimals(animals, dt, world, chunkManager, worldWidth, worldHeight, worldCache, camera)
    -- If we have a world cache, only update nearby animals
    -- Otherwise fall back to chunk-based filtering
    local animalsToUpdate = animals or {}

    if worldCache and worldCache.isReady and worldCache:isReady() and camera then
        -- Get animals near camera
        local cameraCenterX = camera.x + camera.width/2
        local cameraCenterY = camera.y + camera.height/2
        local updateRadius = 500  -- Standard 500 pixels

        animalsToUpdate = worldCache:getNearbyAnimals(cameraCenterX, cameraCenterY, updateRadius)

        -- Standard limit for animal updates
        local maxAnimals = 50
        if #animalsToUpdate > maxAnimals then
            table.sort(animalsToUpdate, function(a, b)
                local distA = (a.x - cameraCenterX)^2 + (a.y - cameraCenterY)^2
                local distB = (b.x - cameraCenterX)^2 + (b.y - cameraCenterY)^2
                return distA < distB
            end)
            -- Keep only the closest animals
            local limitedAnimals = {}
            for i = 1, math.min(maxAnimals, #animalsToUpdate) do
                limitedAnimals[i] = animalsToUpdate[i]
            end
            animalsToUpdate = limitedAnimals
        end
    else
        -- Fallback: filter by chunks (legacy behavior)
        local filteredAnimals = {}
        for _, animal in ipairs(animals) do
            if not chunkManager or chunkManager:isPositionActive(animal.x, animal.y) then
                table.insert(filteredAnimals, animal)
            end
        end
        animalsToUpdate = filteredAnimals
    end

    -- Update the filtered animals
    for _, animal in ipairs(animalsToUpdate) do
        if type(animal.update) == "function" then
            animal:update(dt, function(x, y, width, height)
                return world:checkRockCollision(x, y, width, height, chunkManager) or
                       world:checkWaterCollision(x, y, width, height) or
                       world:checkTreeCollision(x, y, width, height, chunkManager)
            end)
        end
        EntityManager.clampToBounds(animal, worldWidth, worldHeight)
    end
end

-- Update all entities
function EntityManager.updateAll(game, dt)
    local worldWidth = game.world and game.world.worldWidth or 5000
    local worldHeight = game.world and game.world.worldHeight or 5000
    
    EntityManager.updatePlayer(game.player, dt, game.world, game.chunkManager, worldWidth, worldHeight)
    -- game.pet is removed - all pets are in game.remotePets
    EntityManager.updateRemotePlayers(game.remotePlayers, dt, worldWidth, worldHeight)
    EntityManager.updateRemotePets(game.remotePets, dt, worldWidth, worldHeight)
    EntityManager.updateNPCs(game.npcs, dt, game.chunkManager, game.worldCache, game.camera)
    EntityManager.updateAnimals(game.animals, dt, game.world, game.chunkManager, worldWidth, worldHeight, game.worldCache, game.camera)
end

return EntityManager
