#import <Cocoa/Cocoa.h>
#import "CSShortcut.h"

NS_ASSUME_NONNULL_BEGIN

/// Click, then press a key combination. Esc cancels.
@interface ShortcutRecorderView : NSView

@property (nonatomic, strong) CSShortcut *shortcut;
@property (nonatomic, copy, nullable) void (^onShortcutChange)(CSShortcut *shortcut);

@end

NS_ASSUME_NONNULL_END
