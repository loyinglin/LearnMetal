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
    float3 pixelColor;
    float2 textureCoordinate;
    
} RasterizerData;

vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]], // 顶点索引
             constant LYVertex *vertexArray [[ buffer(LYVertexInputIndexVertices) ]], // 顶点数据
             constant LYMatrix *matrix [[ buffer(LYVertexInputIndexMatrix) ]]) { // 变换矩阵
    RasterizerData out; // 输出数据
    out.clipSpacePosition = matrix->projectionMatrix * matrix->modelViewMatrix * vertexArray[vertexID].position; // 变换处理
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate; // 纹理坐标
    out.pixelColor = vertexArray[vertexID].color; // 顶点颜色，调试用
    return out;
}

fragment float4
samplingShader(RasterizerData input [[stage_in]],
               texture2d<half> textureColor [[ texture(LYFragmentInputIndexTexture) ]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // 采样器
    half4 colorTex = textureColor.sample(textureSampler, input.textureCoordinate); // 纹理颜色
//    half4 colorTex = half4(input.pixelColor.x, input.pixelColor.y, input.pixelColor.z, 1); // 顶点颜色，方便调试
    return float4(colorTex);
}
