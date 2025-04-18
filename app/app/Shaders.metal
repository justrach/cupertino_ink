#include <metal_stdlib>
using namespace metal;

// Simple pseudo-random function (replace with better noise like Perlin/Simplex if needed)
float random(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    float time; // Animation progress (0.0 to 1.0)
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    // Simple full-screen quad vertices
    float2 positions[4] = {
        float2(-1.0, -1.0), // bottom-left
        float2( 1.0, -1.0), // bottom-right
        float2(-1.0,  1.0), // top-left
        float2( 1.0,  1.0)  // top-right
    };
    // Texture coordinates (flipped vertically for typical image coords)
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    // Map vertex ID to triangle strip indices (0, 1, 2) and (1, 3, 2)
    // Using vertexID directly works for triangle strip of 4 vertices
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Placeholder fragment shader - will be replaced with dissolve effect later
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    // Simple gradient for now
    return float4(in.texCoord.x, in.texCoord.y, 0.5, 1.0);
}

// --- Dissolve Shader --- //
fragment float4 fragment_dissolve(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]])
{
    float2 uv = in.texCoord;
    float noiseValue = random(uv * 50.0 + uniforms.time * 2.0);

    float threshold = pow(uniforms.time, 1.5);
    threshold += (random(uv * 15.0) - 0.5) * 0.15;
    threshold = saturate(threshold);

    // Calculate intensity: 1.0 (white) if noise >= threshold, 0.0 (black) if noise < threshold
    // Smoothstep can create a slightly softer edge than a hard step
    float intensity = smoothstep(threshold - 0.02, threshold + 0.02, noiseValue);

    // Output grayscale intensity (alpha should also be intensity for masking)
    return float4(intensity, intensity, intensity, intensity);

    /* // Old discard code
    // Discard fragment if noise is below the threshold
    if (noiseValue < threshold) {
        discard_fragment();
    }
    return float4(1.0, 1.0, 1.0, 1.0);
    */
}

// --- Dissolve Shader (Conceptual - Needs Refinement) ---
// We'll need uniforms like time and a noise texture eventually

/*
 struct Uniforms {
     float time;
 };

 fragment float4 fragment_dissolve(VertexOut in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]],
                                  texture2d<float> noiseTexture [[texture(0)]],
                                  sampler noiseSampler [[sampler(0)]])
 {
     float noiseValue = noiseTexture.sample(noiseSampler, in.texCoord).r; // Sample noise
     float threshold = uniforms.time; // Simple time-based threshold

     if (noiseValue < threshold) {
         discard_fragment(); // Discard pixel if below threshold
     }

     // Base color (e.g., could be sampled from another texture or just a solid color)
     float4 baseColor = float4(0.8, 0.8, 0.8, 1.0);

     // Optional: Add edge effect where dissolving
     float edgeWidth = 0.05;
     if (noiseValue < threshold + edgeWidth) {
         // Make edge brighter/different color
         baseColor = float4(1.0, 1.0, 0.5, 1.0); // Example: Yellow edge
     }


     return baseColor;
 }
*/ 