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
local Protocol = require('src.net.protocol')

-- World size (large plaza)
local WORLD_W, WORLD_H = 1600, 1200
local TILE_SIZE = 16

local Game = {
    isHost = false,
    remotePlayers = {},
    remotePets = {},
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
    rocks = {},  -- Array of {x, y, tileId, actualTileNum}
    rocksImage = nil,
    rocksQuads = {},
    rocksImageData = nil,  -- ImageData for pixel-perfect collision
    validTileToActual = {},  -- Mapping from valid tile index to actual tile number
}

function Game:load()
    -- Seed random number generator for true randomness (before player creation)
    -- Use a combination of time sources for better randomness
    local seedValue
    if os and os.time then
        seedValue = os.time()
    elseif love and love.timer then
        seedValue = love.timer.getTime() * 1000000
    else
        seedValue = 12345  -- Fallback
    end
    -- Add microsecond precision if available
    if love and love.timer then
        seedValue = seedValue + (love.timer.getTime() % 1) * 1000000
    end
    math.randomseed(seedValue)
    -- Call random multiple times to mix up the state
    for i = 1, 10 do
        math.random()
    end
    
    -- Create local player at center of world
    self.player = Player:new(WORLD_W / 2, WORLD_H / 2)
    
    -- Create pet that follows the player
    self.pet = Pet:new(self.player)
    
    -- Create NPCs with fragmented cryptic story about love
    self.npcs = {}
    
    -- Part 1: The Beard Guy (Overworked Villager) - Starts the mystery
    local beardGuy = NPC:new(
        WORLD_W / 2 + 80,
        WORLD_H / 2 - 40,
        "assets/img/sprites/humans/Overworked Villager/OverworkedVillager.png",
        "Old Wanderer",
        {
            "They say love is the key. But to what door? I've forgotten.",
            "The one who walks the ancient paths might remember. Find the keeper of old truths.",
        }
    )
    table.insert(self.npcs, beardGuy)
    
    -- Part 2: Elf Lord - The ancient truth
    local elfLord = NPC:new(
        WORLD_W / 2 - 120,
        WORLD_H / 2 + 60,
        "assets/img/sprites/humans/Elf Lord/ElfLord.png",
        "Keeper of Truths",
        {
            "Love binds what time cannot. It's the thread that holds worlds together.",
            "But threads can fray. The mystic knows how they connect. Seek the one who reads the currents.",
        }
    )
    table.insert(self.npcs, elfLord)
    
    -- Part 3: Merfolk Mystic - The connection
    local merfolkMystic = NPC:new(
        WORLD_W / 2 + 150,
        WORLD_H / 2 + 100,
        "assets/img/sprites/humans/Merfolk Mystic/MerfolkMystic.png",
        "Current Reader",
        {
            "Every bond is a current. Love flows between souls like water between stones.",
            "But currents can be redirected. The enchanter understands this power. Find the one who shapes what cannot be seen.",
        }
    )
    table.insert(self.npcs, merfolkMystic)
    
    -- Part 4: Elf Enchanter - The power
    local elfEnchanter = NPC:new(
        WORLD_W / 2 - 200,
        WORLD_H / 2 - 80,
        "assets/img/sprites/humans/Elf Enchanter/ElfEnchanter.png",
        "Shape Shifter",
        {
            "Love shapes reality itself. It's not just feeling—it's a force that remakes the world.",
            "But forces can be dangerous. The young wanderer has seen what happens when it breaks. Look for the one who carries scars.",
        }
    )
    table.insert(self.npcs, elfEnchanter)
    
    -- Part 5: Adventurous Adolescent - The warning
    local adventurousAdolescent = NPC:new(
        WORLD_W / 2 + 250,
        WORLD_H / 2 - 120,
        "assets/img/sprites/humans/Adventurous Adolescent/AdventurousAdolescent.png",
        "Scarred Wanderer",
        {
            "I've seen what happens when love is lost. The world grows cold. Colors fade.",
            "But I've also seen it return. The loud one knows how. Find the voice that never quiets.",
        }
    )
    table.insert(self.npcs, adventurousAdolescent)
    
    -- Part 6: Boisterous Youth - The revelation
    local boisterousYouth = NPC:new(
        WORLD_W / 2 - 80,
        WORLD_H / 2 - 150,
        "assets/img/sprites/humans/Boisterous Youth/BoisterousYouth.png",
        "The Voice",
        {
            "Love isn't found—it's chosen. Every moment you choose connection over isolation.",
            "The wayfarer has walked this path longer than any. They know where it leads. Find the one who never stops moving.",
        }
    )
    table.insert(self.npcs, boisterousYouth)
    
    -- Part 7: Elf Wayfarer - The conclusion
    local elfWayfarer = NPC:new(
        WORLD_W / 2 + 180,
        WORLD_H / 2 + 180,
        "assets/img/sprites/humans/Elf Wayfarer/ElfWayfarer.png",
        "The Eternal Walker",
        {
            "I've walked every path. Love is the only thing that makes any of them matter.",
            "Without it, we're just shadows moving through an empty world. With it... we become real.",
            "The old wanderer was right. It is the key. But the door? That's for you to find.",
        }
    )
    table.insert(self.npcs, elfWayfarer)
    
    -- Additional NPCs for flavor and red herrings
    local joyfulKid = NPC:new(
        WORLD_W / 2 - 300,
        WORLD_H / 2 + 200,
        "assets/img/sprites/humans/Joyful Kid/JoyfulKid.png",
        "Little One",
        {
            "Everyone talks about love but nobody explains it!",
            "Maybe the grown-ups don't know either?",
        }
    )
    table.insert(self.npcs, joyfulKid)
    
    local playfulChild = NPC:new(
        WORLD_W / 2 + 300,
        WORLD_H / 2 - 200,
        "assets/img/sprites/humans/Playful Child/PlayfulChild.png",
        "Curious Child",
        {
            "I heard the old wanderer talking about keys and doors!",
            "Do you think there's a secret door somewhere?",
        }
    )
    table.insert(self.npcs, playfulChild)
    
    local elfBladedancer = NPC:new(
        WORLD_W / 2 - 250,
        WORLD_H / 2 + 250,
        "assets/img/sprites/humans/Elf Bladedancer/ElfBladedancer.png",
        "Silent Guardian",
        {
            "I guard the paths. Many seek answers. Few find them.",
            "The truth is scattered. You must gather all the pieces.",
        }
    )
    table.insert(self.npcs, elfBladedancer)
    
    -- Dialogue system
    self.dialogue = Dialogue:new()
    
    -- Calculate dynamic viewport size based on screen size for zoom on small devices
    local screenWidth = love.graphics and love.graphics.getWidth() or nil
    local screenHeight = love.graphics and love.graphics.getHeight() or nil
    local viewportWidth, viewportHeight = Camera.calculateViewport(screenWidth, screenHeight)
    
    -- Camera follows the player with dynamic viewport
    self.camera = Camera:new(self.player, WORLD_W, WORLD_H, viewportWidth, viewportHeight)
    
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
    
    -- Load and generate rocks
    self:loadRocks()
    self:generateRocks()

    -- 8-bit audio (BGM + dialogue blips)
    Audio:init()
    Audio:playBGM()
    
    -- Auto-join logic: try to find and join a server with space, or create one
    self:autoJoinOrCreateServer()
end

function Game:createFloorTiles()
    print("=== createFloorTiles() called ===")
    -- Load tileset image
    local tilesetPath = "assets/img/tileset/tileset-v1.png"
    print("Loading tileset from: " .. tilesetPath)
    
    -- Try to load the tileset with error handling
    local success, err = pcall(function()
        self.tilesetImage = love.graphics.newImage(tilesetPath)
        self.tilesetImage:setFilter("nearest", "nearest")
    end)
    
    if not success then
        print("ERROR: Failed to load tileset: " .. tilesetPath)
        print("Error: " .. tostring(err))
        -- Fallback: create a simple colored tile
        local fallbackData = love.image.newImageData(16, 16)
        for y = 0, 15 do
            for x = 0, 15 do
                fallbackData:setPixel(x, y, 0.2, 0.6, 0.2, 1)  -- Green fallback
            end
        end
        self.tilesetImage = love.graphics.newImage(fallbackData)
        self.tilesetImage:setFilter("nearest", "nearest")
        print("Using fallback green tile")
    end
    
    -- Get tileset dimensions
    local tilesetWidth, tilesetHeight = self.tilesetImage:getDimensions()
    print("Tileset loaded: " .. tilesetWidth .. "x" .. tilesetHeight)
    
    -- Each tile is 16x16 pixels
    local tileWidth = 16
    local tileHeight = 16
    
    -- Calculate grid dimensions
    local tilesPerRow = math.floor(tilesetWidth / tileWidth)  -- How many tiles across
    local tilesPerCol = math.floor(tilesetHeight / tileHeight)  -- How many tiles down
    print("Tileset dimensions: " .. tilesPerRow .. " columns x " .. tilesPerCol .. " rows")
    print("Total possible tiles: " .. (tilesPerRow * tilesPerCol))
    
    -- Create quads for each tile in the tileset
    -- Try single column first (as described), but also support grid layout
    self.tilesetQuads = {}
    
    -- If width is exactly 16 or close, assume single column
    if tilesPerRow == 1 or tilesetWidth <= 20 then
        print("Assuming single column layout")
        for i = 0, tilesPerCol - 1 do
            local y = i * tileHeight
            self.tilesetQuads[i + 1] = love.graphics.newQuad(
                0, y,  -- Always use x=0 (first column)
                tileWidth, tileHeight,
                tilesetWidth, tilesetHeight
            )
        end
    else
        -- Grid layout: read row by row, left to right, top to bottom
        print("Assuming grid layout")
        local tileIndex = 1
        for row = 0, tilesPerCol - 1 do
            for col = 0, tilesPerRow - 1 do
                local x = col * tileWidth
                local y = row * tileHeight
                self.tilesetQuads[tileIndex] = love.graphics.newQuad(
                    x, y,
                    tileWidth, tileHeight,
                    tilesetWidth, tilesetHeight
                )
                tileIndex = tileIndex + 1
            end
        end
    end
    
    print("Total quads created: " .. #self.tilesetQuads)
    
    -- Use tile 34 (user specified)
    local BASIC_GRASS_TILE_ID = 34
    
    print("Using grass tile ID: " .. BASIC_GRASS_TILE_ID .. " (out of " .. #self.tilesetQuads .. " total)")
    
    -- Verify the quad exists
    if not self.tilesetQuads[BASIC_GRASS_TILE_ID] then
        print("WARNING: Grass tile ID " .. BASIC_GRASS_TILE_ID .. " not found! Using tile 1 instead.")
        BASIC_GRASS_TILE_ID = 1
    end
    
    print("Final grass tile ID: " .. BASIC_GRASS_TILE_ID)
    
    -- Store which quad to use for each tile variation (all use basic grass)
    self.tileQuads = {
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
        self.tilesetQuads[BASIC_GRASS_TILE_ID],
    }
    
    print("Tile quads created: " .. #self.tileQuads)
    print("=== createFloorTiles() completed ===")
    
    -- Verify everything is set up
    if self.tilesetImage then
        print("✓ tilesetImage loaded")
    else
        print("✗ tilesetImage is nil!")
    end
    if self.tileQuads and #self.tileQuads > 0 then
        print("✓ tileQuads created (" .. #self.tileQuads .. " quads)")
    else
        print("✗ tileQuads is empty or nil!")
    end
    if self.tileMap then
        local tileCount = 0
        for _ in pairs(self.tileMap) do tileCount = tileCount + 1 end
        print("✓ tileMap created (" .. tileCount .. " rows)")
    else
        print("✗ tileMap is nil!")
    end
    
    -- Pre-generate which tile variation goes where (deterministic)
    -- Save current random state, set deterministic seed, then restore
    local savedState = math.random()  -- This doesn't actually save state, but we'll reseed after
    math.randomseed(42)
    self.tileMap = {}
    local tilesX = math.ceil(WORLD_W / TILE_SIZE)
    local tilesY = math.ceil(WORLD_H / TILE_SIZE)
    
    for y = 0, tilesY do
        self.tileMap[y] = {}
        for x = 0, tilesX do
            -- All tiles use basic grass (tile variation 1)
            self.tileMap[y][x] = 1
        end
    end
end

function Game:loadRocks()
    print("=== loadRocks() called ===")
    -- Load rocks image (5x4 grid of 16x16 tiles = 80x64 pixels)
    local rocksPath = "assets/img/objects/rocks.png"
    
    local success, err = pcall(function()
        -- Load ImageData first for pixel-perfect collision
        self.rocksImageData = love.image.newImageData(rocksPath)
        self.rocksImage = love.graphics.newImage(self.rocksImageData)
        self.rocksImage:setFilter("nearest", "nearest")
    end)
    
    if not success then
        print("ERROR: Failed to load rocks: " .. rocksPath)
        print("Error: " .. tostring(err))
        return
    end
    
    -- Get image dimensions
    local rocksWidth, rocksHeight = self.rocksImage:getDimensions()
    print("Rocks image loaded: " .. rocksWidth .. "x" .. rocksHeight)
    
    -- Each tile is 16x16 pixels in a 5x4 grid
    local tileWidth = 16
    local tileHeight = 16
    local tilesPerRow = 5
    local tilesPerCol = 4
    local totalTiles = tilesPerRow * tilesPerCol  -- 20 tiles
    
    -- Empty tiles: 10, 13, 14, 15, 18, 19, 20 (1-based indexing)
    local emptyTiles = {[10] = true, [13] = true, [14] = true, [15] = true, [18] = true, [19] = true, [20] = true}
    
    -- Create quads for valid (non-empty) tiles
    self.rocksQuads = {}
    self.validTileToActual = {}  -- Map valid index -> actual tile number
    local validTileIndex = 1
    for tileIndex = 1, totalTiles do
        if not emptyTiles[tileIndex] then
            -- Calculate row and column (0-indexed)
            local row = math.floor((tileIndex - 1) / tilesPerRow)
            local col = (tileIndex - 1) % tilesPerRow
            
            local x = col * tileWidth
            local y = row * tileHeight
            
            self.rocksQuads[validTileIndex] = love.graphics.newQuad(
                x, y,
                tileWidth, tileHeight,
                rocksWidth, rocksHeight
            )
            self.validTileToActual[validTileIndex] = tileIndex  -- Store mapping
            print("Created quad for rock tile " .. tileIndex .. " -> valid index " .. validTileIndex .. " at (" .. col .. ", " .. row .. ")")
            validTileIndex = validTileIndex + 1
        end
    end
    
    print("Total valid rock quads created: " .. (#self.rocksQuads))
    print("=== loadRocks() completed ===")
end

function Game:generateRocks()
    print("=== generateRocks() called ===")
    print("isHost: " .. tostring(self.isHost))
    print("rocksQuads count: " .. (#self.rocksQuads or 0))
    
    -- Check if rocks quads are loaded
    if not self.rocksQuads or #self.rocksQuads == 0 then
        print("ERROR: No rock quads available! Cannot generate rocks.")
        return
    end
    
    -- Generate rocks deterministically (same for all clients)
    -- Use a fixed seed for deterministic generation
    local savedSeed = math.random()
    math.randomseed(12345)  -- Fixed seed for deterministic rock placement
    
    self.rocks = {}
    local numRocks = 200  -- Lots of rocks!
    
    -- Use only 2 rock types (skip first 2, use next 2 valid tiles)
    local rockTypes = {3, 4}  -- Use tile IDs 3 and 4 instead
    
    for i = 1, numRocks do
        -- Random position in world
        local x = math.random(0, WORLD_W - TILE_SIZE)
        local y = math.random(0, WORLD_H - TILE_SIZE)
        
        -- Round to tile grid and ensure integer values
        x = math.floor(math.floor(x / TILE_SIZE) * TILE_SIZE)
        y = math.floor(math.floor(y / TILE_SIZE) * TILE_SIZE)
        
        -- Use only 2 rock types (random between them)
        local tileId = rockTypes[math.random(1, #rockTypes)]
        
        -- Ensure all rocks have consistent structure
        table.insert(self.rocks, {
            x = x,
            y = y,
            tileId = tileId,  -- Only tile IDs 1 or 2
            actualTileNum = self.validTileToActual[tileId] or 1  -- Actual tile number in tileset (1-20)
        })
    end
    
    print("Generated " .. #self.rocks .. " rocks using only tile types: " .. table.concat(rockTypes, ", "))
    
    -- Restore random seed
    math.randomseed(savedSeed)
    
    -- Debug: print first few rock positions
    if #self.rocks > 0 then
        print("First rock at: (" .. self.rocks[1].x .. ", " .. self.rocks[1].y .. "), tileId: " .. self.rocks[1].tileId)
        print("Last rock at: (" .. self.rocks[#self.rocks].x .. ", " .. self.rocks[#self.rocks].y .. "), tileId: " .. self.rocks[#self.rocks].tileId)
    end
    
    -- If we're the host and connected, send rocks to clients
    if self.isHost and self.network then
        self:sendRocksToClients()
    end
    
    print("=== generateRocks() completed ===")
end

function Game:sendRocksToClients()
    if not self.isHost or not self.network or not self.rocks then
        return
    end
    
    -- Build rocks data message
    local parts = {Protocol.MSG.ROCKS_DATA, #self.rocks}
    for _, rock in ipairs(self.rocks) do
        table.insert(parts, math.floor(rock.x))
        table.insert(parts, math.floor(rock.y))
        table.insert(parts, rock.tileId)
        table.insert(parts, rock.actualTileNum or self.validTileToActual[rock.tileId] or 1)
    end
    
    local encoded = table.concat(parts, "|")
    
    -- Send to all clients via network adapter
    if self.network.type == NetworkAdapter.TYPE.LAN and self.network.server then
        -- For LAN, use server's broadcast
        if self.network.server.broadcast then
            self.network.server:broadcast(encoded, nil, true)
            print("Sent " .. #self.rocks .. " rocks to clients (LAN broadcast)")
        end
    elseif self.network.type == NetworkAdapter.TYPE.RELAY and self.network.client then
        -- For relay, send directly through client
        if self.network.client.send then
            self.network.client:send(encoded)
            print("Sent " .. #self.rocks .. " rocks to clients (relay)")
        end
    elseif self.network.sendMessage then
        -- Try sendMessage as fallback
        self.network:sendMessage(encoded)
        print("Sent " .. #self.rocks .. " rocks to clients (via sendMessage)")
    else
        print("WARNING: Could not send rocks - no suitable network method")
    end
end

function Game:getRockPixel(x, y, rock)
    -- Get pixel at position (x, y) in world coordinates for a specific rock
    -- Returns true if pixel is solid (not transparent)
    if not self.rocksImageData or not rock or not rock.actualTileNum then return false end
    
    -- Convert world coordinates to local rock coordinates
    local localX = math.floor(x - rock.x)
    local localY = math.floor(y - rock.y)
    
    -- Check if within rock bounds
    if localX < 0 or localX >= TILE_SIZE or localY < 0 or localY >= TILE_SIZE then
        return false
    end
    
    -- Calculate row and column in the tileset (0-indexed)
    local tilesPerRow = 5
    local actualTileNum = rock.actualTileNum  -- Actual tile number (1-20)
    local row = math.floor((actualTileNum - 1) / tilesPerRow)
    local col = (actualTileNum - 1) % tilesPerRow
    
    -- Calculate pixel position in the full image
    local imageX = col * TILE_SIZE + localX
    local imageY = row * TILE_SIZE + localY
    
    -- Get pixel at this position
    local r, g, b, a = self.rocksImageData:getPixel(imageX, imageY)
    
    -- Return true if pixel is not transparent (alpha > 0.5)
    return a > 0.5
end

function Game:checkRockCollision(x, y, width, height)
    -- Pixel-perfect collision detection with rocks
    -- Character collision: only check the very bottom edge (feet area)
    if not self.rocks or not self.rocksImageData then return false end
    
    -- Use only the bottom-most pixels of the character (feet)
    -- This allows character to get very close to rocks
    local charCollisionHeight = 2  -- Just 2 pixels at the bottom (feet)
    local charCollisionY = y + height - charCollisionHeight  -- Bottom edge of sprite
    
    -- Sample densely along the bottom edge for accurate collision
    local sampleDensity = 1  -- Sample every pixel for maximum accuracy
    local samplePoints = {}
    
    -- Sample along the bottom edge
    for localX = 0, width - 1, sampleDensity do
        -- Bottom edge
        table.insert(samplePoints, {x + localX, charCollisionY})
        -- One pixel up from bottom (for slightly better coverage)
        if charCollisionHeight > 1 then
            table.insert(samplePoints, {x + localX, charCollisionY + 1})
        end
    end
    
    -- Also check corners more precisely
    table.insert(samplePoints, {x, charCollisionY})  -- Bottom left
    table.insert(samplePoints, {x + width - 1, charCollisionY})  -- Bottom right
    table.insert(samplePoints, {x + math.floor(width * 0.5), charCollisionY})  -- Bottom center
    
    -- Check each rock
    for _, rock in ipairs(self.rocks) do
        -- Quick AABB check first (optimization) - use slightly expanded bounds
        local margin = 2  -- Small margin for AABB check
        if x - margin < rock.x + TILE_SIZE and
           x + width + margin > rock.x and
           charCollisionY - margin < rock.y + TILE_SIZE and
           charCollisionY + charCollisionHeight + margin > rock.y then
            
            -- AABB collision detected, now check pixel-perfect
            for _, point in ipairs(samplePoints) do
                if self:getRockPixel(point[1], point[2], rock) then
                    return true  -- Solid pixel found
                end
            end
        end
    end
    return false
end

function Game:update(dt)
    -- Update camera viewport if screen size changed (for dynamic zoom on small devices)
    if self.camera then
        local screenWidth = love.graphics and love.graphics.getWidth() or nil
        local screenHeight = love.graphics and love.graphics.getHeight() or nil
        if screenWidth and screenHeight then
            local newViewportWidth, newViewportHeight = Camera.calculateViewport(screenWidth, screenHeight)
            -- Only update if viewport size actually changed (avoid unnecessary recalculations)
            if math.abs(self.camera.width - newViewportWidth) > 0.1 or math.abs(self.camera.height - newViewportHeight) > 0.1 then
                self.camera:updateViewport(newViewportWidth, newViewportHeight)
            end
        end
    end
    
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
    
    -- Update local player with collision detection
    if self.player then
        -- Store old position
        local oldX = self.player.x
        local oldY = self.player.y
        
        -- Update player (this will change x, y)
        self.player:update(dt)
        
        -- Check collision with rocks
        if self:checkRockCollision(self.player.x, self.player.y, self.player.width, self.player.height) then
            -- Collision detected, revert to old position
            self.player.x = oldX
            self.player.y = oldY
        end
    end
    
    -- Update pet with collision detection
    if self.pet and not self.pet.isRemote then
        -- Give pet access to collision check function for obstacle avoidance
        self.pet.checkCollision = function(x, y, width, height)
            return self:checkRockCollision(x, y, width, height)
        end
        
        -- Update pet (pet now handles its own collision avoidance)
        self.pet:update(dt)
        
        -- Final safety check - if pet somehow still collides, revert
        if self:checkRockCollision(self.pet.x, self.pet.y, self.pet.width, self.pet.height) then
            -- This shouldn't happen often, but as a safety net, try to find a nearby safe position
            local safeFound = false
            for offset = 1, 8 do
                for angle = 0, math.pi * 2, math.pi / 4 do
                    local tryX = self.pet.x + math.cos(angle) * offset
                    local tryY = self.pet.y + math.sin(angle) * offset
                    if not self:checkRockCollision(tryX, tryY, self.pet.width, self.pet.height) then
                        self.pet.x = tryX
                        self.pet.y = tryY
                        safeFound = true
                        break
                    end
                end
                if safeFound then break end
            end
        end
    elseif self.pet then
        -- Remote pet, just update normally
        self.pet:update(dt)
    end
    
    -- Network updates
    if self.network then
        -- Send position updates (throttled to reduce spam)
        if self.network.sendPosition then
            -- Initialize last sent position if not set (force initial send)
            if not self.lastSentX or not self.lastSentY then
                -- Set to a value that will trigger the first send
                self.lastSentX = self.player.x - 10  -- Force initial send by making it different
                self.lastSentY = self.player.y - 10
                self.lastSentDir = nil  -- Force direction change on first send
                print("Game: Initializing position tracking - player at (" .. math.floor(self.player.x) .. ", " .. math.floor(self.player.y) .. ")")
                -- Send initial position immediately
                print("Game: Sending INITIAL position update - x: " .. math.floor(self.player.x) .. ", y: " .. math.floor(self.player.y) .. ", dir: " .. self.player.direction)
                local success = self.network:sendPosition(self.player.x, self.player.y, self.player.direction)
                if success then
                    self.lastSentX = self.player.x
                    self.lastSentY = self.player.y
                    self.lastSentDir = self.player.direction
                    print("Game: Initial position update sent successfully")
                else
                    print("Game: Failed to send initial position update!")
                end
            end
            
            -- Only send if position changed significantly (more than 2 pixels) or direction changed
            local lastX = self.lastSentX
            local lastY = self.lastSentY
            local lastDir = self.lastSentDir or self.player.direction
            local dx = math.abs(self.player.x - lastX)
            local dy = math.abs(self.player.y - lastY)
            local dirChanged = (self.player.direction ~= lastDir)
            
            -- Log position info occasionally (but only if player is actually moving)
            if not self.positionCheckCount then self.positionCheckCount = 0 end
            self.positionCheckCount = self.positionCheckCount + 1
            -- Only log if there's actual movement or every 2 seconds
            if (dx > 0 or dy > 0 or dirChanged) or (self.positionCheckCount % 120 == 0) then
                print("Game: Position check - player: (" .. math.floor(self.player.x) .. ", " .. math.floor(self.player.y) .. "), lastSent: (" .. math.floor(lastX) .. ", " .. math.floor(lastY) .. "), dx: " .. math.floor(dx) .. ", dy: " .. math.floor(dy) .. ", dirChanged: " .. tostring(dirChanged))
            end
            
            if dx > 2 or dy > 2 or dirChanged then
                print("Game: Sending position update - x: " .. math.floor(self.player.x) .. ", y: " .. math.floor(self.player.y) .. ", dir: " .. self.player.direction)
                local success = self.network:sendPosition(self.player.x, self.player.y, self.player.direction, self.player.spriteName)
                if success then
                    self.lastSentX = self.player.x
                    self.lastSentY = self.player.y
                    self.lastSentDir = self.player.direction
                    print("Game: Position update sent successfully")
                else
                    print("Game: Failed to send position update!")
                end
            end
            
            -- Send pet position updates (throttled)
            if self.pet then
                if not self.lastPetSentX or not self.lastPetSentY then
                    self.lastPetSentX = self.pet.x - 10
                    self.lastPetSentY = self.pet.y - 10
                    -- Send initial pet info with monster type
                    self.network:sendPetPosition(self.playerId, self.pet.x, self.pet.y, self.pet.monsterName)
                end
                local petDx = math.abs(self.pet.x - self.lastPetSentX)
                local petDy = math.abs(self.pet.y - self.lastPetSentY)
                if petDx > 5 or petDy > 5 then
                    self.network:sendPetPosition(self.playerId, self.pet.x, self.pet.y, self.pet.monsterName)
                    self.lastPetSentX = self.pet.x
                    self.lastPetSentY = self.pet.y
                end
            end
        else
            -- Log that sendPosition doesn't exist
            if not self.networkWarningShown then
                print("Game: WARNING - network object has no sendPosition method! Type: " .. (self.network.type or "unknown"))
                print("Game: Network object methods: " .. self:getNetworkMethods(self.network))
                self.networkWarningShown = true
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
    
    -- Update remote pets
    if self.remotePets then
        for _, remotePet in pairs(self.remotePets) do
            remotePet:update(dt)
        end
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
        local posX = msg.x or (WORLD_W / 2)
        local posY = msg.y or (WORLD_H / 2)
        local skin = msg.skin
        print("Player joined: " .. playerId .. " at (" .. posX .. ", " .. posY .. ") with skin: " .. (skin or "default"))
        
        -- If we're the host, send rocks to the new client
        if self.isHost and playerId and playerId ~= self.playerId then
            self:sendRocksToClients()
        end
        
        -- Don't create remote player for ourselves
        if playerId and playerId ~= self.playerId then
            if not self.remotePlayers[playerId] then
                self.remotePlayers[playerId] = RemotePlayer:new(posX, posY, skin)
                print("Created remote player: " .. playerId .. " at (" .. posX .. ", " .. posY .. ")")
            else
                print("Remote player already exists: " .. playerId .. ", updating position to (" .. posX .. ", " .. posY .. ")")
                self.remotePlayers[playerId]:setTargetPosition(posX, posY, "down")
                if skin then
                    self.remotePlayers[playerId]:setSprite(skin)
                end
            end
            -- Create remote pet for this player (monster type will come from pet_moved message)
            if not self.remotePets then self.remotePets = {} end
            if not self.remotePets[playerId] then
                self.remotePets[playerId] = Pet:new(self.remotePlayers[playerId], true, nil)  -- true = isRemote, nil = monster will be set later
                print("Created remote pet for player: " .. playerId)
            end
            -- Hide menu when a player joins (host sees client join, client sees host join)
            -- This matches blockdropper's behavior: hide menu when opponent is discovered
            if self.menu:isVisible() then
                if self.isHost and self.menu.state == Menu.STATE.WAITING then
                    self.menu:hide()
                    print("Host: Player joined! Starting game...")
                elseif not self.isHost then
                    -- Client: hide menu when host's PLAYER_JOIN is received
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
            -- Update skin if provided
            if msg.skin then
                remote:setSprite(msg.skin)
            end
        else
            -- Create remote player if we don't have them yet
            print("Creating remote player on move: " .. playerId)
            self.remotePlayers[playerId] = RemotePlayer:new(msg.x or 400, msg.y or 300, msg.skin)
            remote = self.remotePlayers[playerId]
            if remote then
                remote:setTargetPosition(msg.x, msg.y, msg.dir)
            end
            -- Create remote pet (monster type will come from pet_moved message)
            if not self.remotePets then self.remotePets = {} end
            if not self.remotePets[playerId] then
                self.remotePets[playerId] = Pet:new(remote, true, nil)  -- true = isRemote, nil = monster will be set later
            end
        end
        
    elseif msg.type == "pet_moved" then
        local playerId = msg.id or msg.playerId
        if playerId and playerId ~= self.playerId then
            if not self.remotePets then self.remotePets = {} end
            local remotePet = self.remotePets[playerId]
            if remotePet then
                if msg.x and msg.y then
                    -- Smoothly interpolate to target position (similar to remote player)
                    remotePet.targetX = msg.x
                    remotePet.targetY = msg.y
                end
                -- Update monster type if provided
                if msg.monster then
                    remotePet:setMonster(msg.monster)
                end
            else
                -- Create remote pet if it doesn't exist yet
                local owner = self.remotePlayers[playerId]
                if owner then
                    self.remotePets[playerId] = Pet:new(owner, true, msg.monster)  -- true = isRemote
                    self.remotePets[playerId].targetX = msg.x or owner.x
                    self.remotePets[playerId].targetY = msg.y or owner.y
                end
            end
        end
        
    elseif msg.type == "player_left" then
        local playerId = msg.id or msg.playerId
        print("Player left: " .. (playerId or "unknown"))
        if playerId then
            self.remotePlayers[playerId] = nil
            if self.remotePets then
                self.remotePets[playerId] = nil
            end
        end
    elseif msg.type == "connected" then
        print("WebSocket connected: " .. (msg.playerId or "unknown"))
        if msg.playerId then
            self.playerId = msg.playerId
            if self.network then
                self.network.playerId = msg.playerId
            end
        end
        
    elseif msg.type == Protocol.MSG.ROCKS_DATA or msg.type == "rocks" then
        -- Receive rocks data from host
        print("Received rocks data: " .. (msg.count or 0) .. " rocks")
        if msg.rocks then
            self.rocks = msg.rocks
            -- Ensure all rocks have actualTileNum and valid structure
            for _, rock in ipairs(self.rocks) do
                if not rock.actualTileNum and self.validTileToActual then
                    rock.actualTileNum = self.validTileToActual[rock.tileId] or 1
                end
                -- Ensure x, y, and tileId are valid numbers
                rock.x = tonumber(rock.x) or 0
                rock.y = tonumber(rock.y) or 0
                rock.tileId = tonumber(rock.tileId) or 1
            end
            print("Set " .. #self.rocks .. " rocks from host")
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
    
    -- Rocks (drawn before entities, but Y-sorted with them)
    if self.rocks and #self.rocks > 0 then
        for _, rock in ipairs(self.rocks) do
            -- Ensure rock has valid data
            if rock and rock.x and rock.y and rock.tileId then
                -- Use bottom of rock (rock.y + 16) for Y-sorting to match depth correctly
                -- This ensures objects with higher Y values (lower on screen) are drawn on top
                -- Force integer values to avoid floating point precision issues
                local sortY = math.floor(rock.y) + 16  -- Bottom of 16x16 tile
                table.insert(drawList, { 
                    type = "rock",
                    x = math.floor(rock.x), 
                    y = sortY,  -- Bottom of rock for proper depth sorting
                    tileId = rock.tileId,
                    originalY = math.floor(rock.y)  -- Store original Y for drawing
                })
            end
        end
    end
    
    -- Local player - use bottom of sprite for consistent depth sorting with rocks
    table.insert(drawList, { entity = self.player, y = self.player.y + (self.player.height or 16) })
    
    -- Pet - use bottom of sprite for consistent depth sorting with rocks
    table.insert(drawList, { entity = self.pet, y = self.pet.y + (self.pet.height or 16) })
    
    -- Remote players - use bottom of sprite for consistent depth sorting with rocks
    for _, remote in pairs(self.remotePlayers) do
        table.insert(drawList, { entity = remote, y = remote.y + (remote.height or 16) })
    end
    
    -- Remote pets - use bottom of sprite for consistent depth sorting with rocks
    if self.remotePets then
        for _, remotePet in pairs(self.remotePets) do
            table.insert(drawList, { entity = remotePet, y = remotePet.y + (remotePet.height or 16) })
        end
    end
    
    -- NPCs - use bottom of sprite for consistent depth sorting with rocks
    for _, npc in ipairs(self.npcs) do
        table.insert(drawList, { entity = npc, y = npc.y + (npc.height or 16) })
    end
    
    -- Sort by Y
    table.sort(drawList, function(a, b) return a.y < b.y end)
    
    -- Draw entities and rocks
    local rocksDrawn = 0
    for _, item in ipairs(drawList) do
        if item.type == "rock" then
            -- Draw rock - all rocks use the same drawing logic regardless of tile type
            if self.rocksImage and self.rocksQuads and self.rocksQuads[item.tileId] then
                love.graphics.setColor(1, 1, 1, 1)
                -- Use originalY if stored, otherwise calculate from sort Y
                local drawY = item.originalY or (item.y - 12)
                love.graphics.draw(
                    self.rocksImage,
                    self.rocksQuads[item.tileId],
                    item.x,
                    drawY
                )
                rocksDrawn = rocksDrawn + 1
            else
                -- Debug: draw a red rectangle if rock image/quads are missing
                if not self.rocksImage then
                    print("WARNING: rocksImage is nil!")
                end
                if not self.rocksQuads then
                    print("WARNING: rocksQuads is nil!")
                elseif not self.rocksQuads[item.tileId] then
                    print("WARNING: rocksQuads[" .. item.tileId .. "] is nil! (total quads: " .. #self.rocksQuads .. ")")
                end
                love.graphics.setColor(1, 0, 0, 1)  -- Red fallback
                love.graphics.rectangle("fill", item.x, item.y - 12, 16, 16)
                love.graphics.setColor(1, 1, 1, 1)
            end
        elseif item.entity then
            -- Draw entity (item.y is y + originY, but entity.draw() uses entity.y which is top Y)
            -- No adjustment needed - entities draw from their top Y position
            item.entity:draw()
        end
    end
    
    -- Debug output (only occasionally)
    if not self.lastRocksDebugTime then self.lastRocksDebugTime = 0 end
    local currentTime = love.timer and love.timer.getTime() or 0
    if currentTime - self.lastRocksDebugTime > 2 then  -- Print every 2 seconds
        print("Drawing: " .. rocksDrawn .. " rocks (total: " .. (#self.rocks or 0) .. ")")
        if rocksDrawn == 0 and (#self.rocks or 0) > 0 then
            print("WARNING: Rocks exist but none are being drawn! Check camera/viewport.")
        end
        self.lastRocksDebugTime = currentTime
    end
    
    -- Reset graphics state to prevent artifacts
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    
    self.camera:detach()
end

-- Draw UI elements at native resolution (called outside of scale transform)
function Game:drawUI()
    -- Dialogue renders at native resolution for crisp text
    self.dialogue:draw()
    
    -- Menu renders at native resolution for crisp text
    self.menu:draw()
    
    -- Reset graphics state to prevent artifacts
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

function Game:drawStoneFloor()
    -- Check if tileset is loaded
    if not self.tilesetImage then
        print("WARNING: tilesetImage is nil! Drawing fallback green tiles.")
        -- Draw fallback green rectangles
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
        -- Use the rounded camera position (matching Camera:attach() rounding) to avoid gaps
        local cameraX = math.floor(self.camera.x + 0.5)
        local cameraY = math.floor(self.camera.y + 0.5)
        -- Calculate tile bounds with generous margin to prevent black bars
        local margin = 3  -- Increased margin for better coverage
        local startX = math.floor((cameraX - margin * TILE_SIZE) / TILE_SIZE)
        local startY = math.floor((cameraY - margin * TILE_SIZE) / TILE_SIZE)
        local endX = math.ceil((cameraX + self.camera.width + margin * TILE_SIZE) / TILE_SIZE)
        local endY = math.ceil((cameraY + self.camera.height + margin * TILE_SIZE) / TILE_SIZE)
        startX = math.max(0, startX)
        startY = math.max(0, startY)
        endX = math.min(math.ceil(WORLD_W / TILE_SIZE) - 1, endX)
        endY = math.min(math.ceil(WORLD_H / TILE_SIZE) - 1, endY)
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
    if not self.tileQuads then
        print("WARNING: tileQuads is nil! Drawing fallback green tiles.")
        -- Draw fallback green rectangles
        love.graphics.setColor(0.2, 0.6, 0.2, 1)
        -- Use the rounded camera position (matching Camera:attach() rounding) to avoid gaps
        local cameraX = math.floor(self.camera.x + 0.5)
        local cameraY = math.floor(self.camera.y + 0.5)
        -- Calculate tile bounds with generous margin to prevent black bars
        local margin = 3  -- Increased margin for better coverage
        local startX = math.floor((cameraX - margin * TILE_SIZE) / TILE_SIZE)
        local startY = math.floor((cameraY - margin * TILE_SIZE) / TILE_SIZE)
        local endX = math.ceil((cameraX + self.camera.width + margin * TILE_SIZE) / TILE_SIZE)
        local endY = math.ceil((cameraY + self.camera.height + margin * TILE_SIZE) / TILE_SIZE)
        startX = math.max(0, startX)
        startY = math.max(0, startY)
        endX = math.min(math.ceil(WORLD_W / TILE_SIZE) - 1, endX)
        endY = math.min(math.ceil(WORLD_H / TILE_SIZE) - 1, endY)
        for ty = startY, endY do
            for tx = startX, endX do
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    
    -- Calculate visible tile range
    -- Use the rounded camera position (matching Camera:attach() rounding) to avoid gaps
    local cameraX = math.floor(self.camera.x + 0.5)
    local cameraY = math.floor(self.camera.y + 0.5)
    
    -- Calculate tile bounds with generous margin to prevent black bars
    -- The margin accounts for camera rounding and smooth camera movement
    local margin = 3  -- Increased margin for better coverage
    local startX = math.floor((cameraX - margin * TILE_SIZE) / TILE_SIZE)
    local startY = math.floor((cameraY - margin * TILE_SIZE) / TILE_SIZE)
    local endX = math.ceil((cameraX + self.camera.width + margin * TILE_SIZE) / TILE_SIZE)
    local endY = math.ceil((cameraY + self.camera.height + margin * TILE_SIZE) / TILE_SIZE)
    
    -- Clamp to world bounds
    startX = math.max(0, startX)
    startY = math.max(0, startY)
    endX = math.min(math.ceil(WORLD_W / TILE_SIZE) - 1, endX)
    endY = math.min(math.ceil(WORLD_H / TILE_SIZE) - 1, endY)
    
    -- Draw tiles
    love.graphics.setColor(1, 1, 1, 1)
    local tilesDrawn = 0
    for ty = startY, endY do
        for tx = startX, endX do
            local tileIdx = 1
            if self.tileMap and self.tileMap[ty] and self.tileMap[ty][tx] then
                tileIdx = self.tileMap[ty][tx]
            end
            
            -- Draw using the quad for the selected tile variation
            local quad = self.tileQuads[tileIdx]
            if quad and self.tilesetImage then
                love.graphics.draw(
                    self.tilesetImage,
                    quad,
                    tx * TILE_SIZE,
                    ty * TILE_SIZE
                )
                tilesDrawn = tilesDrawn + 1
            else
                -- Fallback: draw a green rectangle if quad is missing
                love.graphics.setColor(0.2, 0.6, 0.2, 1)
                love.graphics.rectangle("fill", tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end
    
    -- Debug output (only print occasionally to avoid spam)
    if not self.lastTileDebugTime then self.lastTileDebugTime = 0 end
    local currentTime = love.timer and love.timer.getTime() or 0
    if currentTime - self.lastTileDebugTime > 2 then  -- Print every 2 seconds
        print("Drew " .. tilesDrawn .. " tiles. Camera: (" .. math.floor(self.camera.x) .. ", " .. math.floor(self.camera.y) .. ")")
        self.lastTileDebugTime = currentTime
    end
end

function Game:countRemotePlayers()
    local count = 0
    for _ in pairs(self.remotePlayers) do count = count + 1 end
    return count
end

-- Helper to debug network object
function Game:getNetworkMethods(obj)
    local methods = {}
    for k, v in pairs(obj) do
        if type(v) == "function" then
            table.insert(methods, k)
        end
    end
    return table.concat(methods, ", ")
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

function Game:autoJoinOrCreateServer()
    -- Only try auto-join if online multiplayer is available
    local OnlineClient = require('src.net.online_client')
    if not OnlineClient.isAvailable() then
        print("Game: Online multiplayer not available, skipping auto-join")
        return
    end
    
    print("Game: Attempting to auto-join or create server...")
    
    -- Try to list available rooms
    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        print("Game: Failed to initialize online client for auto-join")
        return
    end
    
    local rooms = onlineClient:listRooms()
    print("Game: Found " .. #rooms .. " available rooms")
    
    -- Find a room with space
    local roomToJoin = nil
    for _, room in ipairs(rooms) do
        if room.players and room.maxPlayers and room.players < room.maxPlayers then
            roomToJoin = room
            print("Game: Found room with space: " .. room.code .. " (" .. room.players .. "/" .. room.maxPlayers .. ")")
            break
        end
    end
    
    if roomToJoin then
        -- Join the room with space
        print("Game: Auto-joining room: " .. roomToJoin.code)
        ConnectionManager.joinOnline(roomToJoin.code, self)
    else
        -- No rooms with space, create a new public room
        print("Game: No rooms with space available, creating new public room...")
        ConnectionManager.hostOnline(true, self)  -- true = isPublic
    end
end

return Game
