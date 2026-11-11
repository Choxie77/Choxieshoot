#import "CSColorFormatter.h"

@implementation CSColorFormatter

+ (NSColor *)srgbColor:(NSColor *)color {
    NSColor *converted = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return converted ?: color;
}

+ (NSString *)hexStringFromColor:(NSColor *)color {
    NSColor *c = [self srgbColor:color];
    NSInteger r = lround(c.redComponent * 255.0);
    NSInteger g = lround(c.greenComponent * 255.0);
    NSInteger b = lround(c.blueComponent * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)r, (long)g, (long)b];
}

+ (NSString *)rgbStringFromColor:(NSColor *)color {
    NSColor *c = [self srgbColor:color];
    NSInteger r = lround(c.redComponent * 255.0);
    NSInteger g = lround(c.greenComponent * 255.0);
    NSInteger b = lround(c.blueComponent * 255.0);
    return [NSString stringWithFormat:@"RGB  %ld  %ld  %ld", (long)r, (long)g, (long)b];
}

+ (NSString *)hsbStringFromColor:(NSColor *)color {
    NSColor *c = [self srgbColor:color];
    CGFloat h = 0, s = 0, b = 0, a = 0;
    [c getHue:&h saturation:&s brightness:&b alpha:&a];
    return [NSString stringWithFormat:@"HSB  %ld°  %ld%%  %ld%%",
            (long)lround(h * 360.0), (long)lround(s * 100.0), (long)lround(b * 100.0)];
}

+ (NSString *)hslStringFromColor:(NSColor *)color {
    NSColor *c = [self srgbColor:color];
    CGFloat r = c.redComponent, g = c.greenComponent, b = c.blueComponent;
    CGFloat max = MAX(r, MAX(g, b));
    CGFloat min = MIN(r, MIN(g, b));
    CGFloat delta = max - min;
    CGFloat lightness = (max + min) / 2.0;
    CGFloat saturation = 0.0;
    if (delta > 0.0001) {
        saturation = delta / (1.0 - fabs(2.0 * lightness - 1.0));
    }
    CGFloat hue = 0.0;
    if (delta > 0.0001) {
        if (max == r) {
            hue = fmodf((g - b) / delta, 6.0f);
        } else if (max == g) {
            hue = ((b - r) / delta) + 2.0f;
        } else {
            hue = ((r - g) / delta) + 4.0f;
        }
        hue *= 60.0f;
        if (hue < 0) {
            hue += 360.0f;
        }
    }
    return [NSString stringWithFormat:@"HSL  %ld°  %ld%%  %ld%%",
            (long)lround(hue), (long)lround(saturation * 100.0), (long)lround(lightness * 100.0)];
}

@end
