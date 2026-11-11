#import "VideoCropOverlayView.h"
#import "CSTheme.h"

typedef NS_ENUM(NSInteger, CSCropDragHandle) {
    CSCropDragHandleNone = 0,
    CSCropDragHandleMove,
    CSCropDragHandleTopLeft,
    CSCropDragHandleTop,
    CSCropDragHandleTopRight,
    CSCropDragHandleRight,
    CSCropDragHandleBottomRight,
    CSCropDragHandleBottom,
    CSCropDragHandleBottomLeft,
    CSCropDragHandleLeft,
    CSCropDragHandleNewBox
};

@interface VideoCropOverlayView ()

@property (nonatomic) CSCropDragHandle activeHandle;
@property (nonatomic) NSPoint dragStartPoint;
@property (nonatomic) CGRect dragInitialCropRect;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

@end

@implementation VideoCropOverlayView

- (instancetype)initWithFrame:(NSRect)frame videoNaturalSize:(NSSize)videoNaturalSize {
    self = [super initWithFrame:frame];
    if (self) {
        _videoNaturalSize = videoNaturalSize.width > 0 && videoNaturalSize.height > 0
            ? videoNaturalSize
            : NSMakeSize(1920, 1080);
        _cropActive = NO;
        _aspectPreset = CSVideoCropAspectFreeform;
        _normalizedCropRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
        _activeHandle = CSCropDragHandleNone;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea != nil) {
        [self removeTrackingArea:self.trackingArea];
    }
    NSTrackingAreaOptions options = NSTrackingActiveInKeyWindow |
                                    NSTrackingMouseMoved |
                                    NSTrackingCursorUpdate |
                                    NSTrackingInVisibleRect;
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:options
                                                       owner:self
                                                    userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (void)setCropActive:(BOOL)cropActive {
    if (_cropActive != cropActive) {
        _cropActive = cropActive;
        self.needsDisplay = YES;
        if (!_cropActive) {
            [[NSCursor arrowCursor] set];
        }
    }
}

- (void)setAspectPreset:(CSVideoCropAspect)aspectPreset {
    _aspectPreset = aspectPreset;
    if (aspectPreset != CSVideoCropAspectFreeform) {
        [self applyCurrentAspectConstraint];
    }
    self.needsDisplay = YES;
    if (self.onCropChanged) {
        self.onCropChanged([self pixelCropRect]);
    }
}

- (CGFloat)targetAspectRatio {
    switch (self.aspectPreset) {
        case CSVideoCropAspect16_9:
            return 16.0 / 9.0;
        case CSVideoCropAspect4_3:
            return 4.0 / 3.0;
        case CSVideoCropAspect1_1:
            return 1.0;
        case CSVideoCropAspect9_16:
            return 9.0 / 16.0;
        case CSVideoCropAspectOriginal:
            return self.videoNaturalSize.width / MAX(1.0, self.videoNaturalSize.height);
        case CSVideoCropAspectFreeform:
        default:
            return 0.0;
    }
}

- (void)applyCurrentAspectConstraint {
    CGFloat targetAspect = [self targetAspectRatio];
    if (targetAspect <= 0.0) {
        return;
    }
    CGFloat natW = MAX(1.0, self.videoNaturalSize.width);
    CGFloat natH = MAX(1.0, self.videoNaturalSize.height);

    // Current pixel size
    CGFloat currentPixelW = _normalizedCropRect.size.width * natW;
    CGFloat currentPixelH = _normalizedCropRect.size.height * natH;
    CGFloat currentAspect = currentPixelW / MAX(1.0, currentPixelH);

    CGFloat newW = currentPixelW;
    CGFloat newH = currentPixelH;

    if (currentAspect > targetAspect) {
        // Too wide, reduce width
        newW = newH * targetAspect;
    } else {
        // Too tall, reduce height
        newH = newW / targetAspect;
    }

    if (newW > natW) {
        newW = natW;
        newH = newW / targetAspect;
    }
    if (newH > natH) {
        newH = natH;
        newW = newH * targetAspect;
    }

    CGFloat normW = newW / natW;
    CGFloat normH = newH / natH;
    CGFloat normX = _normalizedCropRect.origin.x + (_normalizedCropRect.size.width - normW) / 2.0;
    CGFloat normY = _normalizedCropRect.origin.y + (_normalizedCropRect.size.height - normH) / 2.0;

    normX = MIN(MAX(normX, 0.0), 1.0 - normW);
    normY = MIN(MAX(normY, 0.0), 1.0 - normH);

    _normalizedCropRect = CGRectMake(normX, normY, normW, normH);
}

- (NSRect)videoDisplayRect {
    NSRect bounds = self.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) {
        return NSZeroRect;
    }
    CGFloat natW = MAX(1.0, self.videoNaturalSize.width);
    CGFloat natH = MAX(1.0, self.videoNaturalSize.height);
    CGFloat videoAspect = natW / natH;
    CGFloat viewAspect = bounds.size.width / bounds.size.height;

    CGFloat w, h;
    if (viewAspect > videoAspect) {
        // Pillarboxed (bars on left/right)
        h = bounds.size.height;
        w = floor(h * videoAspect);
    } else {
        // Letterboxed (bars on top/bottom)
        w = bounds.size.width;
        h = floor(w / videoAspect);
    }
    CGFloat x = floor((bounds.size.width - w) / 2.0);
    CGFloat y = floor((bounds.size.height - h) / 2.0);
    return NSMakeRect(x, y, w, h);
}

