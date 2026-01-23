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

    -- Temporarily disable collision detection to test movement
    -- if world:checkRockCollision(player.x, player.y, player.width, player.height, chunkManager) then
    --     print(string.format("Player: Rock collision detected at (%.1f,%.1f), reverting to (%.1f,%.1f)", player.x, player.y, oldX, oldY))
    --     player.x = oldX
    --     player.y = oldY
    -- end
end

-- Update pet with collision detection
function EntityManager.updatePet(pet, dt, world, chunkManager, worldWidth, worldHeight)
    if not pet or type(pet.update) ~= "function" then
        return
    end
    
    if not pet.isRemote then
        pet.checkCollision = function(x, y, width, height)
            return world:checkRockCollision(x, y, width, height, chunkManager)
        end
        
        pet:update(dt)
        
        if pet.x and pet.y then
            EntityManager.clampToBounds(pet, worldWidth, worldHeight)
            
            if world:checkRockCollision(pet.x, pet.y, pet.width or 16, pet.height or 16, chunkManager) then
                local safeFound = false
                for offset = 1, 8 do
                    for angle = 0, math.pi * 2, math.pi / 4 do
                        local tryX = pet.x + math.cos(angle) * offset
                        local tryY = pet.y + math.sin(angle) * offset
                        if not world:checkRockCollision(tryX, tryY, pet.width or 16, pet.height or 16, chunkManager) then
                            pet.x = tryX
                            pet.y = tryY
                            safeFound = true
                            break
                        end
                    end
                    if safeFound then break end
                end
            end
        end
    else
        pet:update(dt)
        if pet.x and pet.y then
            EntityManager.clampToBounds(pet, worldWidth, worldHeight)
        end
    end
end

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

-- Update NPCs (only in active chunks)
function EntityManager.updateNPCs(npcs, dt, chunkManager)
    for _, npc in ipairs(npcs) do
        if not chunkManager or chunkManager:isPositionActive(npc.x, npc.y) then
            npc:update(dt)
        end
    end
end

-- Update animals (only in active chunks)
function EntityManager.updateAnimals(animals, dt, world, chunkManager, worldWidth, worldHeight)
    for _, animal in ipairs(animals) do
        if not chunkManager or chunkManager:isPositionActive(animal.x, animal.y) then
            animal:update(dt, function(x, y, width, height)
                return world:checkRockCollision(x, y, width, height, chunkManager)
            end)
            EntityManager.clampToBounds(animal, worldWidth, worldHeight)
        end
    end
end

-- Update all entities
function EntityManager.updateAll(game, dt)
    local worldWidth = game.world and game.world.worldWidth or 5000
    local worldHeight = game.world and game.world.worldHeight or 5000
    
    EntityManager.updatePlayer(game.player, dt, game.world, game.chunkManager, worldWidth, worldHeight)
    EntityManager.updatePet(game.pet, dt, game.world, game.chunkManager, worldWidth, worldHeight)
    EntityManager.updateRemotePlayers(game.remotePlayers, dt, worldWidth, worldHeight)
    EntityManager.updateRemotePets(game.remotePets, dt, worldWidth, worldHeight)
    EntityManager.updateNPCs(game.npcs, dt, game.chunkManager)
    EntityManager.updateAnimals(game.animals, dt, game.world, game.chunkManager, worldWidth, worldHeight)
end

return EntityManager
