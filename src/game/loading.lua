-- src/game/loading.lua
-- Loading screen and deferred loading logic

local Loading = {}
local WorldCache = require('src.world.world_cache')

function Loading.draw(loadingProgress, loadingMessage, timerFont)
    love.graphics.setColor(0.05, 0.05, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    local font = timerFont or love.graphics.getFont()
    love.graphics.setFont(font)

    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()

    -- Use world cache progress if available and more detailed
    local displayProgress = loadingProgress or 0
    local displayMessage = loadingMessage or "Loading..."

    -- Check if we have a world cache with more detailed progress
    if _G.game and _G.game.worldCache and not _G.game.worldCache:isReady() then
        displayProgress = _G.game.worldCache:getLoadProgress()
        displayMessage = _G.game.worldCache:getLoadMessage()
    end

    local text = displayMessage
    local progress = displayProgress

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
    local startTime = love.timer.getTime()

    -- Temporarily remove pcall to see if there are errors
    game.loadingMessage = "Initializing world cache..."
    game.loadingProgress = 0.1

    -- Initialize world cache for MIYO optimization
    if not game.worldCache then
        game.worldCache = WorldCache:new()
    end

    -- Check initial memory
    local memBefore = collectgarbage("count")

    game.loadingMessage = "Downloading world data..."
    game.loadingProgress = 0.2

    -- Download complete world data for MIYO performance
    -- On desktop, this provides consistency; on MIYO, it's critical for performance
    local downloadStart = love.timer.getTime()
    local Constants = require('src.constants')

    -- For MIYO, we might want to skip world cache entirely if it's causing issues
    local skipWorldCache = Constants.MIYOO_DEVICE and os.getenv("SKIP_WORLD_CACHE") == "1"
    local cacheSuccess = false

    if skipWorldCache then
        game.loadingMessage = "Skipping world download..."
        game.loadingProgress = 0.5
    else
        cacheSuccess = game.worldCache:downloadWorldData()
    end

    local downloadTime = love.timer.getTime() - downloadStart

    if cacheSuccess then
        game.loadingMessage = "World data loaded!"
        game.loadingProgress = 0.6

        -- Check memory after download
        local memAfterDownload = collectgarbage("count")

    else
        -- Fallback: continue without cached world data
        print("WARNING: Failed to download world cache, falling back to streaming")
        game.loadingMessage = "World download failed, using streaming..."
        game.loadingProgress = 0.4
    end

    game.loadingMessage = "Loading entities..."
    game.loadingProgress = 0.7

    local NetworkAdapter = require('src.net.network_adapter')
    local isLANHost = game.network and game.network.type == NetworkAdapter.TYPE.LAN and game.isHost
    local isNotConnected = not game.network

    if isLANHost or isNotConnected then
        -- For local games, create NPCs and animals locally (if not using cache)
        if not game.worldCache:isReady() then
            game.loadingMessage = "Creating NPCs..."
            game.loadingProgress = 0.8
            game:createNPCs()
        end
    else
        -- For networked games, NPCs and animals come from server state or cache
        game.loadingMessage = "Connecting to server..."
        game.loadingProgress = 0.8
    end

    game.loadingMessage = "Finalizing..."
    game.loadingProgress = 0.9

    -- Check final memory
    local memFinal = collectgarbage("count")

    -- Network connection moved to after loading completes
    -- This prevents freeze on low-powered devices like Miyoo

    game.loadingProgress = 1.0
    game.loadingComplete = true
    game.loadingMessage = "Ready!"

    local totalTime = love.timer.getTime() - startTime

    local Audio = require('src.systems.audio')
    pcall(function()
        Audio:init()
        Audio:playBGM()
    end)
end

return Loading
