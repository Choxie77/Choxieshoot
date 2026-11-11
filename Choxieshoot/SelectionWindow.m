#import "SelectionWindow.h"
#import "CSTheme.h"
#import <malloc/malloc.h>

#pragma mark - SelectionView

@interface SelectionView : NSView

@property (nonatomic) CSCaptureMode captureMode;
@property (nonatomic) BOOL recordMicrophone;
@property (nonatomic) BOOL motionBlurEnabled;
@property (nonatomic, copy, nullable) SelectionCompletionBlock completion;
@property (nonatomic, copy, nullable) SelectionModeCompletionBlock modeCompletion;
@property (nonatomic, copy, nullable) SelectionCancelBlock cancelHandler;

- (void)triggerFullScreenOnActiveScreen;

@end

@implementation SelectionView {
    NSPoint _startPoint;
    NSRect _selectionRect;
    NSPoint _mousePoint;
    BOOL _hasMousePoint;
    BOOL _mouseDown;
    BOOL _mouseDownInControlBar;
    NSTrackingArea *_trackingArea;

    NSRect _controlBarRect;
    NSRect _screenshotPillRect;
    NSRect _videoPillRect;
    NSRect _micPillRect;
    NSRect _motionBlurPillRect;
    NSRect _fullScreenPillRect;
    NSRect _cancelPillRect;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                 options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                          NSTrackingActiveAlways | NSTrackingInVisibleRect |
                                                          NSTrackingCursorUpdate)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor crosshairCursor]];
}

- (void)cursorUpdate:(NSEvent *)event {
    [[NSCursor crosshairCursor] set];
}

- (NSRect)activeScreenFrameInView {
    NSRect targetScreenFrame = self.bounds;
    NSPoint mouseScreen = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(mouseScreen, screen.frame)) {
            if (self.window != nil) {
                NSRect inWin = [self.window convertRectFromScreen:screen.frame];
                targetScreenFrame = [self convertRect:inWin fromView:nil];
            }
            break;
        }
    }
    return targetScreenFrame;
}

- (void)updateControlBarLayout {
    NSRect screenFrame = [self activeScreenFrameInView];
    BOOL isVideo = (self.captureMode == CSCaptureModeVideo);
    CGFloat barWidth = isVideo ? 618.0 : 516.0;
    CGFloat barHeight = 42.0;
    CGFloat barX = floor(NSMidX(screenFrame) - barWidth / 2.0);
    CGFloat barY = NSMaxY(screenFrame) - barHeight - 44.0;
    _controlBarRect = NSMakeRect(barX, barY, barWidth, barHeight);

    CGFloat pad = 5.0;
    CGFloat pillH = barHeight - pad * 2.0;
    CGFloat x = barX + pad;
    _screenshotPillRect = NSMakeRect(x, barY + pad, 108.0, pillH);
    x += 108.0 + 4.0;
    _videoPillRect = NSMakeRect(x, barY + pad, 96.0, pillH);
    x += 96.0 + 8.0;
    _micPillRect = NSMakeRect(x, barY + pad, 96.0, pillH);
    x += 96.0 + 6.0;
    if (isVideo) {
        _motionBlurPillRect = NSMakeRect(x, barY + pad, 96.0, pillH);
        x += 96.0 + 6.0;
    } else {
        _motionBlurPillRect = NSZeroRect;
    }
    _fullScreenPillRect = NSMakeRect(x, barY + pad, 98.0, pillH);
    x += 98.0 + 6.0;
    _cancelPillRect = NSMakeRect(x, barY + pad, 82.0, pillH);
}

- (void)finishWithScreenRect:(NSRect)screenRect {
    SelectionModeCompletionBlock modeBlock = self.modeCompletion;
    SelectionCompletionBlock compBlock = self.completion;
    CSCaptureMode mode = self.captureMode;
    BOOL mic = self.recordMicrophone;
    self.modeCompletion = nil;
    self.completion = nil;
    self.cancelHandler = nil;
    [self.window orderOut:nil];
    [self.window close];
    if (modeBlock != nil) {
        modeBlock(screenRect, mode, mic);
    } else if (compBlock != nil) {
        compBlock(screenRect);
    }
}

- (void)triggerFullScreenOnActiveScreen {
    NSScreen *target = [NSScreen mainScreen] ?: [NSScreen screens].firstObject;
    NSPoint mouseScreen = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(mouseScreen, screen.frame)) {
            target = screen;
            break;
        }
    }
    if (target != nil) {
        [self finishWithScreenRect:target.frame];
    }
}

#pragma mark - Mouse

- (void)mouseDown:(NSEvent *)event {
    [self updateControlBarLayout];
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, _controlBarRect)) {
        _mouseDownInControlBar = YES;
        _mouseDown = NO;
        if (NSPointInRect(point, _screenshotPillRect)) {
            self.captureMode = CSCaptureModeScreenshot;
            if ([self.window isKindOfClass:[SelectionWindow class]]) {
                ((SelectionWindow *)self.window).captureMode = CSCaptureModeScreenshot;
            }
            [self setNeedsDisplay:YES];
        } else if (NSPointInRect(point, _videoPillRect)) {
            self.captureMode = CSCaptureModeVideo;
            if ([self.window isKindOfClass:[SelectionWindow class]]) {
                ((SelectionWindow *)self.window).captureMode = CSCaptureModeVideo;
            }
            [self setNeedsDisplay:YES];
        } else if (NSPointInRect(point, _micPillRect)) {
            self.recordMicrophone = !self.recordMicrophone;
            self.captureMode = CSCaptureModeVideo;
            if ([self.window isKindOfClass:[SelectionWindow class]]) {
                ((SelectionWindow *)self.window).recordMicrophone = self.recordMicrophone;
                ((SelectionWindow *)self.window).captureMode = CSCaptureModeVideo;
            }
            [self setNeedsDisplay:YES];
        } else if (self.captureMode == CSCaptureModeVideo && NSPointInRect(point, _motionBlurPillRect)) {
            self.motionBlurEnabled = !self.motionBlurEnabled;
            [[NSUserDefaults standardUserDefaults] setInteger:(self.motionBlurEnabled ? 1 : 0) forKey:@"CSVideoMotionBlur"];
            if ([self.window isKindOfClass:[SelectionWindow class]]) {
                ((SelectionWindow *)self.window).motionBlurEnabled = self.motionBlurEnabled;
            }
            [self setNeedsDisplay:YES];
        } else if (NSPointInRect(point, _fullScreenPillRect)) {
            [self triggerFullScreenOnActiveScreen];
        } else if (NSPointInRect(point, _cancelPillRect)) {
            if (self.cancelHandler != nil) {
                self.cancelHandler();
            }
            [self.window orderOut:nil];
            [self.window close];
        }
        return;
    }

    _mouseDownInControlBar = NO;
    _startPoint = point;
    _selectionRect = NSMakeRect(_startPoint.x, _startPoint.y, 0, 0);
    _mouseDown = YES;
    [self setNeedsDisplay:YES];
}

- (void)rightMouseDown:(NSEvent *)event {
    if (self.cancelHandler != nil) {
        self.cancelHandler();
    }
    [self.window orderOut:nil];
    [self.window close];
}

- (void)mouseDragged:(NSEvent *)event {
    if (_mouseDownInControlBar) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _selectionRect = NSMakeRect(MIN(_startPoint.x, point.x),
                                MIN(_startPoint.y, point.y),
                                fabs(point.x - _startPoint.x),
                                fabs(point.y - _startPoint.y));
    _mousePoint = point;
    _hasMousePoint = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    if (_mouseDownInControlBar) {
        _mouseDownInControlBar = NO;
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect rect = NSMakeRect(MIN(_startPoint.x, point.x),
                             MIN(_startPoint.y, point.y),
                             fabs(point.x - _startPoint.x),
                             fabs(point.y - _startPoint.y));
    _mouseDown = NO;

    if (rect.size.width >= 8.0 && rect.size.height >= 8.0) {
        NSRect windowRect = [self convertRect:rect toView:nil];
        NSRect screenRect = [self.window convertRectToScreen:windowRect];
        [self finishWithScreenRect:screenRect];
    } else {
        if (self.cancelHandler != nil) {
            self.cancelHandler();
        }
        [self.window orderOut:nil];
        [self.window close];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    _mousePoint = [self convertPoint:event.locationInWindow fromView:nil];
    _hasMousePoint = YES;
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (NSColor *)activeModeAccentColor {
    return (self.captureMode == CSCaptureModeVideo) ? [CSTheme danger] : [CSTheme accent];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [self updateControlBarLayout];

    BOOL hasSelection = _selectionRect.size.width > 0.5 && _selectionRect.size.height > 0.5;
    NSColor *dimColor = [[NSColor blackColor] colorWithAlphaComponent:[CSTheme selectionDimAlpha]];
    NSColor *modeAccent = [self activeModeAccentColor];

    if (!hasSelection) {
        [dimColor setFill];
        NSRectFill(self.bounds);
    } else {
        CGFloat width = NSWidth(self.bounds);
        CGFloat height = NSHeight(self.bounds);
        CGFloat minX = NSMinX(_selectionRect);
        CGFloat maxX = NSMaxX(_selectionRect);
        CGFloat minY = NSMinY(_selectionRect);
        CGFloat maxY = NSMaxY(_selectionRect);

        [dimColor setFill];
        NSRectFill(NSMakeRect(0, maxY, width, height - maxY));          // above
        NSRectFill(NSMakeRect(0, 0, width, minY));                      // below
        NSRectFill(NSMakeRect(0, minY, minX, maxY - minY));             // left
        NSRectFill(NSMakeRect(maxX, minY, width - maxX, maxY - minY));  // right

        // Subtle rule-of-thirds grid inside active selection
        if (_selectionRect.size.width >= 60.0 && _selectionRect.size.height >= 60.0) {
            NSBezierPath *grid = [NSBezierPath bezierPath];
            for (int i = 1; i <= 2; i++) {
                CGFloat gx = minX + _selectionRect.size.width * (i / 3.0);
                CGFloat gy = minY + _selectionRect.size.height * (i / 3.0);
                [grid moveToPoint:NSMakePoint(gx, minY)];
                [grid lineToPoint:NSMakePoint(gx, maxY)];
                [grid moveToPoint:NSMakePoint(minX, gy)];
                [grid lineToPoint:NSMakePoint(maxX, gy)];
            }
            grid.lineWidth = 0.75;
            [[[NSColor whiteColor] colorWithAlphaComponent:0.22] setStroke];
            [grid stroke];
        }

        // Glowing accent outer border + crisp white dashed inner border
        NSBezierPath *glowBorder = [NSBezierPath bezierPathWithRect:_selectionRect];
        glowBorder.lineWidth = 2.0;
        [[modeAccent colorWithAlphaComponent:0.88] setStroke];
        [glowBorder stroke];

        NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(_selectionRect, 0.75, 0.75)];
        CGFloat dashes[2] = {6.0, 4.0};
        [border setLineDash:dashes count:2 phase:0];
        border.lineWidth = 1.2;
        [[[NSColor whiteColor] colorWithAlphaComponent:0.9] setStroke];
        [border stroke];

        [self drawCornerHandles];
        [self drawDimensionBadge];
    }

    if (!hasSelection) {
        [self drawInstruction];
    }

    [self drawModeControlBar];

    if (_hasMousePoint && !NSPointInRect(_mousePoint, _controlBarRect)) {
        [self drawCrosshairAtPoint:_mousePoint showCoordinates:!hasSelection];
    }
}

- (void)drawPill:(NSRect)rect
           label:(NSString *)label
        selected:(BOOL)selected
     accentColor:(NSColor *)accentColor {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:rect.size.height / 2.0 yRadius:rect.size.height / 2.0];
    if (selected) {
        [[accentColor colorWithAlphaComponent:0.28] setFill];
        [path fill];
        [[accentColor colorWithAlphaComponent:0.9] setStroke];
        path.lineWidth = 1.25;
        [path stroke];
    } else {
        [[[NSColor whiteColor] colorWithAlphaComponent:0.06] setFill];
        [path fill];
        [[[NSColor whiteColor] colorWithAlphaComponent:0.14] setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    }

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:selected ? NSFontWeightSemibold : NSFontWeightMedium],
        NSForegroundColorAttributeName: selected ? [NSColor whiteColor] : [[NSColor whiteColor] colorWithAlphaComponent:0.78]
    };
    NSSize sz = [label sizeWithAttributes:attrs];
    NSPoint pt = NSMakePoint(NSMidX(rect) - sz.width / 2.0, NSMidY(rect) - sz.height / 2.0);
    [label drawAtPoint:pt withAttributes:attrs];
}

- (void)drawModeControlBar {
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.45];
    shadow.shadowBlurRadius = 16.0;
    shadow.shadowOffset = NSMakeSize(0, -3.0);
    [shadow set];

    NSBezierPath *barPath = [NSBezierPath bezierPathWithRoundedRect:_controlBarRect
                                                            xRadius:_controlBarRect.size.height / 2.0
                                                            yRadius:_controlBarRect.size.height / 2.0];
    [[[NSColor colorWithSRGBRed:0.08 green:0.09 blue:0.12 alpha:1.0] colorWithAlphaComponent:0.90] setFill];
    [barPath fill];
    [NSGraphicsContext restoreGraphicsState];

    barPath.lineWidth = 1.0;
    [[[self activeModeAccentColor] colorWithAlphaComponent:0.55] setStroke];
    [barPath stroke];

    [self drawPill:_screenshotPillRect
             label:@"📷 Screenshot"
          selected:(self.captureMode == CSCaptureModeScreenshot)
       accentColor:[CSTheme accent]];

    [self drawPill:_videoPillRect
             label:@"🎥 Video"
          selected:(self.captureMode == CSCaptureModeVideo)
       accentColor:[CSTheme danger]];

    NSString *micLabel = self.recordMicrophone ? @"🎙 Mic: On" : @"🔇 Mic: Off";
    [self drawPill:_micPillRect
             label:micLabel
          selected:self.recordMicrophone
       accentColor:[CSTheme accent]];

    if (self.captureMode == CSCaptureModeVideo && !NSIsEmptyRect(_motionBlurPillRect)) {
        [self drawPill:_motionBlurPillRect
                 label:self.motionBlurEnabled ? @"✨ Blur: On" : @"✨ Blur: Off"
              selected:self.motionBlurEnabled
           accentColor:[CSTheme accent]];
    }

    [self drawPill:_fullScreenPillRect
             label:@"🖥 Full Screen"
          selected:NO
       accentColor:[self activeModeAccentColor]];

    [self drawPill:_cancelPillRect
             label:@"✕ Cancel"
          selected:YES
       accentColor:[CSTheme danger]];
}

- (void)drawInstruction {
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSDictionary *subtitleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:0.78]
    };
    BOOL isVideo = (self.captureMode == CSCaptureModeVideo);
    NSString *title = isVideo ? @"Drag to record video of an area" : @"Drag to capture an area";
    NSString *subtitle = isVideo
        ? @"Release to start recording  ·  M toggles Mic  ·  Tab switches mode  ·  Click ✕ Cancel or press Esc"
        : @"Release to annotate  ·  Tab switches to Video  ·  Click ✕ Cancel or press Esc";
    NSSize titleSize = [title sizeWithAttributes:titleAttributes];
    NSSize subtitleSize = [subtitle sizeWithAttributes:subtitleAttributes];

    NSRect targetScreenFrame = [self activeScreenFrameInView];
    CGFloat centerX = NSMidX(targetScreenFrame);
    CGFloat centerY = NSMidY(targetScreenFrame);

    CGFloat boxWidth = MAX(titleSize.width, subtitleSize.width) + 64.0;
    CGFloat boxHeight = titleSize.height + subtitleSize.height + 38.0;
    NSRect box = NSMakeRect(centerX - boxWidth / 2.0, centerY - boxHeight / 2.0, boxWidth, boxHeight);

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.45];
    shadow.shadowBlurRadius = 18.0;
    shadow.shadowOffset = NSMakeSize(0, -4.0);
    [shadow set];

    NSBezierPath *boxPath = [NSBezierPath bezierPathWithRoundedRect:box xRadius:16.0 yRadius:16.0];
    [[[NSColor colorWithSRGBRed:0.08 green:0.09 blue:0.12 alpha:1.0] colorWithAlphaComponent:0.84] setFill];
    [boxPath fill];
    [NSGraphicsContext restoreGraphicsState];

    boxPath.lineWidth = 1.2;
    [[[self activeModeAccentColor] colorWithAlphaComponent:0.65] setStroke];
    [boxPath stroke];

    [title drawAtPoint:NSMakePoint(centerX - titleSize.width / 2.0, centerY + 6.0) withAttributes:titleAttributes];
    [subtitle drawAtPoint:NSMakePoint(centerX - subtitleSize.width / 2.0, centerY - 22.0) withAttributes:subtitleAttributes];
}

- (void)drawCornerHandles {
    CGFloat radius = 5.0;
    NSColor *modeAccent = [self activeModeAccentColor];
    NSPoint corners[4] = {
        NSMakePoint(NSMinX(_selectionRect), NSMinY(_selectionRect)),
        NSMakePoint(NSMaxX(_selectionRect), NSMinY(_selectionRect)),
        NSMakePoint(NSMinX(_selectionRect), NSMaxY(_selectionRect)),
        NSMakePoint(NSMaxX(_selectionRect), NSMaxY(_selectionRect))
    };
    for (int i = 0; i < 4; i++) {
        NSRect hr = NSMakeRect(corners[i].x - radius, corners[i].y - radius, radius * 2.0, radius * 2.0);
        NSBezierPath *pill = [NSBezierPath bezierPathWithOvalInRect:hr];
        [modeAccent setFill];
        [pill fill];
        [[NSColor whiteColor] setStroke];
        pill.lineWidth = 1.8;
        [pill stroke];
    }
}

- (void)drawDimensionBadge {
    NSString *prefix = (self.captureMode == CSCaptureModeVideo) ? @"● REC " : @"";
    NSString *label = [NSString stringWithFormat:@"%@%ld × %ld pt",
                       prefix,
                       (long)floor(_selectionRect.size.width),
                       (long)floor(_selectionRect.size.height)];
    NSDictionary *badgeAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [label sizeWithAttributes:badgeAttributes];
    CGFloat badgeWidth = textSize.width + 16.0;
    CGFloat badgeHeight = textSize.height + 8.0;
    CGFloat x = MIN(MAX(NSMinX(_selectionRect), 4.0), NSWidth(self.bounds) - badgeWidth - 4.0);
    CGFloat y = NSMaxY(_selectionRect) + 8.0;
    if (y + badgeHeight > NSHeight(self.bounds)) {
        y = NSMinY(_selectionRect) - badgeHeight - 8.0;
    }
    NSRect badge = NSMakeRect(x, y, badgeWidth, badgeHeight);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:badge xRadius:7.0 yRadius:7.0];
    [[[NSColor colorWithSRGBRed:0.08 green:0.09 blue:0.12 alpha:1.0] colorWithAlphaComponent:0.86] setFill];
    [background fill];
    [[[self activeModeAccentColor] colorWithAlphaComponent:0.75] setStroke];
    background.lineWidth = 1.0;
    [background stroke];
    [label drawAtPoint:NSMakePoint(NSMinX(badge) + 8.0, NSMinY(badge) + 4.0) withAttributes:badgeAttributes];
}

- (void)drawCrosshairAtPoint:(NSPoint)point showCoordinates:(BOOL)showCoords {
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);
    NSColor *lineColor = [[self activeModeAccentColor] colorWithAlphaComponent:0.32];
    [lineColor setStroke];

    NSBezierPath *guides = [NSBezierPath bezierPath];
    [guides moveToPoint:NSMakePoint(0, point.y)];
    [guides lineToPoint:NSMakePoint(width, point.y)];
    [guides moveToPoint:NSMakePoint(point.x, 0)];
    [guides lineToPoint:NSMakePoint(point.x, height)];
    guides.lineWidth = 1.0;
    [guides stroke];

    CGFloat length = 16.0;
    NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross moveToPoint:NSMakePoint(point.x - length, point.y)];
    [cross lineToPoint:NSMakePoint(point.x + length, point.y)];
    [cross moveToPoint:NSMakePoint(point.x, point.y - length)];
    [cross lineToPoint:NSMakePoint(point.x, point.y + length)];
    cross.lineWidth = 1.2;
    [[[NSColor whiteColor] colorWithAlphaComponent:0.88] setStroke];
    [cross stroke];

    if (showCoords) {
        NSString *coordStr = [NSString stringWithFormat:@"%ld, %ld", (long)lround(point.x), (long)lround(point.y)];
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:0.9]
        };
        NSSize cs = [coordStr sizeWithAttributes:attrs];
        NSRect pill = NSMakeRect(point.x + 14.0, point.y - cs.height - 14.0, cs.width + 12.0, cs.height + 6.0);
        NSBezierPath *pillPath = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:5.0 yRadius:5.0];
        [[[NSColor blackColor] colorWithAlphaComponent:0.72] setFill];
        [pillPath fill];
        [coordStr drawAtPoint:NSMakePoint(NSMinX(pill) + 6.0, NSMinY(pill) + 3.0) withAttributes:attrs];
    }
}

@end

#pragma mark - SelectionWindow

@implementation SelectionWindow {
    id _globalKeyMonitor;
    id _localKeyMonitor;
}

- (instancetype)initWithCompletion:(SelectionCompletionBlock)completion
                            cancel:(SelectionCancelBlock)cancel {
    return [self initWithInitialMode:CSCaptureModeScreenshot
                    recordMicrophone:NO
                      modeCompletion:^(NSRect screenRect, CSCaptureMode mode, BOOL recordMicrophone) {
                          (void)mode;
                          (void)recordMicrophone;
                          if (completion != nil) {
                              completion(screenRect);
                          }
                      }
                              cancel:cancel];
}

- (instancetype)initWithInitialMode:(CSCaptureMode)initialMode
                   recordMicrophone:(BOOL)recordMicrophone
                     modeCompletion:(SelectionModeCompletionBlock)modeCompletion
                             cancel:(SelectionCancelBlock)cancel {
    NSRect unionFrame = NSZeroRect;
    for (NSScreen *screen in [NSScreen screens]) {
        unionFrame = NSUnionRect(unionFrame, screen.frame);
    }
    if (NSIsEmptyRect(unionFrame)) {
        unionFrame = [NSScreen mainScreen].frame;
    }

    self = [super initWithContentRect:unionFrame
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil) {
        return nil;
    }

    _captureMode = initialMode;
    _recordMicrophone = recordMicrophone;

    NSInteger blur = [[NSUserDefaults standardUserDefaults] objectForKey:@"CSVideoMotionBlur"]
        ? [[NSUserDefaults standardUserDefaults] integerForKey:@"CSVideoMotionBlur"]
        : 1;
    _motionBlurEnabled = (blur != 0);

    self.floatingPanel = YES;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.level = NSScreenSaverWindowLevel;
    self.releasedWhenClosed = NO;
    self.opaque = NO;
    self.backgroundColor = [NSColor clearColor];
    self.hasShadow = NO;
    self.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorIgnoresCycle);
    self.ignoresMouseEvents = NO;
    [self setFrame:unionFrame display:YES];

    SelectionView *view = [[SelectionView alloc] initWithFrame:NSMakeRect(0, 0, unionFrame.size.width, unionFrame.size.height)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    view.captureMode = initialMode;
    view.recordMicrophone = recordMicrophone;
    view.motionBlurEnabled = _motionBlurEnabled;
    view.modeCompletion = modeCompletion;
    view.cancelHandler = cancel;
    self.contentView = view;

    __weak typeof(self) weakSelf = self;
    _globalKeyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                               handler:^(NSEvent *event) {
        if (event.keyCode == 53) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf cancelOperation:nil];
            });
        }
    }];
    _localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                             handler:^NSEvent *(NSEvent *event) {
        if ([weakSelf handleSelectionKeyEvent:event]) {
            return nil;
        }
        return event;
    }];

    return self;
}

