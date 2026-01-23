-- src/net/relay_client.lua
-- Real-time online multiplayer client using persistent TCP sockets via Relay
-- Much faster than polling HTTP/REST

local socket = require("socket")
local json = require("src.lib.dkjson")
local Protocol = require("src.net.protocol")
local Constants = require("src.constants")

local RelayClient = {}
RelayClient.__index = RelayClient

function RelayClient:new()
    local self = setmetatable({}, RelayClient)
    self.tcp = nil
    self.roomCode = nil
    self.connected = false
    self.playerId = nil
    self.paired = false -- True when opponent is also connected to relay
    self.buffer = "" -- For handling partial TCP packets

    -- Adaptive send rate limiting (Miyoo-optimized for relay client)
    self.lastSendTime = 0
    self.baseSendRate = Constants.MIYOO_BASE_SEND_RATE  -- Miyoo-tuned base rate
    self.minSendRate = Constants.MIYOO_MIN_SEND_RATE   -- Min rate: conservative for poor connections
    self.maxSendRate = Constants.MIYOO_MAX_SEND_RATE   -- Max rate: for excellent connections
    self.sendRate = self.baseSendRate

    -- Connection quality tracking
    self.pingHistory = {}
    self.maxPingSamples = 10
    self.averagePing = 100  -- Initial estimate in ms
    self.connectionQuality = 1.0  -- 0.0 to 1.0 (higher is better)
    self.lastPingTime = 0
    self.pendingPing = nil  -- {timestamp, sent_time}
    self.lastPacketSentTime = 0  -- Track when we last sent any packet

    return self
end

function RelayClient:connect(roomCode, playerId)
    self.roomCode = roomCode:upper()
    self.playerId = playerId -- "host" or "client"
    
    
    -- Resolve hostname to IP to avoid some luasocket issues with DNS
    local ip = socket.dns.toip(Constants.RELAY_HOST)
    if not ip then
        print("RelayClient: Could not resolve hostname: " .. Constants.RELAY_HOST)
        return false
    end

    local tcp, err = socket.tcp()
    if not tcp then
        print("RelayClient: Failed to create socket: " .. tostring(err))
        return false
    end
    
    -- Use non-blocking connect pattern for better reliability across OSs
    tcp:settimeout(0) 
    local success, connectErr = tcp:connect(ip, Constants.RELAY_PORT)
    
    -- "timeout" or "Operation already in progress" means it's connecting in background
    if not success and connectErr ~= "timeout" and connectErr ~= "Operation already in progress" then
        print("RelayClient: Connection failed immediately: " .. tostring(connectErr))
        return false
    end
    
    -- Wait for the socket to become writable (indicates connection success)
    local retries = 0
    local connected = false
    while retries < 5 and not connected do
        local _, writable, selectErr = socket.select(nil, {tcp}, 1) -- 1 second per check
        if writable and #writable > 0 then
            connected = true
        else
            retries = retries + 1
        end
    end
    
    if not connected then
        print("RelayClient: Connection timed out or failed")
        tcp:close()
        return false
    end
    
    -- Connection successful
    tcp:setoption("tcp-nodelay", true)
    tcp:settimeout(0)  -- Non-blocking for polling
    self.tcp = tcp
    self.connected = true
    
    -- Send handshake immediately
    local success, err = self:send("JOIN:" .. self.roomCode)
    if not success then
        print("RelayClient: Failed to send JOIN message: " .. tostring(err))
        tcp:close()
        self.connected = false
        return false
    end
    
    return true
end

