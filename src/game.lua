-- src/game.lua
-- Main game coordinator - delegates to specialized modules

local Player = require('src.entities.player')
local Pet = require('src.entities.pet')
local Camera = require('src.systems.camera')
local Input = require('src.systems.input')
local Discovery = require('src.net.discovery')
local Menu = require('src.ui.menu')
local Dialogue = require('src.ui.dialogue')
local Map = require('src.ui.map')
local ConnectionManager = require('src.game.connection_manager')
local NetworkHandler = require('src.game.network_handler')
local NetworkAdapter = require('src.net.network_adapter')
local World = require('src.world.world')
local ChunkManager = require('src.world.chunk_manager')
local EntityManager = require('src.game.entity_manager')
local Renderer = require('src.game.renderer')
local Loading = require('src.game.loading')
local Interaction = require('src.game.interaction')
local EntitySpawner = require('src.game.entity_spawner')
local NetworkUpdater = require('src.game.network_updater')
local Constants = require('src.constants')

local WORLD_W, WORLD_H = 5000, 5000

local Game = {
    isHost = false,
    remotePlayers = {},
    remotePets = {},
    network = nil,
    player = nil,
    pet = nil,
    npcs = {},
    animals = {},
    dialogue = nil,
    camera = nil,
    discovery = nil,
    menu = nil,
    map = nil,
    connectionManager = nil,
    playerId = nil,
    gameState = nil,
    cycleTime = nil,
    timerFont = nil,
    chunkManager = nil,
    loadingComplete = false,
    loadingProgress = 0,
    loadingMessage = "Loading...",
    desaturationShader = nil,
    worldCanvas = nil,

    -- World cache for MIYO performance optimization
    worldCache = nil,

    -- Network polling optimization for Miyoo
    lastNetworkPoll = 0,
    networkPollInterval = Constants.MIYOO_NETWORK_POLL_RATE, -- Miyoo-tuned polling rate
}

function Game:load()
    local seedValue
    if os and os.time then
        seedValue = os.time()
    elseif love and love.timer then
        seedValue = love.timer.getTime() * 1000000
    else
        seedValue = 12345
    end
    if love and love.timer then
        seedValue = seedValue + (love.timer.getTime() % 1) * 1000000
    end
    math.randomseed(seedValue)
    for i = 1, 10 do
        math.random()
    end
    
    local playerSuccess = pcall(function()
        self.player = Player:new(WORLD_W / 2, WORLD_H / 2)
    end)
    if not playerSuccess then
        self.player = {x = WORLD_W / 2, y = WORLD_H / 2, width = 16, height = 16, direction = "down"}
    end
    
    if self.player and type(self.player) == "table" and self.player.x then
        pcall(function()
            self.pet = Pet:new(self.player)
        end)
    end
    
    self.dialogue = Dialogue:new()
    
    local screenWidth = love.graphics and love.graphics.getWidth() or 320
    local screenHeight = love.graphics and love.graphics.getHeight() or 240
    local viewportWidth, viewportHeight = Camera.calculateViewport(screenWidth, screenHeight)
    
    local playerX = (self.player and self.player.x) or (WORLD_W / 2)
    local playerY = (self.player and self.player.y) or (WORLD_H / 2)
    local cameraPlayer = self.player or {x = playerX, y = playerY}
    self.camera = Camera:new(cameraPlayer, WORLD_W, WORLD_H, viewportWidth, viewportHeight)
    
    self.network = nil
    self.isHost = false
    self.remotePlayers = {}
    self.playerId = nil
    
    self.connectionManager = ConnectionManager.create()
    self.discovery = Discovery:new()
    
    self.menu = Menu:new()
    self.menu.onRoomCreated = function(roomCode, wsUrl)
        local isPublic = self.menu.isPublic or false
        ConnectionManager.hostOnline(isPublic, self)
    end
    self.menu.onRoomJoined = function(roomCode, wsUrl, playerId)
        if roomCode then
            ConnectionManager.joinOnline(roomCode, self)
        end
    end
    self.menu.onCancel = function() 
        ConnectionManager.returnToMainMenu(self)
    end
    
    self.chunkManager = ChunkManager:new(WORLD_W, WORLD_H)
    
    self.world = World:new(WORLD_W, WORLD_H)
    self.world:loadTiles()
    self.world:loadRocks()
    self.world:generateRocks()
    self.world:loadTrees()
    self.world:generateTrees(seedValue)

    self.npcs = {}
    self.animals = {}

    -- NPCs and animals are now loaded dynamically in renderer to avoid loading thousands of entities
    -- They come from server state for networked games, or from world cache for spatial queries
    
    -- Initialize map (after world and player are created)
    self.map = Map:new(self.world, self.player)
    
    self.loadingComplete = false
    self.loadingProgress = 0.3
    self.loadingMessage = "Loading world..."
    
    self.timerFont = love.graphics.newFont("assets/fonts/runescape_uf.ttf", 24)
    self.timerFont:setFilter("nearest", "nearest")
    
    -- Initialize desaturation shader and canvas if enabled
    local Constants = require('src.constants')
    if Constants.ENABLE_DESATURATION_EFFECT then
        local DesaturationShader = require('src.systems.desaturation_shader')
        self.desaturationShader = DesaturationShader.new()
        
        -- Create canvas for rendering world with shader
        -- Use a reasonable size that will be resized as needed
        local canvasWidth = viewportWidth or 320
        local canvasHeight = viewportHeight or 240
        self.worldCanvas = love.graphics.newCanvas(canvasWidth, canvasHeight)
        self.worldCanvas:setFilter("nearest", "nearest")
    end
