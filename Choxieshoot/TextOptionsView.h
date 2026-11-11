#import <Cocoa/Cocoa.h>
#import "Annotation.h"

NS_ASSUME_NONNULL_BEGIN

/// Floating glassmorphic HUD card for Text settings, Spotlight controls, and contextual tool options.
@interface TextOptionsView : NSView

@property (nonatomic, copy, nullable) void (^onChange)(CGFloat fontSize, BOOL bold, BOOL background);
@property (nonatomic, copy, nullable) void (^onSpotlightChange)(CSSpotlightShape shape, CGFloat dimOpacity, BOOL feather);
@property (nonatomic, copy, nullable) void (^onRedactChange)(CSRedactMode mode);
@property (nonatomic, copy, nullable) void (^onArrowChange)(BOOL curved);
@property (nonatomic, copy, nullable) void (^onRectChange)(BOOL rounded);
@property (nonatomic, copy, nullable) void (^onCalloutChange)(BOOL speechBubble);
@property (nonatomic, copy, nullable) void (^onLoupeChange)(CGFloat magnification);

- (void)setFontSize:(CGFloat)fontSize bold:(BOOL)bold background:(BOOL)background;
- (void)configureForSpotlightShape:(CSSpotlightShape)shape dimOpacity:(CGFloat)dimOpacity feather:(BOOL)feather;
- (void)configureForRedactMode:(CSRedactMode)mode;
- (void)configureForArrowCurved:(BOOL)curved;
- (void)configureForRectangleRounded:(BOOL)rounded;
- (void)configureForCalloutSpeechBubble:(BOOL)speechBubble;
- (void)configureForLoupeMagnification:(CGFloat)magnification;

@end

NS_ASSUME_NONNULL_END
