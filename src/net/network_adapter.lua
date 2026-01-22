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

-- Send position update (for walking simulator)
function NetworkAdapter:sendPosition(x, y, direction)
    if not self:isConnected() then return false end
    
    if self.type == NetworkAdapter.TYPE.LAN then
        if self.server then
            self.server:sendPosition(x, y, direction)
        elseif self.client then
            self.client:sendPosition(x, y, direction)
        end
    else
        if self.client then
            self.client:sendPosition(x, y, direction)
        end
    end
    return true
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
        if self.client then
            local onlineMsgs = self.client:poll()
            for _, msg in ipairs(onlineMsgs) do
                table.insert(messages, msg)
            end
        end
    end
    
    return messages
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

return NetworkAdapter