end

function Game:update(dt)
    if not self.loadingComplete then
        -- Emergency timeout for MIYO loading
        self.loadingTimer = (self.loadingTimer or 0) + dt
        local Constants = require('src.constants')
        local timeout = Constants.MIYOO_DEVICE and 30 or 60  -- MIYO: 30 seconds, Desktop: 60 seconds

        if self.loadingTimer > timeout then
            print(string.format("Game: EMERGENCY - Loading timeout after %.1f seconds, forcing completion", self.loadingTimer))
            self.loadingComplete = true
            self.loadingMessage = "Loading timeout - continuing anyway"
            self.loadingProgress = 1.0
            return
        end

        Input:update()
        Loading.complete(self)
        return
    end
    
    -- Connect to network after loading completes (prevents freeze on Miyoo)
    if not self.networkConnectionAttempted then
        self.networkConnectionAttempted = true
        pcall(function()
            self:autoJoinOrCreateServer()
        end)
    end
    
    if self.camera then
        local screenWidth = love.graphics and love.graphics.getWidth() or nil
        local screenHeight = love.graphics and love.graphics.getHeight() or nil
        if screenWidth and screenHeight then
            local newViewportWidth, newViewportHeight = Camera.calculateViewport(screenWidth, screenHeight)
            if math.abs(self.camera.width - newViewportWidth) > 0.1 or math.abs(self.camera.height - newViewportHeight) > 0.1 then
                self.camera:updateViewport(newViewportWidth, newViewportHeight)
            end
        end
    end
    
    self.discovery:update(dt)
    ConnectionManager.update(dt, self)
    
    -- Sync playerId from network adapter (important for relay server which assigns IDs)
    if self.network then
        local networkPlayerId = self.network:getPlayerId()
        if networkPlayerId and networkPlayerId ~= self.playerId then
            -- Player ID changed (e.g., server assigned "p1" instead of "host"/"client")
            self.playerId = networkPlayerId
        elseif not self.playerId and networkPlayerId then
            self.playerId = networkPlayerId
        end
    end
    
    if self.menu:isVisible() then
        self.menu:update(dt)
        if self.network then
            local messages = self.network:poll()
            for _, msg in ipairs(messages) do
                NetworkHandler.handleMessage(msg, self)
            end
        end
        return
    end
    
    if self.dialogue:isActive() then
        self.dialogue:update(dt)
        Input:update()
        return
    end
    
    Input:update()
    
    if self.player and self.chunkManager and self.player.x and self.player.y then
        local unloadedChunks = self.chunkManager:updateActiveChunks(self.player.x, self.player.y)
        
        -- Clean up unloaded chunks
        if self.world and unloadedChunks then
            for _, chunkKey in ipairs(unloadedChunks) do
                self.world:unloadChunk(chunkKey)
            end
        end
    end
    
    -- World update (with error handling for MIYO stability)
    if self.world and self.player and self.player.x and self.player.y and self.network then
        local success, err = pcall(function()
            self.world:update(dt, self.player.x, self.player.y, self.network)
        end)
        if not success then
            print("ERROR: World update failed: " .. tostring(err))
        end
    end

    -- Entity updates (with error handling for MIYO stability)
    local success, err = pcall(function()
        EntityManager.updateAll(self, dt)
    end)
    if not success then
        print("ERROR: Entity update failed: " .. tostring(err))
    end

    -- Network updates (with error handling for MIYO stability)
    success, err = pcall(function()
        NetworkUpdater.update(self, dt)
    end)
    if not success then
        print("ERROR: Network update failed: " .. tostring(err))
    end

    -- Throttle network polling for Miyoo performance
    -- Only poll network at reduced frequency to prevent micro-stutters
    self.lastNetworkPoll = self.lastNetworkPoll + dt
    if self.network and self.lastNetworkPoll >= self.networkPollInterval then
        self.lastNetworkPoll = 0
        local messages = self.network:poll()
        for _, msg in ipairs(messages) do
            NetworkHandler.handleMessage(msg, self)
        end

        if self.isHost then
            self.discovery:setPlayerCount(1 + self:countRemotePlayers())
        end
    end
    
    self.camera:update(dt)
    
    -- Update map if visible
    if self.map and self.map:isVisible() then
        self.map:update(dt)
    end
    
    self:logMemoryUsage(dt)