- (NSRect)displayCropRect {
    NSRect vRect = [self videoDisplayRect];
    if (vRect.size.width <= 0 || vRect.size.height <= 0) {
        return NSZeroRect;
    }
    CGFloat x = vRect.origin.x + _normalizedCropRect.origin.x * vRect.size.width;
    CGFloat w = _normalizedCropRect.size.width * vRect.size.width;
    CGFloat h = _normalizedCropRect.size.height * vRect.size.height;
    // Cocoa coordinates: Y=0 is at bottom
    CGFloat y = vRect.origin.y + (1.0 - _normalizedCropRect.origin.y - _normalizedCropRect.size.height) * vRect.size.height;
    return NSMakeRect(floor(x), floor(y), MAX(16.0, floor(w)), MAX(16.0, floor(h)));
}

- (CGRect)pixelCropRect {
    CGFloat natW = MAX(1.0, self.videoNaturalSize.width);
    CGFloat natH = MAX(1.0, self.videoNaturalSize.height);

    CGFloat px = _normalizedCropRect.origin.x * natW;
    CGFloat py = _normalizedCropRect.origin.y * natH;
    CGFloat pw = _normalizedCropRect.size.width * natW;
    CGFloat ph = _normalizedCropRect.size.height * natH;

    // Snap to even dimensions for video codecs (H.264)
    NSInteger evenW = MAX(32, (NSInteger)llround(pw / 2.0) * 2);
    NSInteger evenH = MAX(32, (NSInteger)llround(ph / 2.0) * 2);
    NSInteger evenX = (NSInteger)llround(px / 2.0) * 2;
    NSInteger evenY = (NSInteger)llround(py / 2.0) * 2;

    if (evenX + evenW > (NSInteger)natW) {
        evenX = MAX(0, (NSInteger)natW - evenW);
    }
    if (evenY + evenH > (NSInteger)natH) {
        evenY = MAX(0, (NSInteger)natH - evenH);
    }
    return CGRectMake(evenX, evenY, evenW, evenH);
}

- (void)setPixelCropRect:(CGRect)pixelRect {
    CGFloat natW = MAX(1.0, self.videoNaturalSize.width);
    CGFloat natH = MAX(1.0, self.videoNaturalSize.height);

    CGFloat nx = MIN(MAX(pixelRect.origin.x / natW, 0.0), 1.0);
    CGFloat ny = MIN(MAX(pixelRect.origin.y / natH, 0.0), 1.0);
    CGFloat nw = MIN(MAX(pixelRect.size.width / natW, 0.02), 1.0 - nx);
    CGFloat nh = MIN(MAX(pixelRect.size.height / natH, 0.02), 1.0 - ny);

    CGRect newRect = CGRectMake(nx, ny, nw, nh);
    if (CGRectEqualToRect(_normalizedCropRect, newRect)) {
        return;
    }
    _normalizedCropRect = newRect;
    self.needsDisplay = YES;
}

- (void)resetToFullVideo {
    _aspectPreset = CSVideoCropAspectFreeform;
    _normalizedCropRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
    self.needsDisplay = YES;
    if (self.onCropChanged) {
        self.onCropChanged([self pixelCropRect]);
    }
}

- (BOOL)isCropped {
    if (_normalizedCropRect.origin.x > 0.005 ||
        _normalizedCropRect.origin.y > 0.005 ||
        _normalizedCropRect.size.width < 0.995 ||
        _normalizedCropRect.size.height < 0.995) {
        return YES;
    }
    return NO;
}

