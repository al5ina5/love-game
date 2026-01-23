-- src/net/network_adapter.lua
-- Unified network interface for both LAN (ENet) and Online (Relay)

local NetworkAdapter = {}
NetworkAdapter.__index = NetworkAdapter

NetworkAdapter.TYPE = {
    LAN = "lan",
    ONLINE = "online",
    RELAY = "relay"
}

function NetworkAdapter:new(type, client, server)
    local self = setmetatable({}, NetworkAdapter)
    self.type = type -- "lan", "online", or "relay"
    self.client = client
    self.server = server -- Only for LAN host
    return self
end

-- Create LAN adapter (ENet)
function NetworkAdapter:createLAN(client, server)
    return NetworkAdapter:new(NetworkAdapter.TYPE.LAN, client, server)
end

-- Create Online adapter (Legacy Ably)
function NetworkAdapter:createOnline(client)
    return NetworkAdapter:new(NetworkAdapter.TYPE.ONLINE, client, nil)
end

-- Create Relay adapter (Socket)
function NetworkAdapter:createRelay(client)
    return NetworkAdapter:new(NetworkAdapter.TYPE.RELAY, client, nil)
end

-- Check if this is a host
function NetworkAdapter:isHost()
    if self.type == NetworkAdapter.TYPE.LAN then
        return self.server ~= nil
    else
        return self.client and self.client.playerId == "host"
    end
end

-- Check if connected
function NetworkAdapter:isConnected()
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            return true -- Host is always "connected"
        else
            return self.client and self.client.connected
        end
    else
        return self.client and self.client.connected
    end
end

-- Check if server logic is available (for host)
function NetworkAdapter:hasServerLogic()
    return self.type == NetworkAdapter.TYPE.LAN and self.server and self.server.serverLogic ~= nil
end

-- Send position update (for walking simulator)
function NetworkAdapter:sendPosition(x, y, direction, skin, sprinting)
    if not self:isConnected() then 
        print("NetworkAdapter: sendPosition called but not connected (type: " .. (self.type or "nil") .. ")")
        return false 
    end
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            self.server:sendPosition(x, y, direction, skin, sprinting)
        elseif self.client then
            self.client:sendPosition(x, y, direction, skin, sprinting)
        end
    else
        if self.client then

            self.client:sendPosition(x, y, direction, skin, sprinting)
        else
            print("NetworkAdapter: sendPosition called but no client available (type: " .. self.type .. ")")
        end
    end
    return true
end

-- Send pet position update
function NetworkAdapter:sendPetPosition(playerId, x, y, monster)
    if not self:isConnected() then return false end
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            self.server:sendPetPosition(playerId, x, y, monster)
        elseif self.client then
            self.client:sendPetPosition(playerId, x, y, monster)
        end
    else
        if self.client then
            self.client:sendPetPosition(playerId, x, y, monster)
        end
    end
    return true
end

-- Send raw encoded message (type, ...)
-- Used by World for requesting chunks, sending roads/rocks etc.
function NetworkAdapter:send(msgType, ...)
    local Protocol = require("src.net.protocol")
    local encoded = Protocol.encode(msgType, ...)
    
    if not self:isConnected() then return false end
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            -- Host (ENet Server)
            -- Delegate to sendMessage which should handle raw data if implemented, 
            -- or we need to access server peer. 
            -- ENet Server generally uses broadcast if no peer specified.
            if self.server.broadcast then
                self.server:broadcast(encoded)
                return true
            elseif self.server.sendMessage then
                return self.server:sendMessage({ data = encoded })
            end
        elseif self.client then
            -- ENet Client
            return self.client:sendMessage({ data = encoded })
        end
    else
        -- Online/Relay
        if self.client then
            local success = false
            if self.client.send then
                -- RelayClient has direct send(data) method
                success = self.client:send(encoded)
            elseif self.client.sendMessage then
                success = self.client:sendMessage({ data = encoded })
            end
            
            -- If we are the host, also loop back locally so we handle our own requests
            if self:isHost() and self.localServer then
                -- The server:poll() will pick this up via its localMessages
                self.localServer:broadcast(encoded)
            end
            
            return success
        end
    end
    return false
end

-- Send generic message
function NetworkAdapter:sendMessage(msg)
    if not self:isConnected() then return false end
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            self.server:sendMessage(msg)
        elseif self.client then
            self.client:sendMessage(msg)
        end
    else
        if self.client then
            self.client:sendMessage(msg)
        end
    end
    return true
end

