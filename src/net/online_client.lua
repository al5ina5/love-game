-- src/net/online_client.lua
-- REST API client for Railway matchmaker server
-- Handles room creation, joining, listing, and keep-alive

local OnlineClient = {}
OnlineClient.__index = OnlineClient

-- Server URL - set this to your Railway deployment
OnlineClient.SERVER_URL = "https://love-game-production.up.railway.app"

-- Try to load dkjson once at module load time
local dkjson = nil
local function loadDkjson()
    if dkjson then return dkjson end
    
    -- Try src.lib.dkjson first
    print("Attempting to require src.lib.dkjson...")
    local success, module = pcall(require, "src.lib.dkjson")
    print("Require result: success=" .. tostring(success) .. ", module type=" .. type(module))
    
    if success then
        if module and type(module) == "table" then
            if module.encode and module.decode then
                dkjson = module
                print("dkjson loaded successfully from src.lib.dkjson (has encode and decode)")
                return dkjson
            else
                print("dkjson table loaded but missing methods. Has encode: " .. tostring(module.encode ~= nil) .. ", Has decode: " .. tostring(module.decode ~= nil))
                -- Try to use it anyway
                dkjson = module
                return dkjson
            end
        else
            print("dkjson returned non-table: " .. tostring(module) .. " (type: " .. type(module) .. ")")
        end
    else
        print("dkjson require failed with error: " .. tostring(module))
    end
    
    -- Try alternative path
    print("Attempting to require lib.dkjson...")
    success, module = pcall(require, "lib.dkjson")
    if success and module and type(module) == "table" then
        if module.encode and module.decode then
            dkjson = module
            print("dkjson loaded from lib.dkjson")
            return dkjson
        end
    end
    
    print("dkjson not available - all load attempts failed")
    return nil
end

-- Try loading immediately and print result
print("Attempting to load dkjson at module init...")
local initResult = loadDkjson()
if initResult then
    print("dkjson initialized successfully")
else
    print("dkjson initialization failed - will retry on first use")
end

function OnlineClient:new()
    local self = setmetatable({}, OnlineClient)
    self.serverUrl = OnlineClient.SERVER_URL
    return self
end

-- Set custom server URL (for testing or different deployments)
function OnlineClient:setServerUrl(url)
    self.serverUrl = url
end

-- Create a new room
-- isPublic: boolean (optional, default false)
-- hostId: string (optional, auto-generated if not provided)
-- Returns: { success: bool, roomCode: string, wsUrl: string } or { success: false, error: string }
function OnlineClient:createRoom(isPublic, hostId)
    isPublic = isPublic or false
    
    local url = self.serverUrl .. "/api/create-room"
    local body = {
        isPublic = isPublic,
        hostId = hostId
    }
    
    print("Creating room at: " .. url)
    local response = self:httpRequest("POST", url, body)
    
    if response then
        print("Response received, type: " .. type(response))
        if type(response) == "table" then
            print("Response keys: " .. table.concat(self:getTableKeys(response), ", "))
            if response.success then
                return {
                    success = true,
                    roomCode = response.roomCode,
                    wsUrl = response.wsUrl
                }
            else
                return {
                    success = false,
                    error = response.error or "Failed to create room"
                }
            end
        else
            print("Unexpected response type: " .. type(response))
            return {
                success = false,
                error = "Invalid response from server"
            }
        end
    else
        print("No response from server (nil)")
        return {
            success = false,
            error = "No response from server. Check network connection and server URL."
        }
    end
end

-- Helper to get table keys for debugging
function OnlineClient:getTableKeys(tbl)
    local keys = {}
    for k, v in pairs(tbl) do
        table.insert(keys, tostring(k))
    end
    return keys
end

-- Join a room by code
-- code: string (6-digit room code)
-- playerId: string (optional, auto-generated if not provided)
-- Returns: { success: bool, roomCode: string, wsUrl: string, playerId: string } or { success: false, error: string }
function OnlineClient:joinRoom(code, playerId)
    if not code then
        return { success = false, error = "Room code required" }
    end
    
    local url = self.serverUrl .. "/api/join-room"
    local body = {
        code = code,
        playerId = playerId
    }
    
    local response = self:httpRequest("POST", url, body)
    
    if response and response.success then
        return {
            success = true,
            roomCode = response.roomCode,
            wsUrl = response.wsUrl,
            playerId = response.playerId
        }
    else
        return {
            success = false,
            error = response and response.error or "Failed to join room"
        }
    end
