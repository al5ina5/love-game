-- src/net/client.lua
-- Simple client for walking simulator
-- Sends position, receives other players' positions

local enet = require("enet")
local Protocol = require("src.net.protocol")

local Client = {}
Client.__index = Client

function Client:new()
    local self = setmetatable({}, Client)
    
    self.host = nil
    self.server = nil
    self.connected = false
    self.playerId = nil
    
    -- Rate limiting
    self.lastSendTime = 0
    self.sendRate = 1/20
    
    return self
end

function Client:connect(address, port)
    if self.host then
        self:disconnect()
    end
    
    self.host = enet.host_create()
    if not self.host then
        print("ERROR: Failed to create ENet host")
        return false
    end
    
    self.server = self.host:connect(address .. ":" .. port)
    print("Connecting to " .. address .. ":" .. port .. "...")
    return true
end

function Client:disconnect()
    if self.server then
        self.server:disconnect_now()
        self.server = nil
    end
    if self.host then
        self.host:flush()
        self.host = nil
    end
    self.connected = false
    self.playerId = nil
    print("Disconnected")
end

function Client:sendPosition(x, y, direction, skin)
    if not self.connected or not self.server then return end
    
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then return end
    self.lastSendTime = now
    
    local data = Protocol.encode(
        Protocol.MSG.PLAYER_MOVE,
        self.playerId or "?",
        math.floor(x),
        math.floor(y),
        direction or "down"
    )
    if skin then
        data = data .. "|" .. skin
    end
    
    self.server:send(data, 0, "unreliable")
end

function Client:sendPetPosition(playerId, x, y, monster)
    if not self.connected or not self.server then return end
    local data = Protocol.encode(
        Protocol.MSG.PET_MOVE,
        playerId or self.playerId or "?",
        math.floor(x),
        math.floor(y)
    )
    if monster then
        data = data .. "|" .. monster
    end
    self.server:send(data, 0, "unreliable")
end

function Client:sendMessage(msg)
    -- Not used in walking simulator
end

function Client:poll()
    local messages = {}
    if not self.host then return messages end
    
    local event = self.host:service(0)
    while event do
        if event.type == "connect" then
            print("Connected to server!")
            self.connected = true
            
        elseif event.type == "receive" then
            local msg = Protocol.decode(event.data)
            
            if msg.type == Protocol.MSG.PLAYER_JOIN and not self.playerId then
                self.playerId = msg.id
                print("Our player ID: " .. self.playerId)
            else
                -- Convert protocol types to game types
                if msg.type == Protocol.MSG.PLAYER_JOIN then
                    msg.type = "player_joined"
                elseif msg.type == Protocol.MSG.PLAYER_MOVE then
                    msg.type = "player_moved"
                elseif msg.type == Protocol.MSG.PLAYER_LEAVE then
                    msg.type = "player_left"
                elseif msg.type == Protocol.MSG.PET_MOVE then
                    msg.type = "pet_moved"
                end
                table.insert(messages, msg)
            end
            
        elseif event.type == "disconnect" then
            print("Disconnected from server")
            self.connected = false
            self.server = nil
            self.playerId = nil
        end
        
        event = self.host:service(0)
    end
    
    return messages
end

return Client
