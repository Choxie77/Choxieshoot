#import "VideoEditorEngine.h"
#import <Cocoa/Cocoa.h>

@implementation VideoEditorEngine

+ (void)exportVideoAtURL:(NSURL *)sourceURL
           trimStartTime:(NSTimeInterval)startTime
             trimEndTime:(NSTimeInterval)endTime
                cropRect:(CGRect)cropPixelRect
          destinationURL:(NSURL *)destinationURL
         progressHandler:(nullable void (^)(float progress))progressHandler
              completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    if (sourceURL == nil || destinationURL == nil) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:400
                                           userInfo:@{NSLocalizedDescriptionKey: @"Source or destination URL is nil."}];
            completion(NO, err);
        }
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:sourceURL.path]) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:404
                                           userInfo:@{NSLocalizedDescriptionKey: @"Source video file not found."}];
            completion(NO, err);
        }
        return;
    }

    // Ensure parent directory exists
    NSURL *parentDir = [destinationURL URLByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:parentDir.path]) {
        NSError *dirErr = nil;
        if (![fm createDirectoryAtURL:parentDir withIntermediateDirectories:YES attributes:nil error:&dirErr]) {
            if (completion) {
                completion(NO, dirErr);
            }
            return;
        }
    }

    // Remove existing file at destination
    if ([fm fileExistsAtPath:destinationURL.path]) {
        [fm removeItemAtURL:destinationURL error:nil];
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        if (completion) {
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:422
                                           userInfo:@{NSLocalizedDescriptionKey: @"No video track found in source video."}];
            completion(NO, err);
        }
        return;
    }

    AVAssetTrack *videoTrack = videoTracks.firstObject;
    CGSize naturalSize = CGSizeApplyAffineTransform(videoTrack.naturalSize, videoTrack.preferredTransform);
    CGFloat origW = fabs(naturalSize.width);
    CGFloat origH = fabs(naturalSize.height);
    Float64 totalDuration = CMTimeGetSeconds(asset.duration);
    if (isnan(totalDuration) || isinf(totalDuration) || totalDuration <= 0) {
        totalDuration = 1.0;
    }

    // Sanitize trim bounds
    NSTimeInterval safeStart = MIN(MAX(startTime, 0.0), totalDuration);
    NSTimeInterval safeEnd = MAX(MIN(endTime, totalDuration), safeStart + 0.05);

    BOOL isTrimmed = (safeStart > 0.05 || (totalDuration - safeEnd) > 0.05);

    // Sanitize crop bounds
    BOOL hasCrop = NO;
    CGRect safeCrop = cropPixelRect;
    if (safeCrop.size.width > 0 && safeCrop.size.height > 0) {
        safeCrop.origin.x = MIN(MAX(safeCrop.origin.x, 0.0), origW - 16.0);
        safeCrop.origin.y = MIN(MAX(safeCrop.origin.y, 0.0), origH - 16.0);
        safeCrop.size.width = MIN(safeCrop.size.width, origW - safeCrop.origin.x);
        safeCrop.size.height = MIN(safeCrop.size.height, origH - safeCrop.origin.y);

        // Snap to even dimensions
        safeCrop.size.width = MAX(32.0, floor(safeCrop.size.width / 2.0) * 2.0);
        safeCrop.size.height = MAX(32.0, floor(safeCrop.size.height / 2.0) * 2.0);
        safeCrop.origin.x = floor(safeCrop.origin.x / 2.0) * 2.0;
        safeCrop.origin.y = floor(safeCrop.origin.y / 2.0) * 2.0;

        if (safeCrop.origin.x > 2.0 || safeCrop.origin.y > 2.0 ||
            fabs(safeCrop.size.width - origW) > 4.0 || fabs(safeCrop.size.height - origH) > 4.0) {
            hasCrop = YES;
        }
    }

    // Direct copy optimization if unedited
    if (!isTrimmed && !hasCrop && [sourceURL.pathExtension.lowercaseString isEqualToString:destinationURL.pathExtension.lowercaseString]) {
        NSError *copyErr = nil;
        BOOL ok = [fm copyItemAtURL:sourceURL toURL:destinationURL error:&copyErr];
        if (progressHandler) {
            progressHandler(1.0);
        }
        if (completion) {
            completion(ok, copyErr);
        }
        return;
    }

    // Build AVMutableComposition for trimming & cropping
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                          preferredTrackID:kCMPersistentTrackID_Invalid];

    CMTime startCM = CMTimeMakeWithSeconds(safeStart, 600);
    CMTime durationCM = CMTimeMakeWithSeconds(safeEnd - safeStart, 600);
    CMTimeRange trimRange = CMTimeRangeMake(startCM, durationCM);

    NSError *insertErr = nil;
    [compVideoTrack insertTimeRange:trimRange ofTrack:videoTrack atTime:kCMTimeZero error:&insertErr];
    if (insertErr) {
        if (completion) {
            completion(NO, insertErr);
        }
        return;
    }

    // Include audio track if present
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count > 0) {
        AVAssetTrack *audioTrack = audioTracks.firstObject;
        AVMutableCompositionTrack *compAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                              preferredTrackID:kCMPersistentTrackID_Invalid];
        [compAudioTrack insertTimeRange:trimRange ofTrack:audioTrack atTime:kCMTimeZero error:nil];
    }

    AVMutableVideoComposition *videoComposition = nil;
    if (hasCrop) {
        videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.renderSize = CGSizeMake(safeCrop.size.width, safeCrop.size.height);
        // Match frame rate or default to 30fps
        float nominalFps = videoTrack.nominalFrameRate > 1.0 ? videoTrack.nominalFrameRate : 30.0;
        videoComposition.frameDuration = CMTimeMake(1, (int32_t)llround(nominalFps));

        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, durationCM);

        AVMutableVideoCompositionLayerInstruction *layerInst =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compVideoTrack];

        // CoreGraphics / AVVideoComposition space: bottom-left is (0, 0).
        // If crop top-left is (safeCrop.origin.x, safeCrop.origin.y), bottom-left is (safeCrop.origin.x, origH - (y + h)).
        CGFloat cropOriginX = safeCrop.origin.x;
        CGFloat cropOriginY = origH - (safeCrop.origin.y + safeCrop.size.height);

        CGAffineTransform t = CGAffineTransformConcat(videoTrack.preferredTransform,
                                                     CGAffineTransformMakeTranslation(-cropOriginX, -cropOriginY));
        [layerInst setTransform:t atTime:kCMTimeZero];

        instruction.layerInstructions = @[layerInst];
        videoComposition.instructions = @[instruction];
    }

    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                           presetName:AVAssetExportPresetHighestQuality];
    if (videoComposition != nil) {
        exportSession.videoComposition = videoComposition;
    }
    exportSession.outputURL = destinationURL;

    NSString *ext = destinationURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mov"]) {
        exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    } else {
        exportSession.outputFileType = AVFileTypeMPEG4;
    }
    exportSession.shouldOptimizeForNetworkUse = YES;

    // Progress timer
    dispatch_source_t progressTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(progressTimer, DISPATCH_TIME_NOW, (uint64_t)(0.1 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(progressTimer, ^{
        if (progressHandler) {
            progressHandler(exportSession.progress);
        }
    });
    dispatch_resume(progressTimer);

    fprintf(stderr, "[VideoEditorEngine] Starting export... source=%s dest=%s isTrimmed=%d hasCrop=%d\n",
            sourceURL.path.UTF8String, destinationURL.path.UTF8String, isTrimmed, hasCrop);

    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        fprintf(stderr, "[VideoEditorEngine] export completed with status=%ld error=%s\n",
                (long)exportSession.status, exportSession.error.localizedDescription.UTF8String ?: "none");
        dispatch_source_cancel(progressTimer);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                if (progressHandler) {
                    progressHandler(1.0);
                }
                if (completion) {
                    completion(YES, nil);
                }
            } else {
                NSError *err = exportSession.error ?: [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                                         code:500
                                                                     userInfo:@{NSLocalizedDescriptionKey: @"Export session failed."}];
                if (completion) {
                    completion(NO, err);
                }
            }
        });
    }];
}

