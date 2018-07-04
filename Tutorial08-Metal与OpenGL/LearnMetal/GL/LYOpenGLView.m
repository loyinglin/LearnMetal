//
//  Created by loyinglin on 2018年06月29日.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#import "LYOpenGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <GLKit/GLKit.h>

// Uniform index.
enum
{
	UNIFORM_INPUT,
	NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
	ATTRIB_VERTEX,
	ATTRIB_TEXCOORD,
	NUM_ATTRIBUTES
};

@interface LYOpenGLView ()
{
	// The pixel dimensions of the CAEAGLLayer.
	GLint _backingWidth;
	GLint _backingHeight;

	EAGLContext *_context;
	CVOpenGLESTextureRef _inputTexture;
	CVOpenGLESTextureCacheRef _textureCache;
	
	GLuint _frameBufferHandle;
	GLuint _colorBufferHandle;
}

@property GLuint program;

- (void)setupBuffers;
- (void)cleanUpTextures;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation LYOpenGLView

+ (Class)layerClass
{
	return [CAEAGLLayer class];
}

- (id)initWithFrame:(CGRect)frame {
	if (self = [super initWithFrame:frame])
	{
		self.contentScaleFactor = [[UIScreen mainScreen] scale];

		CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

		eaglLayer.opaque = TRUE;
		eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
										  kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};

		_context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

		if (!_context || ![EAGLContext setCurrentContext:_context] || ![self loadShaders]) {
			return nil;
		}
		
	}
	return self;
}

# pragma mark - OpenGL setup

- (void)setupGL
{
	[EAGLContext setCurrentContext:_context];
	[self setupBuffers];
	[self loadShaders];
	
	glUseProgram(self.program);
	
	glUniform1i(uniforms[UNIFORM_INPUT], 0);
	
	// Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
	if (!_textureCache) {
		CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_textureCache);
		if (err != noErr) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
			return;
		}
	}
}

#pragma mark - Utilities

