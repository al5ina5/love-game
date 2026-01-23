-- src/net/dns_thread.lua
-- Love2D thread for non-blocking DNS resolution

local socket = require("socket")
local requestChannel = love.thread.getChannel("dns_request")
local responseChannel = love.thread.getChannel("dns_response")

while true do
    local hostname = requestChannel:demand()
    if hostname == "quit" then break end
    
    if type(hostname) == "string" then
        local ip = socket.dns.toip(hostname)
        responseChannel:push({
            hostname = hostname,
            ip = ip
        })
    end
end
