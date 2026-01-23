-- src/constants.lua
-- Common constants for love-game

local Constants = {}

-- Online multiplayer API endpoint
-- Set USE_LOCAL_API=true to use localhost for testing
-- Can be set via:
-- 1. Environment variable: export USE_LOCAL_API=true
-- 2. .env file: USE_LOCAL_API=true
-- 3. config.lua file: Constants.USE_LOCAL_API = true

local env_value = os.getenv("USE_LOCAL_API")
print("Constants: USE_LOCAL_API env value = " .. tostring(env_value))

-- Try to read from .env file if env var is not set
if not env_value then
    -- Helper function to parse .env file content
    local function parseEnvContent(content)
        for line in content:gmatch("[^\r\n]+") do
            -- Skip comments and empty lines
            line = line:match("^%s*(.-)%s*$")  -- trim
            if line and not line:match("^#") and line ~= "" then
                -- Parse KEY=VALUE format (handle quoted values)
                local key, value = line:match("^([^=]+)=(.+)$")
                if key and value then
                    key = key:match("^%s*(.-)%s*$")  -- trim
                    value = value:match("^%s*(.-)%s*$")  -- trim
                    -- Remove quotes if present
                    value = value:match("^[\"'](.-)[\"']$") or value
                    if key == "USE_LOCAL_API" then
                        return value
                    end
                end
            end
        end
        return nil
    end
    
    -- Try multiple paths for .env file
    local env_paths = {}
    
    -- Add current working directory
    table.insert(env_paths, ".env")
    
    -- Add paths relative to LÖVE source
    if love and love.filesystem then
        local source = love.filesystem.getSource()
        if source then
            table.insert(env_paths, source .. "/.env")
            -- Also try parent directory (in case running from src/)
            table.insert(env_paths, source .. "/../.env")
        end
    end
    
    -- Try io.open for each path
    for _, path in ipairs(env_paths) do
        local env_file = io.open(path, "r")
        if env_file then
            print("Constants: Trying to read .env from: " .. path)
            local content = env_file:read("*all")
            env_file:close()
            if content then
                env_value = parseEnvContent(content)
                if env_value then
                    print("Constants: Found USE_LOCAL_API in .env file: " .. tostring(env_value) .. " (from " .. path .. ")")
                    break
                end
            end
        end
    end
    
    -- Try love.filesystem as fallback
    if not env_value and love and love.filesystem then
        local success, contents = pcall(function()
            if love.filesystem.getInfo(".env") then
                return love.filesystem.read(".env")
            end
        end)
        if success and contents then
            print("Constants: Reading .env via love.filesystem")
            env_value = parseEnvContent(contents)
            if env_value then
                print("Constants: Found USE_LOCAL_API in .env file (via love.filesystem): " .. tostring(env_value))
            end
        end
    end
    
    if not env_value then
        print("Constants: No .env file found or USE_LOCAL_API not in .env")
    end
end

local USE_LOCAL_API = env_value == "true"

if USE_LOCAL_API then
    Constants.API_BASE_URL = "http://localhost:3000"
    Constants.RELAY_HOST = "localhost"
    Constants.RELAY_PORT = 12346
    print("========================================")
    print("Constants: Using LOCAL API for testing")
    print("  API: " .. Constants.API_BASE_URL)
    print("  Relay: " .. Constants.RELAY_HOST .. ":" .. Constants.RELAY_PORT)
    print("========================================")
else
    Constants.API_BASE_URL = "https://love-game-production.up.railway.app"
    -- TCP Relay server for real-time communication
    -- Railway TCP Proxy: ballast.proxy.rlwy.net:16563
    Constants.RELAY_HOST = "ballast.proxy.rlwy.net"
    Constants.RELAY_PORT = 16563
    print("========================================")
    print("Constants: Using PRODUCTION API")
    print("  API: " .. Constants.API_BASE_URL)
    print("  Relay: " .. Constants.RELAY_HOST .. ":" .. Constants.RELAY_PORT)
    print("========================================")
end

return Constants
