-- src/ui/menu.lua
-- Menu system for Boon Snatch multiplayer
-- ESC/START to open, not open by default
-- Uses 04B_30__.TTF font and standardized design

local OnlineClient = require("src.net.online_client")

local Menu = {}
Menu.__index = Menu

-- Menu states
Menu.STATE = {
    MAIN = "main",
    MULTIPLAYER = "multiplayer",
    ONLINE = "online",
    CREATE_GAME = "create_game",
    WAITING = "waiting",
    JOIN_CODE = "join_code",
    FIND_GAME = "find_game",
}

-- Design constants (matching dialogue style)
local MARGIN = 12
local TITLE_FONT_SIZE = 24
local BODY_FONT_SIZE = 20
local OPTION_FONT_SIZE = 18
local OPTION_SPACING = 22

function Menu:new()
    local self = setmetatable({}, Menu)
    
    -- Start HIDDEN (state = nil means not visible)
    self.state = nil
    
    -- Online client for REST API
    self.onlineClient = OnlineClient:new()
    
    -- Load fonts (matching dialogue style)
    self.titleFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", TITLE_FONT_SIZE)
    self.titleFont:setFilter("nearest", "nearest")
    
    self.bodyFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", BODY_FONT_SIZE)
    self.bodyFont:setFilter("nearest", "nearest")
    
    self.optionFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", OPTION_FONT_SIZE)
    self.optionFont:setFilter("nearest", "nearest")
    
    self.smallFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", 14)
    self.smallFont:setFilter("nearest", "nearest")
    
    -- Menu navigation
    self.selectedIndex = 1
    
    -- Create game state
    self.isPublic = false
    self.roomCode = nil
    self.wsUrl = nil
    self.playerId = nil
    
    -- Join code state (digit picker)
    self.roomCodeDigits = {"", "", "", "", "", ""}  -- 6 digits
    self.currentDigitIndex = 1
    
    -- Public rooms list
    self.publicRooms = {}
    self.refreshingRooms = false
    
    -- Callback functions (set by game.lua)
    self.onRoomCreated = nil  -- Called when room is created
    self.onRoomJoined = nil    -- Called when room is joined
    self.onCancel = nil        -- Called when returning to game
    
    return self
end

function Menu:show()
    self.state = Menu.STATE.MAIN
    self.selectedIndex = 1
end

function Menu:hide()
    self.state = nil
    self.selectedIndex = 1
    self.roomCode = nil
    self.roomCodeDigits = {"", "", "", "", "", ""}
    self.currentDigitIndex = 1
end

function Menu:isVisible()
    return self.state ~= nil
end

function Menu:update(dt)
    if not self:isVisible() then return end
    -- Menu updates handled in keypressed/gamepadpressed
end

function Menu:draw()
    if not self:isVisible() then return end
    
    -- Draw menu background (matching dialogue style)
    self:drawBackground()
    
    -- Draw based on state
    if self.state == Menu.STATE.MAIN then
        self:drawMainMenu()
    elseif self.state == Menu.STATE.MULTIPLAYER then
        self:drawMultiplayerMenu()
    elseif self.state == Menu.STATE.ONLINE then
        self:drawOnlineMenu()
    elseif self.state == Menu.STATE.CREATE_GAME then
        self:drawCreateGame()
    elseif self.state == Menu.STATE.WAITING then
        self:drawWaiting()
    elseif self.state == Menu.STATE.JOIN_CODE then
        self:drawJoinCode()
    elseif self.state == Menu.STATE.FIND_GAME then
        self:drawFindGame()
    end
end

-- Draw standardized menu background
function Menu:drawBackground()
    local boxW = 280
    local boxH = 160
    local boxX = (320 - boxW) / 2
    local boxY = (180 - boxH) / 2
    
    -- Background (matching dialogue)
    love.graphics.setColor(0.06, 0.06, 0.10, 0.95)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)
    
    -- Border (matching dialogue)
    love.graphics.setColor(0.4, 0.4, 0.45, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)
    love.graphics.setColor(0.65, 0.65, 0.7, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", boxX + 1, boxY + 1, boxW - 2, boxH - 2, 3, 3)
end

-- Draw title (standardized)
function Menu:drawTitle(text, y)
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, 0, y, 320, "center")
end

