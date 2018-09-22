//
//  LYShaderTypes.h
//  LearnMetal
//
//  Created by loyinglin on 2018/6/21.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#ifndef LYShaderTypes_h
#define LYShaderTypes_h

typedef struct
{
    vector_float4 position;
    vector_float2 textureCoordinate;
} LYVertex;

#define LY_CHANNEL_NUM (3)
#define LY_CHANNEL_SIZE (256)

typedef struct
{
    int channel[LY_CHANNEL_NUM][LY_CHANNEL_SIZE]; // rgb三个通道，每个通道有256种可能
} LYLocalBuffer;


typedef enum LYVertexBufferIndex
{
    LYVertexBufferIndexVertices     = 0, // 顶点shader的buffer输入
} LYVertexBufferIndex;

typedef enum LYFragmentTextureIndex
{
    LYFragmentTextureIndexSource     = 0, // 像素shader的纹理输入
} LYFragmentTextureIndex;

typedef enum LYFragmentBufferIndex
{
    LYFragmentBufferIndexConvert     = 0, // 像素shader的buffer输入
} LYFragmentBufferIndex;

typedef enum LYKernelBufferIndex
{
    LYKernelBufferIndexOutput     = 0, // 计算shader的buffer，输出计算结果
} LYKernelBufferIndex;

typedef enum LYKernelTextureIndex
{
    LYKernelTextureIndexSource     = 0, // 计算shader的纹理输入
} LYKernelTextureIndex;




#endif /* LYShaderTypes_h */
