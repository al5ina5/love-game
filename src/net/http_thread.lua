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

local requestChannel = love.thread.getChannel("http_request")
local responseChannel = love.thread.getChannel("http_response")

local function simple_http_request(method, url, body)
    -- Minimal implementation of SimpleHTTP for the thread
    -- This avoids complex dependencies in the thread
    
    local tempFile = os.tmpname()
    local tempStatusFile = os.tmpname()
    local tempBodyFile = nil
    
    local cmd = "curl -s -X " .. method
    cmd = cmd .. " -H 'Content-Type: application/json'"
    
    if body and (method == "POST" or method == "PUT") then
        tempBodyFile = os.tmpname()
        local f = io.open(tempBodyFile, "w")
        if f then
            f:write(body)
            f:close()
            cmd = cmd .. " -d @" .. tempBodyFile
        end
    end
    
    cmd = cmd .. " '" .. url .. "' -o " .. tempFile .. " -w '%{http_code}' > " .. tempStatusFile .. " 2>/dev/null"
    
    local result = os.execute(cmd)
    
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
