-- src/systems/input.lua
-- Input handling system (like a useInput hook in React)
-- Centralizes all keyboard input logic

local Input = {
    keysJustPressed = {},  -- Keys pressed this frame
    keysJustReleased = {}, -- Keys released this frame
}

-- Called at the start of each frame to clear one-shot key states
function Input:update()
    self.keysJustPressed = {}
    self.keysJustReleased = {}
end

-- Check if a key is currently held down (continuous)
function Input:isDown(key)
    return love.keyboard.isDown(key)
end

-- Check if a key was just pressed this frame (one-shot)
function Input:wasPressed(key)
    return self.keysJustPressed[key] == true
end

-- Check if a key was just released this frame (one-shot)
function Input:wasReleased(key)
    return self.keysJustReleased[key] == true
end

-- Called by main.lua when a key is pressed
function Input:keyPressed(key)
    self.keysJustPressed[key] = true
end

-- Called by main.lua when a key is released
function Input:keyReleased(key)
    self.keysJustReleased[key] = true
end

-- Get movement vector from arrow keys, WASD, or gamepad
function Input:getMovementVector()
    local dx, dy = 0, 0
    
    -- Keyboard support
    if self:isDown("left") or self:isDown("a") then dx = dx - 1 end
    if self:isDown("right") or self:isDown("d") then dx = dx + 1 end
    if self:isDown("up") or self:isDown("w") then dy = dy - 1 end
    if self:isDown("down") or self:isDown("s") then dy = dy + 1 end
    
    -- Gamepad support (first available joystick)
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        local stick = joysticks[1]
        
        -- D-pad
        if stick:isGamepadDown("dpleft") then dx = dx - 1 end
        if stick:isGamepadDown("dpright") then dx = dx + 1 end
        if stick:isGamepadDown("dpup") then dy = dy - 1 end
        if stick:isGamepadDown("dpdown") then dy = dy + 1 end
        
        -- Left Analog Stick
        local lx = stick:getGamepadAxis("leftx")
        local ly = stick:getGamepadAxis("lefty")
        
        -- Deadzone for analog sticks
        local deadzone = 0.2
        if math.abs(lx) > deadzone then dx = dx + lx end
        if math.abs(ly) > deadzone then dy = dy + ly end
    end
    
    -- Clamp and normalize
    if dx ~= 0 or dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            dx = dx / len
            dy = dy / len
        end
    end
    
    return dx, dy
end

return Input
