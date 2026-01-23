-- src/ui/menu.lua
-- Menu system for Boon Snatch multiplayer
-- ESC/START to open, not open by default
-- Uses 04B_30__.TTF font and standardized design

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

-- Design constants (clean, standard menu)
local MARGIN = 16
local TITLE_FONT_SIZE = 16
local BODY_FONT_SIZE = 12
local OPTION_FONT_SIZE = 12
local OPTION_SPACING = 18

-- Target game resolution (for calculating relative positions)
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

function Menu:new()
    local self = setmetatable({}, Menu)
    
    -- Start HIDDEN (state = nil means not visible)
    self.state = nil
    
    -- Online error message
    self.onlineError = nil
    self.onlineRoomCode = nil
    
    -- Load fonts with nearest-neighbor filtering for crisp pixel art
    self.titleFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", TITLE_FONT_SIZE)
    self.titleFont:setFilter("nearest", "nearest")
    
    self.bodyFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", BODY_FONT_SIZE)
    self.bodyFont:setFilter("nearest", "nearest")
    
    self.optionFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", OPTION_FONT_SIZE)
    self.optionFont:setFilter("nearest", "nearest")
    
    self.smallFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", 10)
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
    self.onlineRoomCode = nil
    self.onlineError = nil
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

-- Draw standardized menu background (at native resolution with proper scaling)
function Menu:drawBackground()
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local scale = math.min(screenW / GAME_WIDTH, screenH / GAME_HEIGHT)
    local offsetX = (screenW - GAME_WIDTH * scale) / 2
    local offsetY = (screenH - GAME_HEIGHT * scale) / 2
    
    local boxW = 300 * scale
    local boxH = 170 * scale
    local boxX = offsetX + (GAME_WIDTH * scale - boxW) / 2
    local boxY = offsetY + (GAME_HEIGHT * scale - boxH) / 2
    
    -- Background
    love.graphics.setColor(0.08, 0.08, 0.12, 0.98)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4 * scale, 4 * scale)
    
    -- Border
    love.graphics.setColor(0.3, 0.3, 0.35, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4 * scale, 4 * scale)
    
    -- Store for other drawing functions
    self._screenW = screenW
    self._screenH = screenH
    self._scale = scale
    self._offsetX = offsetX
    self._offsetY = offsetY
    self._boxX = boxX
    self._boxY = boxY
    self._boxW = boxW
    self._boxH = boxH
end

-- Draw title (standardized, with safe margins)
function Menu:drawTitle(text, y)
    if not self._scale then return end
    
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(1, 1, 1)
    -- Scale Y position and center text
    local scaledY = self._offsetY + y * self._scale
    local safeY = math.max(scaledY, self._offsetY + 10 * self._scale)
    love.graphics.printf(text, self._offsetX, safeY, GAME_WIDTH * self._scale, "center")
end

-- Draw option list (standardized, with safe bounds)
function Menu:drawOptions(options, startY)
    if not self._scale then return end
    
    love.graphics.setFont(self.optionFont)
    
    local y = self._offsetY + startY * self._scale
    local maxY = self._offsetY + 165 * self._scale
    
    for i, option in ipairs(options) do
        -- Ensure options don't clip at bottom
        if y + self.optionFont:getHeight() > maxY then break end
        
        local x = self._offsetX + 40 * self._scale
        
        if i == self.selectedIndex then
            -- Selected option with background
            love.graphics.setColor(0.2, 0.3, 0.4, 1)
            love.graphics.rectangle("fill", x - 5 * self._scale, y - 2 * self._scale, 250 * self._scale, 14 * self._scale, 2 * self._scale, 2 * self._scale)
            love.graphics.setColor(0.5, 0.7, 1)
            love.graphics.print("> " .. option, x, y)
        else
            -- Unselected option
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.print("  " .. option, x, y)
        end
        y = y + OPTION_SPACING * self._scale
    end
end

-- Draw hint text (standardized, with safe margins)
function Menu:drawHint(text)
    if not self._scale then return end
    
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    -- Ensure text stays within bounds
    local safeY = math.min(
        self._offsetY + 165 * self._scale,
        self._offsetY + GAME_HEIGHT * self._scale - self.smallFont:getHeight() - 2 * self._scale
    )
    love.graphics.printf(text, self._offsetX, safeY, GAME_WIDTH * self._scale, "center")
