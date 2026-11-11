#import "Annotation.h"

@implementation Annotation

- (instancetype)init {
    if ((self = [super init])) {
        _path = [NSBezierPath bezierPath];
        _points = [NSMutableArray array];
        _color = [NSColor systemRedColor];
        _lineWidth = 3.0;
        _fontSize = 18.0;
        _bold = YES;
        _textBackground = NO;
        _speechBubble = NO;
        _calloutNumber = 1;
        _hasShadow = NO;
        _dashed = NO;
        _cornerRadius = 0.0;
        _curved = NO;
        _hasCustomControlPoint = NO;
        _spotlightShape = CSSpotlightShapeRoundedRect;
        _spotlightDimOpacity = 0.58;
        _spotlightFeather = YES;
        _redactMode = CSRedactModePixelate;
        _loupeMagnification = 2.2;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    Annotation *copy = [[Annotation allocWithZone:zone] init];
    copy.toolType = self.toolType;
    copy.path = [self.path copy];
    copy.points = [[NSMutableArray alloc] initWithArray:self.points copyItems:YES];
    copy.color = self.color;
    copy.lineWidth = self.lineWidth;
    copy.filled = self.filled;
    copy.dashed = self.dashed;
    copy.hasShadow = self.hasShadow;
    copy.cornerRadius = self.cornerRadius;
    copy.curved = self.curved;
    copy.controlPoint = self.controlPoint;
    copy.hasCustomControlPoint = self.hasCustomControlPoint;
    copy.text = self.text;
    copy.textPosition = self.textPosition;
    copy.fontSize = self.fontSize;
    copy.bold = self.bold;
    copy.textBackground = self.textBackground;
    copy.speechBubble = self.speechBubble;
    copy.calloutNumber = self.calloutNumber;
    copy.startPoint = self.startPoint;
    copy.endPoint = self.endPoint;
    copy.spotlightShape = self.spotlightShape;
    copy.spotlightDimOpacity = self.spotlightDimOpacity;
    copy.spotlightFeather = self.spotlightFeather;
    copy.redactMode = self.redactMode;
    copy.loupeMagnification = self.loupeMagnification;
    return copy;
}

- (void)rebuildSmoothPathFromPoints {
    NSBezierPath *smooth = [NSBezierPath bezierPath];
    NSUInteger count = self.points.count;
    if (count == 0) {
        self.path = smooth;
        return;
    }
    NSPoint p0 = [self.points[0] pointValue];
    [smooth moveToPoint:p0];
    if (count == 1) {
        [smooth lineToPoint:p0];
        self.path = smooth;
        return;
    }
    if (count == 2) {
        NSPoint p1 = [self.points[1] pointValue];
        [smooth lineToPoint:p1];
        self.path = smooth;
        return;
    }

    // Smooth quadratic-to-cubic spline through consecutive midpoints
    for (NSUInteger i = 1; i < count - 1; i++) {
        NSPoint curr = [self.points[i] pointValue];
        NSPoint next = [self.points[i + 1] pointValue];
        NSPoint mid = NSMakePoint((curr.x + next.x) * 0.5, (curr.y + next.y) * 0.5);
        NSPoint prev = (i == 1) ? p0 : NSMakePoint(([self.points[i - 1] pointValue].x + curr.x) * 0.5,
                                                   ([self.points[i - 1] pointValue].y + curr.y) * 0.5);
        // Convert quadratic Bezier (prev -> curr -> mid) to cubic control points
        NSPoint cp1 = NSMakePoint(prev.x + (2.0 / 3.0) * (curr.x - prev.x),
                                  prev.y + (2.0 / 3.0) * (curr.y - prev.y));
        NSPoint cp2 = NSMakePoint(mid.x + (2.0 / 3.0) * (curr.x - mid.x),
                                  mid.y + (2.0 / 3.0) * (curr.y - mid.y));
        [smooth curveToPoint:mid controlPoint1:cp1 controlPoint2:cp2];
    }
    NSPoint last = [self.points.lastObject pointValue];
    [smooth lineToPoint:last];
    self.path = smooth;
}

- (NSRect)selectionBounds {
    if (self.toolType == ToolTypeCallout && !self.speechBubble) {
        CGFloat radius = MAX(13.0, 10.0 + self.lineWidth * 0.85);
        NSRect badgeRect = NSMakeRect(self.startPoint.x - radius, self.startPoint.y - radius, radius * 2.0, radius * 2.0);
        if (hypot(self.endPoint.x - self.startPoint.x, self.endPoint.y - self.startPoint.y) > radius + 4.0) {
            return NSUnionRect(badgeRect, NSMakeRect(self.endPoint.x - 4.0, self.endPoint.y - 4.0, 8.0, 8.0));
        }
        return badgeRect;
    }
    if (self.path != nil && !self.path.isEmpty) {
        return self.path.bounds;
    }
    return NSMakeRect(MIN(self.startPoint.x, self.endPoint.x),
                      MIN(self.startPoint.y, self.endPoint.y),
                      MAX(fabs(self.endPoint.x - self.startPoint.x), 1.0),
                      MAX(fabs(self.endPoint.y - self.startPoint.y), 1.0));
}

- (void)translateByX:(CGFloat)dx y:(CGFloat)dy {
    NSAffineTransform *shift = [NSAffineTransform transform];
    [shift translateXBy:dx yBy:dy];
    [self.path transformUsingAffineTransform:shift];
    self.textPosition = NSMakePoint(self.textPosition.x + dx, self.textPosition.y + dy);
    self.startPoint = NSMakePoint(self.startPoint.x + dx, self.startPoint.y + dy);
    self.endPoint = NSMakePoint(self.endPoint.x + dx, self.endPoint.y + dy);
    self.controlPoint = NSMakePoint(self.controlPoint.x + dx, self.controlPoint.y + dy);
    if (self.points.count > 0) {
        NSMutableArray<NSValue *> *moved = [NSMutableArray arrayWithCapacity:self.points.count];
        for (NSValue *val in self.points) {
            NSPoint p = [val pointValue];
            [moved addObject:[NSValue valueWithPoint:NSMakePoint(p.x + dx, p.y + dy)]];
        }
        self.points = moved;
    }
}

@end

NSString *ToolTypeName(ToolType type) {
    switch (type) {
        case ToolTypeSelect:     return @"Select & Move";
        case ToolTypePencil:     return @"Pencil";
        case ToolTypeLine:       return @"Line";
        case ToolTypeArrow:      return @"Arrow";
        case ToolTypeRectangle:  return @"Rectangle";
        case ToolTypeEllipse:    return @"Ellipse";
        case ToolTypeMarker:     return @"Highlighter";
        case ToolTypeText:       return @"Text";
        case ToolTypePixelate:   return @"Pixelate / Blur";
        case ToolTypeCallout:    return @"Step Callout";
        case ToolTypeSpotlight:  return @"Spotlight";
        case ToolTypeLoupe:      return @"Magnifier Loupe";
        case ToolTypeCrop:       return @"Crop";
        case ToolTypeColorPicker:return @"Colour Picker";
        case ToolTypeEraser:     return @"Eraser";
    }
    return @"Tool";
}

NSString *ToolTypeSymbolName(ToolType type) {
    switch (type) {
        case ToolTypeSelect:     return @"cursorarrow";
        case ToolTypePencil:     return @"pencil.tip";
        case ToolTypeLine:       return @"line.diagonal";
        case ToolTypeArrow:      return @"arrow.up.right";
        case ToolTypeRectangle:  return @"rectangle";
        case ToolTypeEllipse:    return @"circle";
        case ToolTypeMarker:     return @"highlighter";
        case ToolTypeText:       return @"textformat";
        case ToolTypePixelate:   return @"checkerboard.rectangle";
        case ToolTypeCallout:    return @"1.circle.fill";
        case ToolTypeSpotlight:  return @"rays";
        case ToolTypeLoupe:      return @"plus.magnifyingglass";
        case ToolTypeCrop:       return @"crop";
        case ToolTypeColorPicker:return @"eyedropper.halffull";
        case ToolTypeEraser:     return @"eraser.line.dashed";
    }
    return @"questionmark";
}
