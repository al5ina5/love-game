-- main.lua
-- Pixel Raiders game

local Game = require('src.game')

-- Frame timing for Miyoo optimization
local Constants = require('src.constants')
local targetFPS = Constants.MIYOO_TARGET_FPS
local targetDT = 1 / targetFPS
local accumulator = 0
local lastTime = 0
local frameSleepEnabled = Constants.MIYOO_FRAME_SLEEP_ENABLED

-- Memory optimization for Miyoo
if Constants.MIYOO_DEVICE then
    -- Reduce GC pressure on Miyoo with limited RAM
    collectgarbage("setpause", 200)  -- Increase pause between GC cycles (default 200)
    collectgarbage("setstepmul", 200)  -- Reduce GC step multiplier (default 200)
end

function love.load()
    -- Pixel-art friendly graphics settings
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Set window title
    love.window.setTitle("Pixel Raiders")

    -- Initialize frame timing
    lastTime = love.timer.getTime()

    -- Initialize game
    Game:load()
end

function love.update(dt)
    -- Fixed timestep updates for consistent gameplay
    -- This prevents stuttering from variable frame times
    accumulator = accumulator + dt

    -- Update in fixed time steps to ensure consistent gameplay
    while accumulator >= targetDT do
        Game:update(targetDT)
        accumulator = accumulator - targetDT
    end

    -- Prevent accumulator from getting too large (spiral of death)
    if accumulator > targetDT * 5 then
        accumulator = targetDT * 5
    end
end

function love.draw()
    -- Get window dimensions and calculate scale to maintain aspect ratio
    local screen_width = love.graphics.getWidth()
    local screen_height = love.graphics.getHeight()

    -- Calculate dynamic viewport size based on screen size
    -- Smaller screens get a smaller viewport (more zoomed in) for better visibility
    local Camera = require('src.systems.camera')
    local target_w, target_h = Camera.calculateViewport(screen_width, screen_height)

    local scale = math.min(screen_width / target_w, screen_height / target_h)

    -- Center and scale the game world (pixel art at low res)
    love.graphics.push()
    love.graphics.translate((screen_width - target_w * scale) / 2, (screen_height - target_h * scale) / 2)
    love.graphics.scale(scale)

    -- Draw the game world (sprites, tiles, etc.)
    Game:draw()

    love.graphics.pop()

    -- Draw UI at native resolution (crisp text)
    Game:drawUI()

    -- Frame rate limiting for Miyoo - prevent busy-waiting that causes stuttering
    if frameSleepEnabled then
        local currentTime = love.timer.getTime()
        local frameTime = currentTime - lastTime

        if frameTime < targetDT then
            -- Sleep for remaining time to maintain exactly target FPS
            -- This prevents the CPU from busy-waiting and causing micro-stutters
            love.timer.sleep(targetDT - frameTime)
        end

        lastTime = love.timer.getTime()
    end
end

function love.keypressed(key)
    local Input = require('src.systems.input')
    Input:keyPressed(key)
    Game:keypressed(key)
end

function love.keyreleased(key)
    local Input = require('src.systems.input')
    Input:keyReleased(key)
end

function love.gamepadpressed(joystick, button)
    local Input = require('src.systems.input')
    Input:gamepadPressed(button)
    Game:gamepadpressed(button)
end

function love.gamepadreleased(joystick, button)
    local Input = require('src.systems.input')
    Input:gamepadReleased(button)
    if Game.gamepadreleased then
        Game:gamepadreleased(button)
    end
end

function love.mousepressed(x, y, button)
    Game:mousepressed(x, y, button)
end

function love.wheelmoved(x, y)
    -- Only allow zoom in dev mode
    local Constants = require('src.constants')
    if Constants.DEV_MODE and Game.camera then
        Game.camera:adjustZoom(y)
    end
end

function love.quit()
    Game:quit()
end
