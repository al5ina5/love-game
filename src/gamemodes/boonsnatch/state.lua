-- src/gamemodes/boonsnatch/state.lua
-- Game state structure for Boon Snatch
-- Server-authoritative state that gets synced to clients

local State = {}
State.__index = State

function State:new()
    local self = setmetatable({}, State)
    
    -- Players: { [playerId] = { x, y, hp, maxHp, boons, kills, deaths, direction, invulnerable } }
    self.players = {}
    
    -- Projectiles: { [projId] = { x, y, vx, vy, ownerId, damage, lifetime } }
    self.projectiles = {}
    self.nextProjectileId = 1
    
    -- Chests: { [chestId] = { x, y, opened, respawnTimer, rarity } }
    self.chests = {}
    self.nextChestId = 1
    
    -- Enemies: { [enemyId] = { x, y, hp, maxHp, type, boonDropChance } }
    self.enemies = {}
    self.nextEnemyId = 1
    
    -- Boss: { x, y, hp, maxHp, phase, active }
    self.boss = nil

    -- NPCs: { [npcId] = { x, y, spritePath, name, dialogue } }
    self.npcs = {}
    self.nextNpcId = 1

    -- Animals: { [animalId] = { x, y, spritePath, name, speed, groupCenterX, groupCenterY, groupRadius } }
    self.animals = {}
    self.nextAnimalId = 1

    -- Match state
    self.matchStartTime = 0
    self.matchEndTime = 0
    self.winner = nil
    self.gameStarted = false
    
    return self
end

-- Add a player to the game state
function State:addPlayer(playerId, x, y)
    self.players[playerId] = {
        x = x or 400,
        y = y or 300,
        hp = 100,
        maxHp = 100,
        boons = {},  -- Array of boon objects
        kills = 0,
        deaths = 0,
        direction = "down",
        invulnerable = false,
        invulnerableTimer = 0,
    }
end

-- Remove a player
function State:removePlayer(playerId)
    self.players[playerId] = nil
end

-- Create a projectile
function State:createProjectile(ownerId, x, y, angle, speed, damage)
    print("State:createProjectile - Creating projectile")
    print("  ownerId: " .. (ownerId or "nil"))
    print("  position: (" .. x .. ", " .. y .. ")")
    print("  angle: " .. angle)
    print("  speed: " .. speed)
    print("  damage: " .. (damage or "nil"))
    
    local projId = "proj_" .. self.nextProjectileId
    self.nextProjectileId = self.nextProjectileId + 1
    print("  Generated ID: " .. projId)
    
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed
    print("  Calculated velocity: (" .. vx .. ", " .. vy .. ")")
    
    self.projectiles[projId] = {
        id = projId,
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        ownerId = ownerId,
        damage = damage or 10,
        lifetime = 3.0,  -- Projectiles despawn after 3 seconds
    }
    
    print("  Projectile stored in state.projectiles[" .. projId .. "]")
    print("  Total projectiles now: " .. self:countProjectiles())
    
    return projId
end

-- Helper to count projectiles
function State:countProjectiles()
    local count = 0
    for _ in pairs(self.projectiles) do count = count + 1 end
    return count
end

-- Remove a projectile
function State:removeProjectile(projId)
    self.projectiles[projId] = nil
end

-- Create a chest
function State:createChest(x, y, rarity)
    local chestId = "chest_" .. self.nextChestId
    self.nextChestId = self.nextChestId + 1

    self.chests[chestId] = {
        id = chestId,
        x = x,
        y = y,
        opened = false,
        respawnTimer = 0,
        rarity = rarity or "common",  -- common, rare, epic, legendary
    }

    return chestId
end

-- Create an NPC
function State:createNpc(x, y, spritePath, name, dialogue)
    local npcId = "npc_" .. self.nextNpcId
    self.nextNpcId = self.nextNpcId + 1

    self.npcs[npcId] = {
        id = npcId,
        x = x,
        y = y,
        spritePath = spritePath or "",
        name = name or "NPC",
        dialogue = dialogue or {},
    }

    return npcId
end

-- Create an animal
function State:createAnimal(x, y, spritePath, name, speed, groupCenterX, groupCenterY, groupRadius)
    local animalId = "animal_" .. self.nextAnimalId
    self.nextAnimalId = self.nextAnimalId + 1

    self.animals[animalId] = {
        id = animalId,
        x = x,
        y = y,
        spritePath = spritePath or "",
        name = name or "Animal",
        speed = speed or 30,
        groupCenterX = groupCenterX or x,
        groupCenterY = groupCenterY or y,
        groupRadius = groupRadius or 150,
    }

    return animalId
end

-- Open a chest (returns true if successfully opened)
function State:openChest(chestId, playerId)
    local chest = self.chests[chestId]
    if not chest or chest.opened then
        return false
    end
    
    chest.opened = true
    chest.respawnTimer = 30.0  -- Respawn after 30 seconds
    return true
end

-- Grant a boon to a player
function State:grantBoon(playerId, boonType, boonData)
    local player = self.players[playerId]
    if not player then return false end
    
    local boon = {
        type = boonType,
        data = boonData or {},
        rarity = boonData.rarity or "common",
    }
    
    table.insert(player.boons, boon)
    return true
end

-- Transfer all boons from one player to another (steal on kill)
function State:stealBoons(killerId, victimId)
    local killer = self.players[killerId]
    local victim = self.players[victimId]
    
    if not killer or not victim then return 0 end
    
    local stolenCount = #victim.boons
    
    -- Transfer all boons
    for _, boon in ipairs(victim.boons) do
        table.insert(killer.boons, boon)
    end
    
    -- Clear victim's boons
    victim.boons = {}
    
    return stolenCount
end

-- Damage a player (returns true if player died)
function State:damagePlayer(playerId, damage)
    local player = self.players[playerId]
    if not player or player.invulnerable then return false end
    
    player.hp = math.max(0, player.hp - damage)
    
    if player.hp <= 0 then
        player.hp = 0
        return true  -- Player died
    end
    
    return false
end

-- Respawn a player at a random location
function State:respawnPlayer(playerId, worldWidth, worldHeight)
    local player = self.players[playerId]
    if not player then return end
    
    -- Random spawn location (avoid center where players start)
    local margin = 100
    player.x = margin + math.random() * (worldWidth - margin * 2)
    player.y = margin + math.random() * (worldHeight - margin * 2)
    player.hp = player.maxHp
    player.invulnerable = true
    player.invulnerableTimer = 3.0  -- 3 seconds of invulnerability
end

-- Serialize state to JSON for network transmission
function State:serialize()
    local json = require("src.lib.dkjson")
    return json.encode({
        players = self.players,
        projectiles = self.projectiles,
        chests = self.chests,
        enemies = self.enemies,
        boss = self.boss,
        npcs = self.npcs,
        animals = self.animals,
        matchStartTime = self.matchStartTime,
        matchEndTime = self.matchEndTime,
        winner = self.winner,
        gameStarted = self.gameStarted,
    })
end

-- Deserialize state from JSON
function State:deserialize(jsonString)
    local json = require("src.lib.dkjson")
    local success, data = pcall(json.decode, jsonString)
    if success and data then
        self.players = data.players or {}
        self.projectiles = data.projectiles or {}
        self.chests = data.chests or {}
        self.enemies = data.enemies or {}
        self.boss = data.boss
        self.npcs = data.npcs or {}
        self.animals = data.animals or {}
        self.matchStartTime = data.matchStartTime or 0
        self.matchEndTime = data.matchEndTime or 0
        self.winner = data.winner
        self.gameStarted = data.gameStarted or false
        return true
    end
    return false
end

return State
