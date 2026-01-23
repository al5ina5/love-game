-- src/net/protocol.lua
-- Simple network message protocol

local Protocol = {}

-- Message types
Protocol.MSG = {
    PLAYER_JOIN = "join",
    PLAYER_LEAVE = "leave",
    PLAYER_MOVE = "move",
    PET_MOVE = "pet_move",
    ROCKS_DATA = "rocks",
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
        msg.skin = parts[6]  -- Optional skin name
        
    elseif msgType == Protocol.MSG.PLAYER_JOIN then
        msg.id = parts[2]
        msg.x = tonumber(parts[3]) or 400
        msg.y = tonumber(parts[4]) or 300
        msg.skin = parts[5]  -- Optional skin name
        
    elseif msgType == Protocol.MSG.PLAYER_LEAVE then
        msg.id = parts[2]
        
    elseif msgType == Protocol.MSG.PET_MOVE then
        msg.id = parts[2]  -- Owner player ID
        msg.x = tonumber(parts[3]) or 0
        msg.y = tonumber(parts[4]) or 0
        msg.monster = parts[5]  -- Optional monster name
        
    elseif msgType == Protocol.MSG.ROCKS_DATA then
        -- Format: rocks|count|x1|y1|tileId1|actualTileNum1|x2|y2|tileId2|actualTileNum2|...
        msg.count = tonumber(parts[2]) or 0
        msg.rocks = {}
        for i = 1, msg.count do
            local idx = (i - 1) * 4 + 3  -- 4 values per rock now
            if parts[idx] and parts[idx + 1] and parts[idx + 2] then
                table.insert(msg.rocks, {
                    x = tonumber(parts[idx]) or 0,
                    y = tonumber(parts[idx + 1]) or 0,
                    tileId = tonumber(parts[idx + 2]) or 1,
                    actualTileNum = tonumber(parts[idx + 3]) or 1
                })
            end
        end
    end
    
    return msg
end

return Protocol
