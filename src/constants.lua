-- src/constants.lua
-- Common constants for love-game

local Constants = {}

-- Online multiplayer API endpoint
Constants.API_BASE_URL = "https://love-game-production.up.railway.app"
-- TCP Relay server for real-time communication
-- Railway exposes TCP ports via a TCP Proxy service
-- 
-- SETUP INSTRUCTIONS:
-- 1. Go to Railway dashboard -> Your service -> Networking
-- 2. Enable "TCP Proxy" and set the port to 12346 (the internal port your server listens on)
-- 3. Railway will provide a proxy address like: turntable.proxy.rlwy.net:32378
-- 4. Update RELAY_HOST and RELAY_PORT below with the values Railway provides
--
-- For now, using placeholder values - UPDATE THESE after configuring TCP Proxy in Railway:
Constants.RELAY_HOST = "turntable.proxy.rlwy.net"  -- UPDATE: Your Railway TCP proxy host
Constants.RELAY_PORT = 32378  -- UPDATE: Your Railway TCP proxy port

return Constants
