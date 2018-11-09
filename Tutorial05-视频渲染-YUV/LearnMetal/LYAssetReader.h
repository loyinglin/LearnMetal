//
//  LYAssetReader.h
//  LearnOpenGLESWithGPUImage
//
//  Created by loyinglin on 2018/5/25.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface LYAssetReader : NSObject

- (instancetype)initWithUrl:(NSURL *)url;

- (CMSampleBufferRef)readBuffer;

@end
