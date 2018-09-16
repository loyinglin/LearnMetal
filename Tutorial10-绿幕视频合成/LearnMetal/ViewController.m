//
//  ViewController.m
//  LearnMetal
//
//  Created by loyinglin on 2018/6/21.
//  Copyright © 2018年 loyinglin. All rights reserved.
//
@import MetalKit;
@import GLKit;

#import "LYShaderTypes.h"
#import "ViewController.h"
#import "LYAssetReader.h"

@interface ViewController () <MTKViewDelegate>

// view
@property (nonatomic, strong) MTKView *mtkView;

// reader
@property (nonatomic, strong) LYAssetReader *greenReader;
@property (nonatomic, strong) LYAssetReader *normalReader;
@property (nonatomic, assign) CVMetalTextureCacheRef textureCache;

// data
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLTexture> greenTexture;
@property (nonatomic, strong) id<MTLTexture> normalTexture;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> convertMatrix;
@property (nonatomic, assign) NSUInteger numVertices;


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
    self.mtkView.preferredFramesPerSecond = 30;
    
    self.greenReader = [[LYAssetReader alloc] initWithUrl:[[NSBundle mainBundle] URLForResource:@"greenscreen" withExtension:@"mp4"]];
    self.normalReader = [[LYAssetReader alloc] initWithUrl:[[NSBundle mainBundle] URLForResource:@"abc" withExtension:@"mp4"]];

    CVMetalTextureCacheCreate(NULL, NULL, self.mtkView.device, NULL, &_textureCache); // TextureCache的创建
    
    [self customInit];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)customInit {
    [self setupPipeline];
    [self setupVertex];
    [self setupMatrix];
}


/**
 
 // BT.601, which is the standard for SDTV.
 matrix_float3x3 kColorConversion601Default = (matrix_float3x3){
 (simd_float3){1.164,  1.164, 1.164},
 (simd_float3){0.0, -0.392, 2.017},
 (simd_float3){1.596, -0.813,   0.0},
 };
 
 //// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
 matrix_float3x3 kColorConversion601FullRangeDefault = (matrix_float3x3){
 (simd_float3){1.0,    1.0,    1.0},
 (simd_float3){0.0,    -0.343, 1.765},
 (simd_float3){1.4,    -0.711, 0.0},
 };
 
 //// BT.709, which is the standard for HDTV.
 matrix_float3x3 kColorConversion709Default[] = {
 (simd_float3){1.164,  1.164, 1.164},
 (simd_float3){0.0, -0.213, 2.112},
 (simd_float3){1.793, -0.533,   0.0},
 };
 */
- (void)setupMatrix { // 设置好转换的矩阵
    matrix_float3x3 kColorConversion601FullRangeMatrix = (matrix_float3x3){
        (simd_float3){1.0,    1.0,    1.0},
        (simd_float3){0.0,    -0.343, 1.765},
        (simd_float3){1.4,    -0.711, 0.0},
    };
    
    vector_float3 kColorConversion601FullRangeOffset = (vector_float3){ -(16.0/255.0), -0.5, -0.5}; // 这个是偏移
    
    LYConvertMatrix matrix;
    // 设置参数
    matrix.matrix = kColorConversion601FullRangeMatrix;
    matrix.offset = kColorConversion601FullRangeOffset;
    
    self.convertMatrix = [self.mtkView.device newBufferWithBytes:&matrix
                                                          length:sizeof(LYConvertMatrix)
                                                         options:MTLResourceStorageModeShared];
}

// 设置渲染管道
-(void)setupPipeline {
    id<MTLLibrary> defaultLibrary = [self.mtkView.device newDefaultLibrary]; // .metal
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"]; // 顶点shader，vertexShader是函数名
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"]; // 片元shader，samplingShader是函数名
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.mtkView.colorPixelFormat; // 设置颜色格式
    self.pipelineState = [self.mtkView.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                             error:NULL]; // 创建图形渲染管道，耗性能操作不宜频繁调用
    self.commandQueue = [self.mtkView.device newCommandQueue]; // CommandQueue是渲染指令队列，保证渲染指令有序地提交到GPU
}

