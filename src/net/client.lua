-- src/net/client.lua
-- Simple client for walking simulator
-- Sends position, receives other players' positions

local enet = require("enet")
local Protocol = require("src.net.protocol")
local Constants = require("src.constants")

local Client = {}
Client.__index = Client

function Client:new()
    local self = setmetatable({}, Client)
    
    self.host = nil
    self.server = nil
    self.connected = false
    self.playerId = nil
    
    -- Adaptive rate limiting (Miyoo-optimized, adjusts based on connection quality)
    self.lastSendTime = 0
    self.baseSendRate = Constants.MIYOO_BASE_SEND_RATE  -- Miyoo-tuned base rate
    self.minSendRate = Constants.MIYOO_MIN_SEND_RATE   -- Min rate: conservative for poor connections
    self.maxSendRate = Constants.MIYOO_MAX_SEND_RATE   -- Max rate: for excellent connections
    self.sendRate = self.baseSendRate

    -- Connection quality tracking
    self.pingHistory = {}
    self.maxPingSamples = 10
    self.lastPingTime = 0
    self.averagePing = 100  -- Initial estimate in ms
    self.connectionQuality = 1.0  -- 0.0 to 1.0 (higher is better)
    self.pendingPing = nil  -- {timestamp, sent_time} for manual ping measurement
    self.lastPacketSentTime = 0  -- Track when we last sent any packet
    self.packetsSent = 0  -- Count packets sent for ping estimation
    
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

function Client:sendPosition(x, y, direction, skin, sprinting)
    if not self.connected or not self.server then return end

    local now = love.timer.getTime()
    if now - self.lastSendTime < self.sendRate then return end
    self.lastSendTime = now
    self.lastPacketSentTime = now  -- Track packet send time for ping measurement

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
    if sprinting then
        data = data .. "|1"
    end

    self.server:send(data, 0, "unreliable")
end

-- Update connection quality based on ping measurements
function Client:updateConnectionQuality(manualPingMs)
    if not self.server then return end

    -- Use manual ping measurement if provided, otherwise use ENet's built-in ping
    local pingMs = manualPingMs

    -- If no manual ping, try ENet's built-in measurement
    if not pingMs or pingMs <= 0 then
        pingMs = self.server:round_trip_time()
    end

    -- If still no ping, estimate based on connection
    if not pingMs or pingMs <= 0 then
        pingMs = 50 -- Default LAN ping estimate
    end

    -- Sanity check - ping shouldn't be unreasonably high
    if pingMs > 1000 then
        pingMs = 1000
    end

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
            print(string.format("Client: Ping %.1fms, Quality %.2f, SendRate %.2fhz",
                self.averagePing, self.connectionQuality, 1/self.sendRate))
        end
    end
end

-- Get current connection quality for external monitoring
function Client:getConnectionQuality()
    return self.connectionQuality, self.averagePing
end

-- Force a ping test (useful for debugging)
function Client:testPing()
    if not self.connected or not self.server then return end

    local now = love.timer.getTime()
    local timestamp = now
    local data = Protocol.encode(Protocol.MSG.PING, timestamp)
    self.server:send(data, 0, "unreliable")
    self.pendingPing = {timestamp = timestamp, sent_time = now}
    print("LAN Client: Forced ping test sent")
end

function Client:sendPetPosition(playerId, x, y, monster)
    if not self.connected or not self.server then return end
    self.lastPacketSentTime = love.timer.getTime()
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
    if not self.connected or not self.server then return false end

    self.lastPacketSentTime = love.timer.getTime()

    -- If msg has a data field with encoded string, send it directly
    if msg.data and type(msg.data) == "string" then
        self.server:send(msg.data, 0, "reliable")
        return true
    end

    -- Otherwise encode the message
    if msg.type then
        local Protocol = require("src.net.protocol")
        local encoded = Protocol.encode(msg.type, msg.id or self.playerId or "?", unpack(msg.data or {}))
        self.server:send(encoded, 0, "reliable")
        return true
    end

    return false
end

function Client:poll()
    local messages = {}
    if not self.host then return messages end

    -- Update ping measurement periodically
    local now = love.timer.getTime()
    if now - self.lastPingTime > 1.0 then  -- Update ping every second
        self.lastPingTime = now

        -- Always send manual ping for reliable measurement
        if self.connected and self.server and not self.pendingPing then
            local timestamp = now
            local data = Protocol.encode(Protocol.MSG.PING, timestamp)
            self.server:send(data, 0, "unreliable")
            self.pendingPing = {timestamp = timestamp, sent_time = now}
        end

        -- Also try to use ENet's built-in ping if available
        if self.server then
            local enetPing = self.server:round_trip_time()
            if enetPing and enetPing > 0 and enetPing < 1000 then
                self:updateConnectionQuality(enetPing)
            end
        end
    end

    local event = self.host:service(0)
    while event do
        if event.type == "connect" then
            print("Connected to server!")
            self.connected = true
            
        elseif event.type == "receive" then
            -- Estimate ping based on packet round trip
            if self.lastPacketSentTime > 0 then
                local now = love.timer.getTime()
                local packetRTT = (now - self.lastPacketSentTime) * 1000
                if packetRTT > 0 and packetRTT < 500 then  -- Reasonable ping range
                    self:updateConnectionQuality(packetRTT)
                end
            end

            local msg = Protocol.decode(event.data)

            if msg.type == Protocol.MSG.PLAYER_JOIN and not self.playerId then
                self.playerId = msg.id
                print("Our player ID: " .. self.playerId)
                -- Still add the message so game can handle it
                msg.type = "player_joined"
                table.insert(messages, msg)
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
                elseif msg.type == Protocol.MSG.STATE_SNAPSHOT then
                    msg.type = "state_snapshot"
                elseif msg.type == Protocol.MSG.EVENT_BOON_GRANTED then
                    msg.type = "boon_granted"
                elseif msg.type == Protocol.MSG.EVENT_PLAYER_DIED then
                    msg.type = "player_died"
                elseif msg.type == Protocol.MSG.EVENT_BOON_STOLEN then
                    msg.type = "boon_stolen"
                elseif msg.type == Protocol.MSG.EVENT_CHEST_OPENED then
                    msg.type = "chest_opened"
                elseif msg.type == Protocol.MSG.EVENT_PROJECTILE then
                    msg.type = "projectile"
                elseif msg.type == Protocol.MSG.PONG then
                    -- Calculate ping if we have a pending ping
                    if self.pendingPing and self.pendingPing.timestamp == msg.timestamp then
                        local now = love.timer.getTime()
                        local pingMs = (now - self.pendingPing.sent_time) * 1000  -- Convert to milliseconds
                        self:updateConnectionQuality(pingMs)
                        self.pendingPing = nil
                    end
                    -- Don't add pong messages to game messages
                    return messages
                elseif msg.type == Protocol.MSG.INPUT_SHOOT or msg.type == Protocol.MSG.INPUT_INTERACT then
                    -- Ignore our own inputs echoed back
                    return messages
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
