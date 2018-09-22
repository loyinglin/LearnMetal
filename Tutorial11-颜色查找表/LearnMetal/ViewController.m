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

@interface ViewController () <MTKViewDelegate>

// view
@property (nonatomic, strong) MTKView *mtkView;

// data
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLTexture> lookupTableTexture;
@property (nonatomic, strong) id<MTLTexture> normalTexture;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, assign) NSUInteger numVertices;

@property (nonatomic, strong) UIImageView *imageView;

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
    
    [self customInit];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)customInit {
    [self setupPipeline];
    [self setupVertex];
    [self setupTexture];
}


- (void)setupTexture {
    // 正常的纹理
    {
        UIImage *image = [UIImage imageNamed:@"test.jpeg"];
        // 纹理描述符
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm; // 图片的格式要和数据一致
        textureDescriptor.width = image.size.width;
        textureDescriptor.height = image.size.height;
        textureDescriptor.usage = MTLTextureUsageShaderRead; // 原图片只需要读取
        self.normalTexture = [self.mtkView.device newTextureWithDescriptor:textureDescriptor]; // 创建纹理
        
        MTLRegion region = {{ 0, 0, 0 }, {image.size.width, image.size.height, 1}}; // 纹理上传的范围
        Byte *imageBytes = [self loadImage:image];
        if (imageBytes) { // UIImage的数据需要转成二进制才能上传，且不用jpg、png的NSData
            [self.normalTexture replaceRegion:region
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

    }
    
    {
        UIImage *image = [UIImage imageNamed:@"lookupTable.png"];
        // 纹理描述符
        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm; // 图片的格式要和数据一致
        textureDescriptor.width = image.size.width;
        textureDescriptor.height = image.size.height;
        textureDescriptor.usage = MTLTextureUsageShaderRead; // 原图片只需要读取
        self.lookupTableTexture = [self.mtkView.device newTextureWithDescriptor:textureDescriptor]; // 创建纹理
        
        MTLRegion region = {{ 0, 0, 0 }, {image.size.width, image.size.height, 1}}; // 纹理上传的范围
        Byte *imageBytes = [self loadImage:image];
        if (imageBytes) { // UIImage的数据需要转成二进制才能上传，且不用jpg、png的NSData
            [self.lookupTableTexture replaceRegion:region
                                  mipmapLevel:0
                                    withBytes:imageBytes
                                  bytesPerRow:4 * image.size.width];
            free(imageBytes); // 需要释放资源
            imageBytes = NULL;
        }
    }
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


#pragma mark - delegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.viewportSize = (vector_uint2){size.width, size.height};
}


- (void)drawInMTKView:(MTKView *)view {
    // 每次渲染都要单独创建一个CommandBuffer
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    // MTLRenderPassDescriptor描述一系列attachments的值，类似GL的FrameBuffer；同时也用来创建MTLRenderCommandEncoder

    if(renderPassDescriptor) {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f); // 设置默认颜色
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor]; //编码绘制指令的Encoder
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.x, self.viewportSize.y, -1.0, 1.0 }]; // 设置显示区域
        [renderEncoder setRenderPipelineState:self.pipelineState]; // 设置渲染管道，以保证顶点和片元两个shader会被调用
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:LYVertexInputIndexVertices]; // 设置顶点缓存
        
        [renderEncoder setFragmentTexture:self.normalTexture
                            atIndex:LYFragmentTextureIndexNormal]; // 设置纹理
        [renderEncoder setFragmentTexture:self.lookupTableTexture
                            atIndex:LYFragmentTextureIndexLookupTable]; // 设置纹理
        
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
