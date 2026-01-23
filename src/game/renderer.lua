-- src/game/renderer.lua
-- Main rendering system for the game

local Renderer = {}
local Constants = require('src.constants')

function Renderer.collectDrawList(game)
    local drawList = {}
    
    local rockDrawList = game.world:getRocksForDrawing(game.chunkManager, game.camera)
    for _, rockItem in ipairs(rockDrawList) do
        table.insert(drawList, rockItem)
    end
    
    if game.player and game.player.x and game.player.y then
        table.insert(drawList, { entity = game.player, y = (game.player.y or 0) + (game.player.height or 16) })
    end
    
    if game.pet and game.pet.x and game.pet.y then
        table.insert(drawList, { entity = game.pet, y = (game.pet.y or 0) + (game.pet.height or 16) })
    end
    
    for _, remote in pairs(game.remotePlayers) do
        table.insert(drawList, { entity = remote, y = remote.y + (remote.height or 16) })
    end
    
    if game.remotePets then
        for _, remotePet in pairs(game.remotePets) do
            table.insert(drawList, { entity = remotePet, y = remotePet.y + (remotePet.height or 16) })
        end
    end
    
    for _, npc in ipairs(game.npcs) do
        if not game.chunkManager or game.chunkManager:isPositionActive(npc.x, npc.y) then
            table.insert(drawList, { entity = npc, y = npc.y + (npc.height or 16) })
        end
    end
    
    for _, animal in ipairs(game.animals) do
        if not game.chunkManager or game.chunkManager:isPositionActive(animal.x, animal.y) then
            table.insert(drawList, { entity = animal, y = animal.y + (animal.height or 16) })
        end
    end
    
    table.sort(drawList, function(a, b) return a.y < b.y end)
    
    return drawList
end

local function entityCenter(e)
    return (e.x or 0) + (e.width or 16) / 2, (e.y or 0) + (e.height or 16) / 2
end

local function drawDevModeNPCLines(game)
    if not Constants.DEV_MODE then return end

    local points = {}
    local function add(e)
        if e and e.x and e.y then
            local x, y = entityCenter(e)
            table.insert(points, { x, y })
        end
    end

    -- Only speakable, static NPCs (no animals, remotes, player, pet)
    -- Include all NPCs (no chunk filter) so lines span the map and help locate them
    if game.npcs then
        for _, n in ipairs(game.npcs) do
            add(n)
        end
    end

    if #points < 2 then return end

    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.setLineWidth(1)
    for i = 1, #points - 1 do
        for j = i + 1, #points do
            love.graphics.line(points[i][1], points[i][2], points[j][1], points[j][2])
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
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
            game.worldCanvas = love.graphics.newCanvas(canvasWidth, canvasHeight)
            game.worldCanvas:setFilter("nearest", "nearest")
        end
        
        -- Render world to canvas WITHOUT camera transformations first
        -- We'll apply camera transform when drawing the canvas
        love.graphics.setCanvas(game.worldCanvas)
        love.graphics.clear()
        
        -- Render world content directly to canvas (no camera transform yet)
        -- We need to manually offset by camera position
        love.graphics.push()
        love.graphics.translate(-math.floor(game.camera.x + 0.5), -math.floor(game.camera.y + 0.5))
        
        game.world:drawFloor(game.camera)
        
        local drawList = Renderer.collectDrawList(game)
        
        for _, item in ipairs(drawList) do
            if item.type == "rock" then
                game.world:drawRock(item)
            elseif item.entity then
                item.entity:draw()
            end
        end
        
        local BoonSnatchRenderer = require('src.gamemodes.boonsnatch.renderer')
        BoonSnatchRenderer.drawGameState(game.gameState, game)
        
        drawDevModeNPCLines(game)
        
        love.graphics.pop()
        
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(1)
        love.graphics.setCanvas()
        
        -- Draw canvas with shader applied, using camera transformation
        local DesaturationShader = require('src.systems.desaturation_shader')
        DesaturationShader.setSaturation(game.desaturationShader, saturation)
        
        game.camera:attach()
        love.graphics.setShader(game.desaturationShader)
        love.graphics.setColor(1, 1, 1, 1)
        -- Draw canvas at origin - camera transform will position it correctly
        love.graphics.draw(game.worldCanvas, 0, 0)
        love.graphics.setShader()
        game.camera:detach()
    else
        -- Normal rendering without shader
        game.camera:attach()
        
        game.world:drawFloor(game.camera)
        
        local drawList = Renderer.collectDrawList(game)
        
        for _, item in ipairs(drawList) do
            if item.type == "rock" then
                game.world:drawRock(item)
            elseif item.entity then
                item.entity:draw()
            end
        end
        
        local BoonSnatchRenderer = require('src.gamemodes.boonsnatch.renderer')
        BoonSnatchRenderer.drawGameState(game.gameState, game)
        
        drawDevModeNPCLines(game)
        
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
