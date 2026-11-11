#import "CSTheme.h"

CGFloat const CSSpace4 = 4.0;
CGFloat const CSSpace8 = 8.0;
CGFloat const CSSpace12 = 12.0;
CGFloat const CSSpace16 = 16.0;
CGFloat const CSSpace24 = 24.0;

CGFloat const CSRadiusSmall = 6.0;
CGFloat const CSRadiusMedium = 10.0;
CGFloat const CSRadiusLarge = 14.0;
CGFloat const CSRadiusXL = 18.0;

@implementation CSTheme

+ (NSColor *)dynamicColorWithName:(NSString *)name dark:(NSColor *)dark light:(NSColor *)light {
    return [NSColor colorWithName:name dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName best = [appearance bestMatchFromAppearancesWithNames:@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua
        ]];
        return [best isEqualToString:NSAppearanceNameDarkAqua] ? dark : light;
    }];
}

+ (NSColor *)accent {
    return [self dynamicColorWithName:@"CSAccent"
                                 dark:[NSColor colorWithSRGBRed:0.180 green:0.812 blue:0.730 alpha:1.0]
                                light:[NSColor colorWithSRGBRed:0.043 green:0.533 blue:0.478 alpha:1.0]];
}

+ (NSColor *)accentGlow {
    return [[self accent] colorWithAlphaComponent:0.42];
}

+ (NSColor *)onAccent {
    return [self dynamicColorWithName:@"CSOnAccent"
                                 dark:[NSColor colorWithSRGBRed:0.02 green:0.15 blue:0.13 alpha:1.0]
                                light:[NSColor whiteColor]];
}

+ (NSColor *)danger {
    return [NSColor systemRedColor];
}

+ (NSColor *)surface {
    return [self dynamicColorWithName:@"CSSurface"
                                 dark:[NSColor colorWithSRGBRed:0.11 green:0.12 blue:0.14 alpha:0.96]
                                light:[NSColor colorWithSRGBRed:0.96 green:0.97 blue:0.98 alpha:0.96]];
}

+ (NSColor *)elevatedSurface {
    return [self dynamicColorWithName:@"CSElevatedSurface"
                                 dark:[NSColor colorWithSRGBRed:0.14 green:0.15 blue:0.18 alpha:0.92]
                                light:[NSColor colorWithSRGBRed:0.99 green:0.99 blue:1.00 alpha:0.92]];
}

+ (NSColor *)controlSurface {
    return [self dynamicColorWithName:@"CSControlSurface"
                                 dark:[NSColor colorWithSRGBRed:0.13 green:0.14 blue:0.17 alpha:0.95]
                                light:[NSColor colorWithSRGBRed:0.95 green:0.96 blue:0.97 alpha:0.95]];
}

+ (NSColor *)pillSurface {
    return [self dynamicColorWithName:@"CSPillSurface"
                                 dark:[NSColor colorWithWhite:1.0 alpha:0.055]
                                light:[NSColor colorWithWhite:0.0 alpha:0.045]];
}

+ (NSColor *)border {
    return [self dynamicColorWithName:@"CSBorder"
                                 dark:[NSColor colorWithWhite:1.0 alpha:0.14]
                                light:[NSColor colorWithWhite:0.0 alpha:0.12]];
}

+ (NSColor *)subtleBorder {
    return [self dynamicColorWithName:@"CSSubtleBorder"
                                 dark:[NSColor colorWithWhite:1.0 alpha:0.08]
                                light:[NSColor colorWithWhite:0.0 alpha:0.06]];
}

+ (NSColor *)text {
    return [NSColor labelColor];
}

+ (NSColor *)mutedText {
    return [self dynamicColorWithName:@"CSMutedText"
                                 dark:[NSColor colorWithSRGBRed:0.70 green:0.72 blue:0.76 alpha:1.0]
                                light:[NSColor colorWithSRGBRed:0.35 green:0.37 blue:0.41 alpha:1.0]];
}

+ (NSColor *)selectedToolBackground {
    return [[self accent] colorWithAlphaComponent:0.24];
}

+ (NSColor *)selectedToolBorder {
    return [[self accent] colorWithAlphaComponent:0.65];
}

+ (NSColor *)hoverBackground {
    return [[self accent] colorWithAlphaComponent:0.12];
}

+ (NSColor *)toastBackground {
    return [[NSColor colorWithSRGBRed:0.08 green:0.09 blue:0.11 alpha:1.0] colorWithAlphaComponent:0.88];
}

+ (NSColor *)toastText {
    return [NSColor whiteColor];
}

+ (NSColor *)badgeBackground {
    return [self accent];
}

+ (NSColor *)badgeText {
    return [self onAccent];
}

+ (CGFloat)selectionDimAlpha {
    return 0.46;
}

+ (NSVisualEffectView *)glassViewWithFrame:(NSRect)frame
                                  material:(NSVisualEffectMaterial)material
                              cornerRadius:(CGFloat)cornerRadius {
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:frame];
    effectView.material = material;
    effectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.wantsLayer = YES;
    if (cornerRadius > 0) {
        effectView.layer.cornerRadius = cornerRadius;
        effectView.layer.masksToBounds = YES;
    }
    effectView.layer.borderWidth = 1.0;
    effectView.layer.borderColor = [self border].CGColor;
    return effectView;
}

@end
