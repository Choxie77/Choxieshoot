#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CSCaptureMode) {
    CSCaptureModeScreenshot = 0,
    CSCaptureModeVideo = 1
};

typedef void (^SelectionCompletionBlock)(NSRect screenRect);
typedef void (^SelectionModeCompletionBlock)(NSRect screenRect, CSCaptureMode mode, BOOL recordMicrophone);
typedef void (^SelectionCancelBlock)(void);

/// Full-screen dimmed overlay: drag a rectangle (or click Full Screen) and toggle Screenshot vs. Video mode.
@interface SelectionWindow : NSPanel

@property (nonatomic) CSCaptureMode captureMode;
@property (nonatomic) BOOL recordMicrophone;
@property (nonatomic) BOOL motionBlurEnabled;

- (instancetype)initWithCompletion:(SelectionCompletionBlock)completion
                            cancel:(SelectionCancelBlock)cancel;

- (instancetype)initWithInitialMode:(CSCaptureMode)initialMode
                   recordMicrophone:(BOOL)recordMicrophone
                     modeCompletion:(SelectionModeCompletionBlock)modeCompletion
                             cancel:(SelectionCancelBlock)cancel;

@end

NS_ASSUME_NONNULL_END