end

function Menu:drawMainMenu()
    self:drawTitle("Boon Snatch", 30)
    
    local options = {
        "Multiplayer",
        "Back to Game",
    }
    
    self:drawOptions(options, 70)
end

function Menu:drawMultiplayerMenu()
    self:drawTitle("Multiplayer", 30)
    
    local options = {
        "Online",
        "Back",
    }
    
    self:drawOptions(options, 70)
end

function Menu:drawOnlineMenu()
    self:drawTitle("Online", 30)
    
    local options = {
        "Create Game",
        "Join With Code",
        "Find Game",
        "Back",
    }
    
    self:drawOptions(options, 60)
end

function Menu:drawCreateGame()
    if not self._scale then return end
    
    self:drawTitle("Create Game", 30)
    
    love.graphics.setFont(self.bodyFont)
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.print("Visibility:", self._offsetX + 40 * self._scale, self._offsetY + 60 * self._scale)
    
    -- Public/Private toggle with clear selection
    local toggleY = self._offsetY + 78 * self._scale
    if self.isPublic then
        -- Public selected
        love.graphics.setColor(0.2, 0.4, 0.2, 1)
        love.graphics.rectangle("fill", self._offsetX + 38 * self._scale, toggleY - 2 * self._scale, 80 * self._scale, 18 * self._scale, 2 * self._scale, 2 * self._scale)
        love.graphics.setColor(0.5, 1, 0.5)
        love.graphics.print("PUBLIC", self._offsetX + 40 * self._scale, toggleY)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("Private", self._offsetX + 130 * self._scale, toggleY)
    else
        -- Private selected
        love.graphics.setColor(0.4, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", self._offsetX + 128 * self._scale, toggleY - 2 * self._scale, 80 * self._scale, 18 * self._scale, 2 * self._scale, 2 * self._scale)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("Public", self._offsetX + 40 * self._scale, toggleY)
        love.graphics.setColor(1, 0.5, 0.5)
        love.graphics.print("PRIVATE", self._offsetX + 130 * self._scale, toggleY)
    end
    
    -- Create button
    love.graphics.setColor(0.4, 0.8, 0.4)
    love.graphics.print("ENTER: Create", self._offsetX + 40 * self._scale, self._offsetY + 105 * self._scale)
end

function Menu:drawWaiting()
    if not self._scale then return end
    
    self:drawTitle("Waiting for Player", 30)
    
    local roomCode = self.onlineRoomCode or self.roomCode
    if roomCode then
        -- Display room code prominently
        love.graphics.setFont(self.titleFont)
        love.graphics.setColor(1, 1, 0.3)
        love.graphics.printf(roomCode, self._offsetX, self._offsetY + 75 * self._scale, GAME_WIDTH * self._scale, "center")
        
        -- Show error if any
        if self.onlineError then
            love.graphics.setFont(self.smallFont)
            love.graphics.setColor(1, 0.3, 0.3)
            love.graphics.printf(self.onlineError, self._offsetX, self._offsetY + 100 * self._scale, GAME_WIDTH * self._scale, "center")
        end
    else
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("Creating room...", self._offsetX, self._offsetY + 85 * self._scale, GAME_WIDTH * self._scale, "center")
    end
end

function Menu:drawJoinCode()
    if not self._scale then return end
    
    self:drawTitle("Join With Code", 30)
    
    -- Draw 6 digit boxes
    local startX = self._offsetX + 40 * self._scale
    local y = self._offsetY + 80 * self._scale
    local boxSize = 28 * self._scale
    local spacing = 8 * self._scale
    
    love.graphics.setFont(self.bodyFont)
    
    for i = 1, 6 do
        local x = startX + (i - 1) * (boxSize + spacing)
        
        -- Box background
        if i == self.currentDigitIndex then
            love.graphics.setColor(0.2, 0.3, 0.4, 1)
            love.graphics.rectangle("fill", x - 2 * self._scale, y - 2 * self._scale, boxSize + 4 * self._scale, boxSize + 4 * self._scale, 2 * self._scale, 2 * self._scale)
            love.graphics.setColor(0.5, 0.7, 1)
            love.graphics.rectangle("line", x - 2 * self._scale, y - 2 * self._scale, boxSize + 4 * self._scale, boxSize + 4 * self._scale, 2 * self._scale, 2 * self._scale)
        else
            love.graphics.setColor(0.15, 0.15, 0.2, 1)
            love.graphics.rectangle("fill", x, y, boxSize, boxSize, 2 * self._scale, 2 * self._scale)
            love.graphics.setColor(0.4, 0.4, 0.4)
            love.graphics.rectangle("line", x, y, boxSize, boxSize, 2 * self._scale, 2 * self._scale)
        end
        
        -- Draw digit
        love.graphics.setColor(1, 1, 1)
        if self.roomCodeDigits[i] and self.roomCodeDigits[i] ~= "" then
            love.graphics.printf(self.roomCodeDigits[i], x, y + 4 * self._scale, boxSize, "center")
        end
    end
end

function Menu:drawFindGame()
    if not self._scale then return end
    
    self:drawTitle("Find Game", 30)
    
    if self.refreshingRooms then
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("Loading...", self._offsetX, self._offsetY + 85 * self._scale, GAME_WIDTH * self._scale, "center")
    elseif #self.publicRooms == 0 then
        love.graphics.setFont(self.bodyFont)
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("No public rooms", self._offsetX, self._offsetY + 85 * self._scale, GAME_WIDTH * self._scale, "center")
    else
        love.graphics.setFont(self.optionFont)
        local y = self._offsetY + 60 * self._scale
        local maxY = self._offsetY + 140 * self._scale
        
        for i, room in ipairs(self.publicRooms) do
            if y > maxY then break end
            
            if i == self.selectedIndex then
                love.graphics.setColor(0.2, 0.3, 0.4, 1)
                love.graphics.rectangle("fill", self._offsetX + 30 * self._scale, y - 2 * self._scale, 260 * self._scale, 16 * self._scale, 2 * self._scale, 2 * self._scale)
                love.graphics.setColor(0.5, 0.7, 1)
            else
                love.graphics.setColor(0.7, 0.7, 0.7)
            end
            
            love.graphics.print(room.code or "?", self._offsetX + 40 * self._scale, y)
            love.graphics.printf((room.players or room.playerCount or 0) .. "/" .. (room.maxPlayers or 10), self._offsetX, y, (GAME_WIDTH - 40) * self._scale, "right")
            
            y = y + 18 * self._scale
        end
    end
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
        print("Toggle visibility: " .. (self.isPublic and "PUBLIC" or "PRIVATE"))
        return true
    elseif key == "return" then
        self.state = Menu.STATE.WAITING
        self.roomCode = nil
        self.onlineRoomCode = nil
        self.onlineError = nil
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
        self.onlineRoomCode = nil
        self.onlineError = nil
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
    
    -- This will be handled by ConnectionManager via the callback
    if self.onRoomCreated then
        -- ConnectionManager will handle the actual creation
        -- We just need to trigger the callback with a placeholder
        -- The actual room creation happens in ConnectionManager.hostOnline
        self.onRoomCreated(nil, nil)  -- Will be set by ConnectionManager
    end
end

-- Join a room by code
function Menu:joinRoom(code)
    print("Joining room: " .. code)
    
    -- This will be handled by ConnectionManager via the callback
    if self.onRoomJoined then
        -- ConnectionManager will handle the actual joining
        self.onRoomJoined(code, nil, nil)  -- Will be set by ConnectionManager
    end
end

-- Refresh public rooms list
function Menu:refreshPublicRooms()
    self.refreshingRooms = true
    print("Refreshing public rooms...")
    
    -- This will be handled by ConnectionManager
    -- For now, we'll need to access the game's connectionManager
    -- This is a bit of a hack, but menu needs access to game
    -- In a better design, menu would get a reference to game or connectionManager
    -- For now, we'll keep the direct onlineClient call but it should work
    local OnlineClient = require("src.net.online_client")
    if not OnlineClient.isAvailable() then
        self.publicRooms = {}
        self.refreshingRooms = false
        return
    end
    
    local success, onlineClient = pcall(OnlineClient.new, OnlineClient)
    if not success then
        self.publicRooms = {}
        self.refreshingRooms = false
        return
    end
    
    local rooms = onlineClient:listRooms()
    self.publicRooms = rooms or {}
    print("Found " .. #self.publicRooms .. " public rooms")
    
    self.refreshingRooms = false
    self.selectedIndex = 1
end

return Menu
