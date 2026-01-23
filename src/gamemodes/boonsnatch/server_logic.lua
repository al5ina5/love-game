-- src/gamemodes/boonsnatch/server_logic.lua
-- Server-authoritative game logic for Boon Snatch
-- Runs on the host, simulates the game, sends state to clients

local State = require('src.gamemodes.boonsnatch.state')
local Protocol = require('src.net.protocol')
local Constants = require('src.constants')
local RoadGenerator = require('src.world.road_generator')

local ServerLogic = {}
ServerLogic.__index = ServerLogic

function ServerLogic:new(worldWidth, worldHeight)
    local self = setmetatable({}, ServerLogic)
    
    self.state = State:new()
    self.worldWidth = worldWidth or 5000  -- Match client world size
    self.worldHeight = worldHeight or 5000
    
    -- Game settings
    self.projectileSpeed = 400  -- pixels per second
    self.projectileDamage = 10  -- base damage
    self.playerSpeed = 200  -- pixels per second
    self.respawnTime = 3.0  -- seconds
    
    -- Input queue (from clients)
    self.inputQueue = {}
    
    -- State broadcast rate (send state every N seconds)
    self.stateBroadcastInterval = 1.0 / 20  -- 20 times per second
    self.lastStateBroadcast = 0
    
    -- World Data (Roads, Trees, etc.)
    self.roads = {}
    self.trees = {}  -- Sparse table: map[chunkKey] = { {x, y, variation}, ... }
    self.chunkSize = 512
    
    -- Mock world for RoadGenerator
    local mockWorld = {
        roads = self.roads,
        worldWidth = self.worldWidth,
        worldHeight = self.worldHeight,
        chunkSize = self.chunkSize
    }
    self.roadGenerator = RoadGenerator:new(mockWorld)
    
    -- Generate initial world features
    self:generateRoads()
    self:generateTrees(seedValue or 12345)
    
    return self
end

function ServerLogic:generateRoads()
    print("ServerLogic: Generating road network...")
    local pointsOfInterest = {
        {x = self.worldWidth * 0.15, y = self.worldHeight * 0.15},
        {x = self.worldWidth * 0.85, y = self.worldHeight * 0.2},
        {x = self.worldWidth * 0.5, y = self.worldHeight * 0.5}, -- Center
        {x = self.worldWidth * 0.2, y = self.worldHeight * 0.8},
        {x = self.worldWidth * 0.8, y = self.worldHeight * 0.8}
    }
    self.roadGenerator:generateRoadNetwork(pointsOfInterest, 12345)
end

function ServerLogic:getChunkData(cx, cy)
    local chunkKey = cx .. "," .. cy
    local chunkRoads = self.roads[chunkKey] or {}
    local treeData = self.trees[chunkKey] or {}
    
    -- Format for Protocol.MSG.CHUNK_DATA
    -- { roads = { ["lx,ly"] = tileID, ... } }
    local roadsData = {}
    for lx, col in pairs(chunkRoads) do
        for ly, tileID in pairs(col) do
            roadsData[lx .. "," .. ly] = tileID
        end
    end
    
    return {
        cx = cx,
        cy = cy,
        roads = roadsData,
        water = {}, -- TODO: Generate water if needed
        rocks = {},
        trees = treeData
    }
end

