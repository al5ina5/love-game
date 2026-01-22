-- src/net/simple_http.lua
-- Simple HTTP client using curl/wget as fallback
-- Works for both HTTP and HTTPS

local SimpleHTTP = {}
SimpleHTTP.__index = SimpleHTTP

-- Execute shell command and return output
local function execCommand(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return nil, "Failed to execute command"
    end
    
    local output = handle:read("*a")
    local success = handle:close()
    
    if not success then
        return nil, "Command failed"
    end
    
    return output, nil
end

-- Check if curl is available
local function hasCurl()
    local output, err = execCommand("curl --version")
    return output ~= nil and output ~= ""
end

-- Check if wget is available
local function hasWget()
    local output, err = execCommand("wget --version")
    return output ~= nil and output ~= ""
end

-- Make HTTP request using curl
local function requestWithCurl(method, url, headers, body)
    local cmd = "curl -s -X " .. method
    
    -- Add headers
    if headers then
        for key, value in pairs(headers) do
            -- Escape header values properly for shell
            local escapedValue = value:gsub('"', '\\"')
            cmd = cmd .. " -H \"" .. key .. ": " .. escapedValue .. "\""
        end
    end
    
    -- Add body for POST/PUT
    if body and (method == "POST" or method == "PUT") then
        -- Use --data with single quotes and escape single quotes in the body
        -- Replace single quotes with '\'' (bash escaping)
        local escapedBody = body:gsub("'", "'\\''")
        cmd = cmd .. " --data '" .. escapedBody .. "'"
    end
    
    cmd = cmd .. " \"" .. url .. "\""
    
    print("Executing curl command...")
    if body then
        print("Body length: " .. #body .. " bytes")
        print("Body content: " .. body)
    end
    local output, err = execCommand(cmd)
    
    if err then
        print("Curl error: " .. tostring(err))
        return nil, err
    end
    
    if not output or output == "" then
        print("Curl returned empty response")
        return nil, "Empty response from curl"
    end
    
    -- Check if response is HTML (error page)
    if output:match("^%s*<!DOCTYPE") or output:match("^%s*<html") then
        print("Server returned HTML error page instead of JSON")
        print("Response: " .. output:sub(1, 500))
        return nil, "Server returned HTML error page: " .. output:sub(1, 200)
    end
    
    return output, nil
end

-- Make HTTP request using wget
local function requestWithWget(method, url, headers, body)
    local cmd = "wget -q -O -"
    
    -- Add headers
    if headers then
        for key, value in pairs(headers) do
            cmd = cmd .. " --header=\"" .. key .. ": " .. value .. "\""
        end
    end
    
    -- Add method (wget defaults to GET, need --method for POST)
    if method ~= "GET" then
        cmd = cmd .. " --method=" .. method
    end
    
    -- Add body for POST/PUT
    if body and (method == "POST" or method == "PUT") then
        cmd = cmd .. " --body-data='" .. body:gsub("'", "'\\''") .. "'"
    end
    
    cmd = cmd .. " \"" .. url .. "\""
    
    local output, err = execCommand(cmd)
    if err then
        return nil, err
    end
    
    return output, nil
end

-- Make HTTP/HTTPS request
-- method: string ("GET", "POST", etc.)
-- url: string
-- headers: table (optional)
-- body: string (optional, JSON string)
-- Returns: response body (string) or nil, error message
function SimpleHTTP.request(method, url, headers, body)
    method = method or "GET"
    headers = headers or {}
    
    print("SimpleHTTP: Making " .. method .. " request to " .. url)
    
    -- Try curl first (better HTTPS support)
    if hasCurl() then
        print("SimpleHTTP: Using curl")
        local response, err = requestWithCurl(method, url, headers, body)
        if response then
            print("SimpleHTTP: Curl request successful, response length: " .. #response)
            return response, nil
        else
            print("SimpleHTTP: Curl request failed: " .. (err or "Unknown error"))
            -- If curl fails, try wget
        end
    else
        print("SimpleHTTP: curl not available")
    end
    
    -- Try wget as fallback
    if hasWget() then
        print("SimpleHTTP: Using wget")
        local response, err = requestWithWget(method, url, headers, body)
        if response then
            print("SimpleHTTP: Wget request successful")
            return response, nil
        else
            print("SimpleHTTP: Wget request failed: " .. (err or "Unknown error"))
            return nil, err or "wget request failed"
        end
    else
        print("SimpleHTTP: wget not available")
    end
    
    return nil, "Neither curl nor wget is available"
end

return SimpleHTTP
