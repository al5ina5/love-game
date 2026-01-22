-- src/game/connection_manager.lua
-- Manages network connections, hosting, and joining

local Client = require('src.net.client')
local Server = require('src.net.server')
local OnlineClient = require('src.net.online_client')
local RelayClient = require('src.net.relay_client')
local NetworkAdapter = require('src.net.network_adapter')

local ConnectionManager = {}

function ConnectionManager.create()
    return {
        connectionTimer = 0,
        connectionTimeout = 10.0,
        heartbeatTimer = 0,
        heartbeatInterval = 30.0,
        onlineClient = nil
    }
end

function ConnectionManager.becomeHost(game)
    if game.network then game.network:disconnect() end
    game.remotePlayers = {}
    game.isHost = true
    game.network = Server:new(12345)

    if not game.network then
        print("Connection: Failed to create server")
        game.isHost = false
        return
    end

    game.network = NetworkAdapter:createLAN(nil, game.network)
    game.discovery:startAdvertising("Walking Together", 12345, 4)
    game.playerId = "host"
end

function ConnectionManager.stopHosting(game)
    if not game.isHost then return end
    if game.network then
        game.network:disconnect()
        game.network = nil
    end
    game.discovery:stopAdvertising()
    game.isHost = false
    game.remotePlayers = {}
end

function ConnectionManager.connectToServer(address, port, game)
    if game.isHost then return end
    if game.network then game.network:disconnect() end
    game.remotePlayers = {}
    game.discovery:stopAdvertising()
    local client = Client:new()
    game.network = NetworkAdapter:createLAN(client, nil)
    print("Connection: Attempting to connect to " .. address .. ":" .. port)
    client:connect(address or "localhost", port or 12345)
    game.connectionManager.connectionTimer = 0
end

function ConnectionManager.update(dt, game)
    local cm = game.connectionManager
    
    -- Check for successful client connection (LAN)
    if game.network and game.network.type == NetworkAdapter.TYPE.LAN and not game.playerId then
        local client = game.network.client
        if client and client.playerId then
            game.playerId = client.playerId
            print("Connection: Client connected with playerId: " .. game.playerId)
        end
    elseif game.network and game.network.type == NetworkAdapter.TYPE.LAN and not game.isHost and not game.playerId then
        -- Client is trying to connect, check for timeout
        cm.connectionTimer = cm.connectionTimer + dt
        if cm.connectionTimer >= cm.connectionTimeout then
            print("Connection: Timeout after " .. cm.connectionTimeout .. " seconds")
            if game.network then
                game.network:disconnect()
                game.network = nil
            end
            if game.menu then
                game.menu:show()
            end
            cm.connectionTimer = 0
        end
    end
    
    -- Update discovery player count if host (LAN only)
    if game.isHost and game.network and game.network.type == NetworkAdapter.TYPE.LAN then
        game.discovery:setPlayerCount(1 + game:countRemotePlayers())
    end
    
    -- Online-specific updates
    ConnectionManager.updateOnline(dt, game)
end

function ConnectionManager.returnToMainMenu(game)
    print("Connection: Returning to main menu")
    
    -- Clean up LAN hosting
    if game.isHost then
        ConnectionManager.stopHosting(game)
    end
    
    -- Clean up network connection
    if game.network then
        if game.network.disconnect then
            game.network:disconnect()
        end
        game.network = nil
    end
    
    -- Clean up online client
    if game.connectionManager.onlineClient then
        if game.connectionManager.onlineClient.disconnect then
            game.connectionManager.onlineClient:disconnect()
        end
        game.connectionManager.onlineClient = nil
    end
    
    -- Reset all game state
    game.remotePlayers = {}
    game.playerId = nil
    game.isHost = false
end

-- Online multiplayer functions

