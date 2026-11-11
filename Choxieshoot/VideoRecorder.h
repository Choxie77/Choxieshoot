#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CSVideoMotionBlurMode) {
    CSVideoMotionBlurModeOff = 0,
    CSVideoMotionBlurModeSubtle = 1,    /// ~180° shutter (~32% blend on motion)
    CSVideoMotionBlurModeCinematic = 2, /// ~270° shutter (~45% blend on motion)
    CSVideoMotionBlurModeHeavy = 3      /// ~360° shutter (~58% blend on motion)
};

typedef void (^VideoRecorderCompletionBlock)(NSURL * _Nullable outputURL, NSError * _Nullable error);

/// Records a screen region (and optional microphone audio) into a smooth H.264 .mp4 file with motion blur.
@interface VideoRecorder : NSObject

@property (nonatomic, readonly) NSRect screenRect;
@property (nonatomic, readonly) BOOL recordMicrophone;
@property (nonatomic, readonly) BOOL isRecording;
@property (nonatomic, readonly) BOOL isPaused;
@property (nonatomic, readonly) NSTimeInterval elapsedSeconds;
@property (nonatomic, readonly, nullable) NSURL *outputURL;

@property (nonatomic, readonly) NSInteger fps;
@property (nonatomic, readonly) CSVideoMotionBlurMode motionBlurMode;
@property (nonatomic, readonly) BOOL recordCursor;
@property (nonatomic, readonly) BOOL cursorMotionBlur;

/// Window ID to exclude from capture (captures strictly below this window when non-zero).
@property (nonatomic) CGWindowID excludeAboveWindowID;

/// Called on the main queue whenever elapsed time ticks (~4x per second).
@property (nonatomic, copy, nullable) void (^onDurationUpdate)(NSTimeInterval elapsed);

/// Initializes with defaults loaded from NSUserDefaults (60 FPS, subtle motion blur, cursor enabled).
- (instancetype)initWithScreenRect:(NSRect)screenRect
                  recordMicrophone:(BOOL)recordMicrophone
              excludeAboveWindowID:(CGWindowID)excludeAboveWindowID;

/// Initializes with explicit video options.
- (instancetype)initWithScreenRect:(NSRect)screenRect
                  recordMicrophone:(BOOL)recordMicrophone
              excludeAboveWindowID:(CGWindowID)excludeAboveWindowID
                               fps:(NSInteger)fps
                    motionBlurMode:(CSVideoMotionBlurMode)motionBlurMode
                      recordCursor:(BOOL)recordCursor
                  cursorMotionBlur:(BOOL)cursorMotionBlur;

/// Request microphone permission if needed, then invoke completion on the main queue.
+ (void)requestMicrophoneAccessIfNeeded:(void (^)(BOOL granted))completion;

/// Starts recording to a temporary .mp4 file. Returns NO if writer setup fails.
- (BOOL)startRecordingWithError:(NSError * _Nullable * _Nullable)error;

- (void)pauseRecording;
- (void)resumeRecording;

/// Stops recording asynchronously and finalizes the .mp4 file on disk.
- (void)stopRecordingWithCompletion:(VideoRecorderCompletionBlock)completion;

/// Cancels recording and deletes the temporary file.
- (void)cancelRecording;

@end

NS_ASSUME_NONNULL_END
