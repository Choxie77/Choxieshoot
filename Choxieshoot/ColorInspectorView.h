#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A small Photoshop-style colour inspector shown while the eyedropper is
/// active: swatch, HEX, RGB, HSB and HSL with copy buttons and colour locking.
@interface ColorInspectorView : NSView

@property (nonatomic, readonly) BOOL isLocked;
@property (nonatomic, strong, readonly, nullable) NSColor *currentColor;
@property (nonatomic, copy, nullable) void (^onToggleLock)(void);

- (void)updateWithColor:(nullable NSColor *)color;
- (void)setLocked:(BOOL)locked animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
