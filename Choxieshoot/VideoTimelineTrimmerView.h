#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Interactive timeline scrubber and trim range selector for cutting videos.
@interface VideoTimelineTrimmerView : NSView

@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSTimeInterval currentTime;
@property (nonatomic) NSTimeInterval trimStartTime;
@property (nonatomic) NSTimeInterval trimEndTime;
@property (nonatomic) BOOL isPlaying;

/// Callbacks
@property (nonatomic, copy, nullable) void (^onSeek)(NSTimeInterval time);
@property (nonatomic, copy, nullable) void (^onTrimChanged)(NSTimeInterval startTime, NSTimeInterval endTime);
@property (nonatomic, copy, nullable) void (^onScrubbingStateChanged)(BOOL isScrubbing);
@property (nonatomic, copy, nullable) void (^onPlayPauseToggle)(void);

- (instancetype)initWithFrame:(NSRect)frame duration:(NSTimeInterval)duration;

/// Set the in-point (trim start) to current playhead time.
- (void)setInPointToCurrentTime;

/// Set the out-point (trim end) to current playhead time.
- (void)setOutPointToCurrentTime;

/// Reset trim to full duration (0 to duration).
- (void)resetTrim;

/// Steps playhead by frame interval (e.g. 1.0 / 30.0).
- (void)stepFrames:(NSInteger)frameCount fps:(double)fps;

/// Returns YES if video has been trimmed from full duration.
- (BOOL)isTrimmed;

/// Selected trimmed duration.
- (NSTimeInterval)trimmedDuration;

@end

NS_ASSUME_NONNULL_END