function ConnectionManager.hostOnline(isPublic, game)
    if not OnlineClient.isAvailable() then
        print("Connection: Online multiplayer not available (HTTPS support not found)")
        if game.menu then
            game.menu.onlineError = "Online multiplayer requires HTTPS support.\nPlease use LAN multiplayer instead."
        end
        return false
    end
    
    print("Connection: Creating online room (public: " .. tostring(isPublic) .. ")")
    
    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        print("Connection: Failed to initialize online client: " .. tostring(onlineClient))
        if game.menu then
            game.menu.onlineError = "Failed to initialize online client"
        end
        return false
    end
    
    local roomSuccess, roomCodeOrError = onlineClient:createRoom(isPublic)
    
    if not roomSuccess then
        local errorMsg = roomCodeOrError or "Unknown error"
        print("Connection: Failed to create online room: " .. tostring(errorMsg))
        if game.menu then
            game.menu.onlineError = "Failed to create room: " .. tostring(errorMsg)
            game.menu.state = game.menu.STATE.CREATE_GAME
        end
        return false
    end
    
    local roomCode = roomCodeOrError
    print("Connection: Online room created with code: " .. roomCode)
    
    -- Setup relay client (TCP)
    print("Connection: Attempting to connect to relay server...")
    local relayClient = RelayClient:new()
    if not relayClient:connect(roomCode, "host") then
        print("Connection: Failed to connect to relay server")
        if game.menu then
            game.menu.onlineError = "Room created but failed to connect to relay server.\nRoom code: " .. roomCode .. "\n\nYou may need to set up a TCP relay server."
            game.menu.onlineRoomCode = roomCode  -- Still show the room code
            game.menu.state = game.menu.STATE.WAITING
        end
        -- Don't return false - room was created, just relay failed
        -- This allows the host to share the room code even if relay isn't working
    end

    -- Setup network adapter (only if relay connected successfully)
    if relayClient.connected then
        game.network = NetworkAdapter:createRelay(relayClient)
        print("Connection: Network adapter created with relay client")
        
        -- Host should send initial PLAYER_JOIN when paired (handled in relay_client.lua)
        -- But also send it immediately so client knows about host
        local Protocol = require('src.net.protocol')
        relayClient:send(Protocol.encode(Protocol.MSG.PLAYER_JOIN, "host", 400, 300))
        print("Connection: Host sent initial PLAYER_JOIN message")
    else
        print("Connection: WARNING - Relay not connected, network adapter not created")
        -- Still set up basic state so room code is shown
    end
    
    game.isHost = true
    game.playerId = "host"
    game.connectionManager.onlineClient = onlineClient -- Keep for heartbeat
    
    -- Show waiting screen with room code
    if game.menu then
        game.menu.onlineRoomCode = roomCode
        game.menu.state = game.menu.STATE.WAITING
        print("Connection: Menu state set to WAITING with room code: " .. roomCode)
    end
    
    return true
end

function ConnectionManager.joinOnline(roomCode, game)
    if not OnlineClient.isAvailable() then
        print("Connection: Online multiplayer not available (HTTPS support not found)")
        if game.menu then
            game.menu.onlineError = "Online multiplayer requires HTTPS support.\nPlease use LAN multiplayer instead."
        end
        return false
    end
    
    print("Connection: Joining online room " .. roomCode)
    
    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        print("Connection: Failed to initialize online client: " .. tostring(onlineClient))
        if game.menu then
            game.menu.onlineError = "Failed to initialize online client"
        end
        return false
    end
    
    local joinSuccess, errorMsg = onlineClient:joinRoom(roomCode)
    
    if not joinSuccess then
        print("Connection: Failed to join online room: " .. tostring(errorMsg))
        if game.menu then
            game.menu.onlineError = "Failed to join room: " .. (errorMsg or "Check the room code.")
        end
        return false
    end
    
    print("Connection: Successfully joined online room")
    
    -- Setup relay client (TCP)
    local relayClient = RelayClient:new()
    if not relayClient:connect(roomCode, "client") then
        print("Connection: Failed to connect to relay server")
        if game.menu then
            game.menu.onlineError = "Failed to connect to real-time relay server."
        end
        return false
    end

    -- Setup network adapter
    game.network = NetworkAdapter:createRelay(relayClient)
    game.isHost = false
    game.playerId = "client"
    game.connectionManager.onlineClient = onlineClient
    
    -- Notify relay we are ready (client sends PLAYER_JOIN immediately)
    local Protocol = require('src.net.protocol')
    relayClient:send(Protocol.encode(Protocol.MSG.PLAYER_JOIN, "client", 400, 300))
    print("Connection: Client sent initial PLAYER_JOIN message")
    
    -- Don't hide menu yet - wait for host's PLAYER_JOIN message
    -- Menu will be hidden when player_joined message is received
    if game.menu then
        -- Keep menu visible but in a connecting state
        print("Connection: Client waiting for host to send PLAYER_JOIN")
    end
    
    return true
end

function ConnectionManager.refreshOnlineRooms(game)
    if not OnlineClient.isAvailable() then
        print("Connection: Online multiplayer not available (HTTPS support not found)")
        if game.menu then
            game.menu.publicRooms = {}
            game.menu.onlineError = "Online multiplayer requires HTTPS support.\nPlease use LAN multiplayer instead."
        end
        return
    end
    
    print("Connection: Refreshing online rooms list")
    
    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        print("Connection: Failed to initialize online client: " .. tostring(onlineClient))
        if game.menu then
            game.menu.publicRooms = {}
            game.menu.onlineError = "Failed to initialize online client"
        end
        return
    end
    
    local rooms = onlineClient:listRooms()
    
    print("Connection: Found " .. #rooms .. " online rooms")
    if game.menu then
        game.menu.publicRooms = rooms
    end
end

function ConnectionManager.updateOnline(dt, game)
    local cm = game.connectionManager
    
    -- Send periodic heartbeat if hosting online
    if cm.onlineClient and game.isHost then
        cm.heartbeatTimer = cm.heartbeatTimer + dt
        if cm.heartbeatTimer >= cm.heartbeatInterval then
            cm.onlineClient:heartbeat()
            cm.heartbeatTimer = 0
        end
    end
end

return ConnectionManager
