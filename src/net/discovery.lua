-- src/net/discovery.lua
-- LAN server discovery using UDP broadcast
-- Uses LuaSocket (built into LÖVE) separately from ENet

local socket = require("socket")

local Discovery = {}
Discovery.__index = Discovery

-- Port for discovery broadcast (different from game port)
local DISCOVERY_PORT = 12346
local BROADCAST_INTERVAL = 1.0  -- Seconds between broadcasts
local SERVER_TIMEOUT = 5.0      -- Remove server if no ping for this long

function Discovery:new()
    local self = setmetatable({}, Discovery)
    
    self.servers = {}
    self.broadcastTimer = 0
    self.serverInfo = nil
    self.socket = nil
    self.mode = nil  -- "server" or "client"
    
    return self
end

-- Create and configure a fresh UDP socket
function Discovery:createSocket()
    if self.socket then
        self.socket:close()
    end
    
    -- Try to create an IPv4 UDP socket
    local sock, err = socket.udp()
    if not sock then
        print("Discovery Error: Could not create socket: " .. tostring(err))
        return nil
    end
    
    self.socket = sock
    self.socket:settimeout(0)  -- Non-blocking
    self.socket:setoption("broadcast", true)
    
    return self.socket
end

-- Start advertising as a server
function Discovery:startAdvertising(serverName, gamePort, maxPlayers)
    print("Discovery: Attempting to start advertising...")
    self:createSocket()
    if not self.socket then return end
    
    -- Bind to the discovery port to receive client queries
    -- On Mac/Unix, "0.0.0.0" is often better than "*" for broadcast
    local success, err = self.socket:setsockname("0.0.0.0", DISCOVERY_PORT)
    if not success then
        print("Discovery: port " .. DISCOVERY_PORT .. " busy, falling back: " .. tostring(err))
        self.socket:setsockname("0.0.0.0", 0)
    end
    
    local boundIp, boundPort = self.socket:getsockname()
    print("Discovery: Bound to " .. tostring(boundIp) .. ":" .. tostring(boundPort))
    
    self.mode = "server"
    self.serverInfo = {
        name = serverName or "Pixel Raiders",
        port = gamePort or 12345,
        players = 1,
        maxPlayers = maxPlayers or 4,
    }
    
    -- Reset timer to broadcast immediately
    self.broadcastTimer = BROADCAST_INTERVAL
    print("Discovery: Advertising as '" .. self.serverInfo.name .. "'")
end

-- Stop advertising
function Discovery:stopAdvertising()
    if self.serverInfo then
        print("Discovery: Stopped advertising")
        self.serverInfo = nil
    end
    
    if self.mode == "server" then
        self.mode = nil
        if self.socket then
            self.socket:close()
            self.socket = nil
            print("Discovery: Server socket closed")
        end
    end
end

-- Start listening for servers (as a client)
function Discovery:startListening()
    -- Create socket if we don't have one
    if not self.socket then
        print("Discovery: Starting client listener")
        self:createSocket()
        if self.socket then
            self.socket:setsockname("0.0.0.0", 0)
            local ip, port = self.socket:getsockname()
            print("Discovery: Client bound to " .. tostring(ip) .. ":" .. tostring(port))
            self.mode = "client"
        end
    end
    
    -- Clear current server list to force a refresh
    self.servers = {}
end

-- Update discovery (call every frame)
function Discovery:update(dt)
    if not self.socket then return end
    
    self.broadcastTimer = self.broadcastTimer + dt
    
    -- If we're a server, periodically broadcast our presence
    if self.serverInfo and self.broadcastTimer >= BROADCAST_INTERVAL then
        self.broadcastTimer = 0
        self:broadcastServer()
    end
    
    -- Always receive incoming messages
    self:receiveMessages()
    
    -- Clean up stale servers
    self:cleanupStaleServers()
end

