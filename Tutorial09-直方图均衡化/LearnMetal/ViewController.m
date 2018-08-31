//
//  ViewController.m
//  LearnMetal
//
//  Created by loyinglin on 2018/6/21.
//  Copyright © 2018年 loyinglin. All rights reserved.
//
@import MetalKit;
#import "LYShaderTypes.h"
#import "ViewController.h"

@interface ViewController () <MTKViewDelegate>

// view
@property (nonatomic, strong) MTKView *mtkView;

// data
@property (nonatomic, assign) CGSize viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipelineState;
@property (nonatomic, strong) id<MTLComputePipelineState> computePipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLTexture> sourceTexture;

@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, assign) NSUInteger numVertices;
@property (nonatomic, assign) MTLSize groupSize;
@property (nonatomic, assign) MTLSize groupCount;
@property (nonatomic, strong) id<MTLBuffer> colorBuffer; // 统计颜色的buffer
@property (nonatomic, strong) id<MTLBuffer> convertBuffer; // 转换颜色的buffer

@property (nonatomic, assign) BOOL isDrawing; // 增加正在绘制的属性，以避免多次compute的影响

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *convertImageView;
@end

@implementation ViewController
{
    LYLocalBuffer cpuColorBuffer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // 初始化 MTKView
    self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds];
    self.mtkView.device = MTLCreateSystemDefaultDevice(); // 获取默认的device
    self.view = self.mtkView;
    self.mtkView.delegate = self;
    self.viewportSize = CGSizeMake(self.mtkView.drawableSize.width, self.mtkView.drawableSize.height);
    
    [self customInit];
    
//    [self customDraw];
}

- (void)customInit {
    [self setupPipeline];
    [self setupVertex];
    [self setupTexture];
    [self setupBuffer];
    [self setupThreadGroup];
}

// 设置渲染管道和计算管道
-(void)setupPipeline {
    id<MTLLibrary> defaultLibrary = [self.mtkView.device newDefaultLibrary]; // .metal
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"]; // 顶点shader，vertexShader是函数名
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"]; // 片元shader，samplingShader是函数名
    id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"grayKernel"];
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.mtkView.colorPixelFormat;
    // 创建图形渲染管道，耗性能操作不宜频繁调用
    self.renderPipelineState = [self.mtkView.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                                   error:NULL];
    // 创建计算管道，耗性能操作不宜频繁调用
    self.computePipelineState = [self.mtkView.device newComputePipelineStateWithFunction:kernelFunction
                                                                                   error:NULL];
    // CommandQueue是渲染指令队列，保证渲染指令有序地提交到GPU
    self.commandQueue = [self.mtkView.device newCommandQueue];
}

- (void)setupVertex {
    const LYVertex quadVertices[] =
    {   // 顶点坐标，分别是x、y、z、w；    纹理坐标，x、y；
        { {  0.5, -0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -0.5, -0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 0.f, 1.f } },
        { { -0.5,  0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 0.f, 0.f } },
        
        { {  0.5, -0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -0.5,  0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 0.f, 0.f } },
        { {  0.5,  0.5 / self.viewportSize.height * self.viewportSize.width, 0.0, 1.0 },  { 1.f, 0.f } },
    };
    self.vertices = [self.mtkView.device newBufferWithBytes:quadVertices
                                                     length:sizeof(quadVertices)
                                                    options:MTLResourceStorageModeShared]; // 创建顶点缓存
    self.numVertices = sizeof(quadVertices) / sizeof(LYVertex); // 顶点个数
}

- (void)setupTexture {
    UIImage *image = [UIImage imageNamed:@"234.jpeg"];
    // 纹理描述符
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm; // 图片的格式要和数据一致
    textureDescriptor.width = image.size.width;
    textureDescriptor.height = image.size.height;
    textureDescriptor.usage = MTLTextureUsageShaderRead; // 原图片只需要读取
    self.sourceTexture = [self.mtkView.device newTextureWithDescriptor:textureDescriptor]; // 创建纹理
    
    MTLRegion region = {{ 0, 0, 0 }, {image.size.width, image.size.height, 1}}; // 纹理上传的范围
    Byte *imageBytes = [self loadImage:image];
    if (imageBytes) { // UIImage的数据需要转成二进制才能上传，且不用jpg、png的NSData
        [self.sourceTexture replaceRegion:region
                        mipmapLevel:0
                          withBytes:imageBytes
                        bytesPerRow:4 * image.size.width];
        free(imageBytes); // 需要释放资源
        imageBytes = NULL;
    }
    
    if (!self.imageView) { // 对比的image
        self.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds) / 2, CGRectGetWidth(self.view.bounds) / 2)];
        self.imageView.image = image;
        [self.view addSubview:self.imageView];
    }
    if (!self.convertImageView) { // 对比的convertImage
        self.convertImageView = [[UIImageView alloc] initWithFrame:CGRectMake(CGRectGetWidth(self.view.bounds) / 2, 0, CGRectGetWidth(self.view.bounds) / 2, CGRectGetWidth(self.view.bounds) / 2)];
        self.convertImageView.image = [self cpuConvertImage:image];
        [self.view addSubview:self.convertImageView];
    }
}

- (void)setupBuffer {
    self.colorBuffer = [self.mtkView.device newBufferWithLength:sizeof(LYLocalBuffer) options:MTLResourceStorageModeShared]; //申请颜色统计的buffer，用于computeShader统计
    self.convertBuffer = [self.mtkView.device newBufferWithLength:sizeof(LYLocalBuffer) options:MTLResourceStorageModeShared]; //申请颜色转换的buffer，用于fragmentShader转换颜色
}