-- Draw option list (standardized)
function Menu:drawOptions(options, startY)
    love.graphics.setFont(self.optionFont)
    
    local y = startY
    for i, option in ipairs(options) do
        if i == self.selectedIndex then
            -- Selected option
            love.graphics.setColor(1, 1, 0.5)
            love.graphics.print("> " .. option, 40, y)
        else
            -- Unselected option
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.print("  " .. option, 40, y)
        end
        y = y + OPTION_SPACING
    end
end

-- Draw hint text (standardized)
function Menu:drawHint(text)
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf(text, 0, 160, 320, "center")
end

function Menu:drawMainMenu()
    self:drawTitle("Boon Snatch", 25)
    
    local options = {
        "Multiplayer",
        "Back to Game",
    }
    
    self:drawOptions(options, 65)
    self:drawHint("Arrow Keys: Select | Enter: Confirm | ESC: Back")
end

function Menu:drawMultiplayerMenu()
    self:drawTitle("Multiplayer", 25)
    
    local options = {
        "Online",
        "Back",
    }
    
    self:drawOptions(options, 65)
    self:drawHint("Arrow Keys: Select | Enter: Confirm | ESC: Back")
end

function Menu:drawOnlineMenu()
    self:drawTitle("Online", 25)
    
    local options = {
        "Create Game",
        "Join With Code",
        "Find Game",
        "Back",
    }
    
    self:drawOptions(options, 55)
    self:drawHint("Arrow Keys: Select | Enter: Confirm | ESC: Back")
end

function Menu:drawCreateGame()
    self:drawTitle("Create Game", 25)
    
    love.graphics.setFont(self.bodyFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Visibility:", 40, 55)
    
    -- Public/Private toggle
    if self.isPublic then
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.print("> PUBLIC", 40, 72)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.print("  Private", 40, 92)
    else
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.print("  Public", 40, 72)
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.print("> PRIVATE", 40, 92)
    end
    
    -- Create button
    love.graphics.setColor(0.5, 1, 0.5)
    love.graphics.print("Press ENTER to Create", 40, 115)
    
    self:drawHint("Left/Right: Toggle | ESC: Back")
end

function Menu:drawWaiting()
    self:drawTitle("Waiting for Player", 25)
    
    if self.roomCode then
        -- Display room code prominently
        love.graphics.setFont(self.titleFont)
        love.graphics.setColor(1, 1, 0.5)
        love.graphics.printf(self.roomCode, 0, 70, 320, "center")
        
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.printf("Share this code with your friend", 0, 100, 320, "center")
    else
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("Creating room...", 0, 80, 320, "center")
    end
    
    self:drawHint("ESC: Cancel")
end

function Menu:drawJoinCode()
    self:drawTitle("Join With Code", 25)
    
    -- Draw 6 digit boxes
    local startX = 50
    local y = 75
    local boxSize = 32
    local spacing = 6
    
    love.graphics.setFont(self.bodyFont)
    
    for i = 1, 6 do
        local x = startX + (i - 1) * (boxSize + spacing)
        
        -- Box background
        if i == self.currentDigitIndex then
            love.graphics.setColor(0.2, 0.2, 0.3, 1)
            love.graphics.rectangle("fill", x - 2, y - 2, boxSize + 4, boxSize + 4, 2, 2)
            love.graphics.setColor(1, 1, 0.5)
            love.graphics.rectangle("line", x - 2, y - 2, boxSize + 4, boxSize + 4, 2, 2)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 1)
            love.graphics.rectangle("fill", x, y, boxSize, boxSize, 2, 2)
            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.rectangle("line", x, y, boxSize, boxSize, 2, 2)
        end
        
        -- Draw digit
        love.graphics.setColor(1, 1, 1)
        if self.roomCodeDigits[i] and self.roomCodeDigits[i] ~= "" then
            love.graphics.printf(self.roomCodeDigits[i], x, y + 6, boxSize, "center")
        end
    end
    
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("Enter 0-9 for each digit", 0, 115, 320, "center")
    
    self:drawHint("ENTER: Join | ESC: Back")
