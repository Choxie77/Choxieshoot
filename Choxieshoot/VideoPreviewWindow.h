#import <Cocoa/Cocoa.h>
#import "VideoCropOverlayView.h"
#import "VideoTimelineTrimmerView.h"

NS_ASSUME_NONNULL_BEGIN

@class VideoPreviewWindow;

typedef void (^VideoPreviewCloseBlock)(VideoPreviewWindow *window);

/// Post-recording video preview & editor window with timeline cutting, spatial cropping, Save as MP4/MOV, Copy to clipboard, and Reveal in Finder.
@interface VideoPreviewWindow : NSPanel

@property (nonatomic, readonly) NSURL *videoURL;
@property (nonatomic, copy, nullable) VideoPreviewCloseBlock onClose;
@property (nonatomic, copy, nullable) void (^onNewRecording)(void);

/// Video editing state
@property (nonatomic, readonly) NSSize videoNaturalSize;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval trimStartTime;
@property (nonatomic, readonly) NSTimeInterval trimEndTime;
@property (nonatomic, readonly) CGRect cropPixelRect;
@property (nonatomic, readonly) BOOL cropModeActive;

- (instancetype)initWithScreenRect:(NSRect)screenRect videoURL:(NSURL *)videoURL;

/// Load/switch to a new video file in this editor window.
- (BOOL)loadVideoURL:(NSURL *)newURL;

/// Saves the recorded / edited video file to the destination URL (used by the Save panel and tests).
- (BOOL)saveVideoToURL:(NSURL *)destinationURL error:(NSError * _Nullable * _Nullable)error;

/// Presents the NSSavePanel sheet to save the video with edits applied.
- (void)saveClicked:(nullable id)sender;

/// Copies the video file (with edits applied) to the clipboard.
- (void)copyClicked:(nullable id)sender;

/// Reveals the saved or recorded video in Finder.
- (void)revealInFinderClicked:(nullable id)sender;

/// Triggers a new recording.
- (void)newRecordingClicked:(nullable id)sender;

/// Opens an existing video from disk.
- (void)openVideoClicked:(nullable id)sender;

/// Toggle spatial crop mode.
- (void)toggleCropMode:(nullable id)sender;

/// Reset all cuts and crops.
- (void)resetEdits:(nullable id)sender;

/// Programmatically configure trim points (for testing and automation).
- (void)setTrimStart:(NSTimeInterval)start end:(NSTimeInterval)end;

/// Programmatically configure crop rectangle (in source video pixels).
- (void)setCropPixelRect:(CGRect)pixelRect;

/// Exports edited video asynchronously.
- (void)exportEditedVideoToURL:(NSURL *)destinationURL
               progressHandler:(nullable void (^)(float progress))progressHandler
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Copies the recorded video file to the general pasteboard (test helper).
- (void)copyVideoForTesting;

@end

NS_ASSUME_NONNULL_END
