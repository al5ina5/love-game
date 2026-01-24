-- src/net/relay_client.lua
-- Real-time online multiplayer client using persistent TCP sockets via Relay
-- Much faster than polling HTTP/REST

local socket = require("socket")
local json = require("src.lib.dkjson")
local Protocol = require("src.net.protocol")
local Constants = require("src.constants")

local RelayClient = {}
RelayClient.__index = RelayClient

local dnsThread = nil
local dnsRequestChannel = nil
local dnsResponseChannel = nil

function RelayClient:new()
    local self = setmetatable({}, RelayClient)
    self.tcp = nil
    self.roomCode = nil
    self.connected = false
    self.playerId = nil
    self.paired = false -- True when opponent is also connected to relay
    self.messageQueue = {} -- Queue for incoming raw messages
    self.processedCount = 0

    return self
end

-- ... (connect and updateConnecting remain the same) ...

function RelayClient:poll(timeBudget)
    if self.connecting then
        self:updateConnecting()
    end
    
    if not self.connected or not self.tcp then return {} end

    -- 1. RECEIVE: Read all available data from TCP socket and buffer into queue
    -- Use non-blocking receive with timeout
    self.tcp:settimeout(0)
    local data, err, partial = self.tcp:receive("*a") -- Receive all available data
    
    if err == "closed" then
        print("RelayClient: Connection closed by relay")
        self.connected = false
        -- Generate a player_left message immediately
        return {{ type = "player_left", id = "opponent", disconnectReason = "connection_closed" }}
    elseif err and err ~= "timeout" then
        print("RelayClient: Receive error: " .. tostring(err))
        if err == "closed" or err:match("closed") then
            self.connected = false
            return {{ type = "player_left", id = "opponent", disconnectReason = "connection_closed" }}
        end
    end
    
    -- Append new data to buffer
    self.buffer = self.buffer .. (data or partial or "")
    
    -- Extract complete lines and push to message queue
    while true do
        local line, rest = self.buffer:match("^(.-)\n(.*)$")
        if line then
            table.insert(self.messageQueue, line)
            self.buffer = rest
        else
            break
        end
    end

    -- 2. CONFLATION: Pre-process queue to drop outdated state snapshots
    -- If we have multiple "state" messages, we only need the last one.
    -- This fixes the "Death Spiral" where decoding old states consumes all CPU.
    self:_conflateQueue()

    -- 3. PROCESS: Decode messages from queue within time budget
    return self:_processMessageQueue(timeBudget)
end