function RelayClient:poll()
    if not self.connected or not self.tcp then return {} end

    local messages = {}

    -- Send ping periodically (both TCP and HTTP for comprehensive measurement)
    local now = love.timer.getTime()
    if now - self.lastPingTime > 1.0 and not self.pendingPing then  -- Ping every 1 second
        -- Send TCP ping
        local timestamp = now
        local encoded = Protocol.encode(Protocol.MSG.PING, timestamp)
        if self:send(encoded) then
            self.pendingPing = {timestamp = timestamp, sent_time = now}
            self.lastPingTime = now
        end

        -- Send HTTP ping request (fire and forget, result will be measured via TCP pong)
        self:sendHTTPPing()
    end
    
    -- Use non-blocking receive with timeout
    self.tcp:settimeout(0)
    local data, err, partial = self.tcp:receive("*a") -- Receive all available data
    
    if err == "closed" then
        print("RelayClient: Connection closed by relay")
        self.connected = false
        -- Generate a player_left message so the game handles it properly
        table.insert(messages, { type = "player_left", id = "opponent", disconnectReason = "connection_closed" })
        return messages
    elseif err and err ~= "timeout" then
        print("RelayClient: Receive error: " .. tostring(err))
        if err == "closed" or err:match("closed") then
            self.connected = false
            table.insert(messages, { type = "player_left", id = "opponent", disconnectReason = "connection_closed" })
            return messages
        end
    end
    
    local combinedData = self.buffer .. (data or partial or "")
    
    -- Find the last complete line (ending with newline)
    local lastNewline = combinedData:match(".*\n()")
    if lastNewline then
        -- We have at least one complete line
        self.buffer = combinedData:sub(lastNewline)  -- Keep incomplete part in buffer
        combinedData = combinedData:sub(1, lastNewline - 1)  -- Process complete lines
    else
        -- No complete line yet, keep everything in buffer
        self.buffer = combinedData
        return messages  -- No messages to process yet
    end
    
    -- Split by newline and process messages
    for line in combinedData:gmatch("(.-)\n") do
        -- Estimate ping based on packet round trip when we receive any message
        if self.lastPacketSentTime > 0 then
            local now = love.timer.getTime()
            local packetRTT = (now - self.lastPacketSentTime) * 1000
            if packetRTT > 0 and packetRTT < 500 then  -- Reasonable ping range
                self:updatePingMeasurement(packetRTT)
            end
        end

        if line == "PAIRED" then
            print("RelayClient: Opponent connected to relay!")
            self.paired = true
            -- When paired, connection_manager will send PLAYER_JOIN with actual position
            -- Client already sent its PLAYER_JOIN in connection_manager
        elseif line == "OPPONENT_LEFT" then
            print("RelayClient: Opponent left the room!")
            self.paired = false
            -- Generate a player_left message so the game handles the disconnection
            table.insert(messages, { type = "player_left", id = "opponent", disconnectReason = "opponent_left" })
        elseif line:match("^ERROR:") then
            local errorMsg = line:sub(7)
            print("RelayClient: Server error: " .. errorMsg)
            -- Could generate an error message for the game to handle
        elseif line ~= "" then
            -- Debug logging removed to reduce spam (state/cycle messages are very frequent)
            local msg = Protocol.decode(line)
            if msg then
                -- Skip logging for frequent message types (state snapshots and cycle updates)
                local msgType = msg.type or ""
                if msgType ~= "state" and msgType ~= "cycle" and msgType ~= Protocol.MSG.CYCLE_TIME then
                    print("RelayClient: Decoded message - type: " .. msgType .. ", id: " .. (msg.id or "nil"))
                end
                -- Handle server-assigned player ID from join message
                if msg.type == Protocol.MSG.PLAYER_JOIN and not self.receivedPlayerId then
                    -- First join message is our own ID assignment from server
                    self.playerId = msg.id
                    self.receivedPlayerId = true
                    print("RelayClient: Received server-assigned player ID: " .. self.playerId)
                    -- Don't process this as a player_joined event, it's just our ID assignment
                    -- The state snapshot will have all players including us
                elseif msg.id == self.playerId then
                    print("RelayClient: Ignoring our own message: " .. (msg.type or "unknown") .. " from " .. (msg.id or "?"))
                else
                    -- Translate protocol types to match LAN behavior
                    if msg.type == Protocol.MSG.PLAYER_JOIN then
                        msg.type = "player_joined"
                    elseif msg.type == Protocol.MSG.PLAYER_LEAVE then
                        msg.type = "player_left"
                    elseif msg.type == Protocol.MSG.PLAYER_MOVE then
                        msg.type = "player_moved"
                    elseif msg.type == Protocol.MSG.PET_MOVE then
                        msg.type = "pet_moved"
                    elseif msg.type == Protocol.MSG.STATE_SNAPSHOT or msg.type == "state" then
                        msg.type = "state_snapshot"
                        -- State snapshots are very frequent, logging removed to reduce spam
                    elseif msg.type == Protocol.MSG.EVENT_BOON_GRANTED then
                        msg.type = "boon_granted"
                    elseif msg.type == Protocol.MSG.EVENT_PLAYER_DIED then
                        msg.type = "player_died"
                    elseif msg.type == Protocol.MSG.EVENT_BOON_STOLEN then
                        msg.type = "boon_stolen"
                    elseif msg.type == Protocol.MSG.CYCLE_TIME then
                        msg.type = "cycle"
                        -- Cycle updates are very frequent, logging removed to reduce spam
                    elseif msg.type == Protocol.MSG.EXTRACTION then
                        msg.type = "extract"
                    elseif msg.type == Protocol.MSG.PING then
                        -- Respond to ping with pong
                        local pongData = Protocol.encode(Protocol.MSG.PONG, msg.timestamp)
                        self:send(pongData)
                    elseif msg.type == Protocol.MSG.PONG then
                        -- Calculate ping if we have a pending ping
                        if self.pendingPing and self.pendingPing.timestamp == msg.timestamp then
                            local now = love.timer.getTime()
                            local pingMs = (now - self.pendingPing.sent_time) * 1000  -- Convert to milliseconds
                            self:updatePingMeasurement(pingMs)
                            self.pendingPing = nil
                        end
                    elseif line:match("^npcs%|") then
                        -- Parse NPC data: npcs|count|x|y|spritePath|name|dialogueJSON|...
                        msg = {type = "npcs", npcs = {}}
                        local parts = {}
                        for part in line:gmatch("([^|]+)") do
                            table.insert(parts, part)
                        end
                        local count = tonumber(parts[2]) or 0
                        local idx = 3
                        for i = 1, count do
                            if idx + 4 <= #parts then
                                local npc = {
                                    x = tonumber(parts[idx]) or 0,
                                    y = tonumber(parts[idx + 1]) or 0,
                                    spritePath = parts[idx + 2],
                                    name = parts[idx + 3],
                                    dialogue = json.decode(parts[idx + 4]) or {}
                                }
                                table.insert(msg.npcs, npc)
                                idx = idx + 5
                            end
                        end
                    elseif line:match("^animals%|") then
                        -- Parse Animal data: animals|count|x|y|spritePath|name|speed|groupCenterX|groupCenterY|groupRadius|...
                        msg = {type = "animals", animals = {}}
                        local parts = {}
                        for part in line:gmatch("([^|]+)") do
                            table.insert(parts, part)
                        end
                        local count = tonumber(parts[2]) or 0
                        local idx = 3
                        for i = 1, count do
                            if idx + 7 <= #parts then
                                local animal = {
                                    x = tonumber(parts[idx]) or 0,
                                    y = tonumber(parts[idx + 1]) or 0,
                                    spritePath = parts[idx + 2],
                                    name = parts[idx + 3],
                                    speed = tonumber(parts[idx + 4]) or 30,
                                    groupCenterX = tonumber(parts[idx + 5]) or 0,
                                    groupCenterY = tonumber(parts[idx + 6]) or 0,
                                    groupRadius = tonumber(parts[idx + 7]) or 150
                                }
                                table.insert(msg.animals, animal)
                                idx = idx + 8
                            end
                        end
                    elseif msg.type == Protocol.MSG.INPUT_SHOOT or msg.type == Protocol.MSG.INPUT_INTERACT then
                        -- Ignore our own inputs echoed back
                    end
                    -- Only add non-input messages (inputs are handled server-side)
                    if msg.type ~= Protocol.MSG.INPUT_SHOOT and msg.type ~= Protocol.MSG.INPUT_INTERACT then
                        table.insert(messages, msg)
                    end
                end
            else
                print("RelayClient: Failed to decode message from line: " .. line:sub(1, 100))
            end
        end
    end
    
    return messages
