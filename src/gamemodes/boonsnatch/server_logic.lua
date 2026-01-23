-- src/gamemodes/boonsnatch/server_logic.lua
-- Server-authoritative game logic for Boon Snatch
-- Runs on the host, simulates the game, sends state to clients

local State = require('src.gamemodes.boonsnatch.state')
local Protocol = require('src.net.protocol')
local Constants = require('src.constants')

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
    
    return self
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

-- Spawn animals (server-authoritative)
function ServerLogic:spawnAnimals()
    local WORLD_W, WORLD_H = self.worldWidth, self.worldHeight

    local function addAnimalGroup(centerX, centerY, radius, animalData)
        for i = 1, animalData.count do
            local angle = (i / animalData.count) * math.pi * 2 + (animalData.offset or 0)
            local offsetX = math.cos(angle) * (radius * animalData.distance)
            local offsetY = math.sin(angle) * (radius * animalData.distance)
            local x = centerX + offsetX
            local y = centerY + offsetY

            self.state:createAnimal(
                x, y,
                animalData.spritePath,
                animalData.name,
                animalData.speed,
                centerX, centerY, radius
            )
        end
    end

    -- Farm animals (northwest) - INCREASED DENSITY
    local farmX, farmY, farmR = WORLD_W * 0.15, WORLD_H * 0.15, 500
    addAnimalGroup(farmX, farmY, farmR, {count = 8, distance = 0.3, spritePath = "assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png", name = "Chicken", speed = 25})
    addAnimalGroup(farmX, farmY, farmR, {count = 6, distance = 0.5, spritePath = "assets/img/sprites/animals/Dainty Pig/DaintyPig.png", name = "Pig", speed = 20})
    addAnimalGroup(farmX, farmY, farmR, {count = 6, distance = 0.4, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png", name = "Sheep", speed = 22})
    addAnimalGroup(farmX, farmY, farmR, {count = 5, distance = 0.6, offset = math.pi / 3, spritePath = "assets/img/sprites/animals/Tiny Chick/TinyChick.png", name = "Chick", speed = 18})

    -- Forest animals (northeast) - INCREASED DENSITY
    local forestX, forestY, forestR = WORLD_W * 0.85, WORLD_H * 0.2, 550
    addAnimalGroup(forestX, forestY, forestR, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Snow Fox/SnowFox.png", name = "Fox", speed = 35})
    addAnimalGroup(forestX, forestY, forestR, {count = 4, distance = 0.6, spritePath = "assets/img/sprites/animals/Timber Wolf/TimberWolf.png", name = "Wolf", speed = 40})
    addAnimalGroup(forestX, forestY, forestR, {count = 4, distance = 0.3, offset = math.pi / 4, spritePath = "assets/img/sprites/animals/Spikey Porcupine/SpikeyPorcupine.png", name = "Porcupine", speed = 18})
    addAnimalGroup(forestX, forestY, forestR, {count = 5, distance = 0.5, offset = math.pi / 2, spritePath = "assets/img/sprites/animals/Meowing Cat/MeowingCat.png", name = "Cat", speed = 35})

    -- Swamp animals (southeast) - INCREASED DENSITY
    local swampX, swampY, swampR = WORLD_W * 0.8, WORLD_H * 0.8, 500
    addAnimalGroup(swampX, swampY, swampR, {count = 8, distance = 0.35, spritePath = "assets/img/sprites/animals/Croaking Toad/CroakingToad.png", name = "Toad", speed = 15})
    addAnimalGroup(swampX, swampY, swampR, {count = 6, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Leaping Frog/LeapingFrog.png", name = "Frog", speed = 30})
    addAnimalGroup(swampX, swampY, swampR, {count = 4, distance = 0.25, spritePath = "assets/img/sprites/animals/Slow Turtle/SlowTurtle.png", name = "Turtle", speed = 12})

    -- Wild animals (southwest) - INCREASED DENSITY
    local wildX, wildY, wildR = WORLD_W * 0.2, WORLD_H * 0.85, 550
    addAnimalGroup(wildX, wildY, wildR, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Mad Boar/MadBoar.png", name = "Boar", speed = 32})
    addAnimalGroup(wildX, wildY, wildR, {count = 4, distance = 0.5, offset = math.pi / 4, spritePath = "assets/img/sprites/animals/Stinky Skunk/StinkySkunk.png", name = "Skunk", speed = 28})
    addAnimalGroup(wildX, wildY, wildR, {count = 6, distance = 0.3, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Honking Goose/HonkingGoose.png", name = "Goose", speed = 33})

    -- Coastal animals (center-east) - INCREASED DENSITY
    local coastalX, coastalY, coastalR = WORLD_W * 0.7, WORLD_H * 0.5, 500
    addAnimalGroup(coastalX, coastalY, coastalR, {count = 8, distance = 0.4, spritePath = "assets/img/sprites/animals/Coral Crab/CoralCrab.png", name = "Crab", speed = 20})
    addAnimalGroup(coastalX, coastalY, coastalR * 1.5, {count = 4, distance = 0.6, spritePath = "assets/img/sprites/animals/Meowing Cat/MeowingCat.png", name = "Cat", speed = 35})

    -- Mountain animals (north central) - INCREASED DENSITY
    local mountainX, mountainY, mountainR = WORLD_W * 0.5, WORLD_H * 0.15, 550
    addAnimalGroup(mountainX, mountainY, mountainR, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Timber Wolf/TimberWolf.png", name = "Wolf", speed = 40})
    addAnimalGroup(mountainX, mountainY, mountainR, {count = 6, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Snow Fox/SnowFox.png", name = "Fox", speed = 35})
    addAnimalGroup(mountainX, mountainY, mountainR, {count = 4, distance = 0.3, offset = math.pi / 3, spritePath = "assets/img/sprites/animals/Spikey Porcupine/SpikeyPorcupine.png", name = "Porcupine", speed = 18})

    -- Desert animals (center-west) - INCREASED DENSITY
    local desertX, desertY, desertR = WORLD_W * 0.3, WORLD_H * 0.5, 500
    addAnimalGroup(desertX, desertY, desertR, {count = 8, distance = 0.3, spritePath = "assets/img/sprites/animals/Croaking Toad/CroakingToad.png", name = "Toad", speed = 15})
    addAnimalGroup(desertX, desertY, desertR, {count = 4, distance = 0.5, spritePath = "assets/img/sprites/animals/Slow Turtle/SlowTurtle.png", name = "Turtle", speed = 12})

    -- Grassland animals (center-northwest) - INCREASED DENSITY
    local grasslandX, grasslandY, grasslandR = WORLD_W * 0.35, WORLD_H * 0.35, 550
    addAnimalGroup(grasslandX, grasslandY, grasslandR, {count = 10, distance = 0.5, spritePath = "assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png", name = "Chicken", speed = 25})
    addAnimalGroup(grasslandX, grasslandY, grasslandR, {count = 8, distance = 0.4, offset = math.pi / 8, spritePath = "assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png", name = "Sheep", speed = 22})
    addAnimalGroup(grasslandX, grasslandY, grasslandR, {count = 6, distance = 0.3, offset = math.pi / 4, spritePath = "assets/img/sprites/animals/Dainty Pig/DaintyPig.png", name = "Pig", speed = 20})

    -- River animals (center-south) - INCREASED DENSITY
    local riverX, riverY, riverR = WORLD_W * 0.55, WORLD_H * 0.7, 500
    addAnimalGroup(riverX, riverY, riverR, {count = 8, distance = 0.4, spritePath = "assets/img/sprites/animals/Honking Goose/HonkingGoose.png", name = "Goose", speed = 33})
    addAnimalGroup(riverX, riverY, riverR, {count = 6, distance = 0.5, offset = math.pi / 6, spritePath = "assets/img/sprites/animals/Leaping Frog/LeapingFrog.png", name = "Frog", speed = 30})
    addAnimalGroup(riverX, riverY, riverR, {count = 4, distance = 0.6, offset = math.pi / 3, spritePath = "assets/img/sprites/animals/Coral Crab/CoralCrab.png", name = "Crab", speed = 20})

    -- Tiny chicks (center) - INCREASED DENSITY
    local chickX, chickY, chickR = WORLD_W * 0.5, WORLD_H * 0.5, 400
    addAnimalGroup(chickX, chickY, chickR, {count = 10, distance = 0.5, spritePath = "assets/img/sprites/animals/Tiny Chick/TinyChick.png", name = "Chick", speed = 18})

    -- NEW GROUPS: Additional scattered groups for higher density

    -- Northeast scattered groups
    addAnimalGroup(WORLD_W * 0.75, WORLD_H * 0.3, 300, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Clucking Chicken/CluckingChicken.png", name = "Chicken", speed = 25})
    addAnimalGroup(WORLD_W * 0.9, WORLD_H * 0.35, 350, {count = 5, distance = 0.5, spritePath = "assets/img/sprites/animals/Pasturing Sheep/PasturingSheep.png", name = "Sheep", speed = 22})
    addAnimalGroup(WORLD_W * 0.8, WORLD_H * 0.4, 300, {count = 4, distance = 0.4, spritePath = "assets/img/sprites/animals/Tiny Chick/TinyChick.png", name = "Chick", speed = 18})

    -- Northwest scattered groups
    addAnimalGroup(WORLD_W * 0.25, WORLD_H * 0.25, 350, {count = 5, distance = 0.4, spritePath = "assets/img/sprites/animals/Leaping Frog/LeapingFrog.png", name = "Frog", speed = 30})
    addAnimalGroup(WORLD_W * 0.3, WORLD_H * 0.3, 300, {count = 4, distance = 0.5, spritePath = "assets/img/sprites/animals/Croaking Toad/CroakingToad.png", name = "Toad", speed = 15})

    -- Southeast scattered groups
    addAnimalGroup(WORLD_W * 0.75, WORLD_H * 0.75, 350, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Honking Goose/HonkingGoose.png", name = "Goose", speed = 33})
    addAnimalGroup(WORLD_W * 0.85, WORLD_H * 0.7, 300, {count = 5, distance = 0.5, spritePath = "assets/img/sprites/animals/Meowing Cat/MeowingCat.png", name = "Cat", speed = 35})

    -- Southwest scattered groups
    addAnimalGroup(WORLD_W * 0.25, WORLD_H * 0.75, 350, {count = 5, distance = 0.4, spritePath = "assets/img/sprites/animals/Mad Boar/MadBoar.png", name = "Boar", speed = 32})
    addAnimalGroup(WORLD_W * 0.15, WORLD_H * 0.7, 300, {count = 4, distance = 0.5, spritePath = "assets/img/sprites/animals/Stinky Skunk/StinkySkunk.png", name = "Skunk", speed = 28})

    -- Center-north scattered groups
    addAnimalGroup(WORLD_W * 0.45, WORLD_H * 0.25, 350, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Snow Fox/SnowFox.png", name = "Fox", speed = 35})
    addAnimalGroup(WORLD_W * 0.55, WORLD_H * 0.3, 300, {count = 4, distance = 0.5, spritePath = "assets/img/sprites/animals/Timber Wolf/TimberWolf.png", name = "Wolf", speed = 40})

    -- Center-south scattered groups
    addAnimalGroup(WORLD_W * 0.45, WORLD_H * 0.65, 350, {count = 6, distance = 0.4, spritePath = "assets/img/sprites/animals/Coral Crab/CoralCrab.png", name = "Crab", speed = 20})
    addAnimalGroup(WORLD_W * 0.6, WORLD_H * 0.6, 300, {count = 5, distance = 0.5, spritePath = "assets/img/sprites/animals/Slow Turtle/SlowTurtle.png", name = "Turtle", speed = 12})
end

return ServerLogic
