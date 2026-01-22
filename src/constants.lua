-- src/constants.lua
-- Common constants for love-game

local Constants = {}

-- Online multiplayer API endpoint
Constants.API_BASE_URL = "https://love-game-production.up.railway.app"
-- TCP Relay server for real-time communication
-- NOTE: You need to set up a TCP relay server similar to blockdropper's relay server
-- The relay server should listen on a TCP port and relay messages between players in the same room
-- For now, using the same host but different port - update these when relay server is deployed
Constants.RELAY_HOST = "love-game-production.up.railway.app" 
Constants.RELAY_PORT = 12346  -- TCP relay port (needs to be configured in Railway)

return Constants
