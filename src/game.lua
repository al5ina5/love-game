-- src/game.lua
-- Simple walking simulator - Stone Plaza
-- Large stone brick floor with camera following player

local Player = require('src.entities.player')
local Pet = require('src.entities.pet')
local RemotePlayer = require('src.entities.remote_player')
local NPC = require('src.entities.npc')
local Camera = require('src.systems.camera')
local Input = require('src.systems.input')
local Client = require('src.net.client')
local Server = require('src.net.server')
local Discovery = require('src.net.discovery')
local Menu = require('src.ui.menu')
local Dialogue = require('src.ui.dialogue')
local Audio = require('src.systems.audio')
local ConnectionManager = require('src.game.connection_manager')
local NetworkAdapter = require('src.net.network_adapter')

-- World size (large plaza)
local WORLD_W, WORLD_H = 800, 600
local TILE_SIZE = 16

local Game = {
    isHost = false,
    remotePlayers = {},
    network = nil,
    player = nil,
    pet = nil,
    npcs = {},
    dialogue = nil,
    camera = nil,
    discovery = nil,
    menu = nil,
    floorCanvas = nil,
    connectionManager = nil,
    playerId = nil,
}

function Game:load()
    -- Create local player at center of world
    self.player = Player:new(WORLD_W / 2, WORLD_H / 2)
    
    -- Create pet that follows the player
    self.pet = Pet:new(self.player)
    
    -- Create NPCs
    self.npcs = {}
    local elfBladedancer = NPC:new(
        WORLD_W / 2 + 50,  -- 50 pixels to the right of spawn
        WORLD_H / 2,
        "assets/img/sprites/Elf Bladedancer/ElfBladedancer.png",
        "Bead Guy",
        {
            "The path you walk... few dare to take it. They say the dreamer never sleeps.",
            "Chase what calls you. The rest is noise. Go on, then. The road remembers.",
        }
    )
    table.insert(self.npcs, elfBladedancer)
    
    -- Dialogue system
    self.dialogue = Dialogue:new()
    
    -- Camera follows the player
    self.camera = Camera:new(self.player)
    
    -- Networking
    self.network = nil
    self.isHost = false
    self.remotePlayers = {}
    self.playerId = nil
    
    -- Connection Manager
    self.connectionManager = ConnectionManager.create()
    
    -- Discovery
    self.discovery = Discovery:new()
    
    -- Menu (new online system)
    self.menu = Menu:new()
    self.menu.onRoomCreated = function(roomCode, wsUrl)
        print("Room created callback: " .. (roomCode or "nil"))
        -- Get isPublic from menu state
        local isPublic = self.menu.isPublic or false
        ConnectionManager.hostOnline(isPublic, self)
    end
    self.menu.onRoomJoined = function(roomCode, wsUrl, playerId)
        print("Room joined callback: " .. (roomCode or "nil"))
        if roomCode then
            ConnectionManager.joinOnline(roomCode, self)
        end
    end
    self.menu.onCancel = function() 
        ConnectionManager.returnToMainMenu(self)
    end
    
    -- Create pixel art floor tiles
    self:createFloorTiles()

    -- 8-bit audio (BGM + dialogue blips)
    Audio:init()
    Audio:playBGM()
end

