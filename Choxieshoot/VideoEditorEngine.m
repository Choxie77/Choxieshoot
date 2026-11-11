#import "VideoEditorEngine.h"
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation VideoEditorEngine

#pragma mark - Backward Compatible Convenience APIs

+ (nullable AVAssetExportSession *)exportVideoAtURL:(NSURL *)sourceURL
                                      trimStartTime:(NSTimeInterval)startTime
                                        trimEndTime:(NSTimeInterval)endTime
                                           cropRect:(CGRect)cropPixelRect
                                     destinationURL:(NSURL *)destinationURL
                                    progressHandler:(nullable void (^)(float progress))progressHandler
                                         completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    return [self exportVideoAtURL:sourceURL
                    trimStartTime:startTime
                      trimEndTime:endTime
                         cropRect:cropPixelRect
                         rotation:0
                    playbackSpeed:1.0
                        muteAudio:NO
                   destinationURL:destinationURL
                  progressHandler:progressHandler
                  completionQueue:dispatch_get_main_queue()
                       completion:completion];
}

+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error {
    return [self exportVideoSynchronousAtURL:sourceURL
                               trimStartTime:startTime
                                 trimEndTime:endTime
                                    cropRect:cropPixelRect
                                    rotation:0
                               playbackSpeed:1.0
                                   muteAudio:NO
                              destinationURL:destinationURL
                                       error:error];
}

#pragma mark - Full Video Export

