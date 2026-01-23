-- src/game/network_handler.lua
-- Handles network messages for the game

local Protocol = require('src.net.protocol')
local Menu = require('src.ui.menu')
local RemoteEntityFactory = require('src.game.remote_entity_factory')
local EntityDataHandler = require('src.game.entity_data_handler')

local NetworkHandler = {}
local json = require('src.lib.dkjson')

-- Message handler registry
local messageHandlers = {}

-- Frequent message types (for logging suppression)
local frequentTypes = { "state_snapshot", "state", "cycle", Protocol.MSG.STATE_SNAPSHOT, Protocol.MSG.CYCLE_TIME }

function NetworkHandler.handleMessage(msg, game)
    local isFrequent = false
    for _, freqType in ipairs(frequentTypes) do
        if msg.type == freqType then
            isFrequent = true
            break
        end
    end
    
    local handler = messageHandlers[msg.type]
    if handler then
        handler(msg, game)
    else
        -- Try protocol message types
        for protocolType, handlerFunc in pairs(messageHandlers) do
            if msg.type == protocolType then
                handlerFunc(msg, game)
                return
            end
        end
    end
end

-- Register message handlers
function NetworkHandler.registerHandler(msgType, handler)
    messageHandlers[msgType] = handler
end

-- Player joined handler
messageHandlers["player_joined"] = function(msg, game)
    local playerId = msg.id or msg.playerId
    local posX = msg.x or (game.world.worldWidth / 2)
    local posY = msg.y or (game.world.worldHeight / 2)
    local skin = msg.skin

    if game.isHost and playerId and playerId ~= game.playerId then
        local WorldSync = require('src.game.world_sync')
        if game.world then
            game.world:sendRocksToClients(game.network, game.isHost)
        end
        -- NPCs and animals now come from server state, not separate sync
    end

    if playerId and playerId ~= game.playerId then
        RemoteEntityFactory.createOrUpdateRemotePlayer(game, playerId, posX, posY, skin, "down", false)

        if game.menu:isVisible() then
            if game.isHost and game.menu.state == Menu.STATE.WAITING then
                game.menu:hide()
                print("Host: Player joined! Starting game...")
            elseif not game.isHost then
                game.menu:hide()
                print("Client: Host found! Starting game...")
            end
        end
    else
        -- Clean up any ghost remote player for this ID
        if game.remotePlayers[playerId] then
            game.remotePlayers[playerId] = nil
            print("NetworkHandler: Cleaned up ghost remote player from player_joined for ID: " .. (playerId or "nil"))
        end
    end
end

-- Player moved handler
messageHandlers["player_moved"] = function(msg, game)
    local playerId = msg.id or msg.playerId
    
    if playerId == game.playerId then
        return
    end
    
    if not playerId then
        return
    end
    
    RemoteEntityFactory.createOrUpdateRemotePlayer(
        game, 
        playerId, 
        msg.x or 400, 
        msg.y or 300, 
        msg.skin, 
        msg.dir, 
        msg.sprinting
    )
end

-- Pet moved handler
messageHandlers["pet_moved"] = function(msg, game)
    RemoteEntityFactory.updateRemotePet(game, msg.id or msg.playerId, msg.x, msg.y, msg.monster)
end

-- Player left handler
messageHandlers["player_left"] = function(msg, game)
    RemoteEntityFactory.removeRemotePlayer(game, msg.id or msg.playerId)
end

-- Connected handler
messageHandlers["connected"] = function(msg, game)
    if msg.playerId then
        game.playerId = msg.playerId
        if game.network then
            game.network.playerId = msg.playerId
        end
    end
end

-- Rocks data handler
messageHandlers[Protocol.MSG.ROCKS_DATA] = function(msg, game)
    messageHandlers["rocks"](msg, game)
end