- (void)setCaptureMode:(CSCaptureMode)captureMode {
    _captureMode = captureMode;
    if ([self.contentView isKindOfClass:[SelectionView class]]) {
        SelectionView *view = (SelectionView *)self.contentView;
        view.captureMode = captureMode;
        [view setNeedsDisplay:YES];
    }
}

- (void)setRecordMicrophone:(BOOL)recordMicrophone {
    _recordMicrophone = recordMicrophone;
    if ([self.contentView isKindOfClass:[SelectionView class]]) {
        SelectionView *view = (SelectionView *)self.contentView;
        view.recordMicrophone = recordMicrophone;
        [view setNeedsDisplay:YES];
    }
}

- (void)setMotionBlurEnabled:(BOOL)motionBlurEnabled {
    _motionBlurEnabled = motionBlurEnabled;
    if ([self.contentView isKindOfClass:[SelectionView class]]) {
        SelectionView *view = (SelectionView *)self.contentView;
        view.motionBlurEnabled = motionBlurEnabled;
        [view setNeedsDisplay:YES];
    }
}

- (BOOL)handleSelectionKeyEvent:(NSEvent *)event {
    if (event.keyCode == 53) { // Escape
        [self cancelOperation:nil];
        return YES;
    }
    if (event.keyCode == 48) { // Tab toggles Screenshot <-> Video
        self.captureMode = (self.captureMode == CSCaptureModeScreenshot)
            ? CSCaptureModeVideo
            : CSCaptureModeScreenshot;
        return YES;
    }
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    if ([chars isEqualToString:@"v"] || [chars isEqualToString:@"2"]) {
        self.captureMode = CSCaptureModeVideo;
        return YES;
    }
    if ([chars isEqualToString:@"s"] || [chars isEqualToString:@"1"]) {
        self.captureMode = CSCaptureModeScreenshot;
        return YES;
    }
    if ([chars isEqualToString:@"m"]) {
        self.recordMicrophone = !self.recordMicrophone;
        self.captureMode = CSCaptureModeVideo;
        return YES;
    }
    if ([chars isEqualToString:@"b"]) {
        self.motionBlurEnabled = !self.motionBlurEnabled;
        [[NSUserDefaults standardUserDefaults] setInteger:(self.motionBlurEnabled ? 1 : 0) forKey:@"CSVideoMotionBlur"];
        return YES;
    }
    if ([chars isEqualToString:@"f"] || event.keyCode == 36) { // F or Return -> Full Screen
        if ([self.contentView isKindOfClass:[SelectionView class]]) {
            [(SelectionView *)self.contentView triggerFullScreenOnActiveScreen];
            return YES;
        }
    }
    return NO;
}

- (void)removeKeyMonitors {
    if (_globalKeyMonitor != nil) {
        [NSEvent removeMonitor:_globalKeyMonitor];
        _globalKeyMonitor = nil;
    }
    if (_localKeyMonitor != nil) {
        [NSEvent removeMonitor:_localKeyMonitor];
        _localKeyMonitor = nil;
    }
}

- (void)close {
    [self removeKeyMonitors];
    if ([self.contentView isKindOfClass:[SelectionView class]]) {
        SelectionView *view = (SelectionView *)self.contentView;
        SelectionCancelBlock cancel = view.cancelHandler;
        view.modeCompletion = nil;
        view.completion = nil;
        view.cancelHandler = nil;
        if (cancel != nil) {
            cancel();
        }
    }
    [self orderOut:nil];
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    [super close];
    malloc_zone_pressure_relief(NULL, 0);
}

- (void)dealloc {
    [self removeKeyMonitors];
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(nullable NSScreen *)screen {
    return frameRect;
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    if ([self handleSelectionKeyEvent:event]) {
        return;
    }
    [super keyDown:event];
}

- (void)cancelOperation:(id)sender {
    SelectionView *view = (SelectionView *)self.contentView;
    if (view.cancelHandler != nil) {
        view.cancelHandler();
    }
    [self close];
}

@end
