-- src/ui/menu.lua
-- Simple menu system for server browser and hosting
-- Like a React component with state

local Menu = {}
Menu.__index = Menu

-- Menu states
Menu.STATE = {
    MAIN = "main",
    HOST = "host",
    BROWSE = "browse",
    CONNECTING = "connecting",
}

-- Pass discovery from Game (dependency injection, like passing props)
function Menu:new(discovery)
    local self = setmetatable({}, Menu)
    
    -- Start HIDDEN (state = nil means not visible)
    self.state = nil
    
    -- Use shared discovery instance from Game
    self.discovery = discovery
    
    self.selectedServer = nil
    self.selectedIndex = 1
    self.serverName = "Player's Game"
    self.scanTimer = 0
    
    -- Callback functions (set by game.lua)
    self.onHost = nil      -- Called when user wants to host
    self.onStopHost = nil  -- Called when user wants to stop hosting
    self.onJoin = nil      -- Called when user wants to join a server
    self.onCancel = nil    -- Called when returning to game
    
    return self
end

function Menu:show()
    self.state = Menu.STATE.MAIN
    self.selectedIndex = 1
    self.scanTimer = 0
    
    -- Start listening for servers when menu opens
    self.discovery:startListening()
    self.discovery:sendDiscoveryRequest()
end

function Menu:hide()
    self.state = nil
    -- Don't stop advertising here - Game manages that
end

function Menu:isVisible()
    return self.state ~= nil
end

function Menu:update(dt)
    if not self:isVisible() then return end
    
    -- Periodically rescan for servers when browsing
    if self.state == Menu.STATE.BROWSE then
        self.scanTimer = self.scanTimer + dt
        if self.scanTimer >= 2.0 then
            self.scanTimer = 0
            self.discovery:sendDiscoveryRequest()
        end
    end
end

function Menu:draw()
    if not self:isVisible() then return end
    
    -- Darken background
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", 0, 0, 320, 180)
    
    -- Draw based on state
    if self.state == Menu.STATE.MAIN then
        self:drawMainMenu()
    elseif self.state == Menu.STATE.BROWSE then
        self:drawServerBrowser()
    elseif self.state == Menu.STATE.CONNECTING then
        self:drawConnecting()
    end
    
    love.graphics.setColor(1, 1, 1)
end

function Menu:drawMainMenu()
    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Walking Together", 0, 20, 320, "center")
    
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.printf("Multiplayer", 0, 35, 320, "center")
    
    -- Menu options (dynamic based on hosting state)
    local hostText = "Host Game"
    if self.discovery.mode == "server" then
        hostText = "Stop Hosting"
    end

    local options = {
        hostText,
        "Find Game",
        "Join Localhost",
        "Back to Game",
    }
    
    local y = 60
    for i, option in ipairs(options) do
        if i == self.selectedIndex then
            love.graphics.setColor(1, 1, 0.5)
            love.graphics.print("> " .. option, 100, y)
        else
            love.graphics.setColor(0.8, 0.8, 0.8)
            love.graphics.print("  " .. option, 100, y)
        end
        y = y + 20
    end
    
    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("Arrow Keys: Select | Enter: Confirm", 0, 160, 320, "center")
end

function Menu:drawServerBrowser()
    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Find Game", 0, 10, 320, "center")
    
    local servers = self.discovery:getServers()
    
    if #servers == 0 then
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf("Searching for games...", 0, 70, 320, "center")
        love.graphics.printf("Make sure both devices are on\nthe same WiFi network", 0, 90, 320, "center")
    else
        -- List servers
        local y = 35
        for i, server in ipairs(servers) do
            local isSelected = (i == self.selectedIndex)
            
            if isSelected then
                love.graphics.setColor(0.3, 0.3, 0.5)
                love.graphics.rectangle("fill", 20, y - 2, 280, 24)
                love.graphics.setColor(1, 1, 0.5)
            else
                love.graphics.setColor(0.8, 0.8, 0.8)
            end
            
            -- Server name
            love.graphics.print(server.name, 30, y)
            
            -- Player count
            love.graphics.printf(
                server.players .. "/" .. server.maxPlayers,
                0, y, 290, "right"
            )
            
            -- IP (smaller, dimmer)
            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.print(server.ip, 30, y + 11)
            
            y = y + 30
            if y > 130 then break end  -- Max visible servers
        end
    end
    
    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.printf("Enter: Join | ESC: Back | R: Refresh", 0, 160, 320, "center")
end

function Menu:drawConnecting()
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Connecting...", 0, 80, 320, "center")
    
    if self.selectedServer then
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.printf(self.selectedServer.name, 0, 100, 320, "center")
    end
end

