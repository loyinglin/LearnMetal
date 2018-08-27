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
    unsigned int channel[LY_CHANNEL_NUM][LY_CHANNEL_SIZE]; // rgb三个通道，每个通道有256种可能
} LYLocalBuffer;


typedef enum LYVertexInputIndex
{
    LYVertexInputIndexVertices     = 0,
} LYVertexInputIndex;


typedef enum LYFragmentTextureIndex
{
    LYFragmentTextureIndexTextureSource     = 0,
    LYFragmentTextureIndexTextureDest       = 1,
} LYFragmentTextureIndex;


typedef enum LYKernelBufferIndex
{
    LYKernelBufferIndexOutput     = 0,
} LYKernelBufferIndex;




#endif /* LYShaderTypes_h */