+ (nullable AVAssetExportSession *)exportVideoAtURL:(NSURL *)sourceURL
                                      trimStartTime:(NSTimeInterval)startTime
                                        trimEndTime:(NSTimeInterval)endTime
                                           cropRect:(CGRect)cropPixelRect
                                           rotation:(NSInteger)rotationDegrees
                                      playbackSpeed:(CGFloat)playbackSpeed
                                          muteAudio:(BOOL)muteAudio
                                     destinationURL:(NSURL *)destinationURL
                                    progressHandler:(nullable void (^)(float progress))progressHandler
                                    completionQueue:(nullable dispatch_queue_t)completionQueue
                                         completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    void (^deliverCompletion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        if (!completion) return;
        if (completionQueue != nil) {
            dispatch_async(completionQueue, ^{
                completion(success, error);
            });
        } else {
            completion(success, error);
        }
    };

    if (sourceURL == nil || destinationURL == nil) {
        NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Source or destination URL is nil."}];
        deliverCompletion(NO, err);
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:sourceURL.path]) {
        NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                           code:404
                                       userInfo:@{NSLocalizedDescriptionKey: @"Source video file not found."}];
        deliverCompletion(NO, err);
        return nil;
    }

    // Ensure parent directory exists
    NSURL *parentDir = [destinationURL URLByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:parentDir.path]) {
        NSError *dirErr = nil;
        if (![fm createDirectoryAtURL:parentDir withIntermediateDirectories:YES attributes:nil error:&dirErr]) {
            deliverCompletion(NO, dirErr);
            return nil;
        }
    }

    // Remove existing file at destination
    if ([fm fileExistsAtPath:destinationURL.path]) {
        [fm removeItemAtURL:destinationURL error:nil];
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                           code:422
                                       userInfo:@{NSLocalizedDescriptionKey: @"No video track found in source video."}];
        deliverCompletion(NO, err);
        return nil;
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
    } else {
        safeCrop = CGRectMake(0, 0, origW, origH);
    }

    NSInteger normRotation = ((rotationDegrees % 360) + 360) % 360;
    BOOL hasRotation = (normRotation != 0);

    CGFloat safeSpeed = (playbackSpeed >= 0.25 && playbackSpeed <= 4.0) ? playbackSpeed : 1.0;
    BOOL hasSpeed = (fabs(safeSpeed - 1.0) > 0.02);

    // Direct copy optimization if completely unedited
    if (!isTrimmed && !hasCrop && !hasRotation && !hasSpeed && !muteAudio &&
        [sourceURL.pathExtension.lowercaseString isEqualToString:destinationURL.pathExtension.lowercaseString]) {
        NSError *copyErr = nil;
        BOOL ok = [fm copyItemAtURL:sourceURL toURL:destinationURL error:&copyErr];
        if (progressHandler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                progressHandler(1.0);
            });
        }
        deliverCompletion(ok, copyErr);
        return nil;
    }

    // Build AVMutableComposition
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                          preferredTrackID:kCMPersistentTrackID_Invalid];

    CMTime startCM = CMTimeMakeWithSeconds(safeStart, 600);
    CMTime durationCM = CMTimeMakeWithSeconds(safeEnd - safeStart, 600);
    CMTimeRange trimRange = CMTimeRangeMake(startCM, durationCM);

    NSError *insertErr = nil;
    [compVideoTrack insertTimeRange:trimRange ofTrack:videoTrack atTime:kCMTimeZero error:&insertErr];
    if (insertErr) {
        deliverCompletion(NO, insertErr);
        return nil;
    }

    Float64 scaledDurationSec = (safeEnd - safeStart) / safeSpeed;
    CMTime scaledDurationCM = CMTimeMakeWithSeconds(scaledDurationSec, 600);
    if (hasSpeed) {
        [compVideoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, durationCM) toDuration:scaledDurationCM];
    }

    // Include audio track if audio is not muted
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (!muteAudio && audioTracks.count > 0) {
        AVAssetTrack *audioTrack = audioTracks.firstObject;
        AVMutableCompositionTrack *compAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                                              preferredTrackID:kCMPersistentTrackID_Invalid];
        [compAudioTrack insertTimeRange:trimRange ofTrack:audioTrack atTime:kCMTimeZero error:nil];
        if (hasSpeed) {
            [compAudioTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, durationCM) toDuration:scaledDurationCM];
        }
    }

    AVMutableVideoComposition *videoComposition = nil;
    if (hasCrop || hasRotation) {
        videoComposition = [AVMutableVideoComposition videoComposition];
        float nominalFps = videoTrack.nominalFrameRate > 1.0 ? videoTrack.nominalFrameRate : 30.0;
        videoComposition.frameDuration = CMTimeMake(1, (int32_t)llround(nominalFps));

        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, scaledDurationCM);

        AVMutableVideoCompositionLayerInstruction *layerInst =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compVideoTrack];

        CGFloat cropW = safeCrop.size.width;
        CGFloat cropH = safeCrop.size.height;
        CGFloat cropOriginX = safeCrop.origin.x;
        CGFloat cropOriginY = origH - (safeCrop.origin.y + cropH);

        CGAffineTransform tCrop = CGAffineTransformConcat(videoTrack.preferredTransform,
                                                             CGAffineTransformMakeTranslation(-cropOriginX, -cropOriginY));

        CGAffineTransform finalTransform = tCrop;
        CGSize renderSize = CGSizeMake(cropW, cropH);

        if (normRotation == 90) {
            // 90 deg clockwise
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(-M_PI_2),
                                                            CGAffineTransformMakeTranslation(0, cropW));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropH, cropW);
        } else if (normRotation == 180) {
            // 180 deg
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(M_PI),
                                                            CGAffineTransformMakeTranslation(cropW, cropH));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropW, cropH);
        } else if (normRotation == 270) {
            // 270 deg clockwise (90 deg counter-clockwise)
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(M_PI_2),
                                                            CGAffineTransformMakeTranslation(cropH, 0));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropH, cropW);
        }

        // Even dimensions check
        renderSize.width = floor(renderSize.width / 2.0) * 2.0;
        renderSize.height = floor(renderSize.height / 2.0) * 2.0;
        videoComposition.renderSize = renderSize;

        [layerInst setTransform:finalTransform atTime:kCMTimeZero];
        instruction.layerInstructions = @[layerInst];
        videoComposition.instructions = @[instruction];
    } else {
        compVideoTrack.preferredTransform = videoTrack.preferredTransform;
        // Even dimensions check for uncropped video to prevent encoder stall on odd resolutions
        if ((NSInteger)origW % 2 != 0 || (NSInteger)origH % 2 != 0) {
            videoComposition = [AVMutableVideoComposition videoComposition];
            float nominalFps = videoTrack.nominalFrameRate > 1.0 ? videoTrack.nominalFrameRate : 30.0;
            videoComposition.frameDuration = CMTimeMake(1, (int32_t)llround(nominalFps));

            AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
            instruction.timeRange = CMTimeRangeMake(kCMTimeZero, scaledDurationCM);

            AVMutableVideoCompositionLayerInstruction *layerInst =
                [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compVideoTrack];

            CGSize renderSize = CGSizeMake(floor(origW / 2.0) * 2.0, floor(origH / 2.0) * 2.0);
            videoComposition.renderSize = renderSize;

            [layerInst setTransform:videoTrack.preferredTransform atTime:kCMTimeZero];
            instruction.layerInstructions = @[layerInst];
            videoComposition.instructions = @[instruction];
        }
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

    // Watchdog timer (60s) to abort export session if AVFoundation hangs
    __block BOOL completedOrCancelled = NO;
    dispatch_source_t watchdogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    dispatch_source_set_timer(watchdogTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, (uint64_t)(1.0 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(watchdogTimer, ^{
        if (!completedOrCancelled && exportSession.status == AVAssetExportSessionStatusExporting) {
            fprintf(stderr, "[VideoEditorEngine] Watchdog triggered! Export session timed out after 60s, cancelling...\n");
            [exportSession cancelExport];
        }
    });
    dispatch_resume(watchdogTimer);

    fprintf(stderr, "[VideoEditorEngine] Starting export... source=%s dest=%s trim=%.2f-%.2fs crop=%d rot=%ld spd=%.2f mute=%d\n",
            sourceURL.path.UTF8String, destinationURL.path.UTF8String, safeStart, safeEnd, hasCrop, (long)normRotation, safeSpeed, muteAudio);

    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        completedOrCancelled = YES;
        dispatch_source_cancel(watchdogTimer);
        dispatch_source_cancel(progressTimer);
        fprintf(stderr, "[VideoEditorEngine] export completed with status=%ld error=%s\n",
                (long)exportSession.status, exportSession.error.localizedDescription.UTF8String ?: "none");

        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            if (progressHandler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressHandler(1.0);
                });
            }
            deliverCompletion(YES, nil);
        } else if (exportSession.status == AVAssetExportSessionStatusCancelled) {
            [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
            NSError *cancelErr = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                     code:NSUserCancelledError
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Export was cancelled."}];
            deliverCompletion(NO, cancelErr);
        } else {
            [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
            NSError *err = exportSession.error ?: [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                                     code:500
                                                                 userInfo:@{NSLocalizedDescriptionKey: @"Export session failed."}];
            deliverCompletion(NO, err);
        }
    }];

    return exportSession;
}

