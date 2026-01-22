-- src/constants.lua
-- Common constants for love-game

local Constants = {}

-- Online multiplayer API endpoint
Constants.API_BASE_URL = "https://love-game-production.up.railway.app"
-- TCP Relay server for real-time communication
-- Railway TCP Proxy: ballast.proxy.rlwy.net:16563
Constants.RELAY_HOST = "ballast.proxy.rlwy.net"
Constants.RELAY_PORT = 16563

return Constants
