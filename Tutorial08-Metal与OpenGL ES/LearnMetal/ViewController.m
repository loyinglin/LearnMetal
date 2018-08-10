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
#import "LYOpenGLView.h"

@interface ViewController () <MTKViewDelegate>

// view
@property (nonatomic, strong) MTKView *mtkView;
@property (nonatomic, strong) UIImageView *imageView;


// GL
@property (nonatomic, strong) LYOpenGLView *glView;


// data
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> renderPipelineState;
@property (nonatomic, strong) id<MTLComputePipelineState> computePipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLTexture> sourceTexture;
@property (nonatomic, strong) id<MTLTexture> destTexture;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;
@property (nonatomic, assign) CVPixelBufferRef renderPixelBuffer;


@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, assign) NSUInteger numVertices;

@property (nonatomic, strong) id<MTLBuffer> groupParams;
@property (nonatomic, assign) MTLSize groupSize;
@property (nonatomic, assign) MTLSize groupCount;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // 初始化 MTKView
    self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds];
    self.mtkView.device = MTLCreateSystemDefaultDevice(); // 获取默认的device
    self.view = self.mtkView;
    self.mtkView.delegate = self;
    self.viewportSize = (vector_uint2){self.mtkView.drawableSize.width, self.mtkView.drawableSize.height};
    
    CVMetalTextureCacheCreate(NULL, NULL, self.mtkView.device, NULL, &_textureCache);
    
    self.glView = [[LYOpenGLView alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.view.bounds) - 180, 0, 180, 180)];
    [self.glView setupGL];
    [self.view addSubview:self.glView];
    
    [self customInit];
}

- (void)customInit {
    [self setupPipeline];
    [self setupVertex];
    [self setupTexture];
    [self setupThreadGroup];
}

// 设置渲染管道和计算管道
-(void)setupPipeline {
    id<MTLLibrary> defaultLibrary = [self.mtkView.device newDefaultLibrary]; // .metal
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"]; // 顶点shader，vertexShader是函数名
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"]; // 片元shader，samplingShader是函数名
    id<MTLFunction> kernelFunction = [defaultLibrary newFunctionWithName:@"sobelKernel"];
    
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
        { {  0.5, -0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -0.5, -0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 0.f, 1.f } },
        { { -0.5,  0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 0.f, 0.f } },
        
        { {  0.5, -0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -0.5,  0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 0.f, 0.f } },
        { {  0.5,  0.5 / self.viewportSize.y * self.viewportSize.x, 0.0, 1.0 },  { 1.f, 0.f } },
    };
    self.vertices = [self.mtkView.device newBufferWithBytes:quadVertices
                                                     length:sizeof(quadVertices)
                                                    options:MTLResourceStorageModeShared]; // 创建顶点缓存
    self.numVertices = sizeof(quadVertices) / sizeof(LYVertex); // 顶点个数
}

- (void)setupTexture {
    UIImage *image = [UIImage imageNamed:@"abc"];
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
    
    [self setupRenderTargetWithSize:image.size];
}

- (void)setupThreadGroup {
    self.groupSize = MTLSizeMake(16, 16, 1); // 太大某些GPU不支持，太小效率低；
    
    //保证每个像素都有处理到
    _groupCount.width  = (self.sourceTexture.width  + self.groupSize.width -  1) / self.groupSize.width;
    _groupCount.height = (self.sourceTexture.height + self.groupSize.height - 1) / self.groupSize.height;
    _groupCount.depth = 1; // 我们是2D纹理，深度设为1
    
    
    const TransParam params = {{0.2126, 0.7152, 0.0722}};
    self.groupParams = [self.mtkView.device newBufferWithBytes:&params
                                                     length:sizeof(params)
                                                    options:MTLResourceStorageModeShared]; // 创建groupParam缓存
}

- (Byte *)loadImage:(UIImage *)image {
    // 1获取图片的CGImageRef
    CGImageRef spriteImage = image.CGImage;
    
    // 2 读取图片的大小
    size_t width = CGImageGetWidth(spriteImage);
    size_t height = CGImageGetHeight(spriteImage);
    
    Byte * spriteData = (Byte *) calloc(width * height * 4, sizeof(Byte)); //rgba共4个byte
    
    CGContextRef spriteContext = CGBitmapContextCreate(spriteData, width, height, 8, width * 4,
                                                       CGImageGetColorSpace(spriteImage), kCGImageAlphaPremultipliedLast);
    
    // 3在CGContextRef上绘图
    CGContextDrawImage(spriteContext, CGRectMake(0, 0, width, height), spriteImage);
    
    CGContextRelease(spriteContext);
    
    return spriteData;
}


