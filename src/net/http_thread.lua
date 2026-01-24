-- src/net/http_thread.lua
-- Love2D thread for background HTTP requests

-- Love2D threads have a clean environment, so we need to setup the path
-- to include the project root so we can require dkjson
local projectRoot = ... or ""
if projectRoot ~= "" then
    package.path = projectRoot .. "/?.lua;" .. projectRoot .. "/?/init.lua;" .. package.path
end

local json = nil
pcall(function() json = require("src.lib.dkjson") end)

-- Threads don't load all love modules by default
require("love.system")
require("love.filesystem") -- Also good practice since we use getSourceBaseDirectory passed in, but we might need it.


local requestChannel = love.thread.getChannel("http_request")
local responseChannel = love.thread.getChannel("http_response")

local function isWindows()
    return love.system.getOS() == "Windows"
end

local function getNullDevice()
    return isWindows() and "NUL" or "/dev/null"
end

local function quoteArg(arg)
    if isWindows() then
        return '"' .. arg:gsub('"', '\\"') .. '"'
    else
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



local function simple_http_request(method, url, body)
    -- Minimal implementation of SimpleHTTP for the thread
    -- This avoids complex dependencies in the thread
    
    local tempFile = getTempFile()
    local tempStatusFile = getTempFile()
    local tempBodyFile = nil
    
    local nullDev = getNullDevice()
    
    local cmdString = "curl -s -X " .. method
    cmdString = cmdString .. " -H " .. quoteArg("Content-Type: application/json")
    
    if body and (method == "POST" or method == "PUT") then
        tempBodyFile = getTempFile()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            cmdString = cmdString .. " -d @" .. quoteArg(tempBodyFile)
        end
    end
    
    cmdString = cmdString .. " " .. quoteArg(url)
    cmdString = cmdString .. " -o " .. quoteArg(tempFile)
    cmdString = cmdString .. " -w " .. quoteArg("%{http_code}")
    cmdString = cmdString .. " > " .. quoteArg(tempStatusFile)
    cmdString = cmdString .. " 2>" .. nullDev
    
    local result = os.execute(cmdString)
    
    local statusFile = io.open(tempStatusFile, "r")
    local httpCode = "500"
    if statusFile then
        local statusContent = statusFile:read("*a")
        statusFile:close()
        httpCode = statusContent:match("(%d+)") or "500"
    end
    os.remove(tempStatusFile)
    
    local f = io.open(tempFile, "r")
    local responseBody = ""
    if f then
        responseBody = f:read("*a")
        f:close()
    end
    os.remove(tempFile)
    if tempBodyFile then os.remove(tempBodyFile) end
    
    return tonumber(httpCode) or 500, responseBody
end

while true do
    local request = requestChannel:demand() -- Wait for a request
    if request == "quit" then break end
    if type(request) == "table" then
        local id = request.id
        local method = request.method or "GET"
        local url = request.url
        
        local code, body = simple_http_request(method, url, request.body)
        local responseBody = body
        
        -- Optionally decode JSON in background to prevent main thread stalls
        if request.decodeJson and json and code >= 200 and code < 300 and body ~= "" then
            local success, decoded = pcall(json.decode, body)
            if success then
                responseBody = decoded
            end
        end
        
        responseChannel:push({
            id = id,
            code = code,
            body = responseBody
        })
    end
end
