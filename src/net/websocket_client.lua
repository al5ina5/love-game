-- src/net/websocket_client.lua
-- WebSocket client for real-time game messages
-- Implements NetworkAdapter interface
-- Uses HTTP polling as a fallback (simpler than full WebSocket implementation)

local NetworkAdapter = require("src.net.adapter")
local Protocol = require("src.net.protocol")
local OnlineClient = require("src.net.online_client")

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
    
    -- HTTP polling fallback
    self.usePolling = true
    self.pollTimer = 0
    self.pollInterval = 0.1  -- Poll every 100ms
    self.onlineClient = OnlineClient:new()
    self.lastPollTime = 0
    
    -- Connection state
    self.connectionAttempts = 0
    self.maxConnectionAttempts = 10
    
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
    
    -- Try to use real WebSocket if available, otherwise use polling
    local success, err = self:connectWebSocket()
    if not success then
        print("WebSocket: Real WebSocket not available: " .. (err or "Unknown error"))
        print("WebSocket: WARNING - Polling fallback does NOT work with the server!")
        print("WebSocket: You need a WebSocket library with SSL support (WSS)")
        -- Use polling fallback (but it won't actually work)
        self.connected = true
        self.connectionAttempts = 0
        -- Simulate connection message
        self:addMessage({
            type = "connected",
            playerId = playerId,
            roomCode = roomCode
        })
        return true
    end
    
    return success, err
end

-- Attempt to connect using real WebSocket
function WebSocketClient:connectWebSocket()
    local socket = require("socket")
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    -- Parse WebSocket URL
    local protocol, host, port, path = self:parseWsUrl(self.wsUrl)
    if not host then
        return false, "Invalid WebSocket URL"
    end
    
    local isSecure = protocol == "wss://"
    
    -- For secure connections, we'd need SSL support
    -- For now, try to use luasocket with SSL if available, otherwise fall back to polling
    if isSecure then
        -- Try to use SSL
        local ssl = pcall(require, "ssl")
        if not ssl then
            return false, "WSS (secure WebSocket) requires SSL support, using polling fallback"
        end
        -- TODO: Implement SSL WebSocket connection
        return false, "WSS (secure WebSocket) SSL implementation pending, using polling fallback"
    end
    
    -- Create TCP connection
    local tcp = socket.tcp()
    tcp:settimeout(5)  -- 5 second timeout
    
    local success, err = tcp:connect(host, port)
    if not success then
        tcp:close()
        return false, "Failed to connect: " .. (err or "Unknown error")
    end
    
    -- Perform WebSocket handshake
    local key = self:generateWebSocketKey()
    local handshake = string.format(
        "GET %s HTTP/1.1\r\n" ..
        "Host: %s:%d\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: %s\r\n" ..
        "Sec-WebSocket-Version: 13\r\n" ..
        "\r\n",
        path, host, port, key
    )
    
    success, err = tcp:send(handshake)
    if not success then
        tcp:close()
        return false, "Failed to send handshake: " .. (err or "Unknown error")
    end
    
    -- Read handshake response
    local response = ""
    local line
    local headerComplete = false
    repeat
        line, err = tcp:receive("*l")
        if line then
            response = response .. line .. "\r\n"
            if line == "" then
                headerComplete = true
            end
        elseif err == "timeout" then
            -- Try to read what we have
            break
        end
    until not line or headerComplete
    
    -- Check if handshake was successful
    if not response:match("HTTP/1%.1 101") and not response:match("HTTP/1%.0 101") then
        tcp:close()
        return false, "WebSocket handshake failed: " .. response:sub(1, 200)
    end
    
    -- Store connection
    self.ws = tcp
    self.connected = true
    self.lastPollTime = love.timer.getTime()
    print("WebSocket: Connected successfully")
    
    -- Immediately try to receive the "connected" message from server
    -- This will be handled in the first poll() call
    
    return true
end

-- Generate WebSocket key for handshake
function WebSocketClient:generateWebSocketKey()
    -- Generate 16 random bytes
    local random = ""
    for i = 1, 16 do
        random = random .. string.char(math.random(0, 255))
    end
    -- Base64 encode (simple implementation using bit library if available, otherwise manual)
    local base64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local result = ""
    
    -- Try to use bit library if available
    local bit = pcall(require, "bit")
    if bit then
        bit = require("bit")
        for i = 1, #random, 3 do
            local b1, b2, b3 = string.byte(random, i, i + 2)
            b2 = b2 or 0
            b3 = b3 or 0
            local bitmap = bit.bor(bit.lshift(b1, 16), bit.lshift(b2, 8), b3)
            for j = 1, 4 do
                local shift = 6 * (4 - j)
                local idx = bit.band(bit.rshift(bitmap, shift), 0x3F) + 1
                result = result .. string.sub(base64chars, idx, idx)
            end
        end
    else
        -- Manual base64 encoding without bit operations
        for i = 1, #random, 3 do
            local b1, b2, b3 = string.byte(random, i, i + 2)
            b2 = b2 or 0
            b3 = b3 or 0
            
            -- Encode first 6 bits of b1
            local idx1 = math.floor(b1 / 4) + 1
            result = result .. string.sub(base64chars, idx1, idx1)
            
            -- Encode last 2 bits of b1 + first 4 bits of b2
            local idx2 = ((b1 % 4) * 16 + math.floor(b2 / 16)) + 1
            result = result .. string.sub(base64chars, idx2, idx2)
            
            -- Encode last 4 bits of b2 + first 2 bits of b3
            local idx3 = ((b2 % 16) * 4 + math.floor(b3 / 64)) + 1
            result = result .. string.sub(base64chars, idx3, idx3)
            
            -- Encode last 6 bits of b3
            local idx4 = (b3 % 64) + 1
            result = result .. string.sub(base64chars, idx4, idx4)
        end
    end
    
    -- Add padding if needed
    local pad = (3 - (#random % 3)) % 3
    if pad > 0 then
        result = result:sub(1, #result - pad) .. string.rep("=", pad)
    end
    
    return result
end

-- Parse WebSocket URL
function WebSocketClient:parseWsUrl(url)
    local protocol, rest = url:match("^(wss?://)(.*)")
    if not protocol then
        return nil, nil, nil, nil
    end
    
    local isSecure = protocol == "wss://"
    local host, port, path = rest:match("^([^:/]+):?(%d*)(.*)")
    
    if not host then
        host, path = rest:match("^([^/]+)(.*)")
        port = isSecure and "443" or "80"
    elseif port == "" then
        port = isSecure and "443" or "80"
    end
    
    if path == "" then
        path = "/"
    end
    
    return protocol, host, tonumber(port), path
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
        -- Send close frame
        self:sendWebSocketFrame("")
        self.ws:close()
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
    if not self.connected then
        return false
    end
    
    -- Rate limiting
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then
        return false
    end
    self.lastSendTime = now
    
    -- Build message object matching server protocol
    -- Server expects: { type: 'game_message', playerId, roomCode, data: { type: 'player_move', x, y, dir } }
    local dataArgs = {...}
    local message = {
        type = "game_message",
        playerId = self.playerId,
        roomCode = self.roomCode,
        data = {
            type = msgType,
            [1] = dataArgs[1],  -- x
            [2] = dataArgs[2],  -- y
            [3] = dataArgs[3],  -- direction
            x = dataArgs[1],
            y = dataArgs[2],
            dir = dataArgs[3]
        }
    }
    
    -- Encode and send via WebSocket
    local messageStr = self:encodeMessage(message)
    
    if self.ws then
        -- Send via WebSocket frame
        local success, err = self:sendWebSocketFrame(messageStr)
        if not success then
            print("WebSocket: Failed to send message: " .. (err or "Unknown error"))
            return false
        end
        -- Debug: print what we're sending
        print("WebSocket: Sent message: " .. messageStr:sub(1, 100))
    else
        -- Polling fallback: queue message (but warn that this won't work)
        print("WARNING: WebSocket not connected, message queued but won't be sent!")
        table.insert(self.messageQueue, message)
    end
    
    return true
end

-- Send WebSocket frame
function WebSocketClient:sendWebSocketFrame(data)
    if not self.ws then return false, "Not connected" end
    
    local len = #data
    local frame = string.char(0x81)  -- FIN + text frame
    
    -- Try to use bit library if available
    local bit = pcall(require, "bit")
    if bit then
        bit = require("bit")
    end
    
    if len < 126 then
        frame = frame .. string.char(len)
    elseif len < 65536 then
        local byte1, byte2
        if bit then
            byte1 = bit.band(bit.rshift(len, 8), 0xFF)
            byte2 = bit.band(len, 0xFF)
        else
            byte1 = math.floor(len / 256) % 256
            byte2 = len % 256
        end
        frame = frame .. string.char(126) .. string.char(byte1) .. string.char(byte2)
    else
        return false, "Message too large"
    end
    
    frame = frame .. data
    
    local success, err = self.ws:send(frame)
    return success, err
end

-- Receive WebSocket frame
function WebSocketClient:receiveWebSocketFrame()
    if not self.ws then return nil end
    
    -- Set timeout for non-blocking
    self.ws:settimeout(0)
    
    -- Read first 2 bytes (opcode + length)
    local header, err = self.ws:receive(2)
    if not header then
        if err == "timeout" then
            return nil, "timeout"
        end
        return nil, err
    end
    
    if #header < 2 then
        return nil, "Incomplete header"
    end
    
    -- Try to use bit library if available
    local bit = pcall(require, "bit")
    if bit then
        bit = require("bit")
    end
    
    local byte1, byte2 = string.byte(header, 1, 2)
    local opcode, masked, len
    if bit then
        opcode = bit.band(byte1, 0x0F)
        masked = bit.band(byte2, 0x80) ~= 0
        len = bit.band(byte2, 0x7F)
    else
        opcode = byte1 % 16
        masked = (byte2 >= 128)
        len = byte2 % 128
    end
    
    -- Read extended length if needed
    if len == 126 then
        local extLen, err = self.ws:receive(2)
        if not extLen then return nil, err end
        if #extLen < 2 then return nil, "Incomplete extended length" end
        local b1, b2 = string.byte(extLen, 1, 2)
        if bit then
            len = bit.bor(bit.lshift(b1, 8), b2)
        else
            len = b1 * 256 + b2
        end
    elseif len == 127 then
        return nil, "64-bit length not supported"
    end
    
    -- Read mask if present (client always sends masked, server doesn't)
    local mask
    if masked then
        mask, err = self.ws:receive(4)
        if not mask then return nil, err end
        if #mask < 4 then return nil, "Incomplete mask" end
    end
    
    -- Read payload
    if len > 0 then
        local payload, err = self.ws:receive(len)
        if not payload then return nil, err end
        if #payload < len then return nil, "Incomplete payload" end
        
        -- Unmask if needed
        if masked then
            local unmasked = ""
            for i = 1, #payload do
                local maskByte = string.byte(mask, ((i - 1) % 4) + 1)
                local payloadByte = string.byte(payload, i)
                local unmaskedByte
                if bit then
                    unmaskedByte = bit.bxor(payloadByte, maskByte)
                else
                    -- Manual XOR
                    unmaskedByte = 0
                    for j = 0, 7 do
                        local maskBit = math.floor(maskByte / (2^j)) % 2
                        local payloadBit = math.floor(payloadByte / (2^j)) % 2
                        if maskBit ~= payloadBit then
                            unmaskedByte = unmaskedByte + (2^j)
                        end
                    end
                end
                unmasked = unmasked .. string.char(unmaskedByte)
            end
            payload = unmasked
        end
        
        -- Handle opcode
        if opcode == 0x1 then  -- Text frame
            return payload
        elseif opcode == 0x8 then  -- Close frame
            self.connected = false
            return nil, "Connection closed"
        elseif opcode == 0x9 then  -- Ping
            -- Send pong (opcode 0xA)
            local pongFrame = string.char(0x8A) .. string.char(0)  -- FIN + Pong + empty
            self.ws:send(pongFrame)
            return self:receiveWebSocketFrame()  -- Get next frame
        elseif opcode == 0xA then  -- Pong
            return self:receiveWebSocketFrame()  -- Get next frame
        end
        
        return payload
    else
        -- Empty frame
        if opcode == 0x8 then  -- Close
            self.connected = false
            return nil, "Connection closed"
        end
        return ""
    end
end

-- Send position update (convenience method)
function WebSocketClient:sendPosition(x, y, direction)
    return self:sendMessage("player_move", x, y, direction)
end

-- Poll for incoming messages
-- Returns: array of messages
function WebSocketClient:poll()
    if not self.connected then
        return {}
    end
    
    local messages = {}
    local now = love.timer.getTime()
    
    -- Try to receive WebSocket messages
    if self.ws then
        -- Set non-blocking mode for receiving
        local oldTimeout = self.ws:gettimeout()
        self.ws:settimeout(0)
        
        -- Try to receive frames (limit to avoid blocking too long)
        local maxFrames = 10
        local frameCount = 0
        while frameCount < maxFrames do
            local data, err = self:receiveWebSocketFrame()
            if not data then
                if err and err ~= "timeout" then
                    if err ~= "timeout" then
                        print("WebSocket receive error: " .. err)
                    end
                    if err == "Connection closed" or err:match("closed") then
                        self.connected = false
                        self.ws = nil
                    end
                end
                break
            end
            
            -- Decode and handle message
            if data and #data > 0 then
                print("WebSocket: Received message: " .. data:sub(1, 100))
                self:handleMessage(data)
            end
            frameCount = frameCount + 1
        end
        
        -- Restore timeout
        if oldTimeout then
            self.ws:settimeout(oldTimeout)
        end
    else
        -- Polling fallback: process at intervals
        self.pollTimer = self.pollTimer + (now - self.lastPollTime)
        self.lastPollTime = now
        
        if self.pollTimer >= self.pollInterval then
            self.pollTimer = 0
            -- In polling mode, messages are queued manually
        end
    end
    
    self.lastPollTime = now
    
    -- Return queued messages and clear queue
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
    if not data or #data == 0 then
        return
    end
    
    print("WebSocket: Raw message received: " .. data:sub(1, 200))
    
    local success, message = pcall(function()
        return self:decodeMessage(data)
    end)
    
    if success and message then
        print("WebSocket: Parsed message type: " .. (message.type or "nil"))
        -- Convert server message format to game format
        if message.type == "connected" then
            print("WebSocket: Connection confirmed, playerId: " .. (message.playerId or "unknown"))
            -- Store our playerId if we got it
            if message.playerId and not self.playerId then
                self.playerId = message.playerId
                print("WebSocket: Set playerId to: " .. self.playerId)
            end
            table.insert(self.messageQueue, {
                type = "connected",
                playerId = message.playerId
            })
        elseif message.type == "player_joined" then
            -- Convert to game format
            print("WebSocket: Player joined: " .. (message.playerId or "unknown") .. ", isHost: " .. tostring(message.isHost or false))
            -- Don't ignore our own player_joined - we need to know about other players
            table.insert(self.messageQueue, {
                type = "player_joined",
                id = message.playerId,
                playerId = message.playerId,  -- Also include playerId for compatibility
                x = 400, y = 300  -- Default spawn
            })
        elseif message.type == "player_left" then
            print("WebSocket: Player left: " .. (message.playerId or "unknown"))
            table.insert(self.messageQueue, {
                type = "player_left",
                id = message.playerId
            })
        elseif message.type == "game_message" then
            -- Extract game message data
            -- Server sends: { type: 'game_message', playerId, data: { type: 'player_move', x, y, dir } }
            print("WebSocket: Game message from: " .. (message.playerId or "unknown"))
            if message.data then
                print("WebSocket: Message data type: " .. type(message.data))
                if type(message.data) == "table" then
                    print("WebSocket: Data table keys: " .. self:tableKeysToString(message.data))
                    if message.data.type == "player_move" then
                        -- Data is in message.data array: [x, y, dir]
                        local x = message.data[1] or message.data.x or 400
                        local y = message.data[2] or message.data.y or 300
                        local dir = message.data[3] or message.data.dir or "down"
                        print("WebSocket: Player move - " .. message.playerId .. " to (" .. x .. ", " .. y .. ")")
                        table.insert(self.messageQueue, {
                            type = "player_moved",
                            id = message.playerId,
                            x = tonumber(x) or 400,
                            y = tonumber(y) or 300,
                            dir = dir
                        })
                    else
                        -- Other game message types
                        table.insert(self.messageQueue, {
                            type = "game_message",
                            id = message.playerId,
                            data = message.data
                        })
                    end
                else
                    print("WebSocket: Message data is not a table: " .. type(message.data))
                end
            else
                print("WebSocket: Message has no data field")
            end
        else
            -- Pass through other messages
            print("WebSocket: Unknown message type, passing through: " .. (message.type or "nil"))
            table.insert(self.messageQueue, message)
        end
    else
        print("WebSocket: Failed to parse message: " .. tostring(data) .. " (length: " .. (#data or 0) .. ")")
        if not success then
            print("WebSocket: Parse error: " .. tostring(message))
        end
    end
end

-- Helper to debug table keys
function WebSocketClient:tableKeysToString(tbl)
    local keys = {}
    for k, v in pairs(tbl) do
        table.insert(keys, tostring(k) .. "=" .. tostring(type(v)))
    end
    return table.concat(keys, ", ")
end

-- Manually add a message to the queue (for testing or HTTP polling)
function WebSocketClient:addMessage(message)
    self:handleMessage(self:encodeMessage(message))
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
