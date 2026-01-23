-- src/net/server.lua
-- Simple relay server for walking simulator / Boon Snatch
-- Relays player positions to all connected clients
-- If gameMode is "boonsnatch", runs server-authoritative game simulation

local enet = require("enet")
local Protocol = require("src.net.protocol")

local Server = {}
local json = require('src.lib.dkjson')
Server.__index = Server

function Server:new(port, gameMode)
    local self = setmetatable({}, Server)
    
    self.port = port or 12345
    -- If port is nil, don't create ENet host (local-only server logic)
    if port then
        self.host = enet.host_create("*:" .. self.port, 10)
        
        if not self.host then
            print("ERROR: Failed to create server on port " .. self.port)
            return self
        end
    else
        self.host = nil  -- Local-only server logic, no network
        print("Server: Created local-only server (no network port)")
    end
    
    -- Local loopback for host
    self.localMessages = {}
    
    -- Track connected players: peer -> { id, x, y, direction }
    self.players = {}
    self.nextPlayerId = 1
    self.playerId = "host"
    
    -- Rate limiting
    self.lastSendTime = 0
    self.sendRate = 1/20
    
    -- Game mode: "walking" (default) or "boonsnatch"
    self.gameMode = gameMode or "walking"
    
    -- Boon Snatch game logic (only if gameMode is "boonsnatch")
    self.serverLogic = nil
    if self.gameMode == "boonsnatch" then
        local ServerLogic = require("src.gamemodes.boonsnatch.server_logic")
        self.serverLogic = ServerLogic:new(5000, 5000)  -- Match client world size
        -- Add host player to game state (center of huge world)
        self.serverLogic:addPlayer("host", 2500, 2500)
        -- Spawn initial chests
        self.serverLogic:spawnInitialChests(10)
        -- Spawn NPCs
        self.serverLogic:spawnNPCs()
        -- Spawn animals (Disabled for performance)
        -- self.serverLogic:spawnAnimals()
        print("=== Boon Snatch Game Mode Enabled ===")
    end
    
    -- State broadcast timing
    self.lastStateBroadcast = 0
    self.stateBroadcastInterval = 1.0 / 20  -- 20 times per second
    
    print("=== Server Started ===")
    if self.port then
        print("Port: " .. self.port)
    else
        print("Port: local-only (no network)")
    end
    print("Game Mode: " .. self.gameMode)
    
    return self
end

function Server:disconnect()
    if not self.host then return end
    
    for peer in pairs(self.players) do
        peer:disconnect_now()
    end
    
    self.host:flush()
    self.host = nil
    self.players = {}
    print("Server stopped")
end

function Server:broadcast(data, excludePeer, reliable)
    -- Send to remote peers
    if self.host then
        local flag = reliable and "reliable" or "unreliable"
        for peer in pairs(self.players) do
            if peer ~= excludePeer then
                peer:send(data, 0, flag)
            end
        end
    end
    
    -- Always send to local host loopback
    table.insert(self.localMessages, data)
end

function Server:sendPosition(x, y, direction, skin, sprinting)
    if not self.host then return end
    
    -- Store host's skin for new connections
    if skin then
        self.hostSkin = skin
    end
    
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then return end
    self.lastSendTime = now
    
    local encoded = Protocol.encode(
        Protocol.MSG.PLAYER_MOVE,
        "host",
        math.floor(x),
        math.floor(y),
        direction or "down"
    )
    if skin then
        encoded = encoded .. "|" .. skin
    end
    if sprinting then
        encoded = encoded .. "|1"
    end
    self:broadcast(encoded)
end

function Server:sendPetPosition(playerId, x, y, monster)
    if not self.host then return end
    local encoded = Protocol.encode(
        Protocol.MSG.PET_MOVE,
        playerId or "host",
        math.floor(x),
        math.floor(y)
    )
    if monster then
        encoded = encoded .. "|" .. monster
    end
    self:broadcast(encoded)
end

function Server:sendMessage(msg)
    -- Not used in walking simulator
end

