#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// High-performance export engine for trimming, cropping, rotating, re-timing, audio muting, and animated GIF creation.
@interface VideoEditorEngine : NSObject

/// Exports a video with full editing options: time trimming, spatial cropping, rotation, playback speed, and audio muting.
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
                                         completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Synchronous export helper with full editing options.
+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                           rotation:(NSInteger)rotationDegrees
                      playbackSpeed:(CGFloat)playbackSpeed
                          muteAudio:(BOOL)muteAudio
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error;

/// Exports a trimmed & cropped clip to an animated GIF.
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
                               completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Synchronous GIF export helper.
+ (BOOL)exportGifSynchronousAtURL:(NSURL *)sourceURL
                    trimStartTime:(NSTimeInterval)startTime
                      trimEndTime:(NSTimeInterval)endTime
                         cropRect:(CGRect)cropPixelRect
                         rotation:(NSInteger)rotationDegrees
                    playbackSpeed:(CGFloat)playbackSpeed
                              fps:(CGFloat)fps
                   destinationURL:(NSURL *)destinationURL
                            error:(NSError * _Nullable * _Nullable)error;

/// Captures a single still frame at a specific timestamp, with crop and rotation applied.
+ (nullable NSImage *)captureFrameAtURL:(NSURL *)sourceURL
                                 atTime:(NSTimeInterval)time
                               cropRect:(CGRect)cropPixelRect
                               rotation:(NSInteger)rotationDegrees
                                  error:(NSError * _Nullable * _Nullable)error;

#pragma mark - Backward-Compatible Convenience APIs

+ (nullable AVAssetExportSession *)exportVideoAtURL:(NSURL *)sourceURL
                                      trimStartTime:(NSTimeInterval)startTime
                                        trimEndTime:(NSTimeInterval)endTime
                                           cropRect:(CGRect)cropPixelRect
                                     destinationURL:(NSURL *)destinationURL
                                    progressHandler:(nullable void (^)(float progress))progressHandler
                                         completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
