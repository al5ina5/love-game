-- src/game.lua
-- Main game coordinator - delegates to specialized modules

local Player = require('src.entities.player')
local Pet = require('src.entities.pet')
local Camera = require('src.systems.camera')
local Input = require('src.systems.input')
local Discovery = require('src.net.discovery')
local Menu = require('src.ui.menu')
local Dialogue = require('src.ui.dialogue')
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
    
    self.npcs = {}
    self.animals = {}
    
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
        Input:update()
        Loading.complete(self)
        return
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
            if self.playerId and (self.playerId == "host" or self.playerId == "client") then
                print("Game: Updating playerId from " .. self.playerId .. " to " .. networkPlayerId)
            end
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
        self.chunkManager:updateActiveChunks(self.player.x, self.player.y)
    end
    
    EntityManager.updateAll(self, dt)
    
    NetworkUpdater.update(self, dt)
    
    if self.network then
        local messages = self.network:poll()
        for _, msg in ipairs(messages) do
            NetworkHandler.handleMessage(msg, self)
        end
        
        if self.isHost then
            self.discovery:setPlayerCount(1 + self:countRemotePlayers())
        end
    end
    
    self.camera:update(dt)
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
            Audio:playBlip()
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
        print("Game: Cannot shoot - not connected")
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
        Audio:playBlip()
    end
end

function Game:gamepadpressed(button)
    if self.dialogue:isActive() then
        if button == "a" then
            self.dialogue:advance()
            local Audio = require('src.systems.audio')
            Audio:playBlip()
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
    if self.npcs and #self.npcs > 0 then
        return
    end
    self.npcs = EntitySpawner.createNPCs()
end

function Game:createAnimalGroups()
    if self.animals and #self.animals > 0 then
        return
    end
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

return Game
