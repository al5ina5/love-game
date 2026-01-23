-- src/systems/input.lua
-- Input handling system (like a useInput hook in React)
-- Centralizes all keyboard and gamepad input logic
--
-- Gamepad Support:
-- - Movement: D-pad or left analog stick
-- - Sprint: Left trigger or left shoulder button
-- - Compatible with PortMaster style consoles
-- - Uses standard LÖVE gamepad button names (a, b, x, y, start, back, etc.)

local Input = {
    keysJustPressed = {},  -- Keys pressed this frame
    keysJustReleased = {}, -- Keys released this frame
    gamepadButtonsJustPressed = {},  -- Gamepad buttons pressed this frame
    gamepadButtonsJustReleased = {}, -- Gamepad buttons released this frame
    activeJoystick = nil,  -- Cached reference to first available gamepad
}

-- Called at the start of each frame to clear one-shot key states
function Input:update()
    self.keysJustPressed = {}
    self.keysJustReleased = {}
    self.gamepadButtonsJustPressed = {}
    self.gamepadButtonsJustReleased = {}
    
    -- Update active joystick reference
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        self.activeJoystick = joysticks[1]
    else
        self.activeJoystick = nil
    end
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

-- Called by main.lua when a gamepad button is pressed
function Input:gamepadPressed(button)
    self.gamepadButtonsJustPressed[button] = true
end

-- Called by main.lua when a gamepad button is released
function Input:gamepadReleased(button)
    self.gamepadButtonsJustReleased[button] = true
end

-- Check if a gamepad button is currently held down (continuous)
function Input:isGamepadDown(button)
    if not self.activeJoystick then return false end
    return self.activeJoystick:isGamepadDown(button)
end

-- Check if a gamepad button was just pressed this frame (one-shot)
function Input:wasGamepadPressed(button)
    return self.gamepadButtonsJustPressed[button] == true
end

-- Check if a gamepad button was just released this frame (one-shot)
function Input:wasGamepadReleased(button)
    return self.gamepadButtonsJustReleased[button] == true
end

-- Check if sprint is active (keyboard shift or gamepad trigger/shoulder)
function Input:isSprintDown()
    -- Keyboard sprint
    if self:isDown("lshift") or self:isDown("rshift") then
        return true
    end
    
    -- Gamepad sprint (left trigger or left shoulder button)
    if self.activeJoystick then
        -- Check left trigger (commonly used for sprint in games)
        local leftTrigger = self.activeJoystick:getGamepadAxis("triggerleft")
        if leftTrigger > 0.3 then  -- Deadzone for trigger
            return true
        end
        -- Also check left shoulder button as alternative
        if self.activeJoystick:isGamepadDown("leftshoulder") then
            return true
        end
    end
    
    return false
end

-- Get movement vector from arrow keys, WASD, or gamepad
function Input:getMovementVector()
    local dx, dy = 0, 0

    -- Debug: Check if any movement keys are pressed
    local anyPressed = love.keyboard.isDown("left") or love.keyboard.isDown("right") or
                      love.keyboard.isDown("up") or love.keyboard.isDown("down") or
                      love.keyboard.isDown("a") or love.keyboard.isDown("d") or
                      love.keyboard.isDown("w") or love.keyboard.isDown("s")
    if anyPressed then
        print("Input: Movement keys detected")
    end

    -- Keyboard support
    if self:isDown("left") or self:isDown("a") then dx = dx - 1 end
    if self:isDown("right") or self:isDown("d") then dx = dx + 1 end
    if self:isDown("up") or self:isDown("w") then dy = dy - 1 end
    if self:isDown("down") or self:isDown("s") then dy = dy + 1 end
    
    -- Gamepad support
    if self.activeJoystick then
        -- D-pad
        if self.activeJoystick:isGamepadDown("dpleft") then dx = dx - 1 end
        if self.activeJoystick:isGamepadDown("dpright") then dx = dx + 1 end
        if self.activeJoystick:isGamepadDown("dpup") then dy = dy - 1 end
        if self.activeJoystick:isGamepadDown("dpdown") then dy = dy + 1 end
        
        -- Left Analog Stick
        local lx = self.activeJoystick:getGamepadAxis("leftx")
        local ly = self.activeJoystick:getGamepadAxis("lefty")
        
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
