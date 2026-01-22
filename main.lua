-- main.lua
-- Walking simulator with sprite animation

local Game = require('src.game')

function love.load()
    -- Pixel-art friendly graphics settings
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Set window title
    love.window.setTitle("Walking Together")
    
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
    
    -- Target resolution is 320x180 (16:9 pixel art style, like Stardew Valley / Enter the Gungeon)
    -- With 16x16 sprites, this gives characters ~9% of screen height - nice and prominent
    local target_w, target_h = 320, 180
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
    Game:gamepadpressed(button)
end

function love.mousepressed(x, y, button)
    Game:mousepressed(x, y, button)
end

function love.quit()
    Game:quit()
end