- (void)setupRenderTargetWithSize:(CGSize)size {
    CFDictionaryRef empty= CFDictionaryCreate(kCFAllocatorDefault,
                                              NULL,
                                              NULL,
                                              0,
                                              &kCFTypeDictionaryKeyCallBacks,
                                              &kCFTypeDictionaryValueCallBacks);
    
    CFMutableDictionaryRef attrs= CFDictionaryCreateMutable(kCFAllocatorDefault,
                                                            1,
                                                            &kCFTypeDictionaryKeyCallBacks,
                                                            &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(attrs,
                         kCVPixelBufferIOSurfacePropertiesKey,
                         empty);
    CVPixelBufferRef renderTarget;
    CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height,
                        kCVPixelFormatType_32BGRA,
                        attrs,
                        &renderTarget);
    
    size_t width = CVPixelBufferGetWidthOfPlane(renderTarget, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(renderTarget, 0);
    MTLPixelFormat pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    CVMetalTextureRef texture = NULL;
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, self.textureCache, renderTarget, NULL, pixelFormat, width, height, 0, &texture);
    if(status == kCVReturnSuccess)
    {
        self.destTexture = CVMetalTextureGetTexture(texture);
        self.renderPixelBuffer = renderTarget;
        CFRelease(texture);
    }
    else {
        NSAssert(NO, @"CVMetalTextureCacheCreateTextureFromImage fail");
    }
}


/**
 *  根据CVPixelBufferRef返回图像
 *
 *  @param pixelBufferRef 像素缓存引用
 *
 *  @return UIImage对象
 */
- (UIImage *)lyGetImageFromPixelBuffer:(CVPixelBufferRef)pixelBufferRef {
    CVImageBufferRef imageBuffer =  pixelBufferRef;
    
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0); //
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, baseAddress, bufferSize, NULL);
    
    // rgba的时候是kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrderDefault，这样会导致出现蓝色的图片
    CGImageRef cgImage = CGImageCreate(width, height, 8, 32, bytesPerRow, rgbColorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, NULL, true, kCGRenderingIntentDefault);
    
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    return image;
}


#pragma mark - delegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.viewportSize = (vector_uint2){size.width, size.height};
}

- (void)drawInMTKView:(MTKView *)view {
    // 每次渲染都要单独创建一个CommandBuffer
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    
    // 渲染到纹理
    {
        // 创建计算指令的编码器
        id<MTLComputeCommandEncoder> renderToTextureEncoder = [commandBuffer computeCommandEncoder];
        // 设置计算管道，以调用shaders.metal中的内核计算函数
        [renderToTextureEncoder setComputePipelineState:self.computePipelineState];
        // 输入纹理
        [renderToTextureEncoder setTexture:self.sourceTexture
                           atIndex:LYFragmentTextureIndexTextureSource];
        // 输出纹理
        [renderToTextureEncoder setTexture:self.destTexture
                           atIndex:LYFragmentTextureIndexTextureDest];
        
        [renderToTextureEncoder setThreadgroupMemoryLength:(sizeof(vector_float3) + 15) / 16 * 16 atIndex:0];
        [renderToTextureEncoder setBuffer:self.groupParams offset:0 atIndex:0];
        
        // 计算区域
        [renderToTextureEncoder dispatchThreadgroups:self.groupCount
                       threadsPerThreadgroup:self.groupSize];
        
        // 调用endEncoding释放编码器，下个encoder才能创建
        [renderToTextureEncoder endEncoding];
    }
    
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        if (kCVReturnSuccess == CVPixelBufferLockBaseAddress(self.renderPixelBuffer,
                                                             kCVPixelBufferLock_ReadOnly)) { // 获取到buffer
            dispatch_async(dispatch_get_main_queue(), ^{
                UIImage *image = [self lyGetImageFromPixelBuffer:self.renderPixelBuffer]; // 转成UIImage
                if (!self.imageView) {
                    self.imageView = [[UIImageView alloc] initWithImage:image];
                    [self.view addSubview:self.imageView];
                }
                // OpenGL ES渲染
                [self.glView displayPixelBuffer:self.renderPixelBuffer];
                // 释放资源
                CVPixelBufferUnlockBaseAddress(self.renderPixelBuffer, kCVPixelBufferLock_ReadOnly);
            });
        }
    }];
    
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    // MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    if(renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f); // 设置默认颜色
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor]; //编码绘制指令的Encoder
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.x, self.viewportSize.y, -1.0, 1.0 }]; // 设置显示区域
        [renderEncoder setRenderPipelineState:self.renderPipelineState]; // 设置渲染管道，以保证顶点和片元两个shader会被调用
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:0]; // 设置顶点缓存
        
        [renderEncoder setFragmentTexture:self.destTexture
                                  atIndex:0]; // 设置纹理
        
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:self.numVertices]; // 绘制
        
        [renderEncoder endEncoding]; // 结束
        
        [commandBuffer presentDrawable:view.currentDrawable]; // 显示
    }
    
    [commandBuffer commit]; // 提交；
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
