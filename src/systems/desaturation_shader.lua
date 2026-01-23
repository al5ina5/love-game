-- src/systems/desaturation_shader.lua
-- Shader for desaturating the game based on timer

local DesaturationShader = {}

-- Desaturation shader code
local shaderCode = [[
extern number saturation;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(texture, texture_coords);
    
    // Convert to grayscale using luminance weights
    float gray = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    
    // Interpolate between grayscale and original color based on saturation
    vec3 desaturated = mix(vec3(gray), pixel.rgb, saturation);
    
    return vec4(desaturated, pixel.a);
}
]]

function DesaturationShader.new()
    local shader = love.graphics.newShader(shaderCode)
    if not shader then
        print("Warning: Failed to create desaturation shader")
        return nil
    end
    return shader
end

function DesaturationShader.setSaturation(shader, saturation)
    if shader then
        shader:send("saturation", math.max(0, math.min(1, saturation)))
    end
end

return DesaturationShader
