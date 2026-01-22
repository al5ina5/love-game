-- src/net/adapter.lua
-- NetworkAdapter abstraction interface
-- Allows game logic to work with different network backends (WebSocket, etc.)

local NetworkAdapter = {}

-- Abstract interface that all network implementations must follow
NetworkAdapter.Interface = {
    -- Connect to a room using room code
    -- Returns: success (bool), error message (string or nil)
    connect = function(self, roomCode, playerId, isHost) end,
    
    -- Disconnect from current room
    disconnect = function(self) end,
    
    -- Send a game message
    -- msgType: string (e.g., "input", "state", "event")
    -- ...: message data
    sendMessage = function(self, msgType, ...) end,
    
    -- Poll for incoming messages
    -- Returns: array of messages
    poll = function(self) end,
    
    -- Check if connected
    -- Returns: bool
    isConnected = function(self) end,
    
    -- Get connection info (for debugging)
    -- Returns: table with connection details
    getConnectionInfo = function(self) end,
}

-- Helper to check if an object implements the interface
function NetworkAdapter.implements(obj)
    local required = {"connect", "disconnect", "sendMessage", "poll", "isConnected"}
    for _, method in ipairs(required) do
        if not obj[method] or type(obj[method]) ~= "function" then
            return false, "Missing method: " .. method
        end
    end
    return true
end

return NetworkAdapter
