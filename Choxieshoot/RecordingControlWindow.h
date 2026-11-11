#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Floating HUD control bar + click-through region frame shown during active video recording.
@interface RecordingControlWindow : NSPanel

@property (nonatomic, copy, nullable) void (^onPauseResume)(void);
@property (nonatomic, copy, nullable) void (^onStop)(void);
@property (nonatomic, copy, nullable) void (^onCancel)(void);

/// Window number of the lowest recording overlay window so screen capture can exclude both overlay and HUD.
@property (nonatomic, readonly) CGWindowID lowestOverlayWindowID;

- (instancetype)initWithRecordedScreenRect:(NSRect)screenRect
                          recordMicrophone:(BOOL)recordMicrophone;

- (void)updateElapsedSeconds:(NSTimeInterval)elapsed;
- (void)setPaused:(BOOL)paused;
- (void)dismissAllOverlays;

@end

NS_ASSUME_NONNULL_END