+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                           rotation:(NSInteger)rotationDegrees
                      playbackSpeed:(CGFloat)playbackSpeed
                          muteAudio:(BOOL)muteAudio
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error {
    __block BOOL succeeded = NO;
    __block NSError *exportErr = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    fprintf(stderr, "[VideoEditorEngine] Synchronous export requested\n");
    AVAssetExportSession *session = [self exportVideoAtURL:sourceURL
                                             trimStartTime:startTime
                                               trimEndTime:endTime
                                                  cropRect:cropPixelRect
                                                  rotation:rotationDegrees
                                             playbackSpeed:playbackSpeed
                                                 muteAudio:muteAudio
                                            destinationURL:destinationURL
                                           progressHandler:nil
                                           completionQueue:NULL
                                                completion:^(BOOL success, NSError * _Nullable err) {
        fprintf(stderr, "[VideoEditorEngine] Synchronous completion invoked: success=%d\n", success);
        succeeded = success;
        exportErr = err;
        dispatch_semaphore_signal(sema);
    }];

    // 35.0-second safety timeout instead of DISPATCH_TIME_FOREVER to prevent UI freeze
    intptr_t waitResult = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        fprintf(stderr, "[VideoEditorEngine] Synchronous export timed out after 35s! Cancelling session...\n");
        [session cancelExport];
        succeeded = NO;
        exportErr = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                        code:ETIMEDOUT
                                    userInfo:@{NSLocalizedDescriptionKey: @"Synchronous video export timed out after 35 seconds."}];
    }
    fprintf(stderr, "[VideoEditorEngine] Synchronous export returning: succeeded=%d\n", succeeded);

    if (!succeeded && error != NULL) {
        *error = exportErr;
    }
    return succeeded;
}

