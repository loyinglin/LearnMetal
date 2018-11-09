//
//  LYAssetReader.m
//  LearnOpenGLESWithGPUImage
//
//  Created by loyinglin on 2018/5/25.
//  Copyright © 2018年 loyinglin. All rights reserved.
//

#import "LYAssetReader.h"


@implementation LYAssetReader
{
    AVAssetReaderTrackOutput *readerVideoTrackOutput;
    AVAssetReader   *assetReader;
    NSURL *videoUrl;
    NSLock *lock;
}

- (instancetype)initWithUrl:(NSURL *)url {
    self = [super init];
    videoUrl = url;
    lock = [[NSLock alloc] init];
    [self customInit];
    return self;
}

- (void)customInit {
    NSDictionary *inputOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
    AVURLAsset *inputAsset = [[AVURLAsset alloc] initWithURL:videoUrl options:inputOptions];
    __weak typeof(self) weakSelf = self;
    [inputAsset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:@"tracks"] completionHandler: ^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError *error = nil;
            AVKeyValueStatus tracksStatus = [inputAsset statusOfValueForKey:@"tracks" error:&error];
            if (tracksStatus != AVKeyValueStatusLoaded)
            {
                NSLog(@"error %@", error);
                return;
            }
            [weakSelf processWithAsset:inputAsset];
        });
    }];
}

- (void)processWithAsset:(AVAsset *)asset
{
    [lock lock];
    NSLog(@"processWithAsset");
    NSError *error = nil;
    assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    
    NSMutableDictionary *outputSettings = [NSMutableDictionary dictionary];
    
    [outputSettings setObject:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    readerVideoTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] outputSettings:outputSettings];
    readerVideoTrackOutput.alwaysCopiesSampleData = NO;
    [assetReader addOutput:readerVideoTrackOutput];

    
    if ([assetReader startReading] == NO)
    {
        NSLog(@"Error reading from file at URL: %@", asset);
    }
    [lock unlock];
}

- (CMSampleBufferRef)readBuffer {
    [lock lock];
    CMSampleBufferRef sampleBufferRef = nil;
    
    if (readerVideoTrackOutput) {
        sampleBufferRef = [readerVideoTrackOutput copyNextSampleBuffer];
    }
    
    if (assetReader && assetReader.status == AVAssetReaderStatusCompleted) {
        NSLog(@"customInit");
        readerVideoTrackOutput = nil;
        assetReader = nil;
        [self customInit];
    }
    
    [lock unlock];
    return sampleBufferRef;
}


@end

