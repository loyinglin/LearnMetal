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

constant float stepSize = 0.01;

fragment float4
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<float> normalTexture [[ texture(LYFragmentTextureIndexNormal) ]], // texture表明是纹理数据，LYFragmentTextureIndexNormal是索引
               texture2d<float> lookupTableTexture [[ texture(LYFragmentTextureIndexLookupTable) ]]) // texture表明
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear); // sampler是采样器
    float length = stepSize;
    // (width, height), 宽为3，高为根号3的矩形
    float width = 3, height = 1.732050;
    int xIndex = input.textureCoordinate.x / (width * length), yIndex = input.textureCoordinate.y / (height * length); // 第(x,y)个标志
    float2 pos1, pos2;
    // 奇偶判断，横坐标和纵坐标都为奇数或者都为偶数时，要比较的点，即六边形中点分别为矩形左上点和右下点，否则为左下点和右上点。
    if ((xIndex + yIndex) % 2 == 0) {
        // 都为奇数 或者 都为偶数
        pos1 = float2(length * width * xIndex, length * height * yIndex);
        pos2 = float2(length * width * (xIndex + 1), length * height * (yIndex + 1));
    }
    else {
        // 奇数和偶数
        pos1 = float2(length * width * xIndex, length * height * (yIndex + 1));
        pos2 = float2(length * width * (xIndex + 1), length * height * yIndex);
    }
    // 算出当前像素点，相对pos1、pos2的距离
    float dis1 = sqrt(pow(pos1.x - input.textureCoordinate.x, 2.0) + pow(pos1.y - input.textureCoordinate.y, 2.0));
    float dis2 = sqrt(pow(pos2.x - input.textureCoordinate.x, 2.0) + pow(pos2.y - input.textureCoordinate.y, 2.0));
    
    float4 newColor;
    // 选择距离较近的点，读取其颜色
    if (dis1 < dis2) {
        newColor = normalTexture.sample(textureSampler, pos1);
    } else {
        newColor = normalTexture.sample(textureSampler, pos2);
    }
    
    return newColor;
}
