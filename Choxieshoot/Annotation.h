#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ToolType) {
    ToolTypePencil = 0,
    ToolTypeLine,
    ToolTypeArrow,
    ToolTypeRectangle,
    ToolTypeEllipse,
    ToolTypeMarker,
    ToolTypeText,
    ToolTypePixelate,
    ToolTypeCallout,
    ToolTypeSpotlight,
    ToolTypeCrop,
    ToolTypeColorPicker,
    ToolTypeEraser,
    ToolTypeSelect,
    ToolTypeLoupe
};

typedef NS_ENUM(NSInteger, CSSpotlightShape) {
    CSSpotlightShapeRoundedRect = 0,
    CSSpotlightShapeEllipse,
    CSSpotlightShapePill
};

typedef NS_ENUM(NSInteger, CSRedactMode) {
    CSRedactModePixelate = 0,
    CSRedactModeBlur
};

/// One completed (or in-progress) annotation on the canvas.
@interface Annotation : NSObject <NSCopying>

@property (nonatomic) ToolType toolType;
@property (nonatomic, strong) NSBezierPath *path;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic) BOOL filled;
@property (nonatomic) BOOL dashed;
@property (nonatomic) BOOL hasShadow;
@property (nonatomic) CGFloat cornerRadius;
@property (nonatomic) BOOL curved;
@property (nonatomic) NSPoint controlPoint;
@property (nonatomic) BOOL hasCustomControlPoint;

/// Raw freehand sample points for smooth Bezier curve reconstruction
@property (nonatomic, strong) NSMutableArray<NSValue *> *points;

/// Text & speech-bubble properties
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic) NSPoint textPosition;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) BOOL bold;
@property (nonatomic) BOOL textBackground;
@property (nonatomic) BOOL speechBubble;

/// Step callout properties
@property (nonatomic) NSInteger calloutNumber;
@property (nonatomic) NSPoint startPoint;
@property (nonatomic) NSPoint endPoint;

/// Spotlight properties
@property (nonatomic) CSSpotlightShape spotlightShape;
@property (nonatomic) CGFloat spotlightDimOpacity;
@property (nonatomic) BOOL spotlightFeather;

/// Redaction & Loupe properties
@property (nonatomic) CSRedactMode redactMode;
@property (nonatomic) CGFloat loupeMagnification;

/// Rebuilds `path` as a smooth quadratic Bezier curve from `points`.
- (void)rebuildSmoothPathFromPoints;

/// Returns the logical bounding rect of the annotation for selection and manipulation.
- (NSRect)selectionBounds;

/// Translates the annotation by (dx, dy).
- (void)translateByX:(CGFloat)dx y:(CGFloat)dy;

@end

NSString *ToolTypeName(ToolType type);
NSString *ToolTypeSymbolName(ToolType type);

NS_ASSUME_NONNULL_END