messageHandlers["rocks"] = function(msg, game)
    if msg.rocks then
        game.world.rocks = msg.rocks
        for _, rock in ipairs(game.world.rocks) do
            if not rock.actualTileNum and game.world.validTileToActual then
                rock.actualTileNum = game.world.validTileToActual[rock.tileId] or 1
            end
            rock.x = tonumber(rock.x) or 0
            rock.y = tonumber(rock.y) or 0
            rock.tileId = tonumber(rock.tileId) or 1
        end
    end
end

-- NPC data handler
messageHandlers[Protocol.MSG.NPC_DATA] = function(msg, game)
    EntityDataHandler.handleNPCData(msg.npcs, game)
end

-- Animals data handler
messageHandlers[Protocol.MSG.ANIMALS_DATA] = function(msg, game)
    EntityDataHandler.handleAnimalsData(msg.animals, game)
end

-- State snapshot handler (consolidated)
local function processStateSnapshot(state, game)
    game.gameState = state
    
    if state.npcs then
        EntityDataHandler.handleNPCDataFromState(state.npcs, game)
    end

    if state.animals then
        EntityDataHandler.handleAnimalsDataFromState(state.animals, game)
    end
    
    -- Critical: Don't process remote players until we know our own ID
    -- This prevents the "ghost player" issue where we render ourselves as a remote player
    if not game.playerId then
        return
    end
    
    if state.players then
        for playerId, playerData in pairs(state.players) do
            if playerId ~= game.playerId then
                RemoteEntityFactory.createOrUpdateRemotePlayer(
                    game,
                    playerId,
                    playerData.x or 0,
                    playerData.y or 0,
                    playerData.skin,
                    playerData.direction or "down",
                    playerData.sprinting
                )
            else
                -- Clean up any ghost remote player for current player ID
                if game.remotePlayers[playerId] then
                    game.remotePlayers[playerId] = nil
                    print("NetworkHandler: Cleaned up ghost remote player for current player ID: " .. playerId)
                end
            end
        end
        
        for playerId, _ in pairs(game.remotePlayers) do
            if not state.players[playerId] then
                RemoteEntityFactory.removeRemotePlayer(game, playerId)
            end
        end
    end
    
    local playerCount = 0
    local projCount = 0
    local chestCount = 0
    local npcCount = 0
    local animalCount = 0
    if state.players then
        for _ in pairs(state.players) do playerCount = playerCount + 1 end
    end
    if state.projectiles then
        for _ in pairs(state.projectiles) do projCount = projCount + 1 end
    end
    if state.chests then
        for _ in pairs(state.chests) do chestCount = chestCount + 1 end
    end
    if state.npcs then
        for _ in pairs(state.npcs) do npcCount = npcCount + 1 end
    end
    if state.animals then
        for _ in pairs(state.animals) do animalCount = animalCount + 1 end
    end

    if not game.lastStateLog or love.timer.getTime() - game.lastStateLog > 1 then
        print("NetworkHandler: Updated game state (players: " .. playerCount ..
              ", projectiles: " .. projCount ..
              ", chests: " .. chestCount ..
              ", npcs: " .. npcCount ..
              ", animals: " .. animalCount .. ")")
        game.lastStateLog = love.timer.getTime()
    end
end

-- Base handlers (defined first)
messageHandlers["state"] = function(msg, game)
    local json = require("src.lib.dkjson")
    local stateJson = msg.state
    
    if type(stateJson) == "string" then
        local success, state = pcall(json.decode, stateJson)
        if success and state then
            processStateSnapshot(state, game)
        end
    elseif type(stateJson) == "table" then
        processStateSnapshot(stateJson, game)
    end
end

messageHandlers["state_snapshot"] = function(msg, game)
    messageHandlers["state"](msg, game)
end

messageHandlers["boon_granted"] = function(msg, game)
    print("NetworkHandler: Boon granted to " .. (msg.id or "?") .. ": " .. (msg.boonType or "?"))
    -- TODO: Show boon notification (will be handled by BOON UI)
