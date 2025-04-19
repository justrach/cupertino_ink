#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
};

// Uniforms struct to receive data from CPU
struct Uniforms {
    int colorScheme; // 0 = light, 1 = dark
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    // Simple full-screen quad vertices
    float2 positions[4] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0),
        float2(-1.0,  1.0), float2( 1.0,  1.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    return out;
}

// Fragment shader for static HDR background color
fragment half4 fragment_hdr_background(VertexOut in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(0)]])
{
    half3 color;
    half brightnessFactor = 1.0h; // Default brightness

    if (uniforms.colorScheme == 1) { // Dark mode
        // Deep Navy Blue
        color = half3(0.05h, 0.1h, 0.2h);
        brightnessFactor = 1.2h; // Subtle EDR boost for dark mode
    } else { // Light mode
        // Bright EDR White
        color = half3(1.0h, 1.0h, 1.0h);
        brightnessFactor = 1.5h; // Brighter EDR boost for light mode
    }

    return half4(color * brightnessFactor, 1.0h);
} 