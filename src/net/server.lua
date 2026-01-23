-- src/net/server.lua
-- Simple relay server for walking simulator
-- Relays player positions to all connected clients

local enet = require("enet")
local Protocol = require("src.net.protocol")

local Server = {}
Server.__index = Server

function Server:new(port)
    local self = setmetatable({}, Server)
    
    self.port = port or 12345
    self.host = enet.host_create("*:" .. self.port, 10)
    
    if not self.host then
        print("ERROR: Failed to create server on port " .. self.port)
        return self
    end
    
    -- Track connected players: peer -> { id, x, y, direction }
    self.players = {}
    self.nextPlayerId = 1
    self.playerId = "host"
    
    -- Rate limiting
    self.lastSendTime = 0
    self.sendRate = 1/20
    
    print("=== Server Started ===")
    print("Port: " .. self.port)
    
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
    if not self.host then return end
    
    local flag = reliable and "reliable" or "unreliable"
    for peer in pairs(self.players) do
        if peer ~= excludePeer then
            peer:send(data, 0, flag)
        end
    end
end

function Server:sendPosition(x, y, direction, skin)
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
    if not self.host then return messages end
    
    local event = self.host:service(0)
    while event do
        if event.type == "connect" then
            local playerId = "p" .. self.nextPlayerId
            self.nextPlayerId = self.nextPlayerId + 1
            
            self.players[event.peer] = {
                id = playerId,
                x = 400, y = 300,
                direction = "down"
            }
            
            print("Player " .. playerId .. " connected")
            
            -- Tell new player their ID (skin will be sent by client)
            event.peer:send(Protocol.encode(
                Protocol.MSG.PLAYER_JOIN, playerId, 400, 300
            ), 0, "reliable")
            
            -- Tell others about new player (skin will be sent by client)
            self:broadcast(Protocol.encode(
                Protocol.MSG.PLAYER_JOIN, playerId, 400, 300
            ), event.peer, true)
            
            -- Tell new player about host (with host's skin if available)
            local hostEncoded = Protocol.encode(Protocol.MSG.PLAYER_JOIN, "host", 400, 300)
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
                x = 400, y = 300
            })
            
        elseif event.type == "receive" then
            local msg = Protocol.decode(event.data)
            
            if msg.type == Protocol.MSG.PLAYER_MOVE then
                local player = self.players[event.peer]
                if player then
                    player.x = msg.x
                    player.y = msg.y
                    player.direction = msg.dir
                    if msg.skin then
                        player.skin = msg.skin
                    end
                    
                    -- Relay to others
                    local encoded = Protocol.encode(
                        Protocol.MSG.PLAYER_MOVE,
                        player.id, msg.x, msg.y, msg.dir
                    )
                    if msg.skin then
                        encoded = encoded .. "|" .. msg.skin
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
                    table.insert(messages, moveMsg)
                end
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

return Server
