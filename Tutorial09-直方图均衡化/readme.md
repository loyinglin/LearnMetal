
###核心思路
首先，我们用直方图来表示一张图像：横坐标代表的是颜色值，纵坐标代表的是该颜色值在图像中出现次数。 

如图，对于某些偏暗的图像，可能出现颜色值集中分布在某个区间的情况。
直方图均衡化(Histogram Equalization) ，指的是对图像的颜色值进行重新分配，使得颜色值的分布更加均匀。

本文用compute shader对图像的颜色值进行统计，然后计算得出映射关系，由fragment shader进行颜色映射处理。




1、Metal的render管道、compute管道配置；

2、CPU进行直方图均衡化处理；

2.1 把UIImage转成Bytes；

2.2 颜色统计；

```
    // CPU进行统计
    Byte *color = (Byte *)spriteData;
    for (int i = 0; i < width * height; ++i) {
        for (int j = 0; j < LY_CHANNEL_NUM; ++j) {
            uint c = color[i * 4 + j];
            ++cpuColorBuffer.channel[j][c];
        }
    }
```

2.3 映射关系；

```
    int rgb[3][LY_CHANNEL_SIZE], sum = (int)(width * height);
    int val[3] = {0};
    // 颜色映射
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < LY_CHANNEL_SIZE; ++j) {
            val[i] += cpuColorBuffer.channel[i][j];
            rgb[i][j] = val[i] * 1.0 * (LY_CHANNEL_SIZE - 1) / sum;
        }
    }
```

2.4 颜色值修改；

```
    // 值修改
    for (int i = 0; i < width * height; ++i) {
        for (int j = 0; j < LY_CHANNEL_NUM; ++j) {
            uint c = color[i * 4 + j];
            color[i * 4 + j] = rgb[j][c];
        }
    }
```

最后用处理之后的Bytes生成新图片。


3 GPU进行直方图均衡化处理；

3.1 compute shader进行颜色统计；

```
kernel void
grayKernel(texture2d<float, access::read>  sourceTexture  [[textureLYKernelTextureIndexSource]], // 纹理输入，
           device LYColorBuffer &out [[buffer(LYKernelBufferIndexOutput)]], // 输出的buffer
           uint2                          grid         [[thread_position_in_grid]]) // 格子索引
{
    // 边界保护
    if(grid.x < sourceTexture.get_width() && grid.y < sourceTexture.get_height())
    {
        float4 color  = sourceTexture.read(grid); // 初始颜色
        int3 rgb = int3(color.rgb * SIZE); // 乘以SIZE，得到[0, 255]的颜色值
        // 颜色统计，每个像素点计一次
        atomic_fetch_add_explicit(&out.channel[0][rgb.r], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&out.channel[1][rgb.g], 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&out.channel[2][rgb.b], 1, memory_order_relaxed);
    }
}
```

`atomic_fetch_add_explicit`是用于在多线程进行数据操作，具体的函数解释见[这里](https://en.cppreference.com/w/c/atomic/atomic_fetch_add)。

3.2 映射关系处理；

compute shader回调后，根据GPU统计的颜色分布结果，求出映射关系；

```

        LYLocalBuffer *buffer = (LYLocalBuffer *)strongSelf.colorBuffer.contents; // GPU统计的结果
        LYLocalBuffer *convertBuffer = self.convertBuffer.contents; // 颜色转换的buffer
        int sum = (int)(self.sourceTexture.width * self.sourceTexture.height); // 总的像素点
        int val[3] = {0}; // 累计和
        for (int i = 0; i < 3; ++i) {
            for (int j = 0; j < LY_CHANNEL_SIZE; ++j) {
                val[i] += buffer->channel[i][j]; // 当前[0, j]累计出现的总次数
                convertBuffer->channel[i][j] = val[i] * 1.0 * (LY_CHANNEL_SIZE - 1) / sum;
                
                // 对比CPU和GPU处理的结果
                if (buffer->channel[i][j] != strongSelf->cpuColorBuffer.channel[i][j]) {
                    // 如果不相同，则把对应的结果输出
                    printf("%d, %d, gpuBuffer:%u  cpuBuffer:%u \n", i, j, buffer->channel[i][j], strongSelf->cpuColorBuffer.channel[i][j]);
                }
            }
        }
        memset(buffer, 0, strongSelf.colorBuffer.length);
```

3.3 根据映射关系处理原图片，并渲染到屏幕上；

```
fragment float4
samplingShader(RasterizerData input [[stage_in]], // stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
               texture2d<float> colorTexture [[ texture(LYFragmentTextureIndexSource) ]], // texture表明是纹理数据，LYFragmentTextureIndexSource是索引
               device LYLocalBuffer &convertBuffer [[buffer(LYFragmentBufferIndexConvert)]]) // 转换的buffer
{
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear); // sampler是采样器
    float4 colorSample = colorTexture.sample(textureSampler, input.textureCoordinate); // 得到纹理对应位置的颜色
    int3 rgb = int3(colorSample.rgb * SIZE); // 记得先乘以SIZE
    colorSample.rgb = float3(convertBuffer.channel[0][rgb.r], convertBuffer.channel[1][rgb.g], convertBuffer.channel[2][rgb.b]) / SIZE; // 返回的值也要经过归一化处理
    return colorSample;
}
```