#pragma mark - Animated GIF Export

+ (nullable void (^)(void))exportGifAtURL:(NSURL *)sourceURL
                            trimStartTime:(NSTimeInterval)startTime
                              trimEndTime:(NSTimeInterval)endTime
                                 cropRect:(CGRect)cropPixelRect
                                 rotation:(NSInteger)rotationDegrees
                            playbackSpeed:(CGFloat)playbackSpeed
                                      fps:(CGFloat)fps
                           destinationURL:(NSURL *)destinationURL
                          progressHandler:(nullable void (^)(float progress))progressHandler
                          completionQueue:(nullable dispatch_queue_t)completionQueue
                               completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    void (^deliverCompletion)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
        if (!completion) return;
        if (completionQueue != nil) {
            dispatch_async(completionQueue, ^{
                completion(success, error);
            });
        } else {
            completion(success, error);
        }
    };

    if (sourceURL == nil || destinationURL == nil) {
        NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                           code:400
                                       userInfo:@{NSLocalizedDescriptionKey: @"Source or destination URL is nil."}];
        deliverCompletion(NO, err);
        return nil;
    }

    __block BOOL isCancelled = NO;
    void (^cancelBlock)(void) = ^{
        isCancelled = YES;
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (isCancelled) {
            deliverCompletion(NO, [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                      code:NSUserCancelledError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"GIF export was cancelled."}]);
            return;
        }
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
        NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (videoTracks.count == 0) {
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:422
                                           userInfo:@{NSLocalizedDescriptionKey: @"No video track found for GIF export."}];
            deliverCompletion(NO, err);
            return;
        }

        AVAssetTrack *videoTrack = videoTracks.firstObject;
        CGSize naturalSize = CGSizeApplyAffineTransform(videoTrack.naturalSize, videoTrack.preferredTransform);
        CGFloat origW = fabs(naturalSize.width);
        CGFloat origH = fabs(naturalSize.height);
        Float64 totalDuration = CMTimeGetSeconds(asset.duration);
        if (isnan(totalDuration) || totalDuration <= 0) totalDuration = 1.0;

        NSTimeInterval safeStart = MIN(MAX(startTime, 0.0), totalDuration);
        NSTimeInterval safeEnd = MAX(MIN(endTime, totalDuration), safeStart + 0.1);
        Float64 clipDuration = safeEnd - safeStart;

        CGFloat targetFps = (fps >= 5.0 && fps <= 30.0) ? fps : 15.0;
        CGFloat safeSpeed = (playbackSpeed >= 0.25 && playbackSpeed <= 4.0) ? playbackSpeed : 1.0;
        Float64 finalDuration = clipDuration / safeSpeed;
        NSInteger frameCount = (NSInteger)ceil(finalDuration * targetFps);
        if (frameCount < 2) frameCount = 2;
        if (frameCount > 600) frameCount = 600; // Cap to 600 frames to prevent huge memory usage

        // Build temporary composition to handle cropping/rotation/speed
        AVMutableComposition *composition = [AVMutableComposition composition];
        AVMutableCompositionTrack *compVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                              preferredTrackID:kCMPersistentTrackID_Invalid];

        CMTime startCM = CMTimeMakeWithSeconds(safeStart, 600);
        CMTime durationCM = CMTimeMakeWithSeconds(clipDuration, 600);
        CMTimeRange trimRange = CMTimeRangeMake(startCM, durationCM);
        [compVideoTrack insertTimeRange:trimRange ofTrack:videoTrack atTime:kCMTimeZero error:nil];

        CMTime scaledDurationCM = CMTimeMakeWithSeconds(finalDuration, 600);
        if (fabs(safeSpeed - 1.0) > 0.02) {
            [compVideoTrack scaleTimeRange:CMTimeRangeMake(kCMTimeZero, durationCM) toDuration:scaledDurationCM];
        }

        // Sanitize crop
        CGRect safeCrop = cropPixelRect;
        if (safeCrop.size.width <= 0 || safeCrop.size.height <= 0) {
            safeCrop = CGRectMake(0, 0, origW, origH);
        }
        safeCrop.origin.x = MIN(MAX(safeCrop.origin.x, 0.0), origW - 16.0);
        safeCrop.origin.y = MIN(MAX(safeCrop.origin.y, 0.0), origH - 16.0);
        safeCrop.size.width = MIN(safeCrop.size.width, origW - safeCrop.origin.x);
        safeCrop.size.height = MIN(safeCrop.size.height, origH - safeCrop.origin.y);

        NSInteger normRotation = ((rotationDegrees % 360) + 360) % 360;

        AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.frameDuration = CMTimeMake(1, (int32_t)llround(targetFps));

        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, scaledDurationCM);

        AVMutableVideoCompositionLayerInstruction *layerInst =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compVideoTrack];

        CGFloat cropW = safeCrop.size.width;
        CGFloat cropH = safeCrop.size.height;
        CGFloat cropOriginX = safeCrop.origin.x;
        CGFloat cropOriginY = origH - (safeCrop.origin.y + cropH);

        CGAffineTransform tCrop = CGAffineTransformConcat(videoTrack.preferredTransform,
                                                             CGAffineTransformMakeTranslation(-cropOriginX, -cropOriginY));
        CGAffineTransform finalTransform = tCrop;
        CGSize renderSize = CGSizeMake(cropW, cropH);

        if (normRotation == 90) {
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(-M_PI_2),
                                                            CGAffineTransformMakeTranslation(0, cropW));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropH, cropW);
        } else if (normRotation == 180) {
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(M_PI),
                                                            CGAffineTransformMakeTranslation(cropW, cropH));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropW, cropH);
        } else if (normRotation == 270) {
            CGAffineTransform tRot = CGAffineTransformConcat(CGAffineTransformMakeRotation(M_PI_2),
                                                            CGAffineTransformMakeTranslation(cropH, 0));
            finalTransform = CGAffineTransformConcat(tCrop, tRot);
            renderSize = CGSizeMake(cropH, cropW);
        }
        videoComposition.renderSize = renderSize;
        [layerInst setTransform:finalTransform atTime:kCMTimeZero];
        instruction.layerInstructions = @[layerInst];
        videoComposition.instructions = @[instruction];

        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:composition];
        generator.videoComposition = videoComposition;
        generator.appliesPreferredTrackTransform = YES;
        generator.requestedTimeToleranceBefore = CMTimeMake(1, 120);
        generator.requestedTimeToleranceAfter = CMTimeMake(1, 120);

        if (isCancelled) {
            deliverCompletion(NO, [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                      code:NSUserCancelledError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"GIF export was cancelled."}]);
            return;
        }

        // Delete destination if exists
        [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];

        CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)destinationURL,
                                                                     kUTTypeGIF,
                                                                     frameCount,
                                                                     NULL);
        if (dest == NULL) {
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:500
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to create GIF destination."}];
            deliverCompletion(NO, err);
            return;
        }

        NSDictionary *gifProperties = @{
            (id)kCGImagePropertyGIFDictionary: @{
                (id)kCGImagePropertyGIFLoopCount: @(0) // Infinite loop
            }
        };
        CGImageDestinationSetProperties(dest, (__bridge CFDictionaryRef)gifProperties);

        CGFloat frameDelay = 1.0 / targetFps;
        NSDictionary *frameProperties = @{
            (id)kCGImagePropertyGIFDictionary: @{
                (id)kCGImagePropertyGIFDelayTime: @(frameDelay),
                (id)kCGImagePropertyGIFUnclampedDelayTime: @(frameDelay)
            }
        };

        for (NSInteger i = 0; i < frameCount; i++) {
            if (isCancelled) {
                CFRelease(dest);
                [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
                deliverCompletion(NO, [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                          code:NSUserCancelledError
                                                      userInfo:@{NSLocalizedDescriptionKey: @"GIF export was cancelled."}]);
                return;
            }
            Float64 timeSec = (Float64)i * (finalDuration / (Float64)frameCount);
            CMTime frameTime = CMTimeMakeWithSeconds(timeSec, 600);
            NSError *frameErr = nil;
            CGImageRef img = [generator copyCGImageAtTime:frameTime actualTime:NULL error:&frameErr];
            if (img != NULL) {
                CGImageDestinationAddImage(dest, img, (__bridge CFDictionaryRef)frameProperties);
                CGImageRelease(img);
            }
            if (progressHandler) {
                float p = (float)(i + 1) / (float)frameCount;
                dispatch_async(dispatch_get_main_queue(), ^{
                    progressHandler(p);
                });
            }
        }

        if (isCancelled) {
            CFRelease(dest);
            [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
            deliverCompletion(NO, [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                                      code:NSUserCancelledError
                                                  userInfo:@{NSLocalizedDescriptionKey: @"GIF export was cancelled."}]);
            return;
        }

        BOOL finalized = CGImageDestinationFinalize(dest);
        CFRelease(dest);

        if (finalized) {
            deliverCompletion(YES, nil);
        } else {
            [[NSFileManager defaultManager] removeItemAtURL:destinationURL error:nil];
            NSError *err = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                               code:500
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to finalize animated GIF."}];
            deliverCompletion(NO, err);
        }
    });

    return cancelBlock;
}