end

function Menu:drawFindGame()
    self:drawTitle("Find Game", 25)
    
    if self.refreshingRooms then
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("Loading...", 0, 80, 320, "center")
    elseif #self.publicRooms == 0 then
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("No public rooms found", 0, 80, 320, "center")
    else
        love.graphics.setFont(self.optionFont)
        local y = 55
        for i, room in ipairs(self.publicRooms) do
            if i == self.selectedIndex then
                love.graphics.setColor(0.2, 0.2, 0.3, 1)
                love.graphics.rectangle("fill", 30, y - 2, 260, 18, 2, 2)
                love.graphics.setColor(1, 1, 0.5)
            else
                love.graphics.setColor(0.8, 0.8, 0.8)
            end
            
            love.graphics.print("Room: " .. (room.code or "?"), 40, y)
            love.graphics.printf((room.playerCount or 0) .. " players", 0, y, 280, "right")
            
            y = y + 20
            if y > 130 then break end
        end
    end
    
    self:drawHint("ENTER: Join | R: Refresh | ESC: Back")
end

-- Input handling (unchanged from before)
function Menu:keypressed(key)
    if not self:isVisible() then return false end
    
    if self.state == Menu.STATE.MAIN then
        return self:handleMainMenuKey(key)
    elseif self.state == Menu.STATE.MULTIPLAYER then
        return self:handleMultiplayerKey(key)
    elseif self.state == Menu.STATE.ONLINE then
        return self:handleOnlineKey(key)
    elseif self.state == Menu.STATE.CREATE_GAME then
        return self:handleCreateGameKey(key)
    elseif self.state == Menu.STATE.WAITING then
        return self:handleWaitingKey(key)
    elseif self.state == Menu.STATE.JOIN_CODE then
        return self:handleJoinCodeKey(key)
    elseif self.state == Menu.STATE.FIND_GAME then
        return self:handleFindGameKey(key)
    end
    
    return false
end

function Menu:gamepadpressed(button)
    if not self:isVisible() then return false end
    
    local keyMap = {
        ["dpup"] = "up",
        ["dpdown"] = "down",
        ["dpleft"] = "left",
        ["dpright"] = "right",
        ["a"] = "return",
        ["b"] = "escape",
        ["start"] = "escape",
    }
    
    local key = keyMap[button]
    if key then
        return self:keypressed(key)
    end
    
    return false
end

