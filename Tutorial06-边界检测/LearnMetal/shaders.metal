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
    float4 clipSpacePosition [[position]]; // position的修饰符表示这个是顶点
    float2 textureCoordinate; // 纹理坐标，会做插值处理
    
} RasterizerData;

vertex RasterizerData // 返回给片元着色器的结构体
vertexShader(uint vertexID [[ vertex_id ]], // vertex_id是顶点shader每次处理的index，用于定位当前的顶点
             constant LYVertex *vertexArray [[ buffer(0) ]]) { // buffer表明是缓存数据，0是索引
    RasterizerData out;
    out.clipSpacePosition = vertexArray[vertexID].position;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

fragment float4
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<half> colorTexture [[ texture(0) ]]) // texture表明是纹理数据，0是索引
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // sampler是采样器
    
    half4 colorSample = colorTexture.sample(textureSampler, input.textureCoordinate); // 得到纹理对应位置的颜色
    
    return float4(colorSample);
}


constant half sobelStep = 1 / 180.0; // 因为图片是180
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722); // 把rgba转成亮度值

kernel void
sobelKernel(texture2d<half, access::read>  sourceTexture  [[texture(LYFragmentTextureIndexTextureSource)]],
                texture2d<half, access::write> destTexture [[texture(LYFragmentTextureIndexTextureDest)]],
                uint2                          grid         [[thread_position_in_grid]])
{
    half4 topLeft = sourceTexture.read(uint2(grid.x - sobelStep, grid.y - sobelStep));
    half4 top = sourceTexture.read(uint2(grid.x, grid.y - sobelStep));
    half4 topRight = sourceTexture.read(uint2(grid.x + sobelStep, grid.y - sobelStep));
    half4 centerLeft = sourceTexture.read(uint2(grid.x - sobelStep, grid.y));
    half4 centerRight = sourceTexture.read(uint2(grid.x + sobelStep, grid.y));
    half4 bottomLeft = sourceTexture.read(uint2(grid.x - sobelStep, grid.y + sobelStep));
    half4 bottom = sourceTexture.read(uint2(grid.x, grid.y + sobelStep));
    half4 bottomRight = sourceTexture.read(uint2(grid.x + sobelStep, grid.y + sobelStep));
    
    half4 h = -topLeft - 2.0 * top - topRight + bottomLeft + 2.0 * bottom + bottomRight;
    half4 v = -bottom - 2.0 * centerLeft - topLeft + bottomRight + 2.0 * centerRight + topRight;
    
    half  grayH  = dot(h.rgb, kRec709Luma); // 转换成亮度
    half  grayV  = dot(v.rgb, kRec709Luma); // 转换成亮度
    
    half color = length(half2(grayH, grayV));
    
    destTexture.write(half4(color, color, color, 1.0), grid); // 写回对应纹理
}