+ (BOOL)exportGifSynchronousAtURL:(NSURL *)sourceURL
                    trimStartTime:(NSTimeInterval)startTime
                      trimEndTime:(NSTimeInterval)endTime
                         cropRect:(CGRect)cropPixelRect
                         rotation:(NSInteger)rotationDegrees
                    playbackSpeed:(CGFloat)playbackSpeed
                              fps:(CGFloat)fps
                   destinationURL:(NSURL *)destinationURL
                            error:(NSError * _Nullable * _Nullable)error {
    __block BOOL succeeded = NO;
    __block NSError *exportErr = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    void (^cancelBlock)(void) = [self exportGifAtURL:sourceURL
                                       trimStartTime:startTime
                                         trimEndTime:endTime
                                            cropRect:cropPixelRect
                                            rotation:rotationDegrees
                                       playbackSpeed:playbackSpeed
                                                 fps:fps
                                      destinationURL:destinationURL
                                     progressHandler:nil
                                     completionQueue:NULL
                                          completion:^(BOOL success, NSError * _Nullable err) {
        succeeded = success;
        exportErr = err;
        dispatch_semaphore_signal(sema);
    }];

    // 35.0-second safety timeout instead of DISPATCH_TIME_FOREVER to prevent UI freeze
    intptr_t waitResult = dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(35.0 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        if (cancelBlock) {
            cancelBlock();
        }
        succeeded = NO;
        exportErr = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                        code:ETIMEDOUT
                                    userInfo:@{NSLocalizedDescriptionKey: @"Synchronous GIF export timed out after 35 seconds."}];
    }
    if (!succeeded && error != NULL) {
        *error = exportErr;
    }
    return succeeded;
}

