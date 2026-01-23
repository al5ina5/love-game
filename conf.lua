function love.conf(t)
    t.window.title = "Pixel Raiders"
    t.window.width = 1280   -- 320 * 4 for crisp pixel art
    t.window.height = 720   -- 180 * 4 (16:9 aspect ratio)
    t.window.vsync = 1
    t.window.resizable = true
    t.window.minwidth = 640
    t.window.minheight = 360
    
    -- Game identity (for save files)
    t.identity = "pixel-raider"
    
    -- Enable console for debugging on Windows
    t.console = true
end
