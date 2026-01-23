-- src/game/loading.lua
-- Loading screen and deferred loading logic

local Loading = {}

function Loading.draw(loadingProgress, loadingMessage, timerFont)
    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    
    local font = timerFont or love.graphics.getFont()
    love.graphics.setFont(font)
    
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local text = loadingMessage or "Loading..."
    
    love.graphics.setColor(0, 0, 0, 0.8)
    local textW = font:getWidth(text)
    local textX = (screenW - textW) / 2
    local textY = screenH / 2 - 30
    love.graphics.print(text, textX + 1, textY + 1)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, textX, textY)
    
    local barW = math.min(250, screenW - 40)
    local barH = 12
    local barX = (screenW - barW) / 2
    local barY = screenH / 2 + 10
    
    love.graphics.setColor(0.2, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", barX - 2, barY - 2, barW + 4, barH + 4)
    
    local progress = loadingProgress or 0
    local progressW = barW * progress
    love.graphics.setColor(0.3, 0.7, 1, 1)
    love.graphics.rectangle("fill", barX, barY, progressW, barH)
    
    local progressText = math.floor(progress * 100) .. "%"
    local progressTextW = font:getWidth(progressText)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(progressText, (screenW - progressTextW) / 2, barY + barH + 5)
    
    love.graphics.setColor(1, 1, 1, 1)
end

function Loading.complete(game)
    pcall(function()
        game.loadingMessage = "Loading entities..."
        game.loadingProgress = 0.4
        
        local NetworkAdapter = require('src.net.network_adapter')
        local isLANHost = game.network and game.network.type == NetworkAdapter.TYPE.LAN and game.isHost
        local isNotConnected = not game.network
        
        if isLANHost or isNotConnected then
            -- For local games, create NPCs and animals locally
            game.loadingMessage = "Creating NPCs..."
            game.loadingProgress = 0.5
            game:createNPCs()

            game.loadingMessage = "Creating animals..."
            game.loadingProgress = 0.65
            game:createAnimalGroups()
        else
            -- For networked games, NPCs and animals come from server state
            game.loadingMessage = "Waiting for server..."
            game.loadingProgress = 0.65
        end
        
        game.loadingMessage = "Finalizing..."
        game.loadingProgress = 0.8

        -- Generate roads connecting key locations
        game.loadingMessage = "Building roads..."
        game.loadingProgress = 0.85
        game:generateWorldRoads()

        game.loadingMessage = "Connecting..."
        game.loadingProgress = 0.9
        
        pcall(function()
            game:autoJoinOrCreateServer()
        end)
        
        game.loadingProgress = 1.0
        game.loadingComplete = true
        game.loadingMessage = "Ready!"
        
        local Audio = require('src.systems.audio')
        pcall(function()
            Audio:init()
            Audio:playBGM()
        end)
    end)
    
    if not game.loadingComplete then
        game.loadingComplete = true
        game.loadingMessage = "Ready!"
    end
end

return Loading
