-- src/game/interaction.lua
-- Handles NPC and chest interactions

local Interaction = {}

function Interaction.tryInteractWithChest(game)
    if not game.gameState or not game.gameState.chests or not game.player then
        return false
    end
    
    local interactRange = 32
    for chestId, chest in pairs(game.gameState.chests) do
        if not chest.opened then
            local dx = game.player.x - chest.x
            local dy = game.player.y - chest.y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist <= interactRange then
                if game.network then
                    game.network:sendGameInput("interact", {})
                end
                return true
            end
        end
    end
    
    return false
end

function Interaction.tryInteractWithNPC(game)
    if not game.player then return end
    
    for _, npc in ipairs(game.npcs) do
        if npc:isPlayerInRange(game.player) then
            local name, lines = npc:getDialogue()
            game.dialogue:start(name, lines)
            return
        end
    end
end

function Interaction.drawInteractionPrompt(game)
    if not game.gameState or not game.gameState.chests or not game.player then
        return
    end
    
    local interactRange = 32
    for chestId, chest in pairs(game.gameState.chests) do
        if not chest.opened then
            local dx = game.player.x - chest.x
            local dy = game.player.y - chest.y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist <= interactRange then
                local screenX, screenY = love.graphics.getWidth() / 2, love.graphics.getHeight() / 2 - 50
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.printf("E / A – Open chest", screenX - 100, screenY, 200, "center")
                love.graphics.setColor(1, 1, 1, 1)
                break
            end
        end
    end
end

return Interaction