function Game:createFloorTiles()
    -- Create a few tile variations as ImageData (true pixel art)
    -- Each tile is 16x16 pixels
    
    -- Color palette (matching the dungeon style)
    local colors = {
        dark =    {0.32, 0.30, 0.36, 1},   -- Dark grout/edges
        mid =     {0.45, 0.42, 0.50, 1},   -- Main stone color
        light =   {0.55, 0.52, 0.58, 1},   -- Highlight
        accent =  {0.50, 0.47, 0.54, 1},   -- Mid-light variation
    }
    
    -- Helper to set pixel
    local function setPixel(imageData, x, y, color)
        if x >= 0 and x < 16 and y >= 0 and y < 16 then
            imageData:setPixel(x, y, color[1], color[2], color[3], color[4])
        end
    end
    
    -- Create tile variation 1: Basic stone brick
    local tile1 = love.image.newImageData(16, 16)
    for y = 0, 15 do
        for x = 0, 15 do
            -- Default to mid color
            setPixel(tile1, x, y, colors.mid)
            
            -- Dark edges (grout) - bottom and right
            if x == 15 or y == 15 then
                setPixel(tile1, x, y, colors.dark)
            end
            
            -- Light edges - top and left inner highlight
            if (x == 1 or y == 1) and x < 15 and y < 15 then
                setPixel(tile1, x, y, colors.light)
            end
            
            -- Corner darkness
            if x == 0 and y == 15 then setPixel(tile1, x, y, colors.dark) end
            if x == 15 and y == 0 then setPixel(tile1, x, y, colors.dark) end
            
            -- Some texture spots
            if (x == 5 and y == 7) or (x == 10 and y == 4) or (x == 8 and y == 11) then
                setPixel(tile1, x, y, colors.accent)
            end
            if (x == 6 and y == 9) or (x == 12 and y == 6) then
                setPixel(tile1, x, y, colors.dark)
            end
        end
    end
    
    -- Create tile variation 2: Slightly different texture
    local tile2 = love.image.newImageData(16, 16)
    for y = 0, 15 do
        for x = 0, 15 do
            setPixel(tile2, x, y, colors.mid)
            
            if x == 15 or y == 15 then
                setPixel(tile2, x, y, colors.dark)
            end
            if (x == 1 or y == 1) and x < 15 and y < 15 then
                setPixel(tile2, x, y, colors.light)
            end
            if x == 0 and y == 15 then setPixel(tile2, x, y, colors.dark) end
            if x == 15 and y == 0 then setPixel(tile2, x, y, colors.dark) end
            
            -- Different spots
            if (x == 3 and y == 5) or (x == 11 and y == 8) or (x == 7 and y == 12) then
                setPixel(tile2, x, y, colors.accent)
            end
            if (x == 9 and y == 3) or (x == 4 and y == 10) then
                setPixel(tile2, x, y, colors.dark)
            end
        end
    end
    
    -- Create tile variation 3: With crack
    local tile3 = love.image.newImageData(16, 16)
    for y = 0, 15 do
        for x = 0, 15 do
            setPixel(tile3, x, y, colors.mid)
            
            if x == 15 or y == 15 then
                setPixel(tile3, x, y, colors.dark)
            end
            if (x == 1 or y == 1) and x < 15 and y < 15 then
                setPixel(tile3, x, y, colors.light)
            end
            if x == 0 and y == 15 then setPixel(tile3, x, y, colors.dark) end
            if x == 15 and y == 0 then setPixel(tile3, x, y, colors.dark) end
            
            -- Crack pattern
            if (x == 4 and y == 3) or (x == 5 and y == 4) or (x == 5 and y == 5) or
               (x == 6 and y == 6) or (x == 7 and y == 7) or (x == 7 and y == 8) or
               (x == 8 and y == 9) or (x == 9 and y == 10) then
                setPixel(tile3, x, y, colors.dark)
            end
        end
    end
    
    -- Create tile variation 4: Lighter stone
    local tile4 = love.image.newImageData(16, 16)
    for y = 0, 15 do
        for x = 0, 15 do
            setPixel(tile4, x, y, colors.accent)  -- Slightly lighter base
            
            if x == 15 or y == 15 then
                setPixel(tile4, x, y, colors.dark)
            end
            if (x == 1 or y == 1) and x < 15 and y < 15 then
                setPixel(tile4, x, y, colors.light)
            end
            if x == 0 and y == 15 then setPixel(tile4, x, y, colors.dark) end
            if x == 15 and y == 0 then setPixel(tile4, x, y, colors.dark) end
            
            if (x == 6 and y == 5) or (x == 10 and y == 10) then
                setPixel(tile4, x, y, colors.mid)
            end
        end
    end
    
    -- Convert to images
    self.tileImages = {
        love.graphics.newImage(tile1),
        love.graphics.newImage(tile2),
        love.graphics.newImage(tile3),
        love.graphics.newImage(tile4),
    }
    
    -- Set nearest neighbor filtering for crisp pixels
    for _, img in ipairs(self.tileImages) do
        img:setFilter("nearest", "nearest")
    end
    
    -- Pre-generate which tile variation goes where (deterministic)
    math.randomseed(42)
    self.tileMap = {}
    local tilesX = math.ceil(WORLD_W / TILE_SIZE)
    local tilesY = math.ceil(WORLD_H / TILE_SIZE)
    
    for y = 0, tilesY do
        self.tileMap[y] = {}
        for x = 0, tilesX do
            -- Weight towards basic tiles, occasional crack/light
            local r = math.random(100)
            if r < 40 then
                self.tileMap[y][x] = 1
            elseif r < 75 then
                self.tileMap[y][x] = 2
            elseif r < 90 then
                self.tileMap[y][x] = 4
            else
                self.tileMap[y][x] = 3  -- Rare cracked tile
            end
        end
    end
end