function RelayClient:_conflateQueue()
    -- Scan queue backwards to find the last state snapshot
    local lastStateIdx = nil
    local stateIndices = {}

    local Protocol = require("src.net.protocol")
    
    for i = #self.messageQueue, 1, -1 do
        local line = self.messageQueue[i]
        -- Check for state snapshot markers (fast string match, no decode yet)
        if line:sub(1, 6) == "state|" or line:sub(1, 6) == Protocol.MSG.STATE_SNAPSHOT.."|" then
            if not lastStateIdx then
                lastStateIdx = i
            else
                -- Found an OLDER state snapshot. Mark for deletion.
                table.insert(stateIndices, i)
            end
        end
    end

    -- Remove outdated state snapshots
    -- Iterate backwards so indices don't shift
    if #stateIndices > 0 then
        -- print("RelayClient: Dropping " .. #stateIndices .. " outdated state snapshots due to lag/batching")
        for _, idx in ipairs(stateIndices) do
            table.remove(self.messageQueue, idx)
        end
    end
end

function RelayClient:_processMessageQueue(timeBudget)
    local messages = {}
    local startTime = love.timer.getTime()
    local budget = timeBudget or 0.005 -- Default 5ms budget
    
    -- Safety: If queue is massive, force drop oldest to prevent memory OOM
    if #self.messageQueue > 200 then
        print("RelayClient: WARNING - Queue overflow ("..#self.messageQueue.."), dropping oldest 100")
        for i=1, 100 do table.remove(self.messageQueue, 1) end
    end

    local pingSent = false

    -- Send ping periodically (moved here to ensure it happens even if receiving bunches)
    local now = love.timer.getTime()
    if now - self.lastPingTime > 1.0 and not self.pendingPing then
        local timestamp = now
        local encoded = Protocol.encode(Protocol.MSG.PING, timestamp)
        if self:send(encoded) then
            self.pendingPing = {timestamp = timestamp, sent_time = now}
            self.lastPingTime = now
            pingSent = true
        end
         -- Send HTTP ping (fire and forget)
         self:sendHTTPPing()
    end


    -- Process loop with time check
    while #self.messageQueue > 0 do
        local line = table.remove(self.messageQueue, 1)
        
        -- Estimate ping based on packet round trip (approximate using receive time)
        if self.lastPacketSentTime > 0 and not pingSent then
           -- We can't easily measure per-packet RTT without ID, but we know we just got *some* data
           -- Calculate packetRTT only once per poll handling to avoid noise
           -- (Logic preserved from original but slightly adapted)
           local packetRTT = (now - self.lastPacketSentTime) * 1000
           if packetRTT > 0 and packetRTT < 500 then
                -- self:updatePingMeasurement(packetRTT) 
                -- Commented out: packet RTT is noisy with batching, rely on explicit Ping/Pong
           end
        end

        if line == "PAIRED" then
            print("RelayClient: Opponent connected to relay!")
            self.paired = true
        elseif line == "OPPONENT_LEFT" then
            print("RelayClient: Opponent left the room!")
            self.paired = false
            table.insert(messages, { type = "player_left", id = "opponent", disconnectReason = "opponent_left" })
        elseif line:match("^ERROR:") then
            local errorMsg = line:sub(7)
            print("RelayClient: Server error: " .. errorMsg)
        elseif line ~= "" then
            local msg = Protocol.decode(line)
            if msg then
                 -- Handle server-assigned player ID
                 if msg.type == Protocol.MSG.PLAYER_JOIN and not self.receivedPlayerId then
                    self.playerId = msg.id
                    self.receivedPlayerId = true
                    if self.game then
                        self.game.playerId = msg.id
                        print("RelayClient: Server assigned player ID: " .. msg.id)
                    end
                elseif msg.id == self.playerId then
                    -- print("RelayClient: Ignoring our own message")
                else
                     -- Translate protocol types (legacy compatibility)
                    if msg.type == Protocol.MSG.PLAYER_JOIN then msg.type = "player_joined"
                    elseif msg.type == Protocol.MSG.PLAYER_LEAVE then msg.type = "player_left"
                    elseif msg.type == Protocol.MSG.PLAYER_MOVE then msg.type = "player_moved"
                    elseif msg.type == Protocol.MSG.PET_MOVE then msg.type = "pet_moved"
                    elseif msg.type == Protocol.MSG.STATE_SNAPSHOT or msg.type == "state" then msg.type = "state_snapshot"
                    elseif msg.type == Protocol.MSG.EVENT_BOON_GRANTED then msg.type = "boon_granted"
                    elseif msg.type == Protocol.MSG.EVENT_PLAYER_DIED then msg.type = "player_died"
                    elseif msg.type == Protocol.MSG.EVENT_BOON_STOLEN then msg.type = "boon_stolen"
                    elseif msg.type == Protocol.MSG.CYCLE_TIME then msg.type = "cycle"
                    elseif msg.type == Protocol.MSG.EXTRACTION then msg.type = "extract"
                    elseif msg.type == Protocol.MSG.PING then
                        local pongData = Protocol.encode(Protocol.MSG.PONG, msg.timestamp)
                        self:send(pongData)
                    elseif msg.type == Protocol.MSG.PONG then
                        if self.pendingPing and self.pendingPing.timestamp == msg.timestamp then
                            local pingMs = (love.timer.getTime() - self.pendingPing.sent_time) * 1000
                            self:updatePingMeasurement(pingMs)
                            self.pendingPing = nil
                        end
                    elseif line:match("^npcs%|") or msg.type == "npcs" then
                        -- Protocol.decode now handles npcs natively if structure matches
                        -- But for raw string parsing fallback (if Protocol.decode didn't handle it fully):
                        if not msg.npcs then
                             -- (Logic similar to original manual parse if needed, but Protocol.lua handles it)
                        end
                    elseif line:match("^animals%|") or msg.type == "animals" then
                         -- Protocol.lua handles it
                    end

                    -- Push valid message to result list
                    if msg.type ~= Protocol.MSG.INPUT_SHOOT and msg.type ~= Protocol.MSG.INPUT_INTERACT then
                        table.insert(messages, msg)
                    end
                end
            end
        end

        -- Check Time Budget
        if (love.timer.getTime() - startTime) > budget then
            -- print("RelayClient: Time budget exceeded ("..(budget*1000).."ms), yielding " .. #self.messageQueue .. " messages to next frame")
            break
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
function RelayClient:sendPosition(direction, batch)
    if not self.connected or not self.playerId then
        return false
    end

    -- Rate limiting based on connection quality
    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then
        return true  -- Not an error, just rate limited
    end
    self.lastSendTime = now
    self.lastPacketSentTime = now  -- Track for ping measurement

    -- Build batched message: move|id|count|direction|dx1|dy1|sprint1|dt1|seq1|...
    local Protocol = require('src.net.protocol')
    local parts = {
        Protocol.MSG.PLAYER_MOVE,
        self.playerId,
        #batch,
        direction or "down"
    }

    for _, input in ipairs(batch) do
        table.insert(parts, string.format("%.2f", input.dx))
        table.insert(parts, string.format("%.2f", input.dy))
        table.insert(parts, input.sprinting and "1" or "0")
        table.insert(parts, string.format("%.4f", input.dt))
        table.insert(parts, math.floor(input.seq))
    end

    local encoded = table.concat(parts, "|")
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
