-- src/gamemodes/boonsnatch/server_logic.lua
-- Server-authoritative game logic for Boon Snatch
-- Runs on the host, simulates the game, sends state to clients

local State = require('src.gamemodes.boonsnatch.state')
local Protocol = require('src.net.protocol')

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

return ServerLogic
