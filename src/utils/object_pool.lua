-- src/utils/object_pool.lua
-- Generic object pool for reducing garbage collection pressure
-- Reuses tables instead of creating new ones each frame

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool:new(createFn, resetFn, initialSize)
    local self = setmetatable({}, ObjectPool)
    
    self.createFn = createFn or function() return {} end
    self.resetFn = resetFn or function(obj) 
        -- Default: clear all keys from table
        for k in pairs(obj) do
            obj[k] = nil
        end
    end
    
    self.pool = {}
    self.active = {}
    
    -- Pre-allocate initial objects
    initialSize = initialSize or 0
    for i = 1, initialSize do
        table.insert(self.pool, self.createFn())
    end
    
    return self
end

-- Acquire an object from the pool
function ObjectPool:acquire()
    local obj
    
    if #self.pool > 0 then
        obj = table.remove(self.pool)
    else
        obj = self.createFn()
    end
    
    self.active[obj] = true
    return obj
end

-- Release an object back to the pool
function ObjectPool:release(obj)
    if not self.active[obj] then
        return -- Already released or not from this pool
    end
    
    self.active[obj] = nil
    self.resetFn(obj)
    table.insert(self.pool, obj)
end

-- Release all active objects
function ObjectPool:releaseAll()
    for obj in pairs(self.active) do
        self:release(obj)
    end
end

-- Get pool statistics
function ObjectPool:getStats()
    local activeCount = 0
    for _ in pairs(self.active) do
        activeCount = activeCount + 1
    end
    
    return {
        pooled = #self.pool,
        active = activeCount,
        total = #self.pool + activeCount
    }
end

return ObjectPool