function Menu:keypressed(key)
    if not self:isVisible() then return false end
    
    if self.state == Menu.STATE.MAIN then
        return self:handleMainMenuKey(key)
    elseif self.state == Menu.STATE.BROWSE then
        return self:handleBrowseKey(key)
    elseif self.state == Menu.STATE.CONNECTING then
        if key == "escape" then
            self.state = Menu.STATE.BROWSE
            return true
        end
    end
    
    return false
end

function Menu:gamepadpressed(button)
    if not self:isVisible() then return false end
    
    if self.state == Menu.STATE.MAIN then
        return self:handleMainMenuGamepad(button)
    elseif self.state == Menu.STATE.BROWSE then
        return self:handleBrowseGamepad(button)
    elseif self.state == Menu.STATE.CONNECTING then
        if button == "b" then
            self.state = Menu.STATE.BROWSE
            return true
        end
    end
    
    return false
end

function Menu:handleMainMenuKey(key)
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(4, self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if self.selectedIndex == 1 then
            -- Host or Stop Hosting
            if self.discovery.mode == "server" then
                if self.onStopHost then self.onStopHost() end
            else
                if self.onHost then self.onHost() end
            end
            self:hide()
        elseif self.selectedIndex == 2 then
            -- Find Game
            self.state = Menu.STATE.BROWSE
            self.selectedIndex = 1
            self.scanTimer = 0
            self.discovery:sendDiscoveryRequest()
        elseif self.selectedIndex == 3 then
            -- Join Mac (Hardcoded)
            if self.onJoin then
                self.onJoin("10.0.0.197", 12345)
            end
            self:hide()
        elseif self.selectedIndex == 4 then
            -- Back to Game
            if self.onCancel then
                self.onCancel()
            end
            self:hide()
        end
        return true
    elseif key == "escape" then
        if self.onCancel then
            self.onCancel()
        end
        self:hide()
        return true
    end
    
    return false
end

function Menu:handleMainMenuGamepad(button)
    if button == "dpup" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif button == "dpdown" then
        self.selectedIndex = math.min(4, self.selectedIndex + 1)
        return true
    elseif button == "a" then
        if self.selectedIndex == 1 then
            -- Host or Stop Hosting
            if self.discovery.mode == "server" then
                if self.onStopHost then self.onStopHost() end
            else
                if self.onHost then self.onHost() end
            end
            self:hide()
        elseif self.selectedIndex == 2 then
            -- Find Game
            self.state = Menu.STATE.BROWSE
            self.selectedIndex = 1
            self.scanTimer = 0
            self.discovery:sendDiscoveryRequest()
        elseif self.selectedIndex == 3 then
            -- Join Localhost (for testing)
            if self.onJoin then
                self.onJoin("localhost", 12345)
            end
            self:hide()
        elseif self.selectedIndex == 4 then
            -- Back to Game
            if self.onCancel then
                self.onCancel()
            end
            self:hide()
        end
        return true
    elseif button == "b" or button == "back" then
        if self.onCancel then
            self.onCancel()
        end
        self:hide()
        return true
    end
    
    return false
end

function Menu:handleBrowseKey(key)
    local servers = self.discovery:getServers()
    
    if key == "up" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif key == "down" then
        self.selectedIndex = math.min(math.max(1, #servers), self.selectedIndex + 1)
        return true
    elseif key == "return" or key == "space" then
        if #servers > 0 and self.selectedIndex <= #servers then
            self.selectedServer = servers[self.selectedIndex]
            self.state = Menu.STATE.CONNECTING
            
            if self.onJoin then
                self.onJoin(self.selectedServer.ip, self.selectedServer.port)
            end
            self:hide()
        end
        return true
    elseif key == "escape" then
        self.state = Menu.STATE.MAIN
        self.selectedIndex = 2
        return true
    elseif key == "r" then
        -- Refresh
        self.discovery:sendDiscoveryRequest()
        return true
    end
    
    return false
end

function Menu:handleBrowseGamepad(button)
    local servers = self.discovery:getServers()
    
    if button == "dpup" then
        self.selectedIndex = math.max(1, self.selectedIndex - 1)
        return true
    elseif button == "dpdown" then
        self.selectedIndex = math.min(math.max(1, #servers), self.selectedIndex + 1)
        return true
    elseif button == "a" then
        if #servers > 0 and self.selectedIndex <= #servers then
            self.selectedServer = servers[self.selectedIndex]
            self.state = Menu.STATE.CONNECTING
            
            if self.onJoin then
                self.onJoin(self.selectedServer.ip, self.selectedServer.port)
            end
            self:hide()
        end
        return true
    elseif button == "b" or button == "back" then
        self.state = Menu.STATE.MAIN
        self.selectedIndex = 2
        return true
    elseif button == "x" or button == "y" then
        -- Refresh
        self.discovery:sendDiscoveryRequest()
        return true
    end
    
    return false
end

function Menu:close()
    -- Discovery is owned by Game, don't close it here
end

return Menu
