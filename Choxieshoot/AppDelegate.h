#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (void)handleHotkey;
- (void)startAreaSelectionForTesting;
- (void)startVideoSelectionForTesting;
- (void)showPreferencesForTesting;
- (void)captureTestRect:(NSRect)rect;
- (void)openVideoToEdit:(nullable id)sender;
- (void)openVideoPreviewWithURL:(NSURL *)videoURL screenRect:(NSRect)screenRect;

@end

NS_ASSUME_NONNULL_END