end

function Game:draw()
    if not self.loadingComplete then
        Loading.draw(self.loadingProgress, self.loadingMessage, self.timerFont)
        return
    end
    
    if not self.camera then
        Loading.draw(self.loadingProgress, self.loadingMessage, self.timerFont)
        return
    end
    
    Renderer.drawWorld(self)
end

function Game:drawUI()
    Renderer.drawUI(self)
    
    -- Draw map overlay
    if self.map then
        self.map:draw()
    end
end

function Game:countRemotePlayers()
    local count = 0
    for _ in pairs(self.remotePlayers) do count = count + 1 end
    return count
end

function Game:keypressed(key)
    if self.dialogue:isActive() then
        if key == "e" or key == "E" or key == "space" or key == "return" then
            self.dialogue:advance()
            local Audio = require('src.systems.audio')
            if Audio.advanceBlip then
                Audio:playAdvanceBlip()
            end
        end
        return
    end
    
    if self.menu:isVisible() then
        if self.menu:keypressed(key) then 
            return 
        end
        return  -- don't handle game keys (E interact, etc.) while menu is open
    end
    
    -- Space => shoot (disabled for now)
    -- if key == "space" then
    --     local success = pcall(function() self:handleShoot() end)
    --     if not success then end
    --     return
    -- end
    
    if key == "e" or key == "E" then
        if Interaction.tryInteractWithChest(self) then
            return
        end
        Interaction.tryInteractWithNPC(self)
        return
    end
    
    if key == "m" or key == "M" then
        if self.map then
            self.map:toggle()
        end
        return
    end
    
    if key == "escape" then
        if self.menu:isVisible() then
            self.menu:hide()
        else
            self.menu:show()
        end
    end
end

function Game:handleShoot()
    if not self.player then 
        return 
    end
    
    if not self.network then 
        ConnectionManager.becomeHost(self)
        if not self.network then
            return
        end
        if self.network.server and self.network.server.serverLogic then
            if self.player then
                local hostPlayer = self.network.server.serverLogic.state.players["host"]
                if not hostPlayer then
                    self.network.server.serverLogic:addPlayer("host", self.player.x, self.player.y)
                end
            end
        end
    end
    
    if not self.isHost and not self.network:isConnected() then
        return
    end
    
    local dx, dy = Input:getMovementVector()
    
    local angle = 0
    if dx ~= 0 or dy ~= 0 then
        angle = math.atan2(dy, dx)
    else
        if self.player.direction == "right" then
            angle = 0
        elseif self.player.direction == "down" then
            angle = math.pi / 2
        elseif self.player.direction == "left" then
            angle = math.pi
        elseif self.player.direction == "up" then
            angle = -math.pi / 2
        end
    end
    
    local success, result = pcall(function() 
        return self.network:sendGameInput("shoot", { angle = angle })
    end)
    
    if not success then
        print("Game: ERROR calling sendGameInput: " .. tostring(result))
    end
end

