-- src/net/websocket_client.lua
-- WebSocket client for real-time game messages
-- Implements NetworkAdapter interface
-- 
-- NOTE: Requires a WebSocket library. Options:
-- - love2d-lua-websocket (pure Lua): https://github.com/flaribbit/love2d-lua-websocket
-- - love-ws (C++ native): https://github.com/holywyvern/love-ws
-- 
-- For now, this is a stub that can be adapted to your chosen library

local NetworkAdapter = require("src.net.adapter")
local Protocol = require("src.net.protocol")

local WebSocketClient = {}
WebSocketClient.__index = WebSocketClient

function WebSocketClient:new()
    local self = setmetatable({}, WebSocketClient)
    
    self.ws = nil
    self.connected = false
    self.roomCode = nil
    self.playerId = nil
    self.isHost = false
    self.wsUrl = nil
    
    -- Message queue for received messages
    self.messageQueue = {}
    
    -- Rate limiting
    self.lastSendTime = 0
    self.sendRate = 1/20  -- 20 messages per second
    
    return self
end

-- Connect to WebSocket server
-- roomCode: string (6-digit room code)
-- playerId: string (player ID)
-- isHost: boolean (true if this is the host player)
-- wsUrl: string (full WebSocket URL from matchmaker)
-- Returns: success (bool), error (string or nil)
function WebSocketClient:connect(roomCode, playerId, isHost, wsUrl)
    if self.connected then
        self:disconnect()
    end
    
    self.roomCode = roomCode
    self.playerId = playerId
    self.isHost = isHost
    self.wsUrl = wsUrl or (self:buildWsUrl(roomCode, playerId, isHost))
    
    print("WebSocket: Connecting to " .. self.wsUrl)
    
    -- TODO: Implement actual WebSocket connection using your chosen library
    -- Example with love2d-lua-websocket:
    --[[
    local websocket = require("websocket")
    self.ws = websocket.new(self.wsUrl)
    self.ws:on("open", function()
        self.connected = true
        print("WebSocket: Connected")
    end)
    self.ws:on("message", function(data)
        self:handleMessage(data)
    end)
    self.ws:on("close", function()
        self.connected = false
        print("WebSocket: Disconnected")
    end)
    self.ws:on("error", function(err)
        print("WebSocket: Error - " .. tostring(err))
        self.connected = false
    end)
    self.ws:connect()
    --]]
    
    -- For now, return false to indicate WebSocket library is needed
    print("WARNING: WebSocket library not implemented. Please add a WebSocket library.")
    return false, "WebSocket library not implemented"
end

-- Build WebSocket URL from components
function WebSocketClient:buildWsUrl(roomCode, playerId, isHost)
    -- This should match the format from your Railway server
    local baseUrl = "wss://love-game-production.up.railway.app"
    return baseUrl .. "/ws?room=" .. roomCode .. "&playerId=" .. playerId .. "&isHost=" .. tostring(isHost)
end

-- Disconnect from WebSocket server
function WebSocketClient:disconnect()
    if self.ws then
        -- TODO: Close WebSocket connection
        -- self.ws:close()
        self.ws = nil
    end
    
    self.connected = false
    self.roomCode = nil
    self.playerId = nil
    self.isHost = false
    self.messageQueue = {}
    print("WebSocket: Disconnected")
end

-- Send a game message
-- msgType: string (e.g., "input", "game_message")
-- ...: message data
function WebSocketClient:sendMessage(msgType, ...)
    if not self.connected or not self.ws then
        return false
    end
    
    -- Rate limiting
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then
        return false
    end
    self.lastSendTime = now
    
    -- Build message object
    local message = {
        type = msgType,
        playerId = self.playerId,
        roomCode = self.roomCode,
        data = {...}
    }
    
    -- Encode as JSON (or use pipe-delimited format for compatibility)
    local messageStr = self:encodeMessage(message)
    
    -- TODO: Send via WebSocket
    -- self.ws:send(messageStr)
    
    return true
end

-- Poll for incoming messages
-- Returns: array of messages
function WebSocketClient:poll()
    -- TODO: Update WebSocket connection (call tick/update method)
    -- if self.ws and self.ws.tick then
    --     self.ws:tick()
    -- end
    
    -- Return queued messages and clear queue
    local messages = {}
    for i, msg in ipairs(self.messageQueue) do
        table.insert(messages, msg)
    end
    self.messageQueue = {}
    
    return messages
end

-- Check if connected
function WebSocketClient:isConnected()
    return self.connected
end

-- Get connection info
function WebSocketClient:getConnectionInfo()
    return {
        connected = self.connected,
        roomCode = self.roomCode,
        playerId = self.playerId,
        isHost = self.isHost,
        wsUrl = self.wsUrl
    }
end

-- Handle incoming WebSocket message
function WebSocketClient:handleMessage(data)
    local success, message = pcall(function()
        return self:decodeMessage(data)
    end)
    
    if success and message then
        table.insert(self.messageQueue, message)
    else
        print("WebSocket: Failed to parse message: " .. tostring(data))
    end
end

-- Encode message to string (JSON or pipe-delimited)
function WebSocketClient:encodeMessage(message)
    -- Try JSON first (LOVE2D 11.0+)
    if love.data and love.data.encode then
        local success, json = pcall(function()
            return love.data.encode("string", "json", message)
        end)
        if success then return json end
    end
    
    -- Fallback: pipe-delimited format
    local parts = {message.type}
    if message.playerId then table.insert(parts, message.playerId) end
    if message.roomCode then table.insert(parts, message.roomCode) end
    for _, v in ipairs(message.data or {}) do
        table.insert(parts, tostring(v))
    end
    return table.concat(parts, "|")
end

-- Decode message from string
function WebSocketClient:decodeMessage(data)
    -- Try JSON first
    if love.data and love.data.decode then
        local success, json = pcall(function()
            return love.data.decode("string", "json", data)
        end)
        if success then return json end
    end
    
    -- Fallback: pipe-delimited format
    local parts = {}
    for part in string.gmatch(data, "[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts < 1 then return nil end
    
    return {
        type = parts[1],
        playerId = parts[2],
        roomCode = parts[3],
        data = {select(4, unpack(parts))}
    }
end

return WebSocketClient