+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error {
    __block BOOL succeeded = NO;
    __block BOOL finished = NO;
    __block NSError *exportErr = nil;

    fprintf(stderr, "[VideoEditorEngine] Synchronous export requested\n");
    [self exportVideoAtURL:sourceURL
             trimStartTime:startTime
               trimEndTime:endTime
                  cropRect:cropPixelRect
            destinationURL:destinationURL
           progressHandler:nil
                completion:^(BOOL success, NSError * _Nullable err) {
        fprintf(stderr, "[VideoEditorEngine] Synchronous completion invoked: success=%d\n", success);
        succeeded = success;
        exportErr = err;
        finished = YES;
    }];

    if ([NSThread isMainThread]) {
        while (!finished) {
            @autoreleasepool {
                if (NSApp != nil) {
                    NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                        untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                                           inMode:NSDefaultRunLoopMode
                                                          dequeue:YES];
                    if (event) {
                        [NSApp sendEvent:event];
                    }
                } else {
                    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
                }
            }
        }
    } else {
        while (!finished) {
            [NSThread sleepForTimeInterval:0.01];
        }
    }
    fprintf(stderr, "[VideoEditorEngine] Synchronous export returning: succeeded=%d\n", succeeded);

    if (!succeeded && error != NULL) {
        *error = exportErr;
    }
    return succeeded;
}

@end