function Server:poll()
    local messages = {}
    
    -- Process loopback messages first
    for _, data in ipairs(self.localMessages) do
        local msg = Protocol.decode(data)
        if msg then
            table.insert(messages, msg)
        end
    end
    self.localMessages = {}
    
    if not self.host then 
        -- Local-only server (no network), return only loopback messages
        return messages 
    end
    
    local event = self.host:service(0)
    while event do
        if event.type == "connect" then
            local playerId = "p" .. self.nextPlayerId
            self.nextPlayerId = self.nextPlayerId + 1
            
            -- Spawn position (center of world for Boon Snatch, or default for walking)
            local spawnX, spawnY = 400, 300
            if self.gameMode == "boonsnatch" then
                -- Scatter players in a small spawn area (1-2 tiles = 16-32 pixels apart)
                local centerX, centerY = 2500, 2500  -- Center of 5000x5000 world
                local spawnRadius = 40  -- Maximum distance from center (2.5 tiles)
                local minDistance = 24  -- Minimum distance between players (1.5 tiles)
                
                -- Try to find a valid spawn position that doesn't collide with existing players
                local attempts = 0
                local maxAttempts = 50
                repeat
                    local angle = math.random() * math.pi * 2
                    local distance = math.random() * spawnRadius
                    spawnX = centerX + math.cos(angle) * distance
                    spawnY = centerY + math.sin(angle) * distance
                    
                    -- Check collision with existing players
                    local tooClose = false
                    for _, player in pairs(self.players) do
                        local dx = spawnX - player.x
                        local dy = spawnY - player.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist < minDistance then
                            tooClose = true
                            break
                        end
                    end
                    
                    -- Also check with serverLogic players if available
                    if self.serverLogic and not tooClose then
                        for pid, player in pairs(self.serverLogic.state.players) do
                            if pid ~= playerId then
                                local dx = spawnX - player.x
                                local dy = spawnY - player.y
                                local dist = math.sqrt(dx * dx + dy * dy)
                                if dist < minDistance then
                                    tooClose = true
                                    break
                                end
                            end
                        end
                    end
                    
                    attempts = attempts + 1
                    if not tooClose then break end
                until attempts >= maxAttempts
                
                -- If we couldn't find a good spot after many attempts, just use a random offset
                if attempts >= maxAttempts then
                    spawnX = centerX + (math.random() - 0.5) * spawnRadius * 2
                    spawnY = centerY + (math.random() - 0.5) * spawnRadius * 2
                end
            end
            
            self.players[event.peer] = {
                id = playerId,
                x = spawnX, y = spawnY,
                direction = "down"
            }
            
            print("Player " .. playerId .. " connected")
            
            -- Add to game state if Boon Snatch mode
            if self.serverLogic then
                self.serverLogic:addPlayer(playerId, spawnX, spawnY)
            end
            
            -- Tell new player their ID (skin will be sent by client)
            event.peer:send(Protocol.encode(
                Protocol.MSG.PLAYER_JOIN, playerId, spawnX, spawnY
            ), 0, "reliable")
            
            -- Send initial game state if Boon Snatch mode
            if self.serverLogic then
                local stateJson = self.serverLogic:getStateSnapshot()
                event.peer:send(Protocol.encode(
                    Protocol.MSG.STATE_SNAPSHOT, stateJson
                ), 0, "reliable")
            end
            
            -- Tell others about new player (skin will be sent by client)
            self:broadcast(Protocol.encode(
                Protocol.MSG.PLAYER_JOIN, playerId, spawnX, spawnY
            ), event.peer, true)
            
            -- Tell new player about host (with host's skin if available)
            local hostEncoded = Protocol.encode(Protocol.MSG.PLAYER_JOIN, "host", spawnX, spawnY)
            if self.players and self.hostSkin then
                hostEncoded = hostEncoded .. "|" .. self.hostSkin
            end
            event.peer:send(hostEncoded, 0, "reliable")
            
            -- Tell new player about existing players (with their skins)
            for peer, player in pairs(self.players) do
                if peer ~= event.peer then
                    local playerEncoded = Protocol.encode(
                        Protocol.MSG.PLAYER_JOIN,
                        player.id, player.x, player.y
                    )
                    if player.skin then
                        playerEncoded = playerEncoded .. "|" .. player.skin
                    end
                    event.peer:send(playerEncoded, 0, "reliable")
                end
            end
            
            table.insert(messages, {
                type = "player_joined",
                id = playerId,
                x = spawnX, y = spawnY
            })
            
        elseif event.type == "receive" then
            local msg = Protocol.decode(event.data)
            local player = self.players[event.peer]
            
            if msg.type == Protocol.MSG.PLAYER_MOVE then
                if player then
                    -- Update player position in server state
                    player.x = msg.x
                    player.y = msg.y
                    player.direction = msg.dir
                    if msg.skin then
                        player.skin = msg.skin
                    end
                    if msg.sprinting ~= nil then
                        player.sprinting = msg.sprinting
                    end
                    
                    -- Update game state if Boon Snatch mode
                    if self.serverLogic and self.serverLogic.state.players[player.id] then
                        self.serverLogic.state.players[player.id].x = msg.x
                        self.serverLogic.state.players[player.id].y = msg.y
                        self.serverLogic.state.players[player.id].direction = msg.dir
                    end
                    
                    -- Relay to others
                    local encoded = Protocol.encode(
                        Protocol.MSG.PLAYER_MOVE,
                        player.id, msg.x, msg.y, msg.dir
                    )
                    if msg.skin then
                        encoded = encoded .. "|" .. msg.skin
                    end
                    if msg.sprinting then
                        encoded = encoded .. "|1"
                    end
                    self:broadcast(encoded, event.peer)
                    
                    local moveMsg = {
                        type = "player_moved",
                        id = player.id,
                        x = msg.x, y = msg.y,
                        dir = msg.dir
                    }
                    if msg.skin then
                        moveMsg.skin = msg.skin
                    end
                    if msg.sprinting ~= nil then
                        moveMsg.sprinting = msg.sprinting
                    end
                    table.insert(messages, moveMsg)
                end
                
            -- Boon Snatch game inputs
            elseif msg.type == Protocol.MSG.INPUT_SHOOT and self.serverLogic and player then
                -- Queue shoot input for processing
                self.serverLogic:queueInput({
                    type = Protocol.MSG.INPUT_SHOOT,
                    id = player.id,
                    angle = msg.angle
                })
                
            elseif msg.type == Protocol.MSG.INPUT_INTERACT and self.serverLogic and player then
                -- Queue interact input for processing
                self.serverLogic:queueInput({
                    type = Protocol.MSG.INPUT_INTERACT,
                    id = player.id
                })

            elseif msg.type == Protocol.MSG.PING then
                -- Respond to ping with pong
                local pongData = Protocol.encode(Protocol.MSG.PONG, msg.timestamp)
                event.peer:send(pongData, 0, "unreliable")

            elseif msg.type == Protocol.MSG.PONG then
                -- Server doesn't need to handle pong messages (clients measure ping)

            elseif msg.type == Protocol.MSG.PET_MOVE then
                -- Relay pet position to others
                local encoded = Protocol.encode(
                    Protocol.MSG.PET_MOVE,
                    msg.id, msg.x, msg.y
                )
                if msg.monster then
                    encoded = encoded .. "|" .. msg.monster
                end
                self:broadcast(encoded, event.peer)
                
                local petMsg = {
                    type = "pet_moved",
                    id = msg.id,
                    x = msg.x, y = msg.y
                }
                if msg.monster then
                    petMsg.monster = msg.monster
                end
                table.insert(messages, petMsg)
            end
            
        elseif event.type == "disconnect" then
            local player = self.players[event.peer]
            if player then
                print("Player " .. player.id .. " disconnected")
                
                -- Remove from game state if Boon Snatch mode
                if self.serverLogic then
                    self.serverLogic:removePlayer(player.id)
                end
                
                self:broadcast(Protocol.encode(
                    Protocol.MSG.PLAYER_LEAVE, player.id
                ), nil, true)
                
                table.insert(messages, {
                    type = "player_left",
                    id = player.id
                })
                
                self.players[event.peer] = nil
            end
        end
        
        event = self.host:service(0)
    end
    
    return messages
end

-- Update game simulation (call this from game loop when hosting)
function Server:update(dt)
    if not self.serverLogic then 
        -- For local-only servers, this is expected if not in Boon Snatch mode
        if self.gameMode == "boonsnatch" then
            print("Server:update - No serverLogic!")
        end
        return 
    end
    
    -- Run game simulation
    self.serverLogic:update(dt)
    
    -- Broadcast state snapshot periodically
    local now = love.timer.getTime()
    if now - self.lastStateBroadcast >= self.stateBroadcastInterval then
        local stateJson = self.serverLogic:getStateSnapshot()
        local encoded = Protocol.encode(Protocol.MSG.STATE_SNAPSHOT, stateJson)
        self:broadcast(encoded, nil, false)  -- Unreliable for frequent updates
        
        -- Debug: log projectile count in state
        local json = require("src.lib.dkjson")
        local success, state = pcall(json.decode, stateJson)
        if success and state and state.projectiles then
            local projCount = 0
            for _ in pairs(state.projectiles) do projCount = projCount + 1 end
            if projCount > 0 then
                print("Server: Broadcasting state with " .. projCount .. " projectiles")
            end
        end
        
        self.lastStateBroadcast = now
    end
end

return Server