end

-- List public rooms
-- Returns: { success: bool, rooms: array }
function OnlineClient:listRooms()
    local url = self.serverUrl .. "/api/list-rooms"
    local response = self:httpRequest("GET", url)
    
    if response and response.success then
        return {
            success = true,
            rooms = response.rooms or {}
        }
    else
        return {
            success = false,
            error = response and response.error or "Failed to list rooms",
            rooms = {}
        }
    end
end

-- Keep room alive (heartbeat)
-- code: string (room code)
-- Returns: { success: bool } or { success: false, error: string }
function OnlineClient:keepAlive(code)
    if not code then
        return { success = false, error = "Room code required" }
    end
    
    local url = self.serverUrl .. "/api/keep-alive"
    local body = { code = code }
    
    local response = self:httpRequest("POST", url, body)
    
    if response and response.success then
        return { success = true }
    else
        return {
            success = false,
            error = response and response.error or "Failed to keep room alive"
        }
    end
end

-- Get room status
-- code: string (room code)
-- Returns: { success: bool, room: table } or { success: false, error: string }
function OnlineClient:getRoomStatus(code)
    if not code then
        return { success = false, error = "Room code required" }
    end
    
    local url = self.serverUrl .. "/api/room/" .. code
    local response = self:httpRequest("GET", url)
    
    if response and response.success then
        return {
            success = true,
            room = response.room
        }
    else
        return {
            success = false,
            error = response and response.error or "Failed to get room status"
        }
    end
end

-- HTTP request helper
-- Tries multiple methods in order:
-- 1. lua-https (LOVE2D 12.0+)
-- 2. ssl.https (if available)
-- 3. simple_http (curl/wget fallback) - works for HTTPS
-- 4. luasocket (HTTP only)
-- method: string ("GET", "POST", etc.)
-- url: string
-- body: table (optional, will be JSON encoded)
-- Returns: parsed JSON response or nil
function OnlineClient:httpRequest(method, url, body)
    local headers = {
        ["Content-Type"] = "application/json"
    }
    local requestBody = nil
    if body then
        requestBody = self:jsonEncode(body)
    end
    
    -- Try 1: lua-https (LOVE2D 12.0+)
    local https, httpsErr = pcall(require, "https")
    if https then
        https = require("https")
        local options = {
            method = method,
            headers = headers
        }
        
        if requestBody then
            options.data = requestBody
        end
        
        local code, responseBody, responseHeaders = https.request(url, options)
        
        if code >= 200 and code < 300 then
            if responseBody and #responseBody > 0 then
                return self:jsonDecode(responseBody)
            else
                return {}
            end
        elseif code ~= 0 then
            print("HTTP Error " .. code .. ": " .. (responseBody or ""))
            -- Continue to fallback
        end
    end
    
    -- Try 2: ssl.https (if available)
    local ssl, sslErr = pcall(require, "ssl.https")
    if ssl then
        ssl = require("ssl.https")
        local ltn12 = require("ltn12")
        
        local responseBody = {}
        local result, code, responseHeaders, status = ssl.request{
            url = url,
            method = method,
            headers = headers,
            source = requestBody and ltn12.source.string(requestBody) or nil,
            sink = ltn12.sink.table(responseBody)
        }
        
        if code >= 200 and code < 300 then
            local bodyStr = table.concat(responseBody)
            if #bodyStr > 0 then
                return self:jsonDecode(bodyStr)
            else
                return {}
            end
        elseif code then
            print("HTTP Error " .. code .. ": " .. (status or ""))
            -- Continue to fallback
        end
    end
    
    -- Try 3: simple_http (curl/wget fallback) - works for HTTPS
    local simpleHTTP, simpleErr = pcall(require, "src.net.simple_http")
    if simpleHTTP then
        simpleHTTP = require("src.net.simple_http")
        print("Using curl/wget fallback for HTTPS request...")
        local responseBody, err = simpleHTTP.request(method, url, headers, requestBody)
        
        if responseBody then
            print("HTTP request successful, response length: " .. #responseBody)
            if #responseBody > 0 then
                local decoded = self:jsonDecode(responseBody)
                if decoded then
                    return decoded
                else
                    print("Failed to decode JSON response - server may have returned an error")
                    print("Response: " .. (responseBody:sub(1, 300) or ""))
                    -- Return error response structure
                    return {
                        success = false,
                        error = "Server returned invalid response (not JSON)"
                    }
                end
            else
                return {}
            end
        else
            print("SimpleHTTP error: " .. (err or "Unknown error"))
            return {
                success = false,
                error = err or "HTTP request failed"
            }
        end
    else
        print("SimpleHTTP not available: " .. tostring(simpleErr))
    end
    
    -- Try 4: luasocket (HTTP only, no HTTPS)
    local socket = require("socket")
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    
    -- Check if URL is HTTPS
    if url:match("^https://") then
        print("ERROR: All HTTPS methods failed.")
        print("Tried: lua-https, ssl.https, curl/wget fallback")
        print("URL: " .. url)
        print("Please ensure curl or wget is installed, or upgrade to LOVE2D 12.0+")
        return nil
    end
    
    -- HTTP request using luasocket
    local responseBody = {}
    local result, code, responseHeaders, status = http.request{
        url = url,
        method = method,
        headers = headers,
        source = requestBody and ltn12.source.string(requestBody) or nil,
        sink = ltn12.sink.table(responseBody)
    }
    
    if code >= 200 and code < 300 then
        local bodyStr = table.concat(responseBody)
        if #bodyStr > 0 then
            return self:jsonDecode(bodyStr)
        else
            return {}
        end
    else
        print("HTTP Error " .. code .. ": " .. (status or ""))
        return nil
    end
end

-- JSON encode - tries multiple methods
function OnlineClient:jsonEncode(data)
    -- Try LOVE2D's built-in JSON encoder first
    if love.data and love.data.encode then
        local success, result = pcall(function()
            return love.data.encode("string", "json", data)
        end)
        if success and result then
            return result
        end
    end
    
    -- Try dkjson library (load if not already loaded)
    local jsonLib = dkjson or loadDkjson()
    if jsonLib and type(jsonLib) == "table" then
        if jsonLib.encode then
            local success, result = pcall(function()
                return jsonLib.encode(data)
            end)
            if success and result then
                return result
            else
                print("dkjson.encode pcall failed: " .. tostring(result))
            end
        else
            print("dkjson loaded but missing encode method")
        end
    else
        print("dkjson not available: " .. tostring(jsonLib))
    end
    
    -- Fallback: error if no JSON library available
    error("JSON encoding not available. Please ensure LOVE2D 11.0+ or dkjson library is present. dkjson status: " .. tostring(dkjson))
end

-- JSON decode - tries multiple methods
function OnlineClient:jsonDecode(jsonString)
    if not jsonString or jsonString == "" then
        return nil
    end
    
    -- Check if response is HTML (error page) - don't try to decode as JSON
    if jsonString:match("^%s*<!DOCTYPE") or jsonString:match("^%s*<html") then
        print("Warning: Server returned HTML instead of JSON")
        print("Response: " .. jsonString:sub(1, 200))
        return nil  -- Return nil to indicate error, don't throw
    end
    
    -- Try LOVE2D's built-in JSON decoder first
    if love.data and love.data.decode then
        local success, result = pcall(function()
            return love.data.decode("string", "json", jsonString)
        end)
        if success and result then
            return result
        end
    end
    
    -- Try dkjson library (load if not already loaded)
    local jsonLib = dkjson or loadDkjson()
    if jsonLib and type(jsonLib) == "table" then
        if jsonLib.decode then
            local success, result = pcall(function()
                return jsonLib.decode(jsonString)
            end)
            if success and result then
                return result
            else
                print("dkjson.decode failed - response might not be valid JSON")
                print("Response preview: " .. jsonString:sub(1, 200))
                return nil  -- Return nil instead of throwing error
            end
        else
            print("dkjson loaded but missing decode method")
        end
    else
        print("dkjson not available for decode: " .. tostring(jsonLib))
    end
    
    -- Return nil instead of error - let caller handle it
    return nil
end

return OnlineClient
