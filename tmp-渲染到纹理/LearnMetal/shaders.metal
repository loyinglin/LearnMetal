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

constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722); // 把rgba转成亮度值

fragment float4
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<half> colorTexture [[ texture(0) ]]) // texture表明是纹理数据，0是索引
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // sampler是采样器
    
    half4 colorSample;
    colorSample.bgra = colorTexture.sample(textureSampler, input.textureCoordinate); // 得到纹理对应位置的颜色

    half  gray   = dot(colorSample.rgb, kRec709Luma); // 转换成亮度
//    half  gray   = 1.0;
    
    return (float4){gray, gray, gray, 1.0};
}

kernel void
sobelKernel(texture2d<half, access::read>  sourceTexture  [[texture(LYFragmentTextureIndexTextureSource)]],
                texture2d<half, access::write> destTexture [[texture(LYFragmentTextureIndexTextureDest)]],
                uint2                          grid         [[thread_position_in_grid]])
{
    // 边界保护
    if(grid.x <= destTexture.get_width() && grid.y <= destTexture.get_height())
    {
        half4 color  = sourceTexture.read(grid); // 初始颜色
        half  gray   = dot(color.rgb, kRec709Luma); // 转换成亮度
        destTexture.write(half4(gray, gray, gray, 1.0), grid); // 写回对应纹理
    }
}

