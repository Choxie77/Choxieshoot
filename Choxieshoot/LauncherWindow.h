#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^LauncherActionBlock)(void);

/// The Dock app's home window: start a capture, see Screen Recording status
/// and fix it without hunting through menus.
@interface LauncherWindow : NSPanel

@property (nonatomic, copy, nullable) LauncherActionBlock recordVideoBlock;
@property (nonatomic, copy, nullable) LauncherActionBlock openVideoBlock;
@property (nonatomic, copy, nullable) LauncherActionBlock onClose;

- (instancetype)initWithNewCapture:(LauncherActionBlock)newCapture
                    delayedCapture:(LauncherActionBlock)delayed
                        fullScreen:(LauncherActionBlock)fullScreen
                   grantPermission:(LauncherActionBlock)grant
                   checkPermission:(LauncherActionBlock)check
                      restartBlock:(LauncherActionBlock)restart
                        resetBlock:(LauncherActionBlock)reset;

- (void)updateScreenRecordingGranted:(BOOL)granted;
- (void)setDelaySeconds:(NSInteger)seconds;
- (void)focusPermissions;

@end

NS_ASSUME_NONNULL_END