function Game:mousepressed(x, y, button)
    if not self.dialogue:isActive() then return end
    if button == 1 then
        self.dialogue:advance()
        local Audio = require('src.systems.audio')
        if Audio.advanceBlip then
            Audio:playAdvanceBlip()
        end
    end
end

function Game:gamepadpressed(button)
    if self.dialogue:isActive() then
        if button == "a" then
            local wasFirstAdvance = self.dialogue:advance()
            local Audio = require('src.systems.audio')
            if wasFirstAdvance and Audio.openingBlip then
                Audio:playOpeningBlip()
            elseif Audio.advanceBlip then
                Audio:playAdvanceBlip()
            end
        end
        return
    end
    
    if button == "start" then
        if self.menu:isVisible() then
            self.menu:hide()
        else
            self.menu:show()
        end
        return
    end
    
    if self.menu:isVisible() then
        self.menu:gamepadpressed(button)
        return
    end
    
    if button == "a" then
        if Interaction.tryInteractWithChest(self) then
            return
        end
        Interaction.tryInteractWithNPC(self)
        return
    end
    
    -- X => shoot (disabled for now)
    -- if button == "x" then
    --     local success = pcall(function() self:handleShoot() end)
    --     if not success then end
    --     return
    -- end
end

function Game:becomeHost()
    ConnectionManager.becomeHost(self)
end

function Game:stopHosting()
    ConnectionManager.stopHosting(self)
end

function Game:connectToServer(address, port)
    ConnectionManager.connectToServer(address, port, self)
end

function Game:quit()
    ConnectionManager.returnToMainMenu(self)
    if self.discovery then
        self.discovery:close()
    end
end

function Game:createNPCs()
    -- For local games, create NPCs locally
    -- For networked games, NPCs come from server state
    if self.npcs and #self.npcs > 0 then
        return
    end

    local EntitySpawner = require('src.game.entity_spawner')
    self.npcs = EntitySpawner.createNPCs()
end

function Game:createAnimalGroups()
    -- For local games, create animals locally
    -- For networked games, animals come from server state
    if self.animals and #self.animals > 0 then
        return
    end

    local EntitySpawner = require('src.game.entity_spawner')
    self.animals = EntitySpawner.createAnimalGroups()
end

function Game:autoJoinOrCreateServer()
    pcall(function()
        local OnlineClient = require('src.net.online_client')
        if not OnlineClient.isAvailable() then
            return
        end
        
        local onlineClient = nil
        local initSuccess = pcall(function()
            onlineClient = OnlineClient.new(OnlineClient)
        end)
        
        if not initSuccess or not onlineClient then
            return
        end
        
        local rooms = onlineClient:listRooms()
        
        local roomToJoin = nil
        for _, room in ipairs(rooms) do
            if room.players and room.maxPlayers and room.players < room.maxPlayers then
                roomToJoin = room
                break
            end
        end
        
        if roomToJoin then
            ConnectionManager.joinOnline(roomToJoin.code, self)
        else
            ConnectionManager.hostOnline(true, self)
        end
    end)
end

-- Legacy: Road generation is now server-side and distributed via chunks.
-- Clients should no longer generate roads locally.

function Game:logMemoryUsage(dt)
    local Constants = require('src.constants')
    if not Constants.ENABLE_MEMORY_LOGGING then return end

    self.memLogTimer = (self.memLogTimer or 0) + dt
    if self.memLogTimer >= 1.0 then
        self.memLogTimer = 0
        local count = collectgarbage("count")

        local npcCount = self.npcs and #self.npcs or 0
        local animalCount = self.animals and #self.animals or 0
        local remoteCount = 0
        if self.remotePlayers then for _ in pairs(self.remotePlayers) do remoteCount = remoteCount + 1 end end
        local petriCount = 0
        if self.remotePets then for _ in pairs(self.remotePets) do petriCount = petriCount + 1 end end

        -- Also log world cache status
        local worldCacheStatus = "No Cache"
        if self.worldCache then
            if self.worldCache:isReady() then
                worldCacheStatus = string.format("Ready (%d chunks)", self.worldCache:getChunkCount())
            else
                worldCacheStatus = "Loading"
            end
        end


        -- Force garbage collection periodically to prevent memory creep
        if Constants.MIYOO_DEVICE then
            collectgarbage("collect")
        end
    end
end

return Game
