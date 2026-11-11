#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// 8pt spacing scale
FOUNDATION_EXPORT CGFloat const CSSpace4;
FOUNDATION_EXPORT CGFloat const CSSpace8;
FOUNDATION_EXPORT CGFloat const CSSpace12;
FOUNDATION_EXPORT CGFloat const CSSpace16;
FOUNDATION_EXPORT CGFloat const CSSpace24;

// Radius scale
FOUNDATION_EXPORT CGFloat const CSRadiusSmall;
FOUNDATION_EXPORT CGFloat const CSRadiusMedium;
FOUNDATION_EXPORT CGFloat const CSRadiusLarge;
FOUNDATION_EXPORT CGFloat const CSRadiusXL;

/// Semantic colour roles and glassmorphic styling helpers for Choxieshoot.
@interface CSTheme : NSObject

+ (NSColor *)accent;          // Choxieshoot vibrant teal/cyan
+ (NSColor *)accentGlow;      // Soft outer glow for active states & spotlights
+ (NSColor *)onAccent;        // High-contrast text/icon on accent
+ (NSColor *)danger;          // Destructive / close
+ (NSColor *)surface;         // Window body surface
+ (NSColor *)elevatedSurface; // Floating card / HUD surface
+ (NSColor *)controlSurface;  // Toolbar surface
+ (NSColor *)pillSurface;     // Grouped pill capsule background inside toolbar/HUD
+ (NSColor *)border;          // Hairline border
+ (NSColor *)subtleBorder;    // Soft inner rim highlight
+ (NSColor *)text;            // Primary text
+ (NSColor *)mutedText;       // Secondary text
+ (NSColor *)selectedToolBackground;
+ (NSColor *)selectedToolBorder;
+ (NSColor *)hoverBackground;
+ (NSColor *)toastBackground;
+ (NSColor *)toastText;
+ (NSColor *)badgeBackground;
+ (NSColor *)badgeText;

+ (CGFloat)selectionDimAlpha;

/// Creates a configured glassmorphic NSVisualEffectView with rounded corners and hairline border.
+ (NSVisualEffectView *)glassViewWithFrame:(NSRect)frame
                                  material:(NSVisualEffectMaterial)material
                              cornerRadius:(CGFloat)cornerRadius;

@end

NS_ASSUME_NONNULL_END
