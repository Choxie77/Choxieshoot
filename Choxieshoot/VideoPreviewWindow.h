#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "VideoCropOverlayView.h"
#import "VideoTimelineTrimmerView.h"

NS_ASSUME_NONNULL_BEGIN

@class VideoPreviewWindow;
@class AVAssetExportSession;

typedef void (^VideoPreviewCloseBlock)(VideoPreviewWindow *window);

/// Advanced post-recording video preview & editor window with timeline trimming,
/// spatial cropping, rotation, playback speed control, audio muting, still frame extraction,
/// and MP4 / GIF export.
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
@property (nonatomic, readonly) BOOL cropPreviewActive;
@property (nonatomic, readonly) NSInteger rotationDegrees;
@property (nonatomic, readonly) CGFloat playbackSpeed;
@property (nonatomic, readonly) BOOL audioMuted;
@property (nonatomic, readonly) BOOL isExporting;
@property (nonatomic, strong, readonly, nullable) NSView *exportHUDView;

- (instancetype)initWithScreenRect:(NSRect)screenRect videoURL:(NSURL *)videoURL;

/// Load/switch to a new video file in this editor window.
- (BOOL)loadVideoURL:(NSURL *)newURL;

/// Saves the recorded / edited video file to the destination URL (used by the Save panel and tests).
- (BOOL)saveVideoToURL:(NSURL *)destinationURL error:(NSError * _Nullable * _Nullable)error;

/// Saves the edited clip as an animated GIF.
- (BOOL)saveGifToURL:(NSURL *)destinationURL error:(NSError * _Nullable * _Nullable)error;

/// Presents the NSSavePanel sheet to save the video with edits applied.
- (void)saveClicked:(nullable id)sender;

/// Presents the NSSavePanel sheet to export an animated GIF.
- (void)exportGifClicked:(nullable id)sender;

/// Copies the video file (with edits applied) to the clipboard.
- (void)copyClicked:(nullable id)sender;

/// Captures the current paused/scrubbed frame as a high-res image to clipboard & file.
- (void)captureFrameClicked:(nullable id)sender;

/// Returns the current still frame image with crop & rotation applied.
- (nullable NSImage *)currentFrameImage;

/// Reveals the saved or recorded video in Finder.
- (void)revealInFinderClicked:(nullable id)sender;

/// Triggers a new recording.
- (void)newRecordingClicked:(nullable id)sender;

/// Opens an existing video from disk.
- (void)openVideoClicked:(nullable id)sender;

/// Toggle spatial crop mode.
- (void)toggleCropMode:(nullable id)sender;

/// Toggle real-time preview of the cropped frame.
- (void)toggleCropPreview:(nullable id)sender;

/// Centers the current crop box within the source video.
- (void)centerCropClicked:(nullable id)sender;

/// Swaps aspect orientation (e.g. 16:9 Landscape <-> 9:16 Portrait).
- (void)swapOrientationClicked:(nullable id)sender;

/// Rotates video 90 degrees clockwise.
- (void)rotateClicked:(nullable id)sender;

/// Toggles audio mute for playback and export.
- (void)toggleMuteClicked:(nullable id)sender;

/// Cycles playback speed (0.5x, 0.75x, 1x, 1.25x, 1.5x, 2x).
- (void)cycleSpeedClicked:(nullable id)sender;

/// Reset all cuts, crops, rotations, speed, and audio muting.
- (void)resetEdits:(nullable id)sender;

/// Programmatically configure trim points (for testing and automation).
- (void)setTrimStart:(NSTimeInterval)start end:(NSTimeInterval)end;

/// Programmatically configure crop rectangle (in source video pixels).
- (void)setCropPixelRect:(CGRect)pixelRect;

/// Programmatically configure rotation (0, 90, 180, 270).
- (void)setRotationDegrees:(NSInteger)degrees;

/// Programmatically configure playback speed (0.5, 0.75, 1.0, 1.25, 1.5, 2.0).
- (void)setPlaybackSpeed:(CGFloat)speed;

/// Programmatically configure audio mute.
- (void)setAudioMuted:(BOOL)muted;

/// Exports edited video asynchronously.
- (nullable AVAssetExportSession *)exportEditedVideoToURL:(NSURL *)destinationURL
                                          progressHandler:(nullable void (^)(float progress))progressHandler
                                               completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// Shows or hides the in-flight export HUD.
- (void)showExportHUDWithTitle:(NSString *)title;

/// Cancels any active in-flight export session (MP4 or GIF).
- (void)cancelActiveExport;

/// Shows the export progress HUD overlay (test & internal helper).
- (void)showExportHUDWithTitle:(NSString *)title;

/// Hides the export progress HUD overlay.
- (void)hideExportHUD;

/// Copies the recorded video file to the general pasteboard (test helper).
- (void)copyVideoForTesting;

@end

NS_ASSUME_NONNULL_END
