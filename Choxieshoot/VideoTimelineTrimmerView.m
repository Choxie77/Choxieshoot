#import "VideoTimelineTrimmerView.h"
#import "CSTheme.h"

typedef NS_ENUM(NSInteger, CSTrimDragTarget) {
    CSTrimDragNone = 0,
    CSTrimDragInHandle,
    CSTrimDragOutHandle,
    CSTrimDragPlayhead,
    CSTrimDragRange
};

@interface VideoTimelineTrimmerView ()

@property (nonatomic) CSTrimDragTarget activeDrag;
@property (nonatomic) NSPoint dragStartPoint;
@property (nonatomic) NSTimeInterval dragInitialStartTime;
@property (nonatomic) NSTimeInterval dragInitialEndTime;
@property (nonatomic, strong, nullable) NSTrackingArea *trackingArea;

@property (nonatomic, strong) NSButton *playPauseButton;
@property (nonatomic, strong) NSButton *inButton;
@property (nonatomic, strong) NSButton *outButton;
@property (nonatomic, strong) NSButton *prevFrameButton;
@property (nonatomic, strong) NSButton *nextFrameButton;
@property (nonatomic, strong) NSButton *resetButton;

@end

@implementation VideoTimelineTrimmerView

- (instancetype)initWithFrame:(NSRect)frame duration:(NSTimeInterval)duration {
    self = [super initWithFrame:frame];
    if (self) {
        _duration = MAX(0.1, duration);
        _currentTime = 0.0;
        _trimStartTime = 0.0;
        _trimEndTime = _duration;
        _activeDrag = CSTrimDragNone;
        _isPlaying = NO;
        self.wantsLayer = YES;

        [self setupButtons];
        [self layoutButtons];
    }
    return self;
}

- (void)setupButtons {
    self.playPauseButton = [self createButtonWithSymbol:@"play.fill"
                                                  title:@""
                                                tooltip:@"Play / Pause (Space)"
                                                 action:@selector(playPauseClicked:)];
    self.playPauseButton.bezelColor = [CSTheme accent];
    [self addSubview:self.playPauseButton];

    self.inButton = [self createButtonWithSymbol:nil
                                           title:@"[ In"
                                         tooltip:@"Set In-Point / Cut Start ([ or I)"
                                          action:@selector(inClicked:)];
    [self addSubview:self.inButton];

    self.outButton = [self createButtonWithSymbol:nil
                                            title:@"Out ]"
                                          tooltip:@"Set Out-Point / Cut End (] or O)"
                                           action:@selector(outClicked:)];
    [self addSubview:self.outButton];

    self.prevFrameButton = [self createButtonWithSymbol:@"chevron.backward"
                                                  title:@""
                                                tooltip:@"Step Back 1 Frame (←)"
                                                 action:@selector(prevFrameClicked:)];
    [self addSubview:self.prevFrameButton];

    self.nextFrameButton = [self createButtonWithSymbol:@"chevron.forward"
                                                  title:@""
                                                tooltip:@"Step Forward 1 Frame (→)"
                                                 action:@selector(nextFrameClicked:)];
    [self addSubview:self.nextFrameButton];

    self.resetButton = [self createButtonWithSymbol:@"arrow.counterclockwise"
                                              title:@""
                                            tooltip:@"Reset Trim to Full Video"
                                             action:@selector(resetClicked:)];
    [self addSubview:self.resetButton];
}

- (NSButton *)createButtonWithSymbol:(nullable NSString *)symbol
                               title:(NSString *)title
                             tooltip:(NSString *)tooltip
                              action:(SEL)action {
    NSButton *btn = [NSButton buttonWithTitle:title target:self action:action];
    btn.bezelStyle = NSBezelStyleInline;
    btn.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
    if (symbol != nil) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tooltip];
        if (img != nil) {
            btn.image = img;
            btn.imagePosition = title.length > 0 ? NSImageLeading : NSImageOnly;
        }
    }
    btn.toolTip = tooltip;
    [btn setAccessibilityLabel:tooltip];
    return btn;
}

- (void)playPauseClicked:(id)sender {
    if (self.onPlayPauseToggle) {
        self.onPlayPauseToggle();
    }
}

- (void)inClicked:(id)sender {
    [self setInPointToCurrentTime];
}

- (void)outClicked:(id)sender {
    [self setOutPointToCurrentTime];
}

- (void)prevFrameClicked:(id)sender {
    [self stepFrames:-1 fps:30.0];
}

- (void)nextFrameClicked:(id)sender {
    [self stepFrames:1 fps:30.0];
}

