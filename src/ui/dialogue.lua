-- src/ui/dialogue.lua
-- Gameboy-style dialogue box with typewriter effect
-- Responsive font sizing and pagination for small screens

local Dialogue = {}
Dialogue.__index = Dialogue

-- Target game resolution (for calculating relative positions)
local GAME_WIDTH = 320
local GAME_HEIGHT = 180

-- Sanitize text to remove invalid UTF-8 sequences and problematic characters
local function sanitizeText(text)
    if not text or type(text) ~= "string" then
        return ""
    end
    
    -- Remove or replace problematic characters
    -- Keep only printable ASCII and common UTF-8 characters
    local sanitized = ""
    local i = 1
    while i <= #text do
        local byte = string.byte(text, i)
        
        -- Handle valid ASCII (0x20-0x7E are printable, 0x09 is tab, 0x0A is newline, 0x0D is carriage return)
        if byte >= 0x20 and byte <= 0x7E then
            sanitized = sanitized .. string.char(byte)
            i = i + 1
        elseif byte == 0x09 or byte == 0x0A or byte == 0x0D then
            -- Keep tabs, newlines, and carriage returns
            sanitized = sanitized .. string.char(byte)
            i = i + 1
        -- Handle UTF-8 multi-byte sequences
        elseif byte >= 0xC0 and byte <= 0xDF then
            -- 2-byte UTF-8 sequence
            if i + 1 <= #text then
                local byte2 = string.byte(text, i + 1)
                if byte2 >= 0x80 and byte2 <= 0xBF then
                    sanitized = sanitized .. string.sub(text, i, i + 1)
                    i = i + 2
                else
                    -- Invalid sequence, skip
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip
                i = i + 1
            end
        elseif byte >= 0xE0 and byte <= 0xEF then
            -- 3-byte UTF-8 sequence
            if i + 2 <= #text then
                local byte2 = string.byte(text, i + 1)
                local byte3 = string.byte(text, i + 2)
                if byte2 >= 0x80 and byte2 <= 0xBF and byte3 >= 0x80 and byte3 <= 0xBF then
                    sanitized = sanitized .. string.sub(text, i, i + 2)
                    i = i + 3
                else
                    -- Invalid sequence, skip
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip
                i = i + 1
            end
        elseif byte >= 0xF0 and byte <= 0xF7 then
            -- 4-byte UTF-8 sequence
            if i + 3 <= #text then
                local byte2 = string.byte(text, i + 1)
                local byte3 = string.byte(text, i + 2)
                local byte4 = string.byte(text, i + 3)
                if byte2 >= 0x80 and byte2 <= 0xBF and byte3 >= 0x80 and byte3 <= 0xBF and byte4 >= 0x80 and byte4 <= 0xBF then
                    sanitized = sanitized .. string.sub(text, i, i + 3)
                    i = i + 4
                else
                    -- Invalid sequence, skip
                    i = i + 1
                end
            else
                -- Incomplete sequence, skip
                i = i + 1
            end
        else
            -- Invalid byte, skip it
            i = i + 1
        end
    end
    
    return sanitized
end

function Dialogue:new()
    local self = setmetatable({}, Dialogue)

    -- State
    self.active = false
    self.pages = {}  -- Array of text pages
    self.currentPage = 1
    self.displayedText = ""
    self.charIndex = 0
    self.charTimer = 0
    self.charDelay = 0.03  -- Time between characters
    self.speakerName = ""
    self.isFirstAdvance = true  -- Track if this is the first time dialogue is advanced

    -- Fonts will be created dynamically based on screen size
    self.font = nil
    self.nameFont = nil
    self.fontSize = 14  -- Base font size (Gameboy-style, slightly larger)
    self.nameFontSize = 11

    self.margin = 6  -- Smaller margin for compact layout
    self.edgeMargin = 8  -- Margin from screen edges (doubled)

    -- Blinking indicator
    self.blinkTimer = 0
    self.showIndicator = true

    return self
end