-- Send game input (shoot, interact)
function NetworkAdapter:sendGameInput(inputType, data)
    -- For host, we're always "connected" (server is local)
    if self.type == NetworkAdapter.TYPE.LAN and self.server then
        -- Host can always send inputs
    elseif not self:isConnected() then 
        print("NetworkAdapter:sendGameInput - Not connected! (type: " .. (self.type or "nil") .. ")")
        return false 
    end
    
    local Protocol = require("src.net.protocol")
    local playerId = self:getPlayerId()
    
    if inputType == "shoot" then
        local angle = data.angle or 0
        local encoded = Protocol.encode(Protocol.MSG.INPUT_SHOOT, playerId or "?", angle)
        
        if self.type == NetworkAdapter.TYPE.LAN then
            if self.client then
                return self.client:sendMessage({ type = Protocol.MSG.INPUT_SHOOT, data = encoded })
            elseif self.server then
                -- Host sends directly to server logic
                if self.server.serverLogic then
                    print("NetworkAdapter: Queuing shoot input for host")
                    print("  playerId: " .. (playerId or "host"))
                    print("  angle: " .. angle)
                    print("  serverLogic exists: " .. tostring(self.server.serverLogic ~= nil))
                    self.server.serverLogic:queueInput({
                        type = Protocol.MSG.INPUT_SHOOT,
                        id = playerId or "host",
                        angle = angle
                    })
                    print("NetworkAdapter: Input queued, queue size: " .. #self.server.serverLogic.inputQueue)
                    return true
                else
                    print("NetworkAdapter: ERROR - No serverLogic on server!")
                    print("  server exists: " .. tostring(self.server ~= nil))
                    print("  server.gameMode: " .. (self.server.gameMode or "nil"))
                end
            end
        else
            -- Online/Relay - for host, process locally AND send to relay
            if self.type == NetworkAdapter.TYPE.RELAY and self:isHost() then
                -- Host in relay mode needs local server logic
                -- Check if we have a local server with serverLogic
                if self.localServer and self.localServer.serverLogic then
                    print("NetworkAdapter: Queuing shoot input for relay host (local processing)")
                    self.localServer.serverLogic:queueInput({
                        type = Protocol.MSG.INPUT_SHOOT,
                        id = playerId or "host",
                        angle = angle
                    })
                    -- Also send to relay for other clients
                    if self.client then
                        self.client:sendMessage({ type = Protocol.MSG.INPUT_SHOOT, data = encoded })
                    end
                    return true
                else
                    print("NetworkAdapter: WARNING - Relay host has no local serverLogic!")
                end
            end
            -- Online/Relay client - send via client
            if self.client then
                return self.client:sendMessage({ type = Protocol.MSG.INPUT_SHOOT, data = encoded })
            end
        end
    elseif inputType == "interact" then
        local encoded = Protocol.encode(Protocol.MSG.INPUT_INTERACT, playerId or "?")
        
        if self.type == NetworkAdapter.TYPE.LAN then
            if self.client then
                return self.client:sendMessage({ type = Protocol.MSG.INPUT_INTERACT, data = encoded })
            elseif self.server then
                -- Host sends directly to server logic
                if self.server.serverLogic then
                    self.server.serverLogic:queueInput({
                        type = Protocol.MSG.INPUT_INTERACT,
                        id = playerId or "host"
                    })
                    return true
                end
            end
        else
            -- Online/Relay - send via client
            if self.client then
                return self.client:sendMessage({ type = Protocol.MSG.INPUT_INTERACT, data = encoded })
            end
        end
    end
    
    return false
end

-- Poll for messages
function NetworkAdapter:poll()
    local messages = {}
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            local serverMsgs = self.server:poll()
            for _, msg in ipairs(serverMsgs) do
                table.insert(messages, msg)
            end
        end
        if self.client then
            local clientMsgs = self.client:poll()
            for _, msg in ipairs(clientMsgs) do
                table.insert(messages, msg)
            end
        end
    else
        -- Online/Relay
        if self.client then
            local onlineMsgs = self.client:poll()
            for _, msg in ipairs(onlineMsgs) do
                table.insert(messages, msg)
            end
        end
        -- Also poll localServer for relay host
        if self.localServer then
            local serverMsgs = self.localServer:poll()
            for _, msg in ipairs(serverMsgs) do
                table.insert(messages, msg)
            end
        end
    end
    
    return messages
end

-- Update server simulation (for host)
function NetworkAdapter:update(dt)
    if self.type == NetworkAdapter.TYPE.LAN and self.server then
        self.server:update(dt)
    elseif self.type == NetworkAdapter.TYPE.RELAY and self.localServer then
        self.localServer:update(dt)
    end
end

-- Disconnect
function NetworkAdapter:disconnect()
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            self.server:disconnect()
        end
        if self.client then
            self.client:disconnect()
        end
    else
        if self.client then
            self.client:disconnect()
        end
    end
end

-- Get player ID
function NetworkAdapter:getPlayerId()
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            return self.server.playerId or "host"
        elseif self.client then
            return self.client.playerId
        end
    else
        if self.client then
            return self.client.playerId
        end
    end
    return nil
end

-- Send heartbeat (online only)
function NetworkAdapter:heartbeat()
    if (self.type == NetworkAdapter.TYPE.ONLINE or self.type == NetworkAdapter.TYPE.RELAY) and self.client then
        if self.client.heartbeat then
            return self.client:heartbeat()
        end
    end
    return true -- LAN doesn't need heartbeat
end

-- Get room code (online only)
function NetworkAdapter:getRoomCode()
    if (self.type == NetworkAdapter.TYPE.ONLINE or self.type == NetworkAdapter.TYPE.RELAY) and self.client then
        return self.client.roomCode
    end
    return nil
end

-- Get connection quality and ping
function NetworkAdapter:getConnectionQuality()
    if self.client and self.client.getConnectionQuality then
        return self.client:getConnectionQuality()
    end
    return 1.0, 0  -- Default: perfect quality, 0 ping
end

return NetworkAdapter