- (void)resetClicked:(id)sender {
    [self resetTrim];
}

- (void)setIsPlaying:(BOOL)isPlaying {
    _isPlaying = isPlaying;
    NSString *sym = isPlaying ? @"pause.fill" : @"play.fill";
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:@"Play/Pause"];
    self.playPauseButton.image = img;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutButtons];
}

- (void)layoutButtons {
    CGFloat totalW = NSWidth(self.bounds);
    if (totalW <= 0) { return; }

    CGFloat btnY = 5.0;
    CGFloat btnH = 26.0;

    // Left buttons
    self.playPauseButton.frame = NSMakeRect(8.0, btnY, 30.0, btnH);
    self.inButton.frame = NSMakeRect(42.0, btnY, 44.0, btnH);
    self.outButton.frame = NSMakeRect(90.0, btnY, 44.0, btnH);

    // Right buttons
    CGFloat rightX = totalW - 8.0;
    self.resetButton.frame = NSMakeRect(rightX - 26.0, btnY, 26.0, btnH);
    rightX -= (26.0 + 4.0);

    self.nextFrameButton.frame = NSMakeRect(rightX - 26.0, btnY, 26.0, btnH);
    rightX -= (26.0 + 4.0);

    self.prevFrameButton.frame = NSMakeRect(rightX - 26.0, btnY, 26.0, btnH);
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

- (void)setDuration:(NSTimeInterval)duration {
    _duration = MAX(0.1, duration);
    if (_trimEndTime > _duration || _trimEndTime <= 0.0) {
        _trimEndTime = _duration;
    }
    if (_trimStartTime >= _trimEndTime) {
        _trimStartTime = 0.0;
    }
    _currentTime = MIN(MAX(_currentTime, 0.0), _duration);
    self.needsDisplay = YES;
}

- (void)setCurrentTime:(NSTimeInterval)currentTime {
    _currentTime = MIN(MAX(currentTime, 0.0), _duration);
    self.needsDisplay = YES;
}

- (void)setTrimStartTime:(NSTimeInterval)trimStartTime {
    _trimStartTime = MIN(MAX(trimStartTime, 0.0), _trimEndTime - 0.05);
    self.needsDisplay = YES;
}

- (void)setTrimEndTime:(NSTimeInterval)trimEndTime {
    _trimEndTime = MAX(MIN(trimEndTime, _duration), _trimStartTime + 0.05);
    self.needsDisplay = YES;
}

- (BOOL)isTrimmed {
    return (_trimStartTime > 0.05 || (_duration - _trimEndTime) > 0.05);
}

- (NSTimeInterval)trimmedDuration {
    return MAX(0.0, _trimEndTime - _trimStartTime);
}

- (void)setInPointToCurrentTime {
    NSTimeInterval newIn = MIN(_currentTime, _trimEndTime - 0.05);
    self.trimStartTime = MAX(0.0, newIn);
    if (self.onTrimChanged) {
        self.onTrimChanged(self.trimStartTime, self.trimEndTime);
    }
    self.needsDisplay = YES;
}

- (void)setOutPointToCurrentTime {
    NSTimeInterval newOut = MAX(_currentTime, _trimStartTime + 0.05);
    self.trimEndTime = MIN(self.duration, newOut);
    if (self.onTrimChanged) {
        self.onTrimChanged(self.trimStartTime, self.trimEndTime);
    }
    self.needsDisplay = YES;
}

- (void)resetTrim {
    self.trimStartTime = 0.0;
    self.trimEndTime = self.duration;
    if (self.onTrimChanged) {
        self.onTrimChanged(self.trimStartTime, self.trimEndTime);
    }
    self.needsDisplay = YES;
}

- (void)stepFrames:(NSInteger)frameCount fps:(double)fps {
    double safeFps = fps > 1.0 ? fps : 30.0;
    NSTimeInterval delta = (double)frameCount / safeFps;
    NSTimeInterval newTime = MIN(MAX(self.currentTime + delta, 0.0), self.duration);
    self.currentTime = newTime;
    if (self.onSeek) {
        self.onSeek(newTime);
    }
    self.needsDisplay = YES;
}

#pragma mark - Geometry Helpers

- (NSRect)trackRect {
    CGFloat leftMargin = 142.0;
    CGFloat rightMargin = 100.0;
    CGFloat trackH = 24.0;
    CGFloat padBottom = 6.0;
    CGFloat totalW = NSWidth(self.bounds);
    CGFloat trackW = MAX(60.0, totalW - leftMargin - rightMargin);
    return NSMakeRect(leftMargin, padBottom, trackW, trackH);
}

- (CGFloat)xForTime:(NSTimeInterval)time {
    NSRect track = [self trackRect];
    if (self.duration <= 0.0) {
        return track.origin.x;
    }
    CGFloat fraction = time / self.duration;
    return track.origin.x + fraction * track.size.width;
}

- (NSTimeInterval)timeForX:(CGFloat)x {
    NSRect track = [self trackRect];
    if (track.size.width <= 0) {
        return 0.0;
    }
    CGFloat fraction = (x - track.origin.x) / track.size.width;
    fraction = MIN(MAX(fraction, 0.0), 1.0);
    return fraction * self.duration;
}

- (NSRect)inHandleRect {
    NSRect track = [self trackRect];
    CGFloat x = [self xForTime:self.trimStartTime];
    return NSMakeRect(floor(x - 7.0), track.origin.y - 2.0, 14.0, track.size.height + 4.0);
}

- (NSRect)outHandleRect {
    NSRect track = [self trackRect];
    CGFloat x = [self xForTime:self.trimEndTime];
    return NSMakeRect(floor(x - 7.0), track.origin.y - 2.0, 14.0, track.size.height + 4.0);
}

- (NSRect)playheadRect {
    NSRect track = [self trackRect];
    CGFloat x = [self xForTime:self.currentTime];
    return NSMakeRect(floor(x - 6.0), track.origin.y - 4.0, 12.0, track.size.height + 8.0);
}

#pragma mark - Hit Testing

- (CSTrimDragTarget)targetAtPoint:(NSPoint)point {
    if (NSPointInRect(point, [self inHandleRect])) {
        return CSTrimDragInHandle;
    }
    if (NSPointInRect(point, [self outHandleRect])) {
        return CSTrimDragOutHandle;
    }
    if (NSPointInRect(point, [self playheadRect])) {
        return CSTrimDragPlayhead;
    }
    NSRect track = [self trackRect];
    if (NSPointInRect(point, track)) {
        CGFloat xIn = [self xForTime:self.trimStartTime];
        CGFloat xOut = [self xForTime:self.trimEndTime];
        if (point.x > xIn + 8.0 && point.x < xOut - 8.0) {
            return CSTrimDragPlayhead;
        }
    }
    return CSTrimDragNone;
}

- (void)cursorUpdate:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    CSTrimDragTarget target = [self targetAtPoint:loc];
    if (target == CSTrimDragInHandle || target == CSTrimDragOutHandle) {
        [[NSCursor resizeLeftRightCursor] set];
    } else if (target == CSTrimDragPlayhead) {
        [[NSCursor arrowCursor] set];
    } else {
        [[NSCursor arrowCursor] set];
    }
}