end

function RelayClient:send(data)
    if not self.connected or not self.tcp then return false end
    -- Relay protocol expects one message per line
    local success, err = self.tcp:send(data .. "\n")
    if not success then
        print("RelayClient: Send failed: " .. tostring(err))
        if err == "closed" then self.connected = false end
    end
    return success
end

-- Compatible interface with ENet client
function RelayClient:sendPosition(x, y, direction, skin, sprinting)
    if not self.connected then
        print("RelayClient: sendPosition called but not connected!")
        return false
    end

    -- Rate limiting based on connection quality
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then
        return true  -- Not an error, just rate limited
    end
    self.lastSendTime = now
    self.lastPacketSentTime = now  -- Track for ping measurement

    -- Note: We still send position even if not paired yet (opponent may connect soon)
    -- This allows smooth movement from the start
    local encoded = Protocol.encode(Protocol.MSG.PLAYER_MOVE, self.playerId or "?", math.floor(x), math.floor(y), direction or "down")
    if skin then
        encoded = encoded .. "|" .. skin
    end
    if sprinting then
        encoded = encoded .. "|1"
    end
    -- Position update (logging removed to reduce spam)
    local success = self:send(encoded)
    if not success then
        print("RelayClient: Failed to send position update!")
    end
    return success
end

function RelayClient:sendPetPosition(playerId, x, y, monster)
    if not self.connected then return false end
    self.lastPacketSentTime = love.timer.getTime()
    local encoded = Protocol.encode(Protocol.MSG.PET_MOVE, playerId or self.playerId or "?", math.floor(x), math.floor(y))
    if monster then
        encoded = encoded .. "|" .. monster
    end
    return self:send(encoded)
end

