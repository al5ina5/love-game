-- src/ui/dialogue.lua
-- Gameboy-style dialogue box with typewriter effect
-- Renders at native resolution for crisp text

local Dialogue = {}
Dialogue.__index = Dialogue

-- Target game resolution (for calculating relative positions)
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

function Dialogue:new()
    local self = setmetatable({}, Dialogue)
    
    -- State
    self.active = false
    self.lines = {}
    self.currentLine = 1
    self.displayedText = ""
    self.charIndex = 0
    self.charTimer = 0
    self.charDelay = 0.03  -- Time between characters
    self.speakerName = ""
    
    -- Larger text, 2 lines, ~8 words per line
    self.font = love.graphics.newFont("assets/fonts/04B_30__.TTF", 26)
    self.font:setFilter("nearest", "nearest")
    self.font:setLineHeight(1.4)  -- more line height
    
    self.nameFont = love.graphics.newFont("assets/fonts/04B_30__.TTF", 20)
    self.nameFont:setFilter("nearest", "nearest")
    
    self.margin = 12  -- uniform (scaled with game area)
    
    -- Blinking indicator
    self.blinkTimer = 0
    self.showIndicator = true
    
    return self
end

function Dialogue:start(speakerName, lines)
    self.active = true
    self.speakerName = speakerName or "???"
    self.lines = lines or {"..."}
    self.currentLine = 1
    self.displayedText = ""
    self.charIndex = 0
    self.charTimer = 0
end

function Dialogue:isActive()
    return self.active
end

function Dialogue:isLineComplete()
    return self.charIndex >= #self.lines[self.currentLine]
end

function Dialogue:advance()
    if not self.active then return end
    
    if not self:isLineComplete() then
        -- Skip to end of current line
        self.displayedText = self.lines[self.currentLine]
        self.charIndex = #self.lines[self.currentLine]
    else
        -- Move to next line or close
        self.currentLine = self.currentLine + 1
        if self.currentLine > #self.lines then
            self:close()
        else
            self.displayedText = ""
            self.charIndex = 0
            self.charTimer = 0
        end
    end
end

function Dialogue:close()
    self.active = false
    self.lines = {}
    self.currentLine = 1
    self.displayedText = ""
    self.charIndex = 0
end

function Dialogue:update(dt)
    if not self.active then return end
    
    -- Typewriter effect
    if self.charIndex < #self.lines[self.currentLine] then
        self.charTimer = self.charTimer + dt
        while self.charTimer >= self.charDelay and self.charIndex < #self.lines[self.currentLine] do
            self.charTimer = self.charTimer - self.charDelay
            self.charIndex = self.charIndex + 1
            self.displayedText = string.sub(self.lines[self.currentLine], 1, self.charIndex)
        end
    end
    
    -- Blink indicator
    self.blinkTimer = self.blinkTimer + dt
    if self.blinkTimer >= 0.4 then
        self.blinkTimer = 0
        self.showIndicator = not self.showIndicator
    end
end

function Dialogue:draw()
    if not self.active then return end
    
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    local scale = math.min(screenW / GAME_WIDTH, screenH / GAME_HEIGHT)
    local offsetX = (screenW - GAME_WIDTH * scale) / 2
    local offsetY = (screenH - GAME_HEIGHT * scale) / 2
    
    local m = self.margin * scale
    local gameW = GAME_WIDTH * scale
    local gameH = GAME_HEIGHT * scale
    -- Smaller box: 2 lines, ~8 words/line, larger text fills it
    local boxW = gameW * 0.76
    local boxH = 62 * scale
    local boxX = offsetX + (gameW - boxW) / 2
    local boxY = offsetY + gameH - boxH - m
    
    local oldFont = love.graphics.getFont()
    
    -- Background
    love.graphics.setColor(0.06, 0.06, 0.10, 0.95)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)
    
    -- Border
    love.graphics.setColor(0.4, 0.4, 0.45, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)
    love.graphics.setColor(0.65, 0.65, 0.7, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", boxX + 1, boxY + 1, boxW - 2, boxH - 2, 3, 3)
    
    -- Speaker name (uniform margin)
    love.graphics.setFont(self.nameFont)
    love.graphics.setColor(0.5, 0.75, 1, 1)
    love.graphics.print(self.speakerName, boxX + m, boxY + m)
    
    -- Dialogue text: uniform margin, 2 lines ~8 words each
    love.graphics.setFont(self.font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(
        self.displayedText,
        boxX + m,
        boxY + m + 24,
        boxW - (m * 2),
        "left"
    )
    
    -- Continue indicator (inside margin)
    if self:isLineComplete() and self.showIndicator then
        love.graphics.setColor(0.9, 0.9, 0.85, 1)
        local triSize = 6
        local ix = boxX + boxW - m - triSize
        local iy = boxY + boxH - m - triSize * 0.8
        love.graphics.polygon("fill",
            ix, iy,
            ix + triSize, iy,
            ix + triSize / 2, iy + triSize * 0.7
        )
    end
    
    love.graphics.setLineWidth(1)
    love.graphics.setFont(oldFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return Dialogue
