-- src/net/protocol.lua
-- Simple network message protocol

local Protocol = {}
local json = require("src.lib.dkjson")

-- Message types
Protocol.MSG = {
    PLAYER_JOIN = "join",
    PLAYER_LEAVE = "leave",
    PLAYER_MOVE = "move",
    PET_MOVE = "pet_move",
    ROCKS_DATA = "rocks",
    ROADS_DATA = "roads",  -- Road tile data
    NPC_DATA = "npcs",  -- NPC positions and data
    ANIMALS_DATA = "animals",  -- Animal positions and data
    CYCLE_TIME = "cycle",  -- Cycle time update from server
    EXTRACTION = "extract",  -- Extraction event
    STATE_SNAPSHOT = "state",  -- Full game state snapshot
    INPUT_SHOOT = "shoot",  -- Player shoot input
    INPUT_INTERACT = "interact",  -- Player interact input
    EVENT_BOON_GRANTED = "boon",  -- Boon granted event
    EVENT_PLAYER_DIED = "died",  -- Player death event
    EVENT_BOON_STOLEN = "stolen",  -- Boon stolen event
    EVENT_CHEST_OPENED = "chest",  -- Chest opened event
    EVENT_PROJECTILE = "proj",  -- Projectile event
    PING = "ping",  -- Ping request
    PONG = "pong",  -- Ping response
    CHUNK_DATA = "chunk", -- Chunk data from server
    REQUEST_CHUNK = "req_chunk", -- Request chunk from client
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
        msg.sprinting = parts[7] == "1" or parts[7] == "true"  -- Sprint state (optional, defaults to false)
        
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

    elseif msgType == Protocol.MSG.ROADS_DATA then
        -- Format: roads|count|x1|y1|roadType1|material1|width1|x2|y2|roadType2|material2|width2|...
        msg.count = tonumber(parts[2]) or 0
        msg.roads = {}
        for i = 1, msg.count do
            local idx = (i - 1) * 5 + 3  -- 5 values per road tile: x, y, roadType, material, width
            if parts[idx] and parts[idx + 1] and parts[idx + 2] then
                table.insert(msg.roads, {
                    x = tonumber(parts[idx]) or 0,
                    y = tonumber(parts[idx + 1]) or 0,
                    roadType = tonumber(parts[idx + 2]) or 1,
                    material = parts[idx + 3] or "dirt",
                    width = tonumber(parts[idx + 4]) or 1
                })
            end
        end

    elseif msgType == Protocol.MSG.NPC_DATA then
        -- Format: npcs|count|x1|y1|spritePath1|name1|dialogue1|x2|y2|spritePath2|name2|dialogue2|...
        -- Dialogue is JSON encoded
        msg.count = tonumber(parts[2]) or 0
        msg.npcs = {}
        for i = 1, msg.count do
            local idx = (i - 1) * 5 + 3  -- 5 values per NPC: x, y, spritePath, name, dialogue
            if parts[idx] and parts[idx + 1] then
                local dialogueJson = parts[idx + 4] or "[]"
                local json = require("src.lib.dkjson")
                local dialogue = {}
                local success, decoded = pcall(json.decode, dialogueJson)
                if success and decoded then
                    dialogue = decoded
                end
                table.insert(msg.npcs, {
                    x = tonumber(parts[idx]) or 0,
                    y = tonumber(parts[idx + 1]) or 0,
                    spritePath = parts[idx + 2] or "",
                    name = parts[idx + 3] or "NPC",
                    dialogue = dialogue
                })
            end
        end
        
    elseif msgType == Protocol.MSG.ANIMALS_DATA then
        -- Format: animals|count|x1|y1|spritePath1|name1|speed1|groupCenterX1|groupCenterY1|groupRadius1|x2|y2|...
        msg.count = tonumber(parts[2]) or 0
        msg.animals = {}
        for i = 1, msg.count do
            local idx = (i - 1) * 8 + 3  -- 8 values per animal
            if parts[idx] and parts[idx + 1] then
                table.insert(msg.animals, {
                    x = tonumber(parts[idx]) or 0,
                    y = tonumber(parts[idx + 1]) or 0,
                    spritePath = parts[idx + 2] or "",
                    name = parts[idx + 3] or "Animal",
                    speed = tonumber(parts[idx + 4]) or 30,
                    groupCenterX = tonumber(parts[idx + 5]) or 0,
                    groupCenterY = tonumber(parts[idx + 6]) or 0,
                    groupRadius = tonumber(parts[idx + 7]) or 150
                })
            end
        end
        
    -- Boon Snatch game action messages
    elseif msgType == Protocol.MSG.INPUT_SHOOT then
        -- Format: shoot|playerId|angle
        msg.id = parts[2]
        msg.angle = tonumber(parts[3]) or 0
        
    elseif msgType == Protocol.MSG.INPUT_INTERACT then
        -- Format: interact|playerId
        msg.id = parts[2]
        
    elseif msgType == Protocol.MSG.STATE_SNAPSHOT or msgType == "state" then
        -- Format: state|json_string
        -- JSON contains full game state (players, projectiles, chests, etc.)
        -- Keep as string for NetworkHandler to decode
        msg.state = parts[2] or "{}"
        
    elseif msgType == Protocol.MSG.EVENT_BOON_GRANTED then
        -- Format: boon|playerId|boonType|boonData
        msg.id = parts[2]
        msg.boonType = parts[3]
        msg.boonData = parts[4]  -- Optional JSON string with boon properties
        
    elseif msgType == Protocol.MSG.EVENT_PLAYER_DIED then
        -- Format: died|playerId|killerId
        msg.id = parts[2]
        msg.killerId = parts[3]
        
    elseif msgType == Protocol.MSG.EVENT_BOON_STOLEN then
        -- Format: stolen|killerId|victimId|boonCount
        msg.killerId = parts[2]
        msg.victimId = parts[3]
        msg.boonCount = tonumber(parts[4]) or 0
        
    elseif msgType == Protocol.MSG.EVENT_CHEST_OPENED then
        -- Format: chest|chestId|playerId
        msg.chestId = parts[2]
        msg.id = parts[3]
        
    elseif msgType == Protocol.MSG.EVENT_PROJECTILE then
        -- Format: proj|id|x|y|vx|vy|ownerId|damage
        msg.projId = parts[2]
        msg.x = tonumber(parts[3]) or 0
        msg.y = tonumber(parts[4]) or 0
        msg.vx = tonumber(parts[5]) or 0
        msg.vy = tonumber(parts[6]) or 0
        msg.ownerId = parts[7]
        msg.damage = tonumber(parts[8]) or 10
        
    elseif msgType == Protocol.MSG.CYCLE_TIME then
        -- Format: cycle|timeRemaining|duration
        msg.timeRemaining = tonumber(parts[2]) or 0  -- milliseconds
        msg.duration = tonumber(parts[3]) or 1200000  -- 20 minutes default
        
    elseif msgType == Protocol.MSG.EXTRACTION then
        -- Format: extract|playerId|zoneX|zoneY
        msg.id = parts[2]
        msg.zoneX = tonumber(parts[3]) or 0
        msg.zoneY = tonumber(parts[4]) or 0

    elseif msgType == Protocol.MSG.PING then
        -- Format: ping|timestamp
        msg.timestamp = tonumber(parts[2]) or love.timer.getTime()

    elseif msgType == Protocol.MSG.PONG then
        -- Format: pong|timestamp
        msg.timestamp = tonumber(parts[2]) or 0

    elseif msgType == Protocol.MSG.CHUNK_DATA then
        -- Format: chunk|cx|cy|json_data
        msg.cx = tonumber(parts[2])
        msg.cy = tonumber(parts[3])
        local jsonStr = parts[4]
        if jsonStr then
            local success, decoded = pcall(json.decode, jsonStr)
            if success and decoded then
                msg.data = decoded
            end
        end
    end
    
    return msg
end

return Protocol