function ServerLogic:generateTrees(seed)
    math.randomseed(seed or os.time())
    local WORLD_W, WORLD_H = self.worldWidth, self.worldHeight
    local TILE_SIZE = 16
    
    -- Variations from World.lua
    local variations = {"standard", "purple", "blue", "alien", "white", "red_white", "all_white"}
    
    -- Density based generation
    for i = 1, 500 do
        local x = math.random(50, WORLD_W - 50)
        local y = math.random(50, WORLD_H - 50)
        
        -- Check if it's on a road (don't spawn trees on roads)
        local tileX = math.floor(x / TILE_SIZE)
        local tileY = math.floor(y / TILE_SIZE)
        if not self.roadGenerator:getRoadTile(tileX, tileY) then
            local variation = variations[math.random(1, #variations)]
            
            -- Store in chunk
            local chunkX = math.floor(x / self.chunkSize)
            local chunkY = math.floor(y / self.chunkSize)
            local key = chunkX .. "," .. chunkY
            
            if not self.trees[key] then self.trees[key] = {} end
            table.insert(self.trees[key], {
                x = x,
                y = y,
                variation = variation
            })
        end
    end
    print("ServerLogic: Generated 500 trees.")
end

-- Add a player to the game
function ServerLogic:addPlayer(playerId, x, y)
    self.state:addPlayer(playerId, x, y)
end

-- Remove a player
function ServerLogic:removePlayer(playerId)
    self.state:removePlayer(playerId)
end

-- Queue input from a client
function ServerLogic:queueInput(msg)
    table.insert(self.inputQueue, msg)
end

-- Process all queued inputs
function ServerLogic:processInputs(dt)
    local queueSize = #self.inputQueue
    if queueSize > 0 then
        print("ServerLogic: processInputs called with " .. queueSize .. " inputs")
    end
    
    for _, input in ipairs(self.inputQueue) do
        print("ServerLogic: Processing input type: " .. (input.type or "nil") .. ", id: " .. (input.id or "nil"))
        if input.type == Protocol.MSG.INPUT_SHOOT then
            self:handleShoot(input.id, input.angle)
        elseif input.type == Protocol.MSG.INPUT_INTERACT then
            self:handleInteract(input.id)
        else
            print("ServerLogic: Unknown input type: " .. (input.type or "nil"))
        end
    end
    
    -- Clear input queue
    self.inputQueue = {}
end

-- Handle shoot input
function ServerLogic:handleShoot(playerId, angle)
    print("=== ServerLogic:handleShoot START ===")
    print("  playerId: " .. (playerId or "nil"))
    print("  angle: " .. (angle or "nil"))
    
    local player = self.state.players[playerId]
    if not player then 
        print("  ERROR: Player " .. (playerId or "?") .. " not found in state!")
        print("  Available players:")
        for pid, p in pairs(self.state.players) do
            print("    - " .. pid .. " at (" .. (p.x or "?") .. ", " .. (p.y or "?") .. ")")
        end
        print("=== ServerLogic:handleShoot END (FAILED) ===")
        return 
    end
    
    print("  Player found at (" .. player.x .. ", " .. player.y .. ")")
    print("  Shooting at angle " .. angle)
    
    -- Calculate damage with boon modifiers
    local damage = self.projectileDamage
    for _, boon in ipairs(player.boons) do
        if boon.type == "damage_boost" then
            damage = damage * (1 + (boon.data.multiplier or 0.5))
        end
    end
    
    print("  Damage: " .. damage)
    print("  Projectile speed: " .. self.projectileSpeed)
    
    -- Create projectile
    local projId = self.state:createProjectile(playerId, player.x, player.y, angle, self.projectileSpeed, damage)
    print("  Created projectile ID: " .. (projId or "nil"))
    
    -- Verify projectile was created
    if self.state.projectiles[projId] then
        local proj = self.state.projectiles[projId]
        print("  Projectile verified in state:")
        print("    - Position: (" .. proj.x .. ", " .. proj.y .. ")")
        print("    - Velocity: (" .. proj.vx .. ", " .. proj.vy .. ")")
        print("    - Owner: " .. (proj.ownerId or "nil"))
        print("    - Damage: " .. (proj.damage or "nil"))
        print("    - Lifetime: " .. (proj.lifetime or "nil"))
    else
        print("  ERROR: Projectile not found in state after creation!")
    end
    
    -- Count total projectiles
    local totalProj = 0
    for _ in pairs(self.state.projectiles) do totalProj = totalProj + 1 end
    print("  Total projectiles in state: " .. totalProj)
    print("=== ServerLogic:handleShoot END (SUCCESS) ===")
end

-- Handle interact input (open chests)
function ServerLogic:handleInteract(playerId)
    if Constants.DISABLE_CHESTS then
        return
    end

    local player = self.state.players[playerId]
    if not player then return end
    
    -- Check for nearby chests (within 32 pixels)
    local interactRange = 32
    for chestId, chest in pairs(self.state.chests) do
        if not chest.opened then
            local dx = player.x - chest.x
            local dy = player.y - chest.y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist <= interactRange then
                -- Open chest and grant boon
                if self.state:openChest(chestId, playerId) then
                    -- Grant a random boon based on chest rarity
                    local boonType = self:generateRandomBoon(chest.rarity)
                    self.state:grantBoon(playerId, boonType, { rarity = chest.rarity })
                    return  -- Only open one chest at a time
                end
            end
        end
    end
end

-- Generate a random boon based on rarity
function ServerLogic:generateRandomBoon(rarity)
    local boons = {
        common = { "damage_boost", "speed_boost", "hp_boost" },
        rare = { "triple_shot", "piercing", "lifesteal" },
        epic = { "dash", "shield", "slow_enemies" },
        legendary = { "teleport", "steal_on_hit", "boss_damage" },
    }
    
    local availableBoons = boons[rarity] or boons.common
    return availableBoons[math.random(1, #availableBoons)]
end

-- Update game simulation
function ServerLogic:update(dt)
    -- Process inputs
    if #self.inputQueue > 0 then
        print("ServerLogic:update - Processing " .. #self.inputQueue .. " queued inputs")
    end
    self:processInputs(dt)
    
    -- Debug: log projectile count
    if self.state.projectiles then
        local projCount = 0
        for _ in pairs(self.state.projectiles) do projCount = projCount + 1 end
        if projCount > 0 and (not self.lastProjLog or love.timer.getTime() - self.lastProjLog > 1) then
            print("ServerLogic:update - " .. projCount .. " projectiles active")
            self.lastProjLog = love.timer.getTime()
        end
    end
    
    -- Update players (movement is handled client-side, but we track position)
    -- (For now, we'll trust client position updates, but in future we should validate)
    
    -- Update projectiles
    for projId, proj in pairs(self.state.projectiles) do
        -- Move projectile
        proj.x = proj.x + proj.vx * dt
        proj.y = proj.y + proj.vy * dt
        proj.lifetime = proj.lifetime - dt
        
        -- Check collision with players
        for playerId, player in pairs(self.state.players) do
            if playerId ~= proj.ownerId and not player.invulnerable then
                local dx = player.x - proj.x
                local dy = player.y - proj.y
                local dist = math.sqrt(dx * dx + dy * dy)
                
                if dist < 16 then  -- Hit!
                    local died = self.state:damagePlayer(playerId, proj.damage)
                    self.state:removeProjectile(projId)
                    
                    if died then
                        -- Player died - steal boons!
                        local stolenCount = self.state:stealBoons(proj.ownerId, playerId)
                        self.state.players[proj.ownerId].kills = self.state.players[proj.ownerId].kills + 1
                        self.state.players[playerId].deaths = self.state.players[playerId].deaths + 1
                        
                        -- Respawn player
                        self.state:respawnPlayer(playerId, self.worldWidth, self.worldHeight)
                    end
                    
                    break  -- Projectile hit someone, remove it
                end
            end
        end
        
        -- Remove expired projectiles
        if proj.lifetime <= 0 then
            self.state:removeProjectile(projId)
        end
    end
    
    -- Update chest respawn timers
    for chestId, chest in pairs(self.state.chests) do
        if chest.opened then
            chest.respawnTimer = chest.respawnTimer - dt
            if chest.respawnTimer <= 0 then
                chest.opened = false
            end
        end
    end
    
    -- Update player invulnerability
    for playerId, player in pairs(self.state.players) do
        if player.invulnerable then
            player.invulnerableTimer = player.invulnerableTimer - dt
            if player.invulnerableTimer <= 0 then
                player.invulnerable = false
            end
        end
    end
    
    -- Check win condition (first to 5 kills)
    for playerId, player in pairs(self.state.players) do
        if player.kills >= 5 then
            self.state.winner = playerId
            -- Use os.time or love.timer if available
            if love and love.timer then
                self.state.matchEndTime = love.timer.getTime()
            elseif os and os.time then
                self.state.matchEndTime = os.time()
            else
                self.state.matchEndTime = 0
            end
        end
    end
end

-- Get state snapshot for broadcasting
function ServerLogic:getStateSnapshot()
    return self.state:serialize()
end

-- Spawn initial chests
function ServerLogic:spawnInitialChests(count)
    count = count or 10
    for i = 1, count do
        local x = 100 + math.random() * (self.worldWidth - 200)
        local y = 100 + math.random() * (self.worldHeight - 200)
        local rarity = "common"  -- Start with common chests
        if math.random() < 0.1 then rarity = "rare" end
        if math.random() < 0.02 then rarity = "epic" end

        self.state:createChest(x, y, rarity)
    end
end

-- Spawn NPCs (server-authoritative)
function ServerLogic:spawnNPCs()
    local WORLD_W, WORLD_H = self.worldWidth, self.worldHeight

    -- Create NPCs using the same positions as the client spawner
    self.state:createNpc(
        WORLD_W * 0.15, WORLD_H * 0.15,
        "assets/img/sprites/humans/Overworked Villager/OverworkedVillager.png",
        "Old Wanderer",
        {
            "They say love is the key. But to what door? I've forgotten.",
            "The one who walks the ancient paths might remember. Find the keeper of old truths.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.85, WORLD_H * 0.2,
        "assets/img/sprites/humans/Elf Lord/ElfLord.png",
        "Keeper of Truths",
        {
            "Love binds what time cannot. It's the thread that holds worlds together.",
            "But threads can fray. The mystic knows how they connect. Seek the one who reads the currents.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.8, WORLD_H * 0.75,
        "assets/img/sprites/humans/Merfolk Mystic/MerfolkMystic.png",
        "Current Reader",
        {
            "Every bond is a current. Love flows between souls like water between stones.",
            "But currents can be redirected. The enchanter understands this power. Find the one who shapes what cannot be seen.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.2, WORLD_H * 0.8,
        "assets/img/sprites/humans/Elf Enchanter/ElfEnchanter.png",
        "Shape Shifter",
        {
            "Love shapes reality itself. It's not just feeling—it's a force that remakes the world.",
            "But forces can be dangerous. The young wanderer has seen what happens when it breaks. Look for the one who carries scars.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.5, WORLD_H * 0.1,
        "assets/img/sprites/humans/Adventurous Adolescent/AdventurousAdolescent.png",
        "Scarred Wanderer",
        {
            "I've seen what happens when love is lost. The world grows cold. Colors fade.",
            "But I've also seen it return. The loud one knows how. Find the voice that never quiets.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.5, WORLD_H * 0.9,
        "assets/img/sprites/humans/Boisterous Youth/BoisterousYouth.png",
        "The Voice",
        {
            "Love isn't found—it's chosen. Every moment you choose connection over isolation.",
            "The wayfarer has walked this path longer than any. They know where it leads. Find the one who never stops moving.",
        }
    )

    -- Move Elf Wayfarer away from spawn point (2500, 2500) to avoid collision
    -- Place it slightly northeast of center to maintain story significance
    self.state:createNpc(
        WORLD_W * 0.52, WORLD_H * 0.48,
        "assets/img/sprites/humans/Elf Wayfarer/ElfWayfarer.png",
        "The Eternal Walker",
        {
            "I've walked every path. Love is the only thing that makes any of them matter.",
            "Without it, we're just shadows moving through an empty world. With it... we become real.",
            "The old wanderer was right. It is the key. But the door? That's for you to find.",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.25, WORLD_H * 0.3,
        "assets/img/sprites/humans/Joyful Kid/JoyfulKid.png",
        "Little One",
        {
            "Everyone talks about love but nobody explains it!",
            "Maybe the grown-ups don't know either?",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.75, WORLD_H * 0.3,
        "assets/img/sprites/humans/Playful Child/PlayfulChild.png",
        "Curious Child",
        {
            "I heard the old wanderer talking about keys and doors!",
            "Do you think there's a secret door somewhere?",
        }
    )

    self.state:createNpc(
        WORLD_W * 0.3, WORLD_H * 0.7,
        "assets/img/sprites/humans/Elf Bladedancer/ElfBladedancer.png",
        "Silent Guardian",
        {
            "I guard the paths. Many seek answers. Few find them.",
            "The truth is scattered. You must gather all the pieces.",
        }
    )
end

-- Spawn animals (server-authoritative) (Disabled for performance)
function ServerLogic:spawnAnimals()
    -- local WORLD_W, WORLD_H = self.worldWidth, self.worldHeight
    -- ... (logic removed)
end

return ServerLogic
