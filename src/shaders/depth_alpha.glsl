uniform float u_depth;
uniform bool u_isSilhouette;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_pos) {
    vec4 pos = transform_projection * vertex_pos;
    // Map u_depth [0, 1] to Z [-1, 1] for OpenGL depth buffer
    pos.z = (u_depth * 2.0) - 1.0;
    return pos;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 texColor = Texel(texture, texture_coords);
    
    // Alpha testing: Discard completely transparent pixels so they don't write to depth buffer
    if (texColor.a < 0.1) {
        discard;
    }
    
    if (u_isSilhouette) {
        // Silhouette mode: Output constant color (Black) with 80% opacity
        return vec4(0.0, 0.0, 0.0, 0.8 * texColor.a);
    } else {
        // Normal mode: Output standard texture color
        return color * texColor;
    }
}
#endif