-- Calculate responsive font size based on screen dimensions
function Dialogue:calculateFontSize(screenW, screenH)
    -- Base font size for small screens (Gameboy-style, slightly larger)
    local baseSize = 14
    local baseNameSize = 11
    
    -- Scale based on screen size
    local scale = math.min(screenW / GAME_WIDTH, screenH / GAME_HEIGHT)
    
    -- Small screens: keep exact same behavior (15% boost)
    -- Large screens: scale proportionally to match visual density (no cap, scales naturally)
    local scaleBoost = scale < 1.0 and 1.15 or 1.0  -- 15% boost on small screens only
    local fontSize
    local nameFontSize
    
    if scale < 1.0 then
        -- Small screens: keep current behavior (capped at 1.5x with boost)
        fontSize = math.floor(baseSize * math.min(scale * scaleBoost, 1.5))
        nameFontSize = math.floor(baseNameSize * math.min(scale * scaleBoost, 1.5))
    else
        -- Large screens: scale proportionally to maintain visual density (allow up to 2.5x)
        fontSize = math.floor(baseSize * math.min(scale, 2.5))
        nameFontSize = math.floor(baseNameSize * math.min(scale, 2.5))
    end
    
    -- Ensure minimum readable size (increased for better readability)
    fontSize = math.max(fontSize, 12)
    nameFontSize = math.max(nameFontSize, 9)
    
    return fontSize, nameFontSize
end

-- Split text into pages that fit within the available space
function Dialogue:paginateText(text, screenW, screenH)
    if not self.font or text == "" then
        return {text}
    end
    
    local scale = math.min(screenW / GAME_WIDTH, screenH / GAME_HEIGHT)
    local gameW = GAME_WIDTH * scale
    local m = self.margin * scale
    local edgeM = self.edgeMargin * scale
    local boxW = gameW - (edgeM * 2)  -- Use almost full width with minimal edge margin
    local boxH = 50 * scale  -- Compact box height
    local textWidth = boxW - (m * 2)
    local nameHeight = (self.nameFont and self.nameFont:getHeight() or 12) + 4
    local textHeight = boxH - nameHeight - (m * 2)
    
    -- Calculate how many lines fit
    local lineHeight = self.font:getHeight() * self.font:getLineHeight()
    local maxLines = math.max(1, math.floor(textHeight / lineHeight))
    
    -- Small screens: ensure at least 2 lines of text
    if scale < 1.0 then
        maxLines = math.max(2, maxLines)  -- At least 2 lines on small screens
    end
    
    -- Split text into words (preserve spaces)
    local words = {}
    local wordPattern = "([%S]+)(%s*)"
    for word, spaces in text:gmatch(wordPattern) do
        table.insert(words, {word = word, spaces = spaces})
    end
    
    if #words == 0 then
        return {text}
    end
    
    -- Build pages by fitting words into lines
    local pages = {}
    local currentPageLines = {}
    local currentLine = ""
    
    for i, item in ipairs(words) do
        local word = item.word
        local spaces = item.spaces
        
        -- Test if adding this word fits
        local testLine = currentLine
        if testLine ~= "" then
            testLine = testLine .. " " .. word
        else
            testLine = word
        end
        
        local lineWidth = self.font:getWidth(testLine)
        
        if lineWidth <= textWidth then
            -- Word fits on current line
            currentLine = testLine
        else
            -- Word doesn't fit, start new line
            if currentLine ~= "" then
                table.insert(currentPageLines, currentLine)
                currentLine = word
                
                -- Check if page is full
                if #currentPageLines >= maxLines then
                    table.insert(pages, table.concat(currentPageLines, "\n"))
                    currentPageLines = {}
                end
            else
                -- Word itself is too long, force it anyway
                currentLine = word
            end
        end
    end
    
    -- Add final line
    if currentLine ~= "" then
        table.insert(currentPageLines, currentLine)
    end
    
    -- Add final page
    if #currentPageLines > 0 then
        table.insert(pages, table.concat(currentPageLines, "\n"))
    end
    
    -- Fallback if no pages created
    if #pages == 0 then
        return {text}
    end
    
    return pages
end

function Dialogue:start(speakerName, lines)
    self.active = true
    -- Sanitize speaker name
    self.speakerName = sanitizeText(speakerName) or "???"

    -- Combine all lines into one text string and sanitize
    local sanitizedLines = {}
    for i, line in ipairs(lines) do
        table.insert(sanitizedLines, sanitizeText(tostring(line)))
    end
    local fullText = table.concat(sanitizedLines, " ")

    -- Initialize fonts based on current screen size
    local screenW = love.graphics.getWidth()
    local screenH = love.graphics.getHeight()
    self.fontSize, self.nameFontSize = self:calculateFontSize(screenW, screenH)

    -- Always recreate fonts to ensure correct size
    self.font = love.graphics.newFont("assets/fonts/runescape_uf.ttf", self.fontSize)
    self.font:setFilter("nearest", "nearest")
    self.font:setLineHeight(1.2)  -- Compact line height

    self.nameFont = love.graphics.newFont("assets/fonts/runescape_uf.ttf", self.nameFontSize)
    self.nameFont:setFilter("nearest", "nearest")

    -- Paginate the text
    self.pages = self:paginateText(fullText, screenW, screenH)
    self.currentPage = 1
    self.displayedText = ""
    self.charIndex = 0
    self.charTimer = 0
    self.isFirstAdvance = true  -- Reset first advance flag when starting new dialogue
