//
//  shaders.metal
//  LearnMetal
//
//  Created by loyinglin on 2018/6/21.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#include <metal_stdlib>
#import "LYShaderTypes.h"

using namespace metal;

typedef struct
{
    float4 clipSpacePosition [[position]];
    
    float2 textureCoordinate;
    
} RasterizerData;

vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant LYVertex *vertexArray [[ buffer(0) ]]) {
    RasterizerData out;
    out.clipSpacePosition = vertexArray[vertexID].position;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

fragment float4
samplingShader(RasterizerData input [[stage_in]],
               texture2d<half> colorTexture [[ texture(0) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    half4 colorSample = colorTexture.sample(textureSampler, input.textureCoordinate);
    
    return float4(colorSample);
}
