-- src/net/simple_http.lua
-- Simple HTTP client using system commands (curl/wget) as fallback
-- Works on systems without lua-sec installed

local json = require("src.lib.dkjson")

local SimpleHTTP = {}

-- Check if curl or wget is available
function SimpleHTTP.isAvailable()
    -- Try curl first (most common, built into macOS and Windows 10+)
    local handle = io.popen("curl --version 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result:match("curl") then
            return true, "curl"
        end
    end
    
    -- Try wget (common on Linux)
    handle = io.popen("wget --version 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result:match("GNU Wget") then
            return true, "wget"
        end
    end
    
    return false, nil
end

-- Make HTTP request using curl
function SimpleHTTP.requestWithCurl(method, url, body, headers)
    local tempFile = os.tmpname()
    local tempStatusFile = os.tmpname()
    local tempBodyFile = nil
    
    -- Build curl command
    -- Write status code to separate file for reliable parsing
    local cmd = "curl -s -X " .. method
    
    -- Add headers FIRST (especially Content-Type must come before -d)
    if headers then
        for key, value in pairs(headers) do
            -- Only add Content-Type if we have a body
            if key ~= "Content-Type" or body then
                cmd = cmd .. string.format(" -H '%s: %s'", key, value)
            end
        end
    end
    
    -- Add body for POST requests AFTER headers
    if body then
        tempBodyFile = os.tmpname()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            cmd = cmd .. " -d @" .. tempBodyFile
        end
    end
    
    -- Add URL and output files
    cmd = cmd .. " '" .. url .. "' -o " .. tempFile .. " -w '%{http_code}' > " .. tempStatusFile .. " 2>/dev/null"
    
    -- Execute command
    local result = os.execute(cmd)
    
    -- Read HTTP status code
    local statusFile = io.open(tempStatusFile, "r")
    local httpCode = "500"
    if statusFile then
        local statusContent = statusFile:read("*a")
        statusFile:close()
        httpCode = statusContent:match("(%d+)") or "500"
    end
    os.remove(tempStatusFile)
    
    -- Read response body
    local f = io.open(tempFile, "r")
    if not f then
        if tempBodyFile then os.remove(tempBodyFile) end
        os.remove(tempFile)
        return false, "Failed to read response"
    end
    
    local responseBody = f:read("*a")
    f:close()
    
    -- Cleanup temp files
    os.remove(tempFile)
    if tempBodyFile then os.remove(tempBodyFile) end
    
    local code = tonumber(httpCode) or 500
    
    if code >= 200 and code < 300 then
        if responseBody and responseBody ~= "" then
            local success, data = pcall(json.decode, responseBody)
            if success and data then
                return true, data
            end
        end
        return true, {}
    else
        return false, "HTTP " .. code .. ": " .. (responseBody or "")
    end
end

-- Make HTTP request using wget
function SimpleHTTP.requestWithWget(method, url, body, headers)
    local tempFile = os.tmpname()
    local tempBodyFile = nil
    
    -- Build wget command
    local cmd = "wget -q --method=" .. method
    
    -- Add headers
    if headers then
        for key, value in pairs(headers) do
            cmd = cmd .. string.format(" --header='%s: %s'", key, value)
        end
    end
    
    -- Add body for POST requests
    if body then
        tempBodyFile = os.tmpname()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            cmd = cmd .. " --body-file=" .. tempBodyFile
        end
    end
    
    -- Add URL and output file
    cmd = cmd .. " '" .. url .. "' -O " .. tempFile .. " 2>/dev/null"
    
    -- Execute command
    local result = os.execute(cmd)
    local success = (result == 0 or result == true)
    
    -- Read response
    local f = io.open(tempFile, "r")
    if not f then
        if tempBodyFile then os.remove(tempBodyFile) end
        os.remove(tempFile)
        return false, "Failed to read response"
    end
    
    local responseBody = f:read("*a")
    f:close()
    
    -- Cleanup temp files
    os.remove(tempFile)
    if tempBodyFile then os.remove(tempBodyFile) end
    
    if success and responseBody and responseBody ~= "" then
        local jsonSuccess, data = pcall(json.decode, responseBody)
        if jsonSuccess and data then
            return true, data
        end
    end
    
    return false, "Request failed or invalid JSON response"
end

-- Generic request method that auto-detects which tool to use
function SimpleHTTP.request(method, url, body)
    local available, tool = SimpleHTTP.isAvailable()
    
    if not available then
        return false, "No HTTP client available (curl/wget not found)"
    end
    
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    if tool == "curl" then
        return SimpleHTTP.requestWithCurl(method, url, body, headers)
    elseif tool == "wget" then
        return SimpleHTTP.requestWithWget(method, url, body, headers)
    end
    
    return false, "Unknown HTTP client: " .. tostring(tool)
end

-- Convenience methods
function SimpleHTTP.get(url)
    return SimpleHTTP.request("GET", url, nil)
end

function SimpleHTTP.post(url, body)
    return SimpleHTTP.request("POST", url, body)
end

return SimpleHTTP