-- Broadcast server info to LAN
function Discovery:broadcastServer()
    if not self.serverInfo or not self.socket then return end
    
    local msg = string.format("SERVER|%s|%d|%d|%d",
        self.serverInfo.name,
        self.serverInfo.port,
        self.serverInfo.players,
        self.serverInfo.maxPlayers
    )
    
    -- Attempt broadcast to 255.255.255.255
    self.socket:sendto(msg, "255.255.255.255", DISCOVERY_PORT)
    
    -- Common subnet broadcasts (works better on some OSs)
    self.socket:sendto(msg, "192.168.1.255", DISCOVERY_PORT)
    self.socket:sendto(msg, "192.168.0.255", DISCOVERY_PORT)
    
    -- Also send to localhost to ensure local testing works regardless of broadcast settings
    self.socket:sendto(msg, "127.0.0.1", DISCOVERY_PORT)
end

-- Send a discovery request (as client looking for servers)
function Discovery:sendDiscoveryRequest()
    if not self.socket then
        self:startListening()
    end
    if not self.socket then return end
    
    local msg = "DISCOVER"
    print("Discovery: Sending broadcast request to 255.255.255.255 and common subnets...")
    self.socket:sendto(msg, "255.255.255.255", DISCOVERY_PORT)
    self.socket:sendto(msg, "192.168.1.255", DISCOVERY_PORT)
    self.socket:sendto(msg, "192.168.0.255", DISCOVERY_PORT)
    self.socket:sendto(msg, "127.0.0.1", DISCOVERY_PORT)
end

-- Receive and process messages
function Discovery:receiveMessages()
    if not self.socket then return end
    
    -- Local helper to process a single data packet
    local function process(data, ip, port)
        -- print("Discovery Debug: Received raw [" .. tostring(data) .. "] from " .. tostring(ip) .. ":" .. tostring(port))
        
        local msgType = data:match("^(%w+)")
        
        if msgType == "DISCOVER" and self.serverInfo then
            -- Query received, reply directly
            local response = string.format("SERVER|%s|%d|%d|%d",
                self.serverInfo.name,
                self.serverInfo.port,
                self.serverInfo.players,
                self.serverInfo.maxPlayers
            )
            self.socket:sendto(response, ip, port)
            print("Discovery: Replied to DISCOVER from " .. ip)
            
        elseif msgType == "SERVER" then
            -- Server advertisement received
            local name, gamePort, players, maxPlayers = 
                data:match("SERVER|([^|]+)|(%d+)|(%d+)|(%d+)")
            
            if name and gamePort then
                local sid = ip .. ":" .. gamePort
                if not self.servers[sid] then
                    print("Discovery: Found server '" .. name .. "' at " .. ip)
                end
                
                self.servers[sid] = {
                    name = name,
                    ip = ip,
                    port = tonumber(gamePort),
                    players = tonumber(players) or 1,
                    maxPlayers = tonumber(maxPlayers) or 4,
                    lastSeen = love.timer.getTime(),
                }
            end
        end
    end

    -- Poll all pending messages
    while true do
        local data, ip, port = self.socket:receivefrom()
        if not data then 
            if ip ~= "timeout" then
                -- Any error other than timeout (like "closed" or "refused")
                -- print("Discovery Receive Error: " .. tostring(ip))
            end
            break 
        end
        process(data, ip, port)
    end
end

-- Remove servers we haven't heard from recently
function Discovery:cleanupStaleServers()
    local now = love.timer.getTime()
    for sid, server in pairs(self.servers) do
        if now - server.lastSeen > SERVER_TIMEOUT then
            print("Discovery: Server '" .. server.name .. "' timed out")
            self.servers[sid] = nil
        end
    end
end

-- Get list of discovered servers
function Discovery:getServers()
    local list = {}
    for _, server in pairs(self.servers) do
        table.insert(list, server)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Update player count (call when players join/leave)
function Discovery:setPlayerCount(count)
    if self.serverInfo then
        self.serverInfo.players = count
    end
end

-- Clean up
function Discovery:close()
    if self.socket then
        self.socket:close()
        self.socket = nil
    end
    self.mode = nil
    self.serverInfo = nil
    print("Discovery: Closed")
end

return Discovery