- (void)setupThreadGroup {
    self.groupSize = MTLSizeMake(16, 16, 1); // 太大某些GPU不支持，太小效率低；
    
    //保证每个像素都有处理到
    _groupCount.width  = (self.sourceTexture.width  + self.groupSize.width -  1) / self.groupSize.width;
    _groupCount.height = (self.sourceTexture.height + self.groupSize.height - 1) / self.groupSize.height;
    _groupCount.depth = 1; // 我们是2D纹理，深度设为1
}

- (Byte *)loadImage:(UIImage *)image {
    // 1获取图片的CGImageRef
    CGImageRef spriteImage = image.CGImage;
    
    // 2 读取图片的大小
    size_t width = CGImageGetWidth(spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    Byte * spriteData = (Byte *) calloc(width * height * 4, sizeof(Byte)); //rgba共4个byte
    
    CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width*4,
                                                       CGImageGetColorSpace(spriteImage), kCGImageAlphaPremultipliedLast);
    
    // 3在CGContextRef上绘图
    CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
    
    CGContextRelease(spriteContext);
    
    return spriteData;
}

- (UIImage *)cpuConvertImage:(UIImage *)image {
    // 1获取图片的CGImageRef
    CGImageRef spriteImage = image.CGImage;
    
    // 2 读取图片的大小
    size_t width = CGImageGetWidth(spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    Byte * spriteData = (Byte *) calloc(width * height * 4, sizeof(Byte)); //rgba共4个byte
    
    CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width*4,
                                                       CGImageGetColorSpace(spriteImage), kCGImageAlphaPremultipliedLast);
    
    // 3在CGContextRef上绘图
    CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
    
    
    // 下面是用CPU进行均衡化处理
    
    // CPU进行统计
    Byte *color = (Byte *)spriteData;
    for (int i = 0; i < width * height; ++i) {
        for (int j = 0; j < LY_CHANNEL_NUM; ++j) {
            uint c = color[i * 4 + j];
            ++cpuColorBuffer.channel[j][c];
        }
    }
    // 打印统计的结果
    for (int i = 0; i < LY_CHANNEL_NUM; ++i) {
        for (int j = 0; j < LY_CHANNEL_SIZE; ++j) {
            printf("%u ", cpuColorBuffer.channel[i][j]);
        }
        puts("");
        puts("------");
    }
    
    int rgb[3][LY_CHANNEL_SIZE], sum = (int)(width * height);
    int val[3] = {0};
    // 颜色映射
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < LY_CHANNEL_SIZE; ++j) {
            val[i] += cpuColorBuffer.channel[i][j];
            rgb[i][j] = val[i] * 1.0 * (LY_CHANNEL_SIZE - 1) / sum;
        }
    }
    
    // 值修改
    for (int i = 0; i < width * height; ++i) {
        for (int j = 0; j < LY_CHANNEL_NUM; ++j) {
            uint c = color[i * 4 + j];
            color[i * 4 + j] = rgb[j][c];
        }
    }
    UIImage *convertImage = [UIImage imageWithCGImage:CGBitmapContextCreateImage(spriteContext)];
    
    CGContextRelease(spriteContext);
    
    return convertImage;
}

- (void)customDraw {
    // 每次渲染都要单独创建一个CommandBuffer
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    {
        // 创建计算指令的编码器
        id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
        // 设置计算管道，以调用shaders.metal中的内核计算函数
        [computeEncoder setComputePipelineState:self.computePipelineState];
        // 输入纹理
        [computeEncoder setTexture:self.sourceTexture atIndex:LYKernelTextureIndexSource];
        // 统计结果buffer
        [computeEncoder setBuffer:self.colorBuffer offset:0 atIndex:LYKernelBufferIndexOutput];
        // 计算区域
        [computeEncoder dispatchThreadgroups:self.groupCount threadsPerThreadgroup:self.groupSize];
        // 调用endEncoding释放编码器，下个encoder才能创建
        [computeEncoder endEncoding];
    }
    
    __weak ViewController* weakSelf = self;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> commandBuffer) {
        __strong ViewController* strongSelf = weakSelf;
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
        [strongSelf renderNewImage];
    }];
    
    [commandBuffer commit]; // 提交；
    
}

- (void)renderNewImage {
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = self.mtkView.currentRenderPassDescriptor;
    // MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f); // 设置默认颜色
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor]; //编码绘制指令的Encoder
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.width, self.viewportSize.height, -1.0, 1.0 }]; // 设置显示区域
        [renderEncoder setRenderPipelineState:self.renderPipelineState]; // 设置渲染管道，以保证顶点和片元两个shader会被调用
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:LYVertexBufferIndexVertices]; // 设置顶点缓存
        
        [renderEncoder setFragmentTexture:self.sourceTexture
                                  atIndex:LYFragmentTextureIndexSource]; // 设置纹理
        
        [renderEncoder setFragmentBuffer:self.convertBuffer
                                  offset:0
                                 atIndex:LYFragmentBufferIndexConvert];
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:self.numVertices]; // 绘制
        
        [renderEncoder endEncoding]; // 结束
        
        [commandBuffer presentDrawable:self.mtkView.currentDrawable]; // 显示
    }
    [commandBuffer commit];
    self.isDrawing = NO;
}
#pragma mark - delegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.viewportSize = CGSizeMake(size.width, size.height);
}

- (void)drawInMTKView:(MTKView *)view {
    if (!self.isDrawing) {
        self.isDrawing = YES;
        [self customDraw];
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
