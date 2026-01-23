-- src/game/resource_manager.lua
-- Caches loaded resources to prevent VRAM accumulation

local ResourceManager = {}

local images = {}

function ResourceManager.getImage(path)
    if not path or path == "" then return nil end
    
    if not images[path] then
        local success, img = pcall(function()
            local image = love.graphics.newImage(path)
            image:setFilter("nearest", "nearest")
            return image
        end)
        
        if success then
            images[path] = img
            -- print("ResourceManager: Loaded new image: " .. path)
        else
            print("ResourceManager: Failed to load image: " .. path)
            return nil
        end
    end
    
    return images[path]
end

function ResourceManager.clear()
    images = {}
    collectgarbage("collect")
end

return ResourceManager
