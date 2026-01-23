-- src/game/renderer.lua
-- Main rendering system for the game

local Renderer = {}
local Constants = require('src.constants')
local ObjectPool = require('src.utils.object_pool')

-- Object pool for draw list items to reduce GC pressure
local drawListPool = ObjectPool:new(
    function() return {} end,  -- Create new table
    function(obj)  -- Reset function
        obj.type = nil
        obj.entity = nil
        obj.x = nil
        obj.y = nil
        obj.originalY = nil
        obj.width = nil
        obj.height = nil
        obj.treeType = nil
        obj.tileId = nil
    end,
    100  -- Pre-allocate 100 items
)

-- Reusable draw list (cleared each frame instead of recreated)
local drawList = {}

local depthShader = nil
local function getDepthShader()
    if not depthShader then
        local success, shader = pcall(love.graphics.newShader, "src/shaders/depth_alpha.glsl")
        if success then
            depthShader = shader
        else
            print("Error loading depth shader:", shader)
        end
    end
    return depthShader
end

function Renderer.collectDrawList(game)
    -- Clear the reusable draw list (don't create new table)
    for i = #drawList, 1, -1 do
        drawList[i] = nil
    end
    
    local drawListIndex = 1
    
    -- Helper to add item to draw list
    local function addItem(itemData)
        drawList[drawListIndex] = itemData
        drawListIndex = drawListIndex + 1
    end
    
    -- Trees (use world cache if available, fallback to chunk system)
    local treeDrawList = game.world:getTreesForDrawing(game.chunkManager, game.camera, game.worldCache)
    for _, treeItem in ipairs(treeDrawList) do
        addItem(treeItem)
    end

    -- Rocks (use world cache if available, fallback to chunk system)
    local rockDrawList = game.world:getRocksForDrawing(game.chunkManager, game.camera, game.worldCache)
    for _, rockItem in ipairs(rockDrawList) do
        addItem(rockItem)
    end
    
    -- Player
    if game.player and game.player.x and game.player.y then
        local item = drawListPool:acquire()
        item.entity = game.player
        item.y = (game.player.y or 0) + (game.player.height or 16)
        addItem(item)
    end
    
    -- Pet
    if game.pet and game.pet.x and game.pet.y then
        local item = drawListPool:acquire()
        item.entity = game.pet
        item.y = (game.pet.y or 0) + (game.pet.height or 16)
        addItem(item)
    end
    
    -- Remote players
    for _, remote in pairs(game.remotePlayers) do
        local item = drawListPool:acquire()
        item.entity = remote
        item.y = remote.y + (remote.height or 16)
        addItem(item)
    end
    
    -- Remote pets
    if game.remotePets then
        for _, remotePet in pairs(game.remotePets) do
            local item = drawListPool:acquire()
            item.entity = remotePet
            item.y = remotePet.y + (remotePet.height or 16)
            addItem(item)
        end
    end
    
    -- NPCs (use world cache for spatial filtering when available)
    local cameraCenterX = game.camera and (game.camera.x + game.camera.width/2) or 0
    local cameraCenterY = game.camera and (game.camera.y + game.camera.height/2) or 0
    local viewRadius = 400  -- Draw NPCs within 400 pixels of camera

    local nearbyNPCs = {}
    if game.worldCache and game.worldCache:isReady() then
        -- Use world cache for spatial queries
        nearbyNPCs = game.worldCache:getNearbyNPCs(cameraCenterX, cameraCenterY, viewRadius)
    else
        -- Fallback to chunk-based filtering
        for _, npc in ipairs(game.npcs or {}) do
            if not game.chunkManager or game.chunkManager:isPositionActive(npc.x, npc.y) then
                table.insert(nearbyNPCs, npc)
            end
        end
    end

    -- Limit NPCs drawn on MIYO to reduce CPU usage
    if Constants.MIYOO_DEVICE and #nearbyNPCs > 5 then
        table.sort(nearbyNPCs, function(a, b)
            local distA = (a.x - cameraCenterX)^2 + (a.y - cameraCenterY)^2
            local distB = (b.x - cameraCenterX)^2 + (b.y - cameraCenterY)^2
            return distA < distB
        end)
        -- Keep only the closest 5 NPCs
        local limitedNPCs = {}
        for i = 1, math.min(5, #nearbyNPCs) do
            limitedNPCs[i] = nearbyNPCs[i]
        end
        nearbyNPCs = limitedNPCs
    end

    for _, npc in ipairs(nearbyNPCs) do
        local item = drawListPool:acquire()
        item.entity = npc
        item.y = npc.y + (npc.height or 16)
        addItem(item)
    end

    -- Animals (use world cache for spatial filtering when available)
    local nearbyAnimals = {}
    if game.worldCache and game.worldCache:isReady() then
        -- Use world cache for spatial queries
        nearbyAnimals = game.worldCache:getNearbyAnimals(cameraCenterX, cameraCenterY, viewRadius)
    else
        -- Fallback to chunk-based filtering
        for _, animal in ipairs(game.animals or {}) do
            if not game.chunkManager or game.chunkManager:isPositionActive(animal.x, animal.y) then
                table.insert(nearbyAnimals, animal)
            end
        end
    end

    -- Limit animals drawn on MIYO to reduce CPU usage
    if Constants.MIYOO_DEVICE and #nearbyAnimals > 10 then
        table.sort(nearbyAnimals, function(a, b)
            local distA = (a.x - cameraCenterX)^2 + (a.y - cameraCenterY)^2
            local distB = (b.x - cameraCenterX)^2 + (b.y - cameraCenterY)^2
            return distA < distB
        end)
        -- Keep only the closest 10 animals
        local limitedAnimals = {}
        for i = 1, math.min(10, #nearbyAnimals) do
            limitedAnimals[i] = nearbyAnimals[i]
        end
        nearbyAnimals = limitedAnimals
    end

    for _, animal in ipairs(nearbyAnimals) do
        local item = drawListPool:acquire()
        item.entity = animal
        item.y = animal.y + (animal.height or 16)
        addItem(item)
    end
    
    -- Sort by Y position for depth ordering
    table.sort(drawList, function(a, b) return a.y < b.y end)
    
    return drawList
end

local function entityCenter(e)
    return (e.x or 0) + (e.width or 16) / 2, (e.y or 0) + (e.height or 16) / 2
end



function Renderer.drawWorld(game)
    if not game.camera then return end
    
    -- Calculate saturation based on timer
    local saturation = 1.0  -- Full color by default
    local useShader = false
    
    if Constants.ENABLE_DESATURATION_EFFECT and game.desaturationShader and game.cycleTime then
        if game.cycleTime.timeRemaining and game.cycleTime.duration then
            -- Calculate time remaining (accounting for client-side interpolation)
            local serverTimeRemaining = game.cycleTime.timeRemaining / 1000
            local timeSinceUpdate = love.timer.getTime() - (game.cycleTime.lastUpdate or 0)
            local timeRemaining = math.max(0, serverTimeRemaining - timeSinceUpdate)
            local duration = game.cycleTime.duration / 1000
            
            -- Calculate saturation: 0 = black and white, 1 = full color
            -- When timer is at 0, saturation is 0 (black and white)
            -- When timer is at full duration, saturation is 1 (full color)
            if duration > 0 then
                saturation = math.max(0, math.min(1, timeRemaining / duration))
                useShader = true
            end
        end
    end
    
    -- If using shader, render to canvas first
    if useShader and game.worldCanvas then
        -- Ensure canvas size matches viewport
        local canvasWidth = math.ceil(game.camera.width)
        local canvasHeight = math.ceil(game.camera.height)
        local currentCanvasWidth = game.worldCanvas:getWidth()
        local currentCanvasHeight = game.worldCanvas:getHeight()
        
        if currentCanvasWidth ~= canvasWidth or currentCanvasHeight ~= canvasHeight then
            -- Create canvas with depth buffer support
            game.worldCanvas = love.graphics.newCanvas(canvasWidth, canvasHeight, {
                format = "normal",
                readable = true,
                msaa = 0,
                type = "2d",
                mipmaps = "none"
            })
            game.worldCanvas:setFilter("nearest", "nearest")
        end
        
        -- Render world to canvas WITHOUT global scaling from main.lua
        love.graphics.setCanvas(game.worldCanvas)
        love.graphics.clear(0, 0, 0, 0)

        love.graphics.push()
        love.graphics.origin() -- Reset global scale/translate so we draw 1:1 to canvas

        -- Render world content directly to canvas (no camera transform yet)
        -- We need to manually offset by camera position
        -- Render world content directly to canvas with camera transform
        game.camera:attach()
        
        game.world:drawFloor(game.camera, game.worldCache)
        
        local drawList = Renderer.collectDrawList(game)
        
        -- Draw all entities in sorted order
        for _, item in ipairs(drawList) do
            if item.type == "rock" then
                game.world:drawRock(item)
            elseif item.type == "tree" then
                game.world:drawTree(item)
            elseif item.entity then
                if type(item.entity.draw) == "function" then
                    item.entity:draw()
                else
                    -- Fallback or warning if entity has no draw method
                    -- print("Warning: Entity in drawList missing draw method", item.entity.type or "unknown")
                end
            end
        end

        local BoonSnatchRenderer = require('src.gamemodes.boonsnatch.renderer')
        BoonSnatchRenderer.drawGameState(game.gameState, game)
        
        game.camera:detach()
        love.graphics.pop() -- Restore global scale for final draw
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
        love.graphics.setCanvas()
        
        -- Draw canvas with shader applied (in screen space, no camera transform needed)
        local DesaturationShader = require('src.systems.desaturation_shader')
        DesaturationShader.setSaturation(game.desaturationShader, saturation)
        
        love.graphics.setShader(game.desaturationShader)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(game.worldCanvas, 0, 0)
        love.graphics.setShader()
    else
        -- Normal rendering without shader (Main Screen)
        game.camera:attach()
        
        game.world:drawFloor(game.camera, game.worldCache)
        
        local drawList = Renderer.collectDrawList(game)
        
        -- Draw all entities in sorted order
        for _, item in ipairs(drawList) do
            if item.type == "rock" then
                game.world:drawRock(item)
            elseif item.type == "tree" then
                game.world:drawTree(item)
            elseif item.entity then
                if type(item.entity.draw) == "function" then
                    item.entity:draw()
                else
                    -- Fallback or warning
                end
            end
        end
        
        local BoonSnatchRenderer = require('src.gamemodes.boonsnatch.renderer')
        BoonSnatchRenderer.drawGameState(game.gameState, game)
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
        
        game.camera:detach()
    end
end

function Renderer.drawCycleTimer(game)
    if not game.cycleTime or not game.cycleTime.timeRemaining then
        return
    end

    local serverTimeRemaining = game.cycleTime.timeRemaining / 1000
    local timeSinceUpdate = love.timer.getTime() - (game.cycleTime.lastUpdate or 0)
    local timeRemaining = math.max(0, serverTimeRemaining - timeSinceUpdate)

    local minutes = math.floor(timeRemaining / 60)
    local seconds = math.floor(timeRemaining % 60)
    local timeString = string.format("%02d:%02d", minutes, seconds)

    local fps = love.timer.getFPS()

    -- Get player coordinates
    local playerX = game.player and game.player.x and math.floor(game.player.x) or 0
    local playerY = game.player and game.player.y and math.floor(game.player.y) or 0

    -- Get ping from network client
    local ping = 0
    if game.network and game.network.client then
        local quality, avgPing = game.network.client:getConnectionQuality()
        if avgPing and avgPing > 0 then
            ping = math.floor(avgPing)
        elseif game.network.client.testPing then
            -- If we have no ping data yet, try to trigger a ping test
            game.network.client:testPing()
        end
    end

    -- Format as "time X: x Y: y fps/ping"
    local displayString = string.format("%s X: %d Y: %d %d/%d", timeString, playerX, playerY, fps, ping)

    local padding = 10
    local x = padding
    local y = padding

    if timeRemaining < 120 then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end

    if game.timerFont then
        love.graphics.setFont(game.timerFont)
    end
    love.graphics.print(displayString, x, y)

    love.graphics.setColor(1, 1, 1, 1)
end

function Renderer.drawUI(game)
    Renderer.drawCycleTimer(game)
    
    game.dialogue:draw()
    game.menu:draw()
    
    local Interaction = require('src.game.interaction')
    Interaction.drawInteractionPrompt(game)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return Renderer
