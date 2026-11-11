#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// High-performance export engine for cutting (trimming) and spatial cropping of recorded screen videos.
@interface VideoEditorEngine : NSObject

/// Exports a video with optional time trimming and spatial cropping.
+ (void)exportVideoAtURL:(NSURL *)sourceURL
           trimStartTime:(NSTimeInterval)startTime
             trimEndTime:(NSTimeInterval)endTime
                cropRect:(CGRect)cropPixelRect
          destinationURL:(NSURL *)destinationURL
         progressHandler:(nullable void (^)(float progress))progressHandler
              completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Synchronous export helper (useful for automated testing).
+ (BOOL)exportVideoSynchronousAtURL:(NSURL *)sourceURL
                      trimStartTime:(NSTimeInterval)startTime
                        trimEndTime:(NSTimeInterval)endTime
                           cropRect:(CGRect)cropPixelRect
                     destinationURL:(NSURL *)destinationURL
                              error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