function Game:update(dt)
    -- Discovery always updates
    self.discovery:update(dt)
    
    -- Connection Manager updates
    ConnectionManager.update(dt, self)
    
    -- Sync playerId from network
    if self.network and not self.playerId then
        self.playerId = self.network:getPlayerId()
    end
    
    -- Menu
    if self.menu:isVisible() then
        self.menu:update(dt)
        -- Still process network messages even when menu is visible (for player_joined)
        if self.network then
            local messages = self.network:poll()
            for _, msg in ipairs(messages) do
                self:handleNetworkMessage(msg)
            end
        end
        return
    end
    
    -- Dialogue takes priority
    if self.dialogue:isActive() then
        self.dialogue:update(dt)
        Input:update()
        return
    end
    
    -- Input system update
    Input:update()
    
    -- Update local player
    self.player:update(dt)
    
    -- Update pet
    self.pet:update(dt)
    
    -- Network updates
    if self.network then
        -- Send position updates (throttled to reduce spam)
        if self.network.sendPosition then
            -- Only send if position changed significantly (more than 2 pixels) or direction changed
            local lastX = self.lastSentX or self.player.x
            local lastY = self.lastSentY or self.player.y
            local lastDir = self.lastSentDir or self.player.direction
            local dx = math.abs(self.player.x - lastX)
            local dy = math.abs(self.player.y - lastY)
            local dirChanged = (self.player.direction ~= lastDir)
            
            if dx > 2 or dy > 2 or dirChanged then
                self.network:sendPosition(self.player.x, self.player.y, self.player.direction)
                self.lastSentX = self.player.x
                self.lastSentY = self.player.y
                self.lastSentDir = self.player.direction
            end
        end
        
        -- Poll for messages
        local messages = self.network:poll()
        for _, msg in ipairs(messages) do
            self:handleNetworkMessage(msg)
        end
        
        if self.isHost then
            self.discovery:setPlayerCount(1 + self:countRemotePlayers())
        end
    end
    
    -- Update remote players
    for _, remote in pairs(self.remotePlayers) do
        remote:update(dt)
    end
    
    -- Update NPCs
    for _, npc in ipairs(self.npcs) do
        npc:update(dt)
    end
    
    -- Update camera
    self.camera:update(dt)
end

function Game:handleNetworkMessage(msg)
    print("Game: Handling network message: " .. (msg.type or "unknown") .. ", id: " .. (msg.id or msg.playerId or "none"))
    
    if msg.type == "player_joined" then
        local playerId = msg.id or msg.playerId
        print("Player joined: " .. playerId)
        -- Don't create remote player for ourselves
        if playerId and playerId ~= self.playerId then
            if not self.remotePlayers[playerId] then
                self.remotePlayers[playerId] = RemotePlayer:new(msg.x or 400, msg.y or 300)
                print("Created remote player: " .. playerId .. " at (" .. (msg.x or 400) .. ", " .. (msg.y or 300) .. ")")
            else
                print("Remote player already exists: " .. playerId)
            end
            -- Hide menu when a player joins (host sees client join, client sees host join)
            if self.menu:isVisible() then
                if self.isHost and self.menu.state == Menu.STATE.WAITING then
                    self.menu:hide()
                    print("Host: Player joined! Starting game...")
                elseif not self.isHost and (self.menu.state == Menu.STATE.FIND_GAME or self.menu.state == Menu.STATE.JOIN_CODE) then
                    self.menu:hide()
                    print("Client: Host found! Starting game...")
                end
            end
        else
            print("Ignoring player_joined for ourselves: " .. (playerId or "nil"))
        end
        
    elseif msg.type == "player_moved" then
        local playerId = msg.id or msg.playerId
        -- Don't process our own movement
        if playerId == self.playerId then 
            print("Ignoring our own movement")
            return 
        end
        
        if not playerId then
            print("Warning: player_moved message has no id")
            return
        end
        
        -- Reduce log spam - only log every 10th movement or when direction changes
        if not self.lastMoveLog then self.lastMoveLog = {} end
        local lastLog = self.lastMoveLog[playerId] or { count = 0, x = 0, y = 0 }
        local shouldLog = (lastLog.count % 10 == 0) or (msg.x ~= lastLog.x or msg.y ~= lastLog.y)
        if shouldLog then
            print("Player moved: " .. playerId .. " to (" .. (msg.x or 0) .. ", " .. (msg.y or 0) .. ")")
            self.lastMoveLog[playerId] = { count = lastLog.count + 1, x = msg.x, y = msg.y }
        else
            self.lastMoveLog[playerId] = { count = lastLog.count + 1, x = lastLog.x, y = lastLog.y }
        end
        local remote = self.remotePlayers[playerId]
        if remote then
            remote:setTargetPosition(msg.x, msg.y, msg.dir)
        else
            -- Create remote player if we don't have them yet
            print("Creating remote player on move: " .. playerId)
            self.remotePlayers[playerId] = RemotePlayer:new(msg.x or 400, msg.y or 300)
            remote = self.remotePlayers[playerId]
            if remote then
                remote:setTargetPosition(msg.x, msg.y, msg.dir)
            end
        end
        
    elseif msg.type == "player_left" then
        local playerId = msg.id or msg.playerId
        print("Player left: " .. (playerId or "unknown"))
        if playerId then
            self.remotePlayers[playerId] = nil
        end
    elseif msg.type == "connected" then
        print("WebSocket connected: " .. (msg.playerId or "unknown"))
        if msg.playerId then
            self.playerId = msg.playerId
            if self.network then
                self.network.playerId = msg.playerId
            end
        end
    else
        print("Unknown message type: " .. (msg.type or "nil"))
    end
