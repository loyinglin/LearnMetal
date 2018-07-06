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


typedef struct
{
    float4 output0 [[color(0)]]; // 第0个输出
    float4 output1 [[color(1)]]; // 第1个输出
    
} FramentOuptut;


vertex RasterizerData // 返回给片元着色器的结构体
vertexShader(uint vertexID [[ vertex_id ]], // vertex_id是顶点shader每次处理的index，用于定位当前的顶点
             constant LYVertex *vertexArray [[ buffer(0) ]]) { // buffer表明是缓存数据，0是索引
    RasterizerData out;
    out.clipSpacePosition = vertexArray[vertexID].position;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722); // 把rgba转成亮度值

fragment FramentOuptut
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<half> colorTexture [[ texture(0) ]]) // texture表明是纹理数据，0是索引
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // sampler是采样器
    
    half4 colorSample;
    colorSample.bgra = colorTexture.sample(textureSampler, input.textureCoordinate); // 得到纹理对应位置的颜色

    half  gray   = dot(colorSample.rgb, kRec709Luma); // 转换成亮度
    
    return (FramentOuptut){(float4){gray, gray, gray, 1.0}, (float4){gray, gray, gray, 1.0}};
}


