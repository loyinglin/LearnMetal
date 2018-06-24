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
@property (nonatomic, strong) IBOutlet UISwitch *rotationX;
@property (nonatomic, strong) IBOutlet UISwitch *rotationY;
@property (nonatomic, strong) IBOutlet UISwitch *rotationZ;

@property (nonatomic, strong) IBOutlet UISlider *slider;

// data
@property (nonatomic, assign) vector_uint2 viewportSize;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) id<MTLBuffer> vertices;
@property (nonatomic, strong) id<MTLBuffer> indexs;
@property (nonatomic, assign) NSUInteger indexCount;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.mtkView = [[MTKView alloc] initWithFrame:self.view.bounds];
    self.mtkView.device = MTLCreateSystemDefaultDevice();
    [self.view insertSubview:self.mtkView atIndex:0];
    self.mtkView.delegate = self;
    self.viewportSize = (vector_uint2){self.mtkView.drawableSize.width, self.mtkView.drawableSize.height};
    
    [self customInit];
}

- (void)customInit {
    [self setupPipeline];
    [self setupVertex];
    [self setupTexture];
}

-(void)setupPipeline {
    id<MTLLibrary> defaultLibrary = [self.mtkView.device newDefaultLibrary];
    id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];
    
    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.mtkView.colorPixelFormat;
    self.pipelineState = [self.mtkView.device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                         error:NULL];
    self.commandQueue = [self.mtkView.device newCommandQueue];
}

- (void)setupVertex {
    static const LYVertex quadVertices[] =
    {  // 顶点坐标                          顶点颜色                    纹理坐标
        {{-0.5f, 0.5f, 0.0f, 1.0f},      {0.0f, 0.0f, 0.5f},       {0.0f, 1.0f}},//左上
        {{0.5f, 0.5f, 0.0f, 1.0f},       {0.0f, 0.5f, 0.0f},       {1.0f, 1.0f}},//右上
        {{-0.5f, -0.5f, 0.0f, 1.0f},     {0.5f, 0.0f, 1.0f},       {0.0f, 0.0f}},//左下
        {{0.5f, -0.5f, 0.0f, 1.0f},      {0.0f, 0.0f, 0.5f},       {1.0f, 0.0f}},//右下
        {{0.0f, 0.0f, 1.0f, 1.0f},       {1.0f, 1.0f, 1.0f},       {0.5f, 0.5f}},//顶点
    };
    self.vertices = [self.mtkView.device newBufferWithBytes:quadVertices
                                                 length:sizeof(quadVertices)
                                                options:MTLResourceStorageModeShared];
    static int indices[] =
    { // 索引
        0, 3, 2,
        0, 1, 3,
        0, 2, 4,
        0, 4, 1,
        2, 3, 4,
        1, 4, 3,
    };
    self.indexs = [self.mtkView.device newBufferWithBytes:indices
                                                     length:sizeof(indices)
                                                    options:MTLResourceStorageModeShared];
    self.indexCount = sizeof(indices) / sizeof(int);
}

- (void)setupTexture {
    UIImage *image = [UIImage imageNamed:@"abc"];
    MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    textureDescriptor.width = image.size.width;
    textureDescriptor.height = image.size.height;
    self.texture = [self.mtkView.device newTextureWithDescriptor:textureDescriptor];
    
    MTLRegion region = {{ 0, 0, 0 }, {image.size.width, image.size.height, 1}};
    Byte *imageBytes = [self loadImage:image];
    if (imageBytes) {
        [self.texture replaceRegion:region
                    mipmapLevel:0
                      withBytes:imageBytes
                    bytesPerRow:4 * image.size.width];
        free(imageBytes);
        imageBytes = NULL;
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


/**
 找了很多文档，都没有发现metalKit或者simd相关的接口可以快捷创建矩阵的，于是只能从GLKit里面借力

 @param matrix GLKit的矩阵
 @return metal用的矩阵
 */
- (matrix_float4x4)getMetalMatrixFromGLKMatrix:(GLKMatrix4)matrix {
    matrix_float4x4 ret = (matrix_float4x4){
        simd_make_float4(matrix.m00, matrix.m01, matrix.m02, matrix.m03),
        simd_make_float4(matrix.m10, matrix.m11, matrix.m12, matrix.m13),
        simd_make_float4(matrix.m20, matrix.m21, matrix.m22, matrix.m23),
        simd_make_float4(matrix.m30, matrix.m31, matrix.m32, matrix.m33),
    };
    return ret;
}

- (void)setupMatrixWithEncoder:(id<MTLRenderCommandEncoder>)renderEncoder {
    CGSize size = self.view.bounds.size;
    float aspect = fabs(size.width / size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(90.0), aspect, 0.1f, 10.f);
    GLKMatrix4 modelViewMatrix = GLKMatrix4Translate(GLKMatrix4Identity, 0.0f, 0.0f, -2.0f);
    static float x = 0.0, y = 0.0, z = M_PI;
    if (self.rotationX.on) {
        x += self.slider.value;
    }
    if (self.rotationY.on) {
        y += self.slider.value;
    }
    if (self.rotationZ.on) {
        z += self.slider.value;
    }
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, x, 1, 0, 0);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, y, 0, 1, 0);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, z, 0, 0, 1);
    
    LYMatrix matrix = {[self getMetalMatrixFromGLKMatrix:projectionMatrix], [self getMetalMatrixFromGLKMatrix:modelViewMatrix]};
    
    [renderEncoder setVertexBytes:&matrix
                           length:sizeof(matrix)
                          atIndex:LYVertexInputIndexMatrix];
}

#pragma mark - delegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    self.viewportSize = (vector_uint2){size.width, size.height};
}

- (void)drawInMTKView:(MTKView *)view {
    
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    
    if(renderPassDescriptor != nil)
    {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.5, 0.5, 1.0f);
        renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, self.viewportSize.x, self.viewportSize.y, -1.0, 1.0 }];
        [renderEncoder setRenderPipelineState:self.pipelineState];
        [self setupMatrixWithEncoder:renderEncoder];
        
        [renderEncoder setVertexBuffer:self.vertices
                                offset:0
                               atIndex:LYVertexInputIndexVertices];
        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        
        [renderEncoder setFragmentTexture:self.texture
                                  atIndex:LYFragmentInputIndexTexture];
        
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                  indexCount:self.indexCount
                                   indexType:MTLIndexTypeUInt32
                                 indexBuffer:self.indexs
                           indexBufferOffset:0];
        
        [renderEncoder endEncoding];
        
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    [commandBuffer commit];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