#pragma mark - Hit Testing & Handles

- (NSView *)hitTest:(NSPoint)point {
    if (!self.cropActive || self.hidden) {
        return nil;
    }
    return [super hitTest:point];
}

- (CSCropDragHandle)handleAtPoint:(NSPoint)point {
    if (!self.cropActive) {
        return CSCropDragHandleNone;
    }
    NSRect cropRect = [self displayCropRect];
    CGFloat handleHitRadius = 10.0;

    NSPoint corners[4] = {
        NSMakePoint(NSMinX(cropRect), NSMaxY(cropRect)), // Top-Left
        NSMakePoint(NSMaxX(cropRect), NSMaxY(cropRect)), // Top-Right
        NSMakePoint(NSMaxX(cropRect), NSMinY(cropRect)), // Bottom-Right
        NSMakePoint(NSMinX(cropRect), NSMinY(cropRect))  // Bottom-Left
    };

    if (hypot(point.x - corners[0].x, point.y - corners[0].y) <= handleHitRadius) {
        return CSCropDragHandleTopLeft;
    }
    if (hypot(point.x - corners[1].x, point.y - corners[1].y) <= handleHitRadius) {
        return CSCropDragHandleTopRight;
    }
    if (hypot(point.x - corners[2].x, point.y - corners[2].y) <= handleHitRadius) {
        return CSCropDragHandleBottomRight;
    }
    if (hypot(point.x - corners[3].x, point.y - corners[3].y) <= handleHitRadius) {
        return CSCropDragHandleBottomLeft;
    }

    // Edge midpoints
    if (fabs(point.y - NSMaxY(cropRect)) <= 7.0 && point.x >= NSMinX(cropRect) && point.x <= NSMaxX(cropRect)) {
        return CSCropDragHandleTop;
    }
    if (fabs(point.y - NSMinY(cropRect)) <= 7.0 && point.x >= NSMinX(cropRect) && point.x <= NSMaxX(cropRect)) {
        return CSCropDragHandleBottom;
    }
    if (fabs(point.x - NSMinX(cropRect)) <= 7.0 && point.y >= NSMinY(cropRect) && point.y <= NSMaxY(cropRect)) {
        return CSCropDragHandleLeft;
    }
    if (fabs(point.x - NSMaxX(cropRect)) <= 7.0 && point.y >= NSMinY(cropRect) && point.y <= NSMaxY(cropRect)) {
        return CSCropDragHandleRight;
    }

    // Inside box -> move
    if (NSPointInRect(point, cropRect)) {
        return CSCropDragHandleMove;
    }

    NSRect vRect = [self videoDisplayRect];
    if (NSPointInRect(point, vRect)) {
        return CSCropDragHandleNewBox;
    }

    return CSCropDragHandleNone;
}

- (void)cursorUpdate:(NSEvent *)event {
    if (!self.cropActive) {
        [super cursorUpdate:event];
        return;
    }
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CSCropDragHandle handle = [self handleAtPoint:loc];
    switch (handle) {
        case CSCropDragHandleTopLeft:
        case CSCropDragHandleBottomRight:
            [[NSCursor crosshairCursor] set];
            break;
        case CSCropDragHandleTopRight:
        case CSCropDragHandleBottomLeft:
            [[NSCursor crosshairCursor] set];
            break;
        case CSCropDragHandleTop:
        case CSCropDragHandleBottom:
            [[NSCursor resizeUpDownCursor] set];
            break;
        case CSCropDragHandleLeft:
        case CSCropDragHandleRight:
            [[NSCursor resizeLeftRightCursor] set];
            break;
        case CSCropDragHandleMove:
            [[NSCursor openHandCursor] set];
            break;
        case CSCropDragHandleNewBox:
            [[NSCursor crosshairCursor] set];
            break;
        case CSCropDragHandleNone:
        default:
            [[NSCursor arrowCursor] set];
            break;
    }
}

