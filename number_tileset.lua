-- Number Tileset Utility
-- Run this script to add numbers to your tileset for easy identification

function love.load()
    -- Load the original tileset
    local tilesetPath = "assets/img/tileset/tileset-v1.png"
    local tilesetImage = love.graphics.newImage(tilesetPath)
    local tilesetWidth, tilesetHeight = tilesetImage:getDimensions()

    -- Create a canvas to draw on
    local canvas = love.graphics.newCanvas(tilesetWidth, tilesetHeight)
    canvas:setFilter("nearest", "nearest")

    -- Draw the original tileset
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)  -- Black background
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(tilesetImage, 0, 0)

    -- Add numbers to each 16x16 tile
    local tileSize = 16
    local tilesPerRow = math.floor(tilesetWidth / tileSize)
    local tilesPerCol = math.floor(tilesetHeight / tileSize)
    local tileNumber = 1

    -- Set up font for numbers
    local font = love.graphics.newFont(8)  -- Small font
    love.graphics.setFont(font)

    for row = 0, tilesPerCol - 1 do
        for col = 0, tilesPerRow - 1 do
            local x = col * tileSize + 2  -- Offset slightly from corner
            local y = row * tileSize + 2

            -- Draw semi-transparent background for number
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", x - 1, y - 1, 14, 10)

            -- Draw the number
            love.graphics.setColor(1, 1, 0, 1)  -- Yellow text
            love.graphics.print(tostring(tileNumber), x, y)

            tileNumber = tileNumber + 1
        end
    end

    -- Reset canvas and save the image
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    -- Save the numbered tileset
    local canvasImageData = canvas:newImageData()
    local success = canvasImageData:encode("png", "tileset-v1-numbered.png")

    if success then
        print("SUCCESS: Numbered tileset saved as 'tileset-v1-numbered.png'")
        print("Total tiles: " .. (tileNumber - 1))
        print("Grid: " .. tilesPerRow .. "x" .. tilesPerCol)
    else
        print("ERROR: Failed to save numbered tileset")
    end

    -- Also print the tile layout for reference
    print("\nTile Layout (" .. tilesPerRow .. " tiles per row):")
    tileNumber = 1
    for row = 0, tilesPerCol - 1 do
        local rowStr = string.format("Row %d: ", row)
        for col = 0, tilesPerRow - 1 do
            rowStr = rowStr .. string.format("%3d ", tileNumber)
            tileNumber = tileNumber + 1
        end
        print(rowStr)
    end

    love.event.quit()
end

function love.draw()
    -- Just display some text while processing
    love.graphics.print("Processing tileset... Check console for results.", 10, 10)
end

function love.update(dt)
    -- Nothing to update
end