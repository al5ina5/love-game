-- src/net/simple_http.lua
-- Simple HTTP client using system commands (curl/wget) as fallback
-- Works on systems without lua-sec installed

local json = require("src.lib.dkjson")

local SimpleHTTP = {}

-- Detect OS
local function isWindows()
    return love.system.getOS() == "Windows"
end

-- Get null device path based on OS
local function getNullDevice()
    return isWindows() and "NUL" or "/dev/null"
end

-- Quote arguments safely based on OS
local function quoteArg(arg)
    if isWindows() then
        -- Windows uses double quotes and escapes internal double quotes
        return '"' .. arg:gsub('"', '\\"') .. '"'
    else
        -- Unix uses single quotes and escapes internal single quotes
        return "'" .. arg:gsub("'", "'\\''") .. "'"
    end
end

-- Get a temporary file path that is safe to write to
local function getTempFile()
    local name = os.tmpname()
    -- Lua on Windows returns a name starting with backslash (e.g. \s2k3.) which tries to write to root C:
    -- We need to prepend the TEMP environment variable
    if isWindows() and name:sub(1,1) == "\\" then
        local temp = os.getenv("TEMP") or os.getenv("TMP")
        if temp then
            return temp .. name
        end
    end
    return name
end



-- Check if curl or wget is available
function SimpleHTTP.isAvailable()
    local nullDev = getNullDevice()
    
    -- Try curl first (most common, built into macOS and Windows 10+)
    local handle = io.popen("curl --version 2>" .. nullDev)
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result:match("curl") then
            return true, "curl"
        end
    end
    
    -- Try wget (common on Linux)
    handle = io.popen("wget --version 2>" .. nullDev)
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
    local tempFile = getTempFile()
    local tempStatusFile = getTempFile()
    local tempBodyFile = nil
    
    -- OS-specific settings
    local nullDev = getNullDevice()
    
    -- Build curl command
    -- Write status code to separate file for reliable parsing
    -- Note: We don't quote arguments yet, we do it when assembling the string
    local cmdParts = {"curl", "-s", "-X", method}
    
    -- Add headers FIRST (especially Content-Type must come before -d)
    if headers then
        for key, value in pairs(headers) do
            -- Only add Content-Type if we have a body
            if key ~= "Content-Type" or body then
                table.insert(cmdParts, "-H")
                table.insert(cmdParts, string.format("%s: %s", key, value))
            end
        end
    end
    
    -- Add body for POST requests AFTER headers
    if body then
        tempBodyFile = getTempFile()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            table.insert(cmdParts, "-d")
            -- On Windows, we can't use @ with tmpname directly if it has spaces? 
            -- Actually lua's os.tmpname() usually returns valid paths.
            -- But we should quote the file path too just in case.
            -- Curl treats @ as "read from file", so we attach it to the quoted path.
            -- EXCEPT: quoteArg adds quotes around the whole thing.
            -- So we need to handle this carefully.
            -- Actually, simpler approach: just quote the path.
            if isWindows() then
                table.insert(cmdParts, "@" .. tempBodyFile)
            else
                table.insert(cmdParts, "@" .. tempBodyFile)
            end
        end
    end
    
    -- URL
    table.insert(cmdParts, url)
    
    -- Output options (these are flags/paths, care with quoting if paths have spaces)
    -- We'll manually construct the final string to handle the complex parts
    
    local cmdString = "curl -s -X " .. method
    
    if headers then
        for key, value in pairs(headers) do
            if key ~= "Content-Type" or body then
                cmdString = cmdString .. " -H " .. quoteArg(string.format("%s: %s", key, value))
            end
        end
    end
    
    if body and tempBodyFile then
        local bodyPath = quoteArg(tempBodyFile)
        -- Remove quotes for the @ prefix construction if strictly needed, but curl handles @"path" fine in many shells? 
        -- Actually, safer is: -d @path. We just assume os.tmpname doesn't return spaces.
        -- If it does, we need quotes.
        -- Windows curl: -d @"C:\Path With Spaces\File" works.
        cmdString = cmdString .. " -d @" .. bodyPath
    end
    
    cmdString = cmdString .. " " .. quoteArg(url)
    
    -- Output flags
    cmdString = cmdString .. " -o " .. quoteArg(tempFile)
    cmdString = cmdString .. " -w " .. quoteArg("%{http_code}")
    cmdString = cmdString .. " > " .. quoteArg(tempStatusFile)
    cmdString = cmdString .. " 2>" .. nullDev
    
    -- Execute command
    print("Executing: " .. cmdString) -- Debug print
    local result = os.execute(cmdString)
    
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
        return false, "Failed to read response (Code " .. httpCode .. ")"
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
    local tempFile = getTempFile()
    local tempBodyFile = nil
    
    local nullDev = getNullDevice()
    
    -- Build wget command
    local cmdString = "wget -q --method=" .. method
    
    -- Add headers
    if headers then
        for key, value in pairs(headers) do
            cmdString = cmdString .. " " .. quoteArg(string.format("--header=%s: %s", key, value))
        end
    end
    
    -- Add body for POST requests
    if body then
        tempBodyFile = getTempFile()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            cmdString = cmdString .. " " .. quoteArg("--body-file=" .. tempBodyFile)
        end
    end
    
    -- Add URL and output file
    cmdString = cmdString .. " " .. quoteArg(url)
    cmdString = cmdString .. " -O " .. quoteArg(tempFile)
    cmdString = cmdString .. " 2>" .. nullDev
    
    -- Execute command
    local result = os.execute(cmdString)
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