end

function Game:draw()
    -- Apply camera transform
    self.camera:attach()
    
    -- Draw stone floor
    self:drawStoneFloor()
    
    -- Collect entities for Y-sorting
    local drawList = {}
    
    -- Local player
    table.insert(drawList, { entity = self.player, y = self.player.y + (self.player.originY or 0) })
    
    -- Pet
    table.insert(drawList, { entity = self.pet, y = self.pet.y + (self.pet.originY or 0) })
    
    -- Remote players
    for _, remote in pairs(self.remotePlayers) do
        table.insert(drawList, { entity = remote, y = remote.y + (remote.originY or 0) })
    end
    
    -- NPCs
    for _, npc in ipairs(self.npcs) do
        table.insert(drawList, { entity = npc, y = npc.y + (npc.originY or 0) })
    end
    
    -- Sort by Y
    table.sort(drawList, function(a, b) return a.y < b.y end)
    
    -- Draw entities
    for _, item in ipairs(drawList) do
        item.entity:draw()
    end
    
    self.camera:detach()
end

-- Draw UI elements at native resolution (called outside of scale transform)
function Game:drawUI()
    -- Dialogue renders at native resolution for crisp text
    self.dialogue:draw()
    
    -- Menu renders at native resolution for crisp text
    self.menu:draw()
end

function Game:drawStoneFloor()
    -- Calculate visible tile range
    local startX = math.floor(self.camera.x / TILE_SIZE) - 1
    local startY = math.floor(self.camera.y / TILE_SIZE) - 1
    local endX = math.ceil((self.camera.x + 320) / TILE_SIZE) + 1
    local endY = math.ceil((self.camera.y + 180) / TILE_SIZE) + 1
    
    -- Clamp to world bounds
    startX = math.max(0, startX)
    startY = math.max(0, startY)
    endX = math.min(math.ceil(WORLD_W / TILE_SIZE) - 1, endX)
    endY = math.min(math.ceil(WORLD_H / TILE_SIZE) - 1, endY)
    
    -- Draw tiles
    love.graphics.setColor(1, 1, 1)
    for ty = startY, endY do
        for tx = startX, endX do
            local tileIdx = 1
            if self.tileMap[ty] and self.tileMap[ty][tx] then
                tileIdx = self.tileMap[ty][tx]
            end
            
            love.graphics.draw(
                self.tileImages[tileIdx],
                tx * TILE_SIZE,
                ty * TILE_SIZE
            )
        end
    end
end

function Game:countRemotePlayers()
    local count = 0
    for _ in pairs(self.remotePlayers) do count = count + 1 end
    return count
end

function Game:keypressed(key)
    -- Dialogue interaction
    if self.dialogue:isActive() then
        if key == "space" or key == "return" or key == "z" then
            self.dialogue:advance()
            Audio:playBlip()
        end
        return
    end
    
    if self.menu:isVisible() then
        if self.menu:keypressed(key) then return end
    end
    
    -- Interact with nearby NPC
    if key == "space" or key == "z" then
        self:tryInteractWithNPC()
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

function Game:tryInteractWithNPC()
    for _, npc in ipairs(self.npcs) do
        if npc:isPlayerInRange(self.player) then
            local name, lines = npc:getDialogue()
            self.dialogue:start(name, lines)
            return
        end
    end
end

function Game:mousepressed(x, y, button)
    if not self.dialogue:isActive() then return end
    if button == 1 then  -- left click
        self.dialogue:advance()
        Audio:playBlip()
    end
end

function Game:gamepadpressed(button)
    -- Dialogue interaction
    if self.dialogue:isActive() then
        if button == "a" then
            self.dialogue:advance()
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
    
    -- Interact with nearby NPC
    if button == "a" then
        self:tryInteractWithNPC()
    end
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

return Game
