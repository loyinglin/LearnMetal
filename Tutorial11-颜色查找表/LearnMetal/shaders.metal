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
             constant LYVertex *vertexArray [[ buffer(LYVertexInputIndexVertices) ]]) { // buffer表明是缓存数据，0是索引
    RasterizerData out;
    out.clipSpacePosition = vertexArray[vertexID].position;
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}

constant float SquareSize = 63.0 / 512.0;
constant float stepSize = 0.0; //0.5 / 512.0;

fragment float4
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<float> normalTexture [[ texture(LYFragmentTextureIndexNormal) ]], // texture表明是纹理数据，LYFragmentTextureIndexNormal是索引
               texture2d<float> lookupTableTexture [[ texture(LYFragmentTextureIndexLookupTable) ]]) // texture表明
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // sampler是采样器
    float4 textureColor = normalTexture.sample(textureSampler, input.textureCoordinate); //正常的纹理颜色
    
    float blueColor = textureColor.b * 63.0; // 蓝色部分[0, 63] 共64种
    
    float2 quad1; // 第一个正方形的位置, 假如blueColor=22.5，则y=22/8=2，x=22-8*2=6，即是第2行，第6个正方形；（因为y是纵坐标）
    quad1.y = floor(floor(blueColor) * 0.125);
    quad1.x = floor(blueColor) - (quad1.y * 8.0);
    
    float2 quad2; // 第二个正方形的位置，同上。注意x、y坐标的计算，还有这里用int值也可以，但是为了效率使用float
    quad2.y = floor(ceil(blueColor) * 0.125);
    quad2.x = ceil(blueColor) - (quad2.y * 8.0);
    
    float2 texPos1; // 计算颜色(r,b,g)在第一个正方形中对应位置
    /*
     quad1是正方形的坐标，每个正方形占纹理大小的1/8，即是0.125，所以quad1.x * 0.125是算出正方形的左下角x坐标
     stepSize这里设置为0，可以忽略；
     SquareSize是63/512，一个正方形小格子在整个图片的纹理宽度
     */
    
    texPos1.x = (quad1.x * 0.125) + stepSize + (SquareSize * textureColor.r);
    texPos1.y = (quad1.y * 0.125) + stepSize + (SquareSize * textureColor.g);
    
    float2 texPos2; // 同上
    texPos2.x = (quad2.x * 0.125) + stepSize + (SquareSize * textureColor.r);
    texPos2.y = (quad2.y * 0.125) + stepSize + (SquareSize * textureColor.g);
    
    float4 newColor1 = lookupTableTexture.sample(textureSampler, texPos1); // 正方形1的颜色值
    float4 newColor2 = lookupTableTexture.sample(textureSampler, texPos2); // 正方形2的颜色值
    
    float4 newColor = mix(newColor1, newColor2, fract(blueColor)); // 根据小数点的部分进行mix
    return float4(newColor.rgb, textureColor.w); //不修改alpha值
}