end

function Dialogue:isActive()
    return self.active
end

function Dialogue:isPageComplete()
    if #self.pages == 0 then return true end
    if self.currentPage <= 0 or self.currentPage > #self.pages then return true end
    local currentPageText = self.pages[self.currentPage] or ""
    return self.charIndex >= #currentPageText
end

function Dialogue:advance()
    if not self.active then return false end
    if #self.pages == 0 then
        self:close()
        return false
    end

    local wasFirstAdvance = self.isFirstAdvance
    self.isFirstAdvance = false

    if not self:isPageComplete() then
        -- Skip to end of current page
        if self.currentPage > 0 and self.currentPage <= #self.pages then
            self.displayedText = self.pages[self.currentPage] or ""
            self.charIndex = #self.displayedText
        end
    else
        -- Move to next page or close
        self.currentPage = self.currentPage + 1
        if self.currentPage > #self.pages then
            self:close()
        else
            self.displayedText = ""
            self.charIndex = 0
            self.charTimer = 0
        end
    end

    return wasFirstAdvance
end

function Dialogue:close()
    self.active = false
    self.pages = {}
    self.currentPage = 1
    self.displayedText = ""
    self.charIndex = 0
end

function Dialogue:update(dt)
    if not self.active then return end
    
    -- Typewriter effect
    if #self.pages > 0 and self.currentPage > 0 and self.currentPage <= #self.pages then
        local currentPageText = self.pages[self.currentPage] or ""
        if self.charIndex < #currentPageText then
            self.charTimer = self.charTimer + dt
            while self.charTimer >= self.charDelay and self.charIndex < #currentPageText do
                self.charTimer = self.charTimer - self.charDelay
                self.charIndex = self.charIndex + 1
                self.displayedText = string.sub(currentPageText, 1, self.charIndex)
            end
        elseif self.displayedText == "" then
            -- Ensure displayedText is set even if typewriter hasn't started
            self.displayedText = currentPageText
            self.charIndex = #currentPageText
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
    local edgeM = self.edgeMargin * scale
    local gameW = GAME_WIDTH * scale
    local gameH = GAME_HEIGHT * scale
    
    -- Larger box with minimal edge margins (same on all sides)
    local boxW = gameW - (edgeM * 2)  -- Use almost full width
    local boxH = 50 * scale  -- Compact height
    local boxX = offsetX + edgeM  -- Minimal margin from left edge
    local boxY = screenH - boxH - edgeM  -- Position from screen bottom with same margin as sides
    
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
    
    -- Speaker name
    if self.nameFont then
        love.graphics.setFont(self.nameFont)
        love.graphics.setColor(0.5, 0.75, 1, 1)
        local safeName = sanitizeText(self.speakerName) or "???"
        love.graphics.print(safeName, boxX + m, boxY + m)
    end
    
    -- Dialogue text
    if self.font and #self.pages > 0 and self.currentPage > 0 and self.currentPage <= #self.pages then
        love.graphics.setFont(self.font)
        love.graphics.setColor(1, 1, 1, 1)
        local nameHeight = self.nameFont and (self.nameFont:getHeight() + 4) or 0
        local textWidth = math.max(1, boxW - (m * 2))  -- Ensure width is at least 1
        local textToDisplay = sanitizeText(self.displayedText or "")
        if textToDisplay ~= "" then
            love.graphics.printf(
                textToDisplay,
                boxX + m,
                boxY + m + nameHeight,
                textWidth,
                "left"
            )
        end
    end
    
    -- Continue indicator (show if page complete and more pages exist)
    if self:isPageComplete() and self.currentPage < #self.pages and self.showIndicator then
        love.graphics.setColor(0.9, 0.9, 0.85, 1)
        local triSize = 6 * scale
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
