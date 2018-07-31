//
//  LYShaderTypes.h
//  LearnMetal
//
//  Created by loyinglin on 2018/6/21.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#ifndef LYShaderTypes_h
#define LYShaderTypes_h

#include <simd/simd.h>

typedef struct
{
    vector_float4 position; // 顶点
    vector_float3 color; // 颜色
    vector_float2 textureCoordinate; // 纹理
} LYVertex;


typedef struct
{
    matrix_float4x4 projectionMatrix; // 投影变换
    matrix_float4x4 modelViewMatrix; // 模型变换
} LYMatrix;



typedef enum LYVertexInputIndex
{
    LYVertexInputIndexVertices     = 0,
    LYVertexInputIndexMatrix       = 1,
} LYVertexInputIndex;



typedef enum LYFragmentInputIndex
{
    LYFragmentInputIndexTexture     = 0,
} LYFragmentInputIndex;

#endif /* LYShaderTypes_h */