#pragma mark - Still Frame Extraction

+ (nullable NSImage *)captureFrameAtURL:(NSURL *)sourceURL
                                 atTime:(NSTimeInterval)time
                               cropRect:(CGRect)cropPixelRect
                               rotation:(NSInteger)rotationDegrees
                                  error:(NSError * _Nullable * _Nullable)error {
    if (sourceURL == nil || ![[NSFileManager defaultManager] fileExistsAtPath:sourceURL.path]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey: @"Video file not found."}];
        }
        return nil;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"com.choxieshoot.videoeditor"
                                         code:422
                                     userInfo:@{NSLocalizedDescriptionKey: @"No video track found."}];
        }
        return nil;
    }

    AVAssetTrack *track = videoTracks.firstObject;
    CGSize naturalSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    CGFloat origW = fabs(naturalSize.width);
    CGFloat origH = fabs(naturalSize.height);

    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = CMTimeMake(1, 60);
    generator.requestedTimeToleranceAfter = CMTimeMake(1, 60);

    CMTime targetCM = CMTimeMakeWithSeconds(time, 600);
    NSError *cgErr = nil;
    CGImageRef rawCG = [generator copyCGImageAtTime:targetCM actualTime:NULL error:&cgErr];
    if (rawCG == NULL) {
        if (error != NULL) *error = cgErr;
        return nil;
    }

    // Crop if needed
    CGImageRef processedCG = rawCG;
    CGRect safeCrop = cropPixelRect;
    if (safeCrop.size.width > 0 && safeCrop.size.height > 0 &&
        (safeCrop.origin.x > 2.0 || safeCrop.origin.y > 2.0 ||
         fabs(safeCrop.size.width - origW) > 4.0 || fabs(safeCrop.size.height - origH) > 4.0)) {
        safeCrop.origin.x = MIN(MAX(safeCrop.origin.x, 0.0), origW - 16.0);
        safeCrop.origin.y = MIN(MAX(safeCrop.origin.y, 0.0), origH - 16.0);
        safeCrop.size.width = MIN(safeCrop.size.width, origW - safeCrop.origin.x);
        safeCrop.size.height = MIN(safeCrop.size.height, origH - safeCrop.origin.y);

        CGImageRef cropped = CGImageCreateWithImageInRect(rawCG, safeCrop);
        if (cropped != NULL) {
            CGImageRelease(rawCG);
            processedCG = cropped;
        }
    }

    // Rotation if needed
    NSInteger normRot = ((rotationDegrees % 360) + 360) % 360;
    if (normRot != 0) {
        CGFloat curW = CGImageGetWidth(processedCG);
        CGFloat curH = CGImageGetHeight(processedCG);
        CGFloat newW = (normRot == 90 || normRot == 270) ? curH : curW;
        CGFloat newH = (normRot == 90 || normRot == 270) ? curW : curH;

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)newW, (size_t)newH, 8, 0, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);

        if (ctx != NULL) {
            if (normRot == 90) {
                CGContextTranslateCTM(ctx, newW, 0);
                CGContextRotateCTM(ctx, M_PI_2);
            } else if (normRot == 180) {
                CGContextTranslateCTM(ctx, newW, newH);
                CGContextRotateCTM(ctx, M_PI);
            } else if (normRot == 270) {
                CGContextTranslateCTM(ctx, 0, newH);
                CGContextRotateCTM(ctx, -M_PI_2);
            }
            CGContextDrawImage(ctx, CGRectMake(0, 0, curW, curH), processedCG);
            CGImageRef rotCG = CGBitmapContextCreateImage(ctx);
            CGContextRelease(ctx);
            if (rotCG != NULL) {
                CGImageRelease(processedCG);
                processedCG = rotCG;
            }
        }
    }

    NSImage *resultImage = [[NSImage alloc] initWithCGImage:processedCG
                                                       size:NSMakeSize(CGImageGetWidth(processedCG), CGImageGetHeight(processedCG))];
    CGImageRelease(processedCG);
    return resultImage;
}

@end
