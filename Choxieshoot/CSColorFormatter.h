#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Formats a sampled colour for the eyedropper/inspector.
@interface CSColorFormatter : NSObject

+ (NSString *)hexStringFromColor:(NSColor *)color;
+ (NSString *)rgbStringFromColor:(NSColor *)color;
+ (NSString *)hsbStringFromColor:(NSColor *)color;
+ (NSString *)hslStringFromColor:(NSColor *)color;

@end

NS_ASSUME_NONNULL_END