- (void)mouseMoved:(NSEvent *)event {
    [self cursorUpdate:event];
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragStartPoint = loc;
    self.dragInitialStartTime = self.trimStartTime;
    self.dragInitialEndTime = self.trimEndTime;

    self.activeDrag = [self targetAtPoint:loc];

    if (self.activeDrag == CSTrimDragNone) {
        NSRect track = [self trackRect];
        if (NSPointInRect(loc, track)) {
            NSTimeInterval t = [self timeForX:loc.x];
            self.currentTime = t;
            self.activeDrag = CSTrimDragPlayhead;
            if (self.onSeek) {
                self.onSeek(t);
            }
        }
    }

    if (self.onScrubbingStateChanged && self.activeDrag != CSTrimDragNone) {
        self.onScrubbingStateChanged(YES);
    }
    self.needsDisplay = YES;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.activeDrag == CSTrimDragNone) {
        return;
    }
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    NSTimeInterval t = [self timeForX:loc.x];

    switch (self.activeDrag) {
        case CSTrimDragInHandle: {
            self.trimStartTime = MIN(MAX(t, 0.0), self.trimEndTime - 0.05);
            self.currentTime = self.trimStartTime;
            if (self.onSeek) {
                self.onSeek(self.trimStartTime);
            }
            if (self.onTrimChanged) {
                self.onTrimChanged(self.trimStartTime, self.trimEndTime);
            }
            break;
        }
        case CSTrimDragOutHandle: {
            self.trimEndTime = MAX(MIN(t, self.duration), self.trimStartTime + 0.05);
            self.currentTime = self.trimEndTime;
            if (self.onSeek) {
                self.onSeek(self.trimEndTime);
            }
            if (self.onTrimChanged) {
                self.onTrimChanged(self.trimStartTime, self.trimEndTime);
            }
            break;
        }
        case CSTrimDragPlayhead: {
            self.currentTime = t;
            if (self.onSeek) {
                self.onSeek(t);
            }
            break;
        }
        case CSTrimDragRange: {
            NSRect track = [self trackRect];
            CGFloat deltaFrac = (loc.x - self.dragStartPoint.x) / track.size.width;
            NSTimeInterval deltaT = deltaFrac * self.duration;
            NSTimeInterval span = self.dragInitialEndTime - self.dragInitialStartTime;
            NSTimeInterval newIn = self.dragInitialStartTime + deltaT;
            if (newIn < 0.0) {
                newIn = 0.0;
            }
            if (newIn + span > self.duration) {
                newIn = self.duration - span;
            }
            self.trimStartTime = newIn;
            self.trimEndTime = newIn + span;
            if (self.onTrimChanged) {
                self.onTrimChanged(self.trimStartTime, self.trimEndTime);
            }
            break;
        }
        default:
            break;
    }
    self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)event {
    if (self.activeDrag != CSTrimDragNone) {
        self.activeDrag = CSTrimDragNone;
        if (self.onScrubbingStateChanged) {
            self.onScrubbingStateChanged(NO);
        }
    }
    self.needsDisplay = YES;
}

#pragma mark - Formatting Helpers

- (NSString *)stringForSeconds:(NSTimeInterval)seconds {
    if (seconds < 0) { seconds = 0; }
    NSInteger totalHundredths = (NSInteger)llround(seconds * 100.0);
    NSInteger mins = totalHundredths / 6000;
    NSInteger secs = (totalHundredths % 6000) / 100;
    NSInteger hundredths = totalHundredths % 100;
    return [NSString stringWithFormat:@"%02ld:%02ld.%02ld", (long)mins, (long)secs, (long)hundredths];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [self layoutButtons];
    NSRect track = [self trackRect];

    // 1. Text Labels Header (Time Readouts)
    CGFloat labelY = NSMaxY(track) + 3.0;
    NSDictionary *labelAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [CSTheme mutedText]
    };
    NSDictionary *boldAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [CSTheme text]
    };
    NSDictionary *accentAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [CSTheme accent]
    };

    // Left label: In point
    NSString *inStr = [NSString stringWithFormat:@"In %@", [self stringForSeconds:self.trimStartTime]];
    [inStr drawAtPoint:NSMakePoint(track.origin.x, labelY) withAttributes:labelAttr];

    // Center label: Playhead & cut info
    NSTimeInterval cutDuration = self.duration - [self trimmedDuration];
    NSString *centerStr;
    if (cutDuration > 0.05) {
        centerStr = [NSString stringWithFormat:@"✂ %@ (cut %.1fs)",
                     [self stringForSeconds:[self trimmedDuration]], cutDuration];
    } else {
        centerStr = [NSString stringWithFormat:@"▶ %@", [self stringForSeconds:self.currentTime]];
    }
    NSSize centerSize = [centerStr sizeWithAttributes:accentAttr];
    CGFloat centerX = floor(NSMidX(track) - centerSize.width / 2.0);
    [centerStr drawAtPoint:NSMakePoint(centerX, labelY) withAttributes:cutDuration > 0.05 ? accentAttr : boldAttr];

    // Right label: Out point / total
    NSString *outStr = [NSString stringWithFormat:@"Out %@ / %@",
                        [self stringForSeconds:self.trimEndTime],
                        [self stringForSeconds:self.duration]];
    NSSize outSize = [outStr sizeWithAttributes:labelAttr];
    CGFloat outLabelX = NSMaxX(track) - outSize.width;
    [outStr drawAtPoint:NSMakePoint(outLabelX, labelY) withAttributes:labelAttr];

    // 2. Track Background
    NSBezierPath *trackPath = [NSBezierPath bezierPathWithRoundedRect:track xRadius:4.0 yRadius:4.0];
    [[[NSColor blackColor] colorWithAlphaComponent:0.6] setFill];
    [trackPath fill];
    [[CSTheme subtleBorder] setStroke];
    trackPath.lineWidth = 1.0;
    [trackPath stroke];

    // 3. Tick Marks along track
    NSInteger tickCount = 20;
    NSBezierPath *ticks = [NSBezierPath bezierPath];
    ticks.lineWidth = 1.0;
    for (NSInteger i = 1; i < tickCount; i++) {
        CGFloat tx = track.origin.x + (track.size.width / (CGFloat)tickCount) * i;
        CGFloat th = (i % 5 == 0) ? 5.0 : 2.5;
        [ticks moveToPoint:NSMakePoint(tx, track.origin.y + 2.0)];
        [ticks lineToPoint:NSMakePoint(tx, track.origin.y + 2.0 + th)];
    }
    [[NSColor colorWithWhite:1.0 alpha:0.12] setStroke];
    [ticks stroke];

    // 4. Highlighted Active Trim Range
    CGFloat inX = [self xForTime:self.trimStartTime];
    CGFloat outX = [self xForTime:self.trimEndTime];
    CGFloat rangeW = MAX(2.0, outX - inX);
    NSRect activeRect = NSMakeRect(inX, track.origin.y, rangeW, track.size.height);

    NSBezierPath *activeFill = [NSBezierPath bezierPathWithRect:activeRect];
    [[[CSTheme accent] colorWithAlphaComponent:0.25] setFill];
    [activeFill fill];

    // Top and bottom borders on active range
    NSBezierPath *activeBorders = [NSBezierPath bezierPath];
    [activeBorders moveToPoint:NSMakePoint(inX, track.origin.y)];
    [activeBorders lineToPoint:NSMakePoint(outX, track.origin.y)];
    [activeBorders moveToPoint:NSMakePoint(inX, NSMaxY(track))];
    [activeBorders lineToPoint:NSMakePoint(outX, NSMaxY(track))];
    [[CSTheme accent] setStroke];
    activeBorders.lineWidth = 1.5;
    [activeBorders stroke];

    // Dimmed excluded areas outside active range
    if (inX > track.origin.x) {
        NSRect leftDim = NSMakeRect(track.origin.x, track.origin.y, inX - track.origin.x, track.size.height);
        NSBezierPath *ld = [NSBezierPath bezierPathWithRect:leftDim];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] setFill];
        [ld fill];
    }
    if (outX < NSMaxX(track)) {
        NSRect rightDim = NSMakeRect(outX, track.origin.y, NSMaxX(track) - outX, track.size.height);
        NSBezierPath *rd = [NSBezierPath bezierPathWithRect:rightDim];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] setFill];
        [rd fill];
    }

    // 5. In-Point Handle (Left)
    NSRect inR = [self inHandleRect];
    NSBezierPath *inHandle = [NSBezierPath bezierPathWithRoundedRect:inR xRadius:3.5 yRadius:3.5];
    [[CSTheme accent] setFill];
    [inHandle fill];
    [[NSColor whiteColor] setStroke];
    inHandle.lineWidth = 1.0;
    [inHandle stroke];

    NSDictionary *gripAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightBlack],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSString *inIcon = @"[";
    NSSize inIconSize = [inIcon sizeWithAttributes:gripAttr];
    [inIcon drawAtPoint:NSMakePoint(floor(NSMidX(inR) - inIconSize.width / 2.0),
                                    floor(NSMidY(inR) - inIconSize.height / 2.0))
         withAttributes:gripAttr];

    // 6. Out-Point Handle (Right)
    NSRect outR = [self outHandleRect];
    NSBezierPath *outHandle = [NSBezierPath bezierPathWithRoundedRect:outR xRadius:3.5 yRadius:3.5];
    [[CSTheme accent] setFill];
    [outHandle fill];
    [[NSColor whiteColor] setStroke];
    outHandle.lineWidth = 1.0;
    [outHandle stroke];

    NSString *outIcon = @"]";
    NSSize outIconSize = [outIcon sizeWithAttributes:gripAttr];
    [outIcon drawAtPoint:NSMakePoint(floor(NSMidX(outR) - outIconSize.width / 2.0),
                                     floor(NSMidY(outR) - outIconSize.height / 2.0))
          withAttributes:gripAttr];

    // 7. Playhead Needle
    CGFloat phX = [self xForTime:self.currentTime];
    NSBezierPath *needle = [NSBezierPath bezierPath];
    needle.lineWidth = 1.5;
    [needle moveToPoint:NSMakePoint(phX, track.origin.y - 1.0)];
    [needle lineToPoint:NSMakePoint(phX, track.origin.y + track.size.height + 3.0)];
    [[NSColor whiteColor] setStroke];
    [needle stroke];

    // Playhead top marker
    NSBezierPath *phHead = [NSBezierPath bezierPath];
    CGFloat headY = track.origin.y + track.size.height + 3.0;
    [phHead moveToPoint:NSMakePoint(phX - 4.5, headY + 4.5)];
    [phHead lineToPoint:NSMakePoint(phX + 4.5, headY + 4.5)];
    [phHead lineToPoint:NSMakePoint(phX, headY)];
    [phHead closePath];
    [[NSColor whiteColor] setFill];
    [phHead fill];
}

@end