- (void)setupBuffers
{
	glDisable(GL_DEPTH_TEST);
	
	glEnableVertexAttribArray(ATTRIB_VERTEX);
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
	
	glEnableVertexAttribArray(ATTRIB_TEXCOORD);
	glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
	
	glGenFramebuffers(1, &_frameBufferHandle);
	glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
	
	glGenRenderbuffers(1, &_colorBufferHandle);
	glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
	
	[_context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);

	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
		NSLog(@"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	}
}

- (void)cleanUpTextures
{
	if (_inputTexture) {
		CFRelease(_inputTexture);
		_inputTexture = NULL;
	}
	
	// Periodic texture cache flush every frame
	CVOpenGLESTextureCacheFlush(_textureCache, 0);
}

- (void)dealloc
{
	[self cleanUpTextures];
	
	if(_textureCache) {
		CFRelease(_textureCache);
	}
}

#pragma mark - OpenGLES drawing

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
	CVReturn err;
	if (pixelBuffer != NULL) {
		int frameWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
		int frameHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
		
		if (!_textureCache) {
			NSLog(@"No video texture cache");
			return;
		}
        if ([EAGLContext currentContext] != _context) {
            [EAGLContext setCurrentContext:_context]; // 非常重要的一行代码
        }
		[self cleanUpTextures];
		
					
		/*
         CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture optimally from CVPixelBufferRef.
         */
		
		glActiveTexture(GL_TEXTURE0);
		err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
														   _textureCache,
														   pixelBuffer,
														   NULL,
														   GL_TEXTURE_2D,
														   GL_RGBA,
														   frameWidth,
														   frameHeight,
														   GL_RGBA,
														   GL_UNSIGNED_BYTE,
														   0,
														   &_inputTexture);
		if (err) {
			NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
		}
		
        glBindTexture(CVOpenGLESTextureGetTarget(_inputTexture), CVOpenGLESTextureGetName(_inputTexture));
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		
        
		glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
		
		// Set the view port to the entire view.
		glViewport(0, 0, _backingWidth, _backingHeight);
	}
	
	glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	
	// Use shader program.
	glUseProgram(self.program);
	
	// Set up the quad vertices with respect to the orientation and aspect ratio of the video.
	CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(_backingWidth, _backingHeight), self.layer.bounds);
	
	// Compute normalized quad coordinates to draw the frame into.
	CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
	CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/self.layer.bounds.size.width, vertexSamplingRect.size.height/self.layer.bounds.size.height);
	
	// Normalize the quad vertices.
	if (cropScaleAmount.width > cropScaleAmount.height) {
		normalizedSamplingSize.width = 1.0;
		normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
	}
	else {
		normalizedSamplingSize.width = 1.0;
		normalizedSamplingSize.height = cropScaleAmount.width/cropScaleAmount.height;
	}
	
	/*
     The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
     Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively, covers the entire screen.
     */
	GLfloat quadVertexData [] = {
		-1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
			 normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
		-1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
			 normalizedSamplingSize.width, normalizedSamplingSize.height,
	};
	
	// 更新顶点数据
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
	glEnableVertexAttribArray(ATTRIB_VERTEX);
    
    GLfloat quadTextureData[] =  { // 正常坐标
        0, 1,
        1, 1,
        0, 0,
        1, 0
    };
	
	glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, 0, 0, quadTextureData);
	glEnableVertexAttribArray(ATTRIB_TEXCOORD);
	
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    
    if ([EAGLContext currentContext] == _context) {
        [_context presentRenderbuffer:GL_RENDERBUFFER];
    }
    
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
	GLuint vertShader, fragShader;
	NSURL *vertShaderURL, *fragShaderURL;
	
	self.program = glCreateProgram();
	
	// Create and compile the vertex shader.
	vertShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"vsh"];
	if (![self compileShader:&vertShader type:GL_VERTEX_SHADER URL:vertShaderURL]) {
		NSLog(@"Failed to compile vertex shader");
		return NO;
	}
	
	// Create and compile fragment shader.
	fragShaderURL = [[NSBundle mainBundle] URLForResource:@"Shader" withExtension:@"fsh"];
	if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER URL:fragShaderURL]) {
		NSLog(@"Failed to compile fragment shader");
		return NO;
	}
	
	// Attach vertex shader to program.
	glAttachShader(self.program, vertShader);
	
	// Attach fragment shader to program.
	glAttachShader(self.program, fragShader);
	
	// Bind attribute locations. This needs to be done prior to linking.
	glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
	glBindAttribLocation(self.program, ATTRIB_TEXCOORD, "texCoord");
	
	// Link the program.
	if (![self linkProgram:self.program]) {
		NSLog(@"Failed to link program: %d", self.program);
		
		if (vertShader) {
			glDeleteShader(vertShader);
			vertShader = 0;
		}
		if (fragShader) {
			glDeleteShader(fragShader);
			fragShader = 0;
		}
		if (self.program) {
			glDeleteProgram(self.program);
			self.program = 0;
		}
		
		return NO;
	}
	
	// Get uniform locations.
	uniforms[UNIFORM_INPUT] = glGetUniformLocation(self.program, "texture");
	
	// Release vertex and fragment shaders.
	if (vertShader) {
		glDetachShader(self.program, vertShader);
		glDeleteShader(vertShader);
	}
	if (fragShader) {
		glDetachShader(self.program, fragShader);
		glDeleteShader(fragShader);
	}
	
	return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL
{
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
		NSLog(@"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }
    
	GLint status;
	const GLchar *source;
	source = (GLchar *)[sourceString UTF8String];
	
	*shader = glCreateShader(type);
	glShaderSource(*shader, 1, &source, NULL);
	glCompileShader(*shader);
	
#if defined(DEBUG)
	GLint logLength;
	glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetShaderInfoLog(*shader, logLength, &logLength, log);
		NSLog(@"Shader compile log:\n%s", log);
		free(log);
	}
#endif
	
	glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	if (status == 0) {
		glDeleteShader(*shader);
		return NO;
	}
	
	return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
	GLint status;
	glLinkProgram(prog);
	
#if defined(DEBUG)
	GLint logLength;
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program link log:\n%s", log);
		free(log);
	}
#endif
	
	glGetProgramiv(prog, GL_LINK_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
	GLint logLength, status;
	
	glValidateProgram(prog);
	glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
	if (logLength > 0) {
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(prog, logLength, &logLength, log);
		NSLog(@"Program validate log:\n%s", log);
		free(log);
	}
	
	glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
	if (status == 0) {
		return NO;
	}
	
	return YES;
}

@end