// 设置顶点
- (void)setupVertex {
    static const LYVertex quadVertices[] =
    {   // 顶点坐标，分别是x、y、z、w；    纹理坐标，x、y；
        { {  1.0, -1.0, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -1.0, -1.0, 0.0, 1.0 },  { 0.f, 1.f } },
        { { -1.0,  1.0, 0.0, 1.0 },  { 0.f, 0.f } },
        
        { {  1.0, -1.0, 0.0, 1.0 },  { 1.f, 1.f } },
        { { -1.0,  1.0, 0.0, 1.0 },  { 0.f, 0.f } },
        { {  1.0,  1.0, 0.0, 1.0 },  { 1.f, 0.f } },
    };
    self.vertices = [self.mtkView.device newBufferWithBytes:quadVertices
                                                     length:sizeof(quadVertices)
                                                    options:MTLResourceStorageModeShared]; // 创建顶点缓存
    self.numVertices = sizeof(quadVertices) / sizeof(LYVertex); // 顶点个数
}

// 设置纹理
- (void)setupTextureWithEncoder:(id<MTLRenderCommandEncoder>)encoder buffer:(CMSampleBufferRef)sampleBuffer isGreen:(BOOL)isGreen {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer); // 从CMSampleBuffer读取CVPixelBuffer，
    
    id<MTLTexture> textureY = nil;
    id<MTLTexture> textureUV = nil;
    // textureY 设置
    {
        size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
        MTLPixelFormat pixelFormat = MTLPixelFormatR8Unorm; // 这里的颜色格式不是RGBA

        CVMetalTextureRef texture = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, self.textureCache, pixelBuffer, NULL, pixelFormat, width, height, 0, &texture);
        if(status == kCVReturnSuccess)
        {
            textureY = CVMetalTextureGetTexture(texture); // 转成Metal用的纹理
            CFRelease(texture);
        }
    }
    
    // textureUV 设置
    {
        size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
        size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
        MTLPixelFormat pixelFormat = MTLPixelFormatRG8Unorm; // 2-8bit的格式
        
        CVMetalTextureRef texture = NULL; // CoreVideo的Metal纹理
        CVReturn status = CVMetalTextureCacheCreateTextureFromImage(NULL, self.textureCache, pixelBuffer, NULL, pixelFormat, width, height, 1, &texture);
        if(status == kCVReturnSuccess)
        {
            textureUV = CVMetalTextureGetTexture(texture); // 转成Metal用的纹理
            CFRelease(texture);
        }
    }
    
    if(textureY != nil && textureUV != nil)
    {
        if (isGreen) {
            [encoder setFragmentTexture:textureY
                                atIndex:LYFragmentTextureIndexGreenTextureY]; // 设置纹理
            [encoder setFragmentTexture:textureUV
                                atIndex:LYFragmentTextureIndexGreenTextureUV]; // 设置纹理
        }
        else {
            [encoder setFragmentTexture:textureY
                                atIndex:LYFragmentTextureIndexNormalTextureY]; // 设置纹理
            [encoder setFragmentTexture:textureUV
                                atIndex:LYFragmentTextureIndexNormalTextureUV]; // 设置纹理
        }
    }
    CFRelease(sampleBuffer); // 记得释放
}


#pragma mark - delegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.viewportSize = (vector_uint2){size.width, size.height};
}


- (void)drawInMTKView:(MTKView *)view {
    // 每次渲染都要单独创建一个CommandBuffer
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    // MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder
    CMSampleBufferRef greenSampleBuffer = [self.greenReader readBuffer]; // 从LYAssetReader中读取图像数据
    CMSampleBufferRef normalSampleBuffer = [self.normalReader readBuffer]; // 从LYAssetReader中读取图像数据
    if(renderPassDescriptor && greenSampleBuffer && normalSampleBuffer)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f); // 设置默认颜色
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor]; //编码绘制指令的Encoder
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.x, self.viewportSize.y, -1.0, 1.0 }]; // 设置显示区域
        [renderEncoder setRenderPipelineState:self.pipelineState]; // 设置渲染管道，以保证顶点和片元两个shader会被调用
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:LYVertexInputIndexVertices]; // 设置顶点缓存
        
        [self setupTextureWithEncoder:renderEncoder buffer:greenSampleBuffer isGreen:YES];
        [self setupTextureWithEncoder:renderEncoder buffer:normalSampleBuffer isGreen:NO];
        
        [renderEncoder setFragmentBuffer:self.convertMatrix
                                  offset:0
                                 atIndex:LYFragmentInputIndexMatrix];
        
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
