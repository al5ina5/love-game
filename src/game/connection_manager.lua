-- src/game/connection_manager.lua
-- Manages network connections, hosting, and joining

local Client = require('src.net.client')
local Server = require('src.net.server')
local OnlineClient = require('src.net.online_client')
local RelayClient = require('src.net.relay_client')
local NetworkAdapter = require('src.net.network_adapter')
local json = require('src.lib.dkjson')

local ConnectionManager = {}

function ConnectionManager.create()
    return {
        connectionTimer = 0,
        connectionTimeout = 10.0,
        heartbeatTimer = 0,
        heartbeatInterval = 30.0,
        onlineClient = nil,
        hostSentJoin = false  -- Track if host has sent PLAYER_JOIN when paired
    }
end

function ConnectionManager.becomeHost(game)
    if game.network then game.network:disconnect() end
    game.remotePlayers = {}
    game.isHost = true
    -- Enable Boon Snatch game mode
    game.network = Server:new(12345, "boonsnatch")

    if not game.network then
        print("Connection: Failed to create server")
        game.isHost = false
        return
    end

    game.network = NetworkAdapter:createLAN(nil, game.network)
    game.discovery:startAdvertising("Pixel Raiders", 12345, 10)
    game.playerId = "host"
    
    -- For Boon Snatch mode, NPCs and animals are server-authoritative and come from server state
    -- The server creates them when initialized
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
        end
    elseif game.network and game.network.type == NetworkAdapter.TYPE.LAN and not game.isHost and not game.playerId then
        -- Client is trying to connect, check for timeout
        cm.connectionTimer = cm.connectionTimer + dt
        if cm.connectionTimer >= cm.connectionTimeout then
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
    
    -- Poll for async networking responses
    OnlineClient.update()
end

function ConnectionManager.returnToMainMenu(game)
    
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

-- Async hosting
function ConnectionManager.hostOnlineAsync(isPublic, game, callback)
    if not OnlineClient.isAvailable() then
        if callback then callback(false, "HTTPS support not found") end
        return
    end

    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        if callback then callback(false, "Failed to initialize online client") end
        return
    end

    onlineClient:requestAsync("POST", onlineClient.apiUrl .. "/api/create-room", json.encode({ isPublic = isPublic or false }), function(roomSuccess, response)
        if not roomSuccess then
            if callback then callback(false, response or "Unknown error") end
            return
        end

        local roomCode = response.roomCode
        if not roomCode then
            if callback then callback(false, "Invalid response from server") end
            return
        end

        -- Setup relay client (TCP) - starts in background
        local relayClient = RelayClient:new()
        relayClient:connect(roomCode, "host")
        
        -- We'll handle the adapter creation in updateOnline once relay is connected
        game.network = NetworkAdapter:createRelay(relayClient)

        game.isHost = true
        game.playerId = "host"
        game.connectionManager.onlineClient = onlineClient
        
        if game.menu then
            game.menu.onlineRoomCode = roomCode
            game.menu:hide()
        end

        if callback then callback(true, roomCode) end
    end)
end

function ConnectionManager.hostOnline(isPublic, game)
    -- Legacy sync version - eventually remove
    return ConnectionManager.hostOnlineAsync(isPublic, game)
end

-- Async joining
function ConnectionManager.joinOnlineAsync(roomCode, game, callback)
    if not OnlineClient.isAvailable() then
        if callback then callback(false, "HTTPS support not found") end
        return
    end

    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        if callback then callback(false, "Failed to initialize online client") end
        return
    end

    onlineClient:requestAsync("POST", onlineClient.apiUrl .. "/api/join-room", json.encode({ roomCode = roomCode:upper() }), function(joinSuccess, response)
        if not joinSuccess then
            if callback then callback(false, response or "Check the room code.") end
            return
        end

        local relayClient = RelayClient:new()
        relayClient:connect(roomCode, "client")

        game.network = NetworkAdapter:createRelay(relayClient)
        game.isHost = false
        game.playerId = "client"
        game.connectionManager.onlineClient = onlineClient

        -- PLAYER_JOIN will be sent in updateOnline once relay.connected is true
        
        if game.menu then
            game.menu:hide()
        end

        if callback then callback(true) end
    end)
end

function ConnectionManager.joinOnline(roomCode, game)
    -- Legacy sync version
    return ConnectionManager.joinOnlineAsync(roomCode, game)
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
    
    -- Host: Send PLAYER_JOIN when relay becomes paired (client connected)
    if game.network and game.network.type == NetworkAdapter.TYPE.RELAY then
        local relayClient = game.network.client
        if relayClient and relayClient.connected then
            -- Create local server for host if it doesn't exist yet
            if game.isHost and not game.network.localServer then
                local Server = require('src.net.server')
                local localServer = Server:new(nil, "boonsnatch")
                if localServer and localServer.serverLogic then
                    game.network.localServer = localServer
                    if game.player then
                        localServer.serverLogic:addPlayer("host", game.player.x, game.player.y)
                        localServer.serverLogic:spawnInitialChests(10)
                        localServer.serverLogic:spawnNPCs()
                        localServer.serverLogic:spawnAnimals()
                    end
                    print("Connection: Local serverLogic initialized for relay host")
                end
            end

            -- Send PLAYER_JOIN if not sent yet (immediately for client, when paired for host)
            if not cm.sentJoin then
                local shouldJoin = false
                if not game.isHost then
                    shouldJoin = true -- Client joins immediately
                elseif relayClient.paired then
                    shouldJoin = true -- Host joins when opponent joins
                end

                if shouldJoin then
                    local Protocol = require('src.net.protocol')
                    local playerX = game.player and game.player.x or 400
                    local playerY = game.player and game.player.y or 300
                    local skin = game.player and game.player.spriteName or nil
                    local encoded = Protocol.encode(Protocol.MSG.PLAYER_JOIN, game.playerId or (game.isHost and "host" or "client"), math.floor(playerX), math.floor(playerY))
                    if skin then
                        encoded = encoded .. "|" .. skin
                    end
                    relayClient:send(encoded)
                    cm.sentJoin = true
                    print("Connection: PLAYER_JOIN sent (" .. (game.playerId or "unknown") .. ")")
                end
            end
        end
    end
end

return ConnectionManager