function RelayClient:sendMessage(msg)
    self.lastPacketSentTime = love.timer.getTime()

    local encoded
    if msg.type == Protocol.MSG.PLAYER_MOVE then
        encoded = Protocol.encode(Protocol.MSG.PLAYER_MOVE, self.playerId or "?", msg.x or 0, msg.y or 0, msg.dir or "down")
    elseif msg.type == Protocol.MSG.PLAYER_JOIN then
        encoded = Protocol.encode(Protocol.MSG.PLAYER_JOIN, self.playerId or "?", msg.x or 400, msg.y or 300)
    elseif msg.type == Protocol.MSG.PLAYER_LEAVE then
        encoded = Protocol.encode(Protocol.MSG.PLAYER_LEAVE, self.playerId or "?")
    elseif msg.type == Protocol.MSG.INPUT_SHOOT or msg.type == Protocol.MSG.INPUT_INTERACT then
        -- Game input messages - send the encoded data directly
        if msg.data and type(msg.data) == "string" then
            encoded = msg.data
        else
            encoded = Protocol.encode(msg.type, self.playerId or "?", msg.angle or msg.data or "")
        end
        print("RelayClient: Sending game input: " .. (msg.type or "nil"))
    else
        encoded = Protocol.encode(msg.type, self.playerId or "?", msg.data or "")
    end
    return self:send(encoded)
end

function RelayClient:updatePingMeasurement(pingMs)
    if pingMs and pingMs > 0 then
        table.insert(self.pingHistory, pingMs)
        if #self.pingHistory > self.maxPingSamples then
            table.remove(self.pingHistory, 1)
        end

        -- Calculate average ping
        local sum = 0
        for _, p in ipairs(self.pingHistory) do
            sum = sum + p
        end
        self.averagePing = sum / #self.pingHistory

        -- Calculate connection quality (0.0 to 1.0)
        -- Good ping (< 50ms) = 1.0, Poor ping (> 200ms) = 0.0
        self.connectionQuality = math.max(0, math.min(1, 1 - (self.averagePing - 50) / 150))

    end
end

function RelayClient:sendHTTPPing()
    if not self.roomCode then return end

    -- Use HTTP ping endpoint for additional latency measurement
    local http = require("src.net.simple_http")
    local Constants = require("src.constants")

    -- Build ping URL
    local pingUrl = Constants.RELAY_HTTP .. "/ping"

    -- Send async HTTP request (fire and forget)
    http.request(pingUrl, "GET", nil, function(response)
        -- HTTP ping completed - this helps measure HTTP latency but we primarily use TCP
        -- The TCP ping-pong is more reliable for real-time gaming
    end, function(error)
        -- HTTP ping failed - this is expected if server is down, we rely on TCP
    end)
end

function RelayClient:getConnectionQuality()
    return self.connectionQuality, self.averagePing
end

-- Force a ping test (useful for debugging)
function RelayClient:testPing()
    if not self.connected then return end

    local now = love.timer.getTime()
    local timestamp = now
    local encoded = Protocol.encode(Protocol.MSG.PING, timestamp)

    if self:send(encoded) then
        self.pendingPing = {timestamp = timestamp, sent_time = now}
        print("RelayClient: Forced ping test sent")
    end
end

function RelayClient:disconnect()
    if self.tcp then
        self.tcp:close()
        self.tcp = nil
    end
    self.connected = false
    self.roomCode = nil
    self.paired = false
    self.pendingPing = nil
    print("RelayClient: Disconnected")
end

-- Update connection quality based on ping measurements
function RelayClient:updateConnectionQuality(pingMs)
    if pingMs and pingMs > 0 then
        table.insert(self.pingHistory, pingMs)
        if #self.pingHistory > self.maxPingSamples then
            table.remove(self.pingHistory, 1)
        end

        -- Calculate average ping
        local sum = 0
        for _, p in ipairs(self.pingHistory) do
            sum = sum + p
        end
        self.averagePing = sum / #self.pingHistory

        -- Calculate connection quality (0.0 to 1.0)
        -- Good ping (< 50ms) = 1.0, Poor ping (> 200ms) = 0.0
        self.connectionQuality = math.max(0, math.min(1, 1 - (self.averagePing - 50) / 150))

        -- Adjust send rate based on connection quality
        -- Higher quality = higher send rate
        self.sendRate = self.minSendRate + (self.maxSendRate - self.minSendRate) * self.connectionQuality

        -- Debug logging (infrequent)
        if math.random() < 0.01 then
            print(string.format("RelayClient: Ping %.1fms, Quality %.2f, SendRate %.2fhz",
                self.averagePing, self.connectionQuality, 1/self.sendRate))
        end
    end
end

-- Get current connection quality for external monitoring
function RelayClient:getConnectionQuality()
    return self.connectionQuality, self.averagePing
end

return RelayClient