end

messageHandlers["player_died"] = function(msg, game)
    -- TODO: Show death effects
end

messageHandlers["boon_stolen"] = function(msg, game)
    print("NetworkHandler: " .. (msg.killerId or "?") .. " stole " .. (msg.boonCount or 0) .. " boons from " .. (msg.victimId or "?"))
    -- TODO: Show steal notification
end

messageHandlers["cycle"] = function(msg, game)
    if not game.cycleTime then
        game.cycleTime = {}
    end
    game.cycleTime.timeRemaining = msg.timeRemaining or 0
    game.cycleTime.duration = msg.duration or 1200000
    game.cycleTime.lastUpdate = love.timer.getTime()
end

messageHandlers["extract"] = function(msg, game)
    -- TODO: Show extraction notification/effects
end

-- Protocol message handlers (reference base handlers)
-- Note: Protocol.MSG.STATE_SNAPSHOT is "state", so it already has a handler above
-- We don't need to register it again to avoid overwriting the handler

messageHandlers[Protocol.MSG.EVENT_BOON_GRANTED] = function(msg, game)
    messageHandlers["boon_granted"](msg, game)
end

messageHandlers[Protocol.MSG.EVENT_PLAYER_DIED] = function(msg, game)
    messageHandlers["player_died"](msg, game)
end

messageHandlers[Protocol.MSG.EVENT_BOON_STOLEN] = function(msg, game)
    messageHandlers["boon_stolen"](msg, game)
end

-- Note: Protocol.MSG.CYCLE_TIME is "cycle", so it already has a handler above
-- We don't need to register it again to avoid overwriting the handler

-- Note: Protocol.MSG.EXTRACTION is "extract", so it already has a handler above
-- We don't need to register it again to avoid overwriting the handler

-- Request chunk handler (Server-side handling on Host)
NetworkHandler.registerHandler(Protocol.MSG.REQUEST_CHUNK, function(msg, game)
    if not game.isHost or not game.network then return end
    
    -- Request format: type|cx|cy
    -- It is sent as network:send(Protocol.MSG.REQUEST_CHUNK, tx, ty)
    -- So parts will be ["req_chunk", tx, ty]
    local cx, cy
    if msg.cx and msg.cy then
        cx, cy = tonumber(msg.cx), tonumber(msg.cy)
    else
        -- Manually decode if not already decoded by Protocol.decode
        -- Protocol.decode for unknown types returns {type=msgType}
        -- We need to check if there are numeric indices
        cx = tonumber(msg[2])
        cy = tonumber(msg[3])
    end
    
    if not cx or not cy then return end
    
    -- Get chunk data from local server logic
    local serverLogic = nil
    if game.network.type == "lan" and game.network.server then
        serverLogic = game.network.server.serverLogic
    elseif game.network.type == "relay" and game.network.localServer then
        serverLogic = game.network.localServer.serverLogic
    end
    
    if serverLogic then
        local chunkData = serverLogic:getChunkData(cx, cy)
        local json = require("src.lib.dkjson")
        local encodedData = json.encode(chunkData)
        
        -- Send response
        game.network:send(Protocol.MSG.CHUNK_DATA, cx, cy, encodedData)
    end
end)

-- Chunk data handler (Client-side)
NetworkHandler.registerHandler(Protocol.MSG.CHUNK_DATA, function(msg, game)
    if game.world and msg.cx and msg.cy and msg.data then
        game.world:loadChunkData(msg.cx, msg.cy, msg.data)
    end
end)

-- Handle NPCs message from server
messageHandlers["npcs"] = function(msg, game)
    if msg.npcs then
        EntityDataHandler.handleNPCData(msg.npcs, game)
    end
end

-- Handle Animals message from server
messageHandlers["animals"] = function(msg, game)
    if msg.animals then
        EntityDataHandler.handleAnimalsData(msg.animals, game)
    end
end

return NetworkHandler