function Menu:handleMainMenuKey(key)
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(2, self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if self.selectedIndex == 1 then
            self.state = Menu.STATE.MULTIPLAYER
            self.selectedIndex = 1
        elseif self.selectedIndex == 2 then
            self:hide()
        end
        return true
    elseif key == "escape" then
        self:hide()
        return true
    end
    return false
end

function Menu:handleMultiplayerKey(key)
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(2, self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if self.selectedIndex == 1 then
            self.state = Menu.STATE.ONLINE
            self.selectedIndex = 1
        elseif self.selectedIndex == 2 then
            self.state = Menu.STATE.MAIN
            self.selectedIndex = 1
        end
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.MAIN
        self.selectedIndex = 1
        return true
    end
    return false
end

function Menu:handleOnlineKey(key)
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(4, self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if self.selectedIndex == 1 then
            self.state = Menu.STATE.CREATE_GAME
            self.isPublic = false
        elseif self.selectedIndex == 2 then
            self.state = Menu.STATE.JOIN_CODE
            self.roomCodeDigits = {"", "", "", "", "", ""}
            self.currentDigitIndex = 1
        elseif self.selectedIndex == 3 then
            self.state = Menu.STATE.FIND_GAME
            self.selectedIndex = 1
            self:refreshPublicRooms()
        elseif self.selectedIndex == 4 then
            self.state = Menu.STATE.MULTIPLAYER
            self.selectedIndex = 1
        end
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.MULTIPLAYER
        self.selectedIndex = 1
        return true
    end
    return false
end

function Menu:handleCreateGameKey(key)
    if key == "left" or key == "right" then
        self.isPublic = not self.isPublic
        return true
    elseif key == "return" then
        self.state = Menu.STATE.WAITING
        self.roomCode = nil
        self:createRoom()
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.ONLINE
        self.selectedIndex = 1
        return true
    end
    return false
end

function Menu:handleWaitingKey(key)
    if key == "escape" then
        self.state = Menu.STATE.ONLINE
        self.selectedIndex = 1
        self.roomCode = nil
        return true
    end
    return false
end

function Menu:handleJoinCodeKey(key)
    local digit = tonumber(key)
    if digit ~= nil and digit >= 0 and digit <= 9 then
        self.roomCodeDigits[self.currentDigitIndex] = tostring(digit)
        if self.currentDigitIndex < 6 then
            self.currentDigitIndex = self.currentDigitIndex + 1
        end
        return true
    elseif key == "backspace" then
        if self.currentDigitIndex > 1 then
            self.currentDigitIndex = self.currentDigitIndex - 1
            self.roomCodeDigits[self.currentDigitIndex] = ""
        end
        return true
    elseif key == "return" then
        local code = table.concat(self.roomCodeDigits)
        if #code == 6 then
            self:joinRoom(code)
        end
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.ONLINE
        self.selectedIndex = 2
        self.roomCodeDigits = {"", "", "", "", "", ""}
        self.currentDigitIndex = 1
        return true
    end
    return false
end

function Menu:handleFindGameKey(key)
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(math.max(1, #self.publicRooms), self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if #self.publicRooms > 0 and self.selectedIndex <= #self.publicRooms then
            local room = self.publicRooms[self.selectedIndex]
            if room.code then
                self:joinRoom(room.code)
            end
        end
        return true
    elseif key == "r" then
        self:refreshPublicRooms()
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.ONLINE
        self.selectedIndex = 3
        return true
    end
    return false
end

-- Create a new room via REST API
function Menu:createRoom()
    print("Creating room (public: " .. tostring(self.isPublic) .. ")...")
    
    local result = self.onlineClient:createRoom(self.isPublic)
    
    if result.success then
        self.roomCode = result.roomCode
        self.wsUrl = result.wsUrl
        print("Room created! Code: " .. self.roomCode)
        
        if self.onRoomCreated then
            self.onRoomCreated(self.roomCode, self.wsUrl)
        end
    else
        print("Failed to create room: " .. (result.error or "Unknown error"))
        self.state = Menu.STATE.CREATE_GAME
    end
end

-- Join a room by code
function Menu:joinRoom(code)
    print("Joining room: " .. code)
    
    local result = self.onlineClient:joinRoom(code)
    
    if result.success then
        self.roomCode = result.roomCode
        self.wsUrl = result.wsUrl
        self.playerId = result.playerId
        print("Joined room! Code: " .. self.roomCode)
        
        if self.onRoomJoined then
            self.onRoomJoined(self.roomCode, self.wsUrl, self.playerId)
        end
        
        self:hide()
    else
        print("Failed to join room: " .. (result.error or "Unknown error"))
    end
end

-- Refresh public rooms list
function Menu:refreshPublicRooms()
    self.refreshingRooms = true
    print("Refreshing public rooms...")
    
    local result = self.onlineClient:listRooms()
    
    if result.success then
        self.publicRooms = result.rooms or {}
        print("Found " .. #self.publicRooms .. " public rooms")
    else
        print("Failed to list rooms: " .. (result.error or "Unknown error"))
        self.publicRooms = {}
    end
    
    self.refreshingRooms = false
    self.selectedIndex = 1
end

return Menu
