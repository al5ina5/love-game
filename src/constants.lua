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

-- Helper function to parse .env file content
local function parseEnvContent(content)
    local env_vars = {}
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
                env_vars[key] = value
            end
        end
    end
    return env_vars
end

-- Always try to read .env file for custom API URLs and USE_LOCAL_API
local env_vars = {}

-- When running from a .love file, love.filesystem is the only way to read files
-- Try love.filesystem first (works for both .love archives and regular files)
if love and love.filesystem then
    local success, contents = pcall(function()
        if love.filesystem.getInfo(".env") then
            return love.filesystem.read(".env")
        end
    end)
    if success and contents then
        env_vars = parseEnvContent(contents)
        -- Only override env_value if it wasn't set via environment variable
        if not env_value and env_vars["USE_LOCAL_API"] then
            env_value = env_vars["USE_LOCAL_API"]
        end
    end
end

-- Fallback: Try io.open for development (when not running from .love file)
if not next(env_vars) then
    local env_paths = {}
    table.insert(env_paths, ".env")
    
    if love and love.filesystem then
        local source = love.filesystem.getSource()
        if source then
            table.insert(env_paths, source .. "/.env")
            table.insert(env_paths, source .. "/../.env")
        end
    end
    
    for _, path in ipairs(env_paths) do
        local env_file = io.open(path, "r")
        if env_file then
            local content = env_file:read("*all")
            env_file:close()
            if content then
                env_vars = parseEnvContent(content)
                -- Only override env_value if it wasn't set via environment variable
                if not env_value and env_vars["USE_LOCAL_API"] then
                    env_value = env_vars["USE_LOCAL_API"]
                end
                if next(env_vars) then
                    break
                end
            end
        end
    end
end

if not env_value and not next(env_vars) then
    print("Constants: No .env file found")
end

local USE_LOCAL_API = env_value == "true"

-- Check for custom API URLs in .env file (takes precedence)
local custom_api_url = env_vars["API_BASE_URL"]
local custom_relay_host = env_vars["RELAY_HOST"]
local custom_relay_port = env_vars["RELAY_PORT"]

if custom_api_url then
    -- Use custom API URLs from .env file
    Constants.API_BASE_URL = custom_api_url
    Constants.RELAY_HTTP = custom_api_url
    Constants.RELAY_HOST = custom_relay_host or "localhost"
    Constants.RELAY_PORT = tonumber(custom_relay_port) or 12346
    print("========================================")
    print("Constants: Using CUSTOM API from .env")
    print("  API: " .. Constants.API_BASE_URL)
    print("  Relay: " .. Constants.RELAY_HOST .. ":" .. Constants.RELAY_PORT)
    print("========================================")
elseif USE_LOCAL_API then
    Constants.API_BASE_URL = "http://localhost:3000"
    Constants.RELAY_HTTP = "http://localhost:3000"
    Constants.RELAY_HOST = "localhost"
    Constants.RELAY_PORT = 12346
    print("========================================")
    print("Constants: Using LOCAL API for testing")
    print("  API: " .. Constants.API_BASE_URL)
    print("  Relay: " .. Constants.RELAY_HOST .. ":" .. Constants.RELAY_PORT)
    print("========================================")
else
    Constants.API_BASE_URL = "https://love-game-production.up.railway.app"
    Constants.RELAY_HTTP = "https://love-game-production.up.railway.app"
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

-- Desaturation effect: Set to false to disable timer-based desaturation for development
-- When enabled, the game will gradually lose saturation as the timer approaches 0
Constants.ENABLE_DESATURATION_EFFECT = env_vars["ENABLE_DESATURATION_EFFECT"] == "true" or false

-- Dev mode: show debug visuals (e.g. faint lines from player to NPCs for distance)
Constants.DEV_MODE = env_vars["DEV_MODE"] == "true" or (env_vars["DEV_MODE"] == nil and true)
Constants.DEV_SPRINT_MULTIPLIER = tonumber(env_vars["DEV_SPRINT_MULTIPLIER"]) or 5.0 -- Much faster for dev

-- Temporarily disable chest interactions
Constants.DISABLE_CHESTS = env_vars["DISABLE_CHESTS"] == "true" or (env_vars["DISABLE_CHESTS"] == nil and true)

-- Performance and Network Settings
Constants.NETWORK_POLL_RATE = 1/30  -- 30Hz network polling
Constants.TARGET_FPS = 60          -- 60 FPS target
Constants.FRAME_SLEEP_ENABLED = false

-- Prediction and Interpolation
Constants.PREDICTION_CORRECTION_SPEED = 5.0
Constants.MAX_PREDICTION_ERROR = 50
Constants.INTERPOLATION_SPEED = 8

-- Network Rates
Constants.BASE_SEND_RATE = 1/30
Constants.MAX_SEND_RATE = 1/60
Constants.MIN_SEND_RATE = 1/10

-- Remote Player Tuning
Constants.REMOTE_LERP_SPEED = 8
Constants.MAX_EXTRAPOLATION_TIME = 0.5



-- World Generation Feature Toggles (Debugging)
Constants.ENABLE_GENERATION_TREES = true
Constants.ENABLE_GENERATION_WATER = true
Constants.ENABLE_GENERATION_ROADS = true

-- Debug Logging
Constants.ENABLE_MEMORY_LOGGING = true

-- Water Collision Masks (0-16 range within a tile)
-- IDs match WATER_TILES in water_generator.lua
Constants.WATER_COLLISION_MASKS = {
    [1] = { {x = 4, y = 4, w = 12, h = 12} }, -- CORNER_NW (Water in Bottom-Right)
    [3] = { {x = 0, y = 4, w = 12, h = 12} }, -- CORNER_NE (Water in Bottom-Left)
    [7] = { {x = 4, y = 0, w = 12, h = 12} }, -- CORNER_SW (Water in Top-Right)
    [9] = { {x = 0, y = 0, w = 12, h = 12} }, -- CORNER_SE (Water in Top-Left)
    [2] = { {x = 0, y = 4, w = 16, h = 12} }, -- EDGE_N (Water in Bottom)
    [8] = { {x = 0, y = 0, w = 16, h = 12} }, -- EDGE_S (Water in Top)
    [4] = { {x = 4, y = 0, w = 12, h = 16} }, -- EDGE_W (Water in Right)
    [6] = { {x = 0, y = 0, w = 12, h = 16} }, -- EDGE_E (Water in Left)
    [5] = { {x = 0, y = 0, w = 16, h = 16} }, -- CENTER (Full tile)
    
    -- Inner Corners (Mainly water, small grass corner)
    [14] = { {x = 4, y = 0, w = 12, h = 16}, {x = 0, y = 4, w = 4, h = 12} }, -- INNER_NW (Grass in top-left)
    [13] = { {x = 0, y = 0, w = 12, h = 16}, {x = 12, y = 4, w = 4, h = 12} }, -- INNER_NE (Grass in top-right)
    [11] = { {x = 0, y = 0, w = 12, h = 16}, {x = 12, y = 0, w = 4, h = 12} }, -- INNER_SW (Grass in bottom-left)
    [10] = { {x = 4, y = 0, w = 12, h = 16}, {x = 0, y = 0, w = 4, h = 12} }, -- INNER_SE (Grass in bottom-right)
}

return Constants
