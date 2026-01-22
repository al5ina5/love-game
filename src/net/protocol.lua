-- src/net/protocol.lua
-- Simple network message protocol

local Protocol = {}

-- Message types
Protocol.MSG = {
    PLAYER_JOIN = "join",
    PLAYER_LEAVE = "leave",
    PLAYER_MOVE = "move",
}

-- Serialize: type|field1|field2|...
function Protocol.encode(msgType, ...)
    local parts = {msgType}
    for _, v in ipairs({...}) do
        table.insert(parts, tostring(v))
    end
    return table.concat(parts, "|")
end

-- Deserialize
function Protocol.decode(data)
    local parts = {}
    for part in string.gmatch(data, "[^|]+") do
        table.insert(parts, part)
    end
    
    local msgType = parts[1]
    local msg = { type = msgType }
    
    if msgType == Protocol.MSG.PLAYER_MOVE then
        msg.id = parts[2]
        msg.x = tonumber(parts[3]) or 0
        msg.y = tonumber(parts[4]) or 0
        msg.dir = parts[5] or "down"
        
    elseif msgType == Protocol.MSG.PLAYER_JOIN then
        msg.id = parts[2]
        msg.x = tonumber(parts[3]) or 400
        msg.y = tonumber(parts[4]) or 300
        
    elseif msgType == Protocol.MSG.PLAYER_LEAVE then
        msg.id = parts[2]
    end
    
    return msg
end

return Protocol
