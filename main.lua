-- main.lua
-- Pixel Raiders game

local Game = require('src.game')

function love.load()
    -- Pixel-art friendly graphics settings
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Set window title
    love.window.setTitle("Pixel Raiders")
    
    -- Initialize game
    Game:load()
end

function love.update(dt)
    Game:update(dt)
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
end

function love.keypressed(key)
    Game:keypressed(key)
end

function love.gamepadpressed(joystick, button)
    local Input = require('src.systems.input')
    Input:gamepadPressed(button)
    Game:gamepadpressed(button)
end

function love.gamepadreleased(joystick, button)
    local Input = require('src.systems.input')
    Input:gamepadReleased(button)
end

function love.mousepressed(x, y, button)
    Game:mousepressed(x, y, button)
end

function love.quit()
    Game:quit()
end
