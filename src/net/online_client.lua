-- src/net/online_client.lua
-- Online multiplayer matchmaker client for the Render service
-- Handles room creation, listing, and joining via REST API

local json = require("src.lib.dkjson")
local Constants = require("src.constants")

-- Try to load HTTPS support (lua-sec - preferred method)
local https
local ltn12
local hasLuaSec = pcall(function()
    https = require("ssl.https")
    ltn12 = require("ltn12")
end)

-- Fallback: Try simple HTTP (curl/wget)
local SimpleHTTP
local hasSimpleHTTP = false
if not hasLuaSec then
    local success, module = pcall(require, "src.net.simple_http")
    if success then
        SimpleHTTP = module
        hasSimpleHTTP = SimpleHTTP.isAvailable()
    end
end

local OnlineClient = {}
OnlineClient.__index = OnlineClient

-- Check if online multiplayer is available
function OnlineClient.isAvailable()
    return hasLuaSec or hasSimpleHTTP
end

function OnlineClient:new()
    if not OnlineClient.isAvailable() then
        error("Online multiplayer requires HTTPS support (install lua-sec or ensure curl/wget is available)")
    end
    
    local self = setmetatable({}, OnlineClient)
    self.roomCode = nil
    self.connected = false
    self.apiUrl = Constants.API_BASE_URL
    self.httpMethod = hasLuaSec and "luasec" or "simple"
    
    return self
end

-- Helper: Make HTTP request
function OnlineClient:httpRequest(method, url, body)
    print("OnlineClient: HTTP " .. method .. " " .. url)
    if body then
        print("OnlineClient: Request body: " .. body:sub(1, 200))
    end
    
    if self.httpMethod == "luasec" then
        local response = {}
        local headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = body and tostring(#body) or "0"
        }
        
        local request = {
            url = url,
            method = method,
            headers = headers,
            source = body and ltn12.source.string(body) or nil,
            sink = ltn12.sink.table(response)
        }
        
        local ok, code = https.request(request)
        if not ok then 
            print("OnlineClient: luasec request failed: " .. tostring(code))
            return false, "Request failed: " .. tostring(code) 
        end
        
        local responseBody = table.concat(response)
        print("OnlineClient: Response code: " .. tostring(code) .. ", body length: " .. #responseBody)
        if code >= 200 and code < 300 then
            local success, data = pcall(json.decode, responseBody)
            if not success then
                print("OnlineClient: JSON decode failed. Response: " .. responseBody:sub(1, 500))
                return false, "Invalid JSON response"
            end
            return success, data
        else
            print("OnlineClient: HTTP error " .. code .. ": " .. responseBody:sub(1, 200))
            return false, "HTTP " .. code .. ": " .. (responseBody:sub(1, 100) or "")
        end
    else
        local success, data = SimpleHTTP.request(method, url, body)
        if not success then
            print("OnlineClient: SimpleHTTP request failed: " .. tostring(data))
        else
            print("OnlineClient: SimpleHTTP request succeeded")
        end
        return success, data
    end
end

-- Matchmaking API
function OnlineClient:createRoom(isPublic)
    print("OnlineClient: Creating room (public: " .. tostring(isPublic) .. ") at " .. self.apiUrl .. "/api/create-room")
    local success, response = self:httpRequest("POST", self.apiUrl .. "/api/create-room", json.encode({ isPublic = isPublic or false }))
    if not success then 
        print("OnlineClient: createRoom failed - success=" .. tostring(success) .. ", response=" .. tostring(response))
        return false, response or "Unknown error"
    end
    if not response or not response.roomCode then
        print("OnlineClient: createRoom response missing roomCode. Response: " .. (response and json.encode(response) or "nil"))
        return false, "Invalid response from server"
    end
    self.roomCode = response.roomCode
    print("OnlineClient: Room created successfully: " .. self.roomCode)
    return true, self.roomCode
end

function OnlineClient:joinRoom(roomCode)
    local success = self:httpRequest("POST", self.apiUrl .. "/api/join-room", json.encode({ roomCode = roomCode:upper() }))
    if not success then return false end
    self.roomCode = roomCode:upper()
    return true
end

function OnlineClient:listRooms()
    local success, response = self:httpRequest("GET", self.apiUrl .. "/api/list-rooms")
    if not success then return {} end
    return response.rooms or {}
end

function OnlineClient:heartbeat()
    if not self.roomCode then return false end
    return self:httpRequest("POST", self.apiUrl .. "/api/heartbeat", json.encode({ roomCode = self.roomCode }))
end

function OnlineClient:disconnect()
    self.roomCode = nil
    self.connected = false
end

return OnlineClient