- (void)mouseMoved:(NSEvent *)event {
    [self cursorUpdate:event];
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    if (!self.cropActive) {
        [super mouseDown:event];
        return;
    }
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragStartPoint = loc;
    self.dragInitialCropRect = _normalizedCropRect;
    self.activeHandle = [self handleAtPoint:loc];

    if (self.activeHandle == CSCropDragHandleNewBox) {
        NSRect vRect = [self videoDisplayRect];
        CGFloat normX = MIN(MAX((loc.x - vRect.origin.x) / vRect.size.width, 0.0), 1.0);
        CGFloat normY = MIN(MAX(1.0 - (loc.y - vRect.origin.y) / vRect.size.height, 0.0), 1.0);
        _normalizedCropRect = CGRectMake(normX, normY, 0.01, 0.01);
        self.dragInitialCropRect = _normalizedCropRect;
        self.activeHandle = CSCropDragHandleBottomRight;
        self.needsDisplay = YES;
    } else if (self.activeHandle == CSCropDragHandleMove) {
        [[NSCursor closedHandCursor] set];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.cropActive || self.activeHandle == CSCropDragHandleNone) {
        [super mouseDragged:event];
        return;
    }
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect vRect = [self videoDisplayRect];
    if (vRect.size.width <= 0 || vRect.size.height <= 0) {
        return;
    }

    CGFloat deltaX = (loc.x - self.dragStartPoint.x) / vRect.size.width;
    // Y in normalized coords: downward delta = -deltaY in Cocoa
    CGFloat deltaY = -(loc.y - self.dragStartPoint.y) / vRect.size.height;

    CGRect initRect = self.dragInitialCropRect;
    CGFloat x = initRect.origin.x;
    CGFloat y = initRect.origin.y;
    CGFloat w = initRect.size.width;
    CGFloat h = initRect.size.height;

    CGFloat minSize = 0.05;

    switch (self.activeHandle) {
        case CSCropDragHandleMove: {
            x += deltaX;
            y += deltaY;
            x = MIN(MAX(x, 0.0), 1.0 - w);
            y = MIN(MAX(y, 0.0), 1.0 - h);
            break;
        }
        case CSCropDragHandleTopLeft: {
            x += deltaX;
            y += deltaY;
            w -= deltaX;
            h -= deltaY;
            break;
        }
        case CSCropDragHandleTop: {
            y += deltaY;
            h -= deltaY;
            break;
        }
        case CSCropDragHandleTopRight: {
            y += deltaY;
            w += deltaX;
            h -= deltaY;
            break;
        }
        case CSCropDragHandleRight: {
            w += deltaX;
            break;
        }
        case CSCropDragHandleBottomRight: {
            w += deltaX;
            h += deltaY;
            break;
        }
        case CSCropDragHandleBottom: {
            h += deltaY;
            break;
        }
        case CSCropDragHandleBottomLeft: {
            x += deltaX;
            w -= deltaX;
            h += deltaY;
            break;
        }
        case CSCropDragHandleLeft: {
            x += deltaX;
            w -= deltaX;
            break;
        }
        default:
            break;
    }

    // Minimum size enforcement
    if (w < minSize) {
        if (self.activeHandle == CSCropDragHandleLeft ||
            self.activeHandle == CSCropDragHandleTopLeft ||
            self.activeHandle == CSCropDragHandleBottomLeft) {
            x = initRect.origin.x + initRect.size.width - minSize;
        }
        w = minSize;
    }
    if (h < minSize) {
        if (self.activeHandle == CSCropDragHandleTop ||
            self.activeHandle == CSCropDragHandleTopLeft ||
            self.activeHandle == CSCropDragHandleTopRight) {
            y = initRect.origin.y + initRect.size.height - minSize;
        }
        h = minSize;
    }

    // Boundary constraints
    x = MIN(MAX(x, 0.0), 1.0 - minSize);
    y = MIN(MAX(y, 0.0), 1.0 - minSize);
    w = MIN(w, 1.0 - x);
    h = MIN(h, 1.0 - y);

    _normalizedCropRect = CGRectMake(x, y, w, h);

    if (self.aspectPreset != CSVideoCropAspectFreeform) {
        [self applyCurrentAspectConstraint];
    }

    self.needsDisplay = YES;
    if (self.onCropChanged) {
        self.onCropChanged([self pixelCropRect]);
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (!self.cropActive) {
        [super mouseUp:event];
        return;
    }
    self.activeHandle = CSCropDragHandleNone;
    [self cursorUpdate:event];
    if (self.onCropChanged) {
        self.onCropChanged([self pixelCropRect]);
    }
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    if (!self.cropActive) {
        return;
    }

    NSRect vRect = [self videoDisplayRect];
    if (vRect.size.width <= 0 || vRect.size.height <= 0) {
        return;
    }
    NSRect crop = [self displayCropRect];

    // 1. Dim mask outside crop area
    NSBezierPath *outerPath = [NSBezierPath bezierPathWithRect:vRect];
    NSBezierPath *innerPath = [NSBezierPath bezierPathWithRect:crop];
    [outerPath appendBezierPath:[innerPath bezierPathByReversingPath]];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.62] setFill];
    [outerPath fill];

    // 2. Rule of thirds grid lines inside crop box
    NSBezierPath *grid = [NSBezierPath bezierPath];
    grid.lineWidth = 1.0;
    CGFloat colW = crop.size.width / 3.0;
    CGFloat rowH = crop.size.height / 3.0;
    [grid moveToPoint:NSMakePoint(crop.origin.x + colW, crop.origin.y)];
    [grid lineToPoint:NSMakePoint(crop.origin.x + colW, crop.origin.y + crop.size.height)];
    [grid moveToPoint:NSMakePoint(crop.origin.x + colW * 2.0, crop.origin.y)];
    [grid lineToPoint:NSMakePoint(crop.origin.x + colW * 2.0, crop.origin.y + crop.size.height)];
    [grid moveToPoint:NSMakePoint(crop.origin.x, crop.origin.y + rowH)];
    [grid lineToPoint:NSMakePoint(crop.origin.x + crop.size.width, crop.origin.y + rowH)];
    [grid moveToPoint:NSMakePoint(crop.origin.x, crop.origin.y + rowH * 2.0)];
    [grid lineToPoint:NSMakePoint(crop.origin.x + crop.size.width, crop.origin.y + rowH * 2.0)];
    [[NSColor colorWithWhite:1.0 alpha:0.25] setStroke];
    [grid stroke];

    // 3. Crisp border
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:crop];
    border.lineWidth = 2.0;
    [[CSTheme accent] setStroke];
    [border stroke];

    // 4. Handles: 4 corners + 4 edge midpoints
    CGFloat handleR = 5.0;
    NSColor *handleFill = [CSTheme accent];
    NSColor *handleStroke = [NSColor whiteColor];

    NSPoint points[8] = {
        NSMakePoint(NSMinX(crop), NSMaxY(crop)), // TL
        NSMakePoint(NSMidX(crop), NSMaxY(crop)), // Top
        NSMakePoint(NSMaxX(crop), NSMaxY(crop)), // TR
        NSMakePoint(NSMaxX(crop), NSMidY(crop)), // Right
        NSMakePoint(NSMaxX(crop), NSMinY(crop)), // BR
        NSMakePoint(NSMidX(crop), NSMinY(crop)), // Bottom
        NSMakePoint(NSMinX(crop), NSMinY(crop)), // BL
        NSMakePoint(NSMinX(crop), NSMidY(crop))  // Left
    };

    for (int i = 0; i < 8; i++) {
        NSRect hr = NSMakeRect(points[i].x - handleR, points[i].y - handleR, handleR * 2.0, handleR * 2.0);
        NSBezierPath *hp = [NSBezierPath bezierPathWithOvalInRect:hr];
        [handleFill setFill];
        [hp fill];
        [handleStroke setStroke];
        hp.lineWidth = 1.6;
        [hp stroke];
    }

    // 5. Dimension badge
    CGRect pxRect = [self pixelCropRect];
    NSString *badgeText = [NSString stringWithFormat:@"%ld × %ld px", (long)pxRect.size.width, (long)pxRect.size.height];
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [badgeText sizeWithAttributes:attr];
    CGFloat badgeW = textSize.width + 16.0;
    CGFloat badgeH = textSize.height + 8.0;

    CGFloat badgeX = floor(NSMidX(crop) - badgeW / 2.0);
    badgeX = MIN(MAX(badgeX, NSMinX(vRect) + 4.0), NSMaxX(vRect) - badgeW - 4.0);

    CGFloat badgeY = NSMaxY(crop) + 8.0;
    if (badgeY + badgeH > NSMaxY(vRect)) {
        badgeY = NSMinY(crop) - badgeH - 8.0;
    }
    if (badgeY < NSMinY(vRect)) {
        badgeY = NSMinY(crop) + 8.0;
    }

    NSRect badgeRect = NSMakeRect(badgeX, badgeY, badgeW, badgeH);
    NSBezierPath *badgeBg = [NSBezierPath bezierPathWithRoundedRect:badgeRect xRadius:6.0 yRadius:6.0];
    [[[NSColor blackColor] colorWithAlphaComponent:0.80] setFill];
    [badgeBg fill];
    [[[CSTheme accent] colorWithAlphaComponent:0.80] setStroke];
    badgeBg.lineWidth = 1.0;
    [badgeBg stroke];

    [badgeText drawAtPoint:NSMakePoint(badgeX + 8.0, badgeY + 4.0) withAttributes:attr];
}

@end
