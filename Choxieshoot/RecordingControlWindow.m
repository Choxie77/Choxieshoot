#import "RecordingControlWindow.h"
#import "CSTheme.h"
#import "ChoxieshootPreferences.h"

#pragma mark - RecordingRegionBorderView

@interface RecordingRegionBorderView : NSView
@property (nonatomic) CGFloat borderPadding;
@property (nonatomic) BOOL paused;
@end

@implementation RecordingRegionBorderView

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat pad = MAX(2.0, self.borderPadding);
    NSRect frameRect = NSInsetRect(self.bounds, pad - 1.5, pad - 1.5);
    if (frameRect.size.width <= 0 || frameRect.size.height <= 0) {
        return;
    }

    NSColor *strokeColor = self.paused
        ? [NSColor colorWithSRGBRed:0.96 green:0.68 blue:0.18 alpha:0.92]
        : [[CSTheme danger] colorWithAlphaComponent:0.92];

    NSBezierPath *outerGlow = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(frameRect, -1.0, -1.0)
                                                              xRadius:3.0
                                                              yRadius:3.0];
    outerGlow.lineWidth = 2.0;
    [[strokeColor colorWithAlphaComponent:0.35] setStroke];
    [outerGlow stroke];

    NSBezierPath *dashed = [NSBezierPath bezierPathWithRect:frameRect];
    CGFloat pattern[2] = {6.0, 4.0};
    [dashed setLineDash:pattern count:2 phase:0];
    dashed.lineWidth = 1.5;
    [strokeColor setStroke];
    [dashed stroke];
}

@end

#pragma mark - RecordingControlWindow

@interface RecordingControlWindow ()

@property (nonatomic, strong, nullable) NSPanel *regionFrameWindow;
@property (nonatomic, strong, nullable) RecordingRegionBorderView *regionBorderView;
@property (nonatomic, strong) NSView *recordingDot;
@property (nonatomic, strong) NSTextField *timerLabel;
@property (nonatomic, strong) NSView *micPill;
@property (nonatomic, strong) NSTextField *micBadgeLabel;
@property (nonatomic, strong) NSView *smoothPill;
@property (nonatomic, strong) NSTextField *smoothBadgeLabel;
@property (nonatomic, strong) NSButton *pauseButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSButton *minimizeButton;
@property (nonatomic, strong) NSButton *cancelButton;
@property (nonatomic) BOOL isPausedState;
@property (nonatomic) BOOL isMinimizedHUD;
@property (nonatomic) NSRect expandedHUDFrame;
@property (nonatomic) NSRect targetVisibleFrame;

@end

@implementation RecordingControlWindow

- (instancetype)initWithRecordedScreenRect:(NSRect)screenRect
                          recordMicrophone:(BOOL)recordMicrophone {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger fps = [defaults integerForKey:CSVideoFPSKey];
    if (fps <= 0) fps = 60;
    NSInteger blur = [defaults objectForKey:CSVideoMotionBlurKey] ? [defaults integerForKey:CSVideoMotionBlurKey] : 1;
    BOOL hasBlur = (blur != 0);

    CGFloat hudWidth = 448.0;
    CGFloat hudHeight = 44.0;

    NSScreen *targetScreen = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens]) {
        if (NSIntersectsRect(s.frame, screenRect)) {
            targetScreen = s;
            break;
        }
    }
    NSRect visible = targetScreen != nil ? targetScreen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    _targetVisibleFrame = visible;

    // Place HUD below the recorded region if space allows; otherwise above or inside bottom center
    CGFloat hudX = floor(NSMidX(screenRect) - hudWidth / 2.0);
    hudX = MIN(MAX(hudX, NSMinX(visible) + 12.0), NSMaxX(visible) - hudWidth - 12.0);
    CGFloat hudY = NSMinY(screenRect) - hudHeight - 12.0;
    if (hudY < NSMinY(visible) + 8.0) {
        hudY = NSMaxY(screenRect) + 12.0;
        if (hudY + hudHeight > NSMaxY(visible) - 8.0) {
            hudY = NSMinY(visible) + 20.0;
        }
    }
    _expandedHUDFrame = NSMakeRect(hudX, hudY, hudWidth, hudHeight);

    self = [super initWithContentRect:_expandedHUDFrame
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil) {
        return nil;
    }

    self.floatingPanel = YES;
    self.becomesKeyOnlyIfNeeded = YES;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.level = NSStatusWindowLevel;
    self.releasedWhenClosed = NO;
    self.opaque = NO;
    self.backgroundColor = [NSColor clearColor];
    self.hasShadow = YES;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary);

    NSVisualEffectView *glass = [CSTheme glassViewWithFrame:NSMakeRect(0, 0, hudWidth, hudHeight)
                                                   material:NSVisualEffectMaterialHUDWindow
                                               cornerRadius:hudHeight / 2.0];
    glass.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentView = glass;

    // Recording indicator dot
    self.recordingDot = [[NSView alloc] initWithFrame:NSMakeRect(14, 16, 12, 12)];
    self.recordingDot.wantsLayer = YES;
    self.recordingDot.layer.cornerRadius = 6.0;
    self.recordingDot.layer.backgroundColor = [CSTheme danger].CGColor;
    [glass addSubview:self.recordingDot];

    // Elapsed time label
    self.timerLabel = [NSTextField labelWithString:@"00:00"];
    self.timerLabel.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightBold];
    self.timerLabel.textColor = [CSTheme text];
    self.timerLabel.frame = NSMakeRect(32, 13, 50, 18);
    [glass addSubview:self.timerLabel];

    // Microphone status pill
    NSView *micPill = [[NSView alloc] initWithFrame:NSMakeRect(86, 10, 66, 24)];
    micPill.wantsLayer = YES;
    micPill.layer.cornerRadius = 12.0;
    micPill.layer.backgroundColor = [CSTheme pillSurface].CGColor;
    micPill.layer.borderWidth = 1.0;
    micPill.layer.borderColor = [CSTheme subtleBorder].CGColor;
    self.micPill = micPill;
    [glass addSubview:micPill];

    self.micBadgeLabel = [NSTextField labelWithString:recordMicrophone ? @"🎙 Mic" : @"🔇 Silent"];
    self.micBadgeLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    self.micBadgeLabel.textColor = recordMicrophone ? [CSTheme accent] : [CSTheme mutedText];
    self.micBadgeLabel.alignment = NSTextAlignmentCenter;
    self.micBadgeLabel.frame = NSMakeRect(4, 4, 58, 15);
    [micPill addSubview:self.micBadgeLabel];

    // Video FPS & Motion Blur status pill
    NSView *smoothPill = [[NSView alloc] initWithFrame:NSMakeRect(156, 10, 74, 24)];
    smoothPill.wantsLayer = YES;
    smoothPill.layer.cornerRadius = 12.0;
    smoothPill.layer.backgroundColor = [CSTheme pillSurface].CGColor;
    smoothPill.layer.borderWidth = 1.0;
    smoothPill.layer.borderColor = [CSTheme subtleBorder].CGColor;
    smoothPill.toolTip = [NSString stringWithFormat:@"Recording at %ld FPS with %@motion blur", (long)fps, hasBlur ? @"" : @"no "];
    self.smoothPill = smoothPill;
    [glass addSubview:smoothPill];

    NSString *smoothText = [NSString stringWithFormat:@"%@ %ldfps", hasBlur ? @"✨" : @"⚡", (long)fps];
    self.smoothBadgeLabel = [NSTextField labelWithString:smoothText];
    self.smoothBadgeLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    self.smoothBadgeLabel.textColor = [CSTheme accent];
    self.smoothBadgeLabel.alignment = NSTextAlignmentCenter;
    self.smoothBadgeLabel.frame = NSMakeRect(4, 4, 66, 15);
    [smoothPill addSubview:self.smoothBadgeLabel];

    // Pause / Resume button
    self.pauseButton = [NSButton buttonWithTitle:@"Pause" target:self action:@selector(pauseResumeClicked:)];
    self.pauseButton.bezelStyle = NSBezelStyleRounded;
    self.pauseButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
    NSImage *pauseImg = [NSImage imageWithSystemSymbolName:@"pause.fill" accessibilityDescription:@"Pause"];
    if (pauseImg != nil) {
        self.pauseButton.image = pauseImg;
        self.pauseButton.imagePosition = NSImageLeading;
    }
    self.pauseButton.frame = NSMakeRect(236, 8, 72, 28);
    self.pauseButton.toolTip = @"Pause or resume recording";
    [glass addSubview:self.pauseButton];

    // Stop button
    self.stopButton = [NSButton buttonWithTitle:@"Stop" target:self action:@selector(stopClicked:)];
    self.stopButton.bezelStyle = NSBezelStyleRounded;
    self.stopButton.bezelColor = [CSTheme danger];
    self.stopButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightBold];
    self.stopButton.toolTip = @"Stop recording and open preview to save (⌘S) or copy";
    NSImage *stopImg = [NSImage imageWithSystemSymbolName:@"stop.fill" accessibilityDescription:@"Stop"];
    if (stopImg != nil) {
        self.stopButton.image = stopImg;
        self.stopButton.imagePosition = NSImageLeading;
    }
    self.stopButton.frame = NSMakeRect(312, 8, 66, 28);
    [glass addSubview:self.stopButton];

    // Minimize / Tuck out of the way button
    self.minimizeButton = [NSButton buttonWithTitle:@"" target:self action:@selector(minimizeHUDClicked:)];
    self.minimizeButton.bezelStyle = NSBezelStyleRounded;
    self.minimizeButton.toolTip = @"Minimize recording controls to corner";
    NSImage *minusImg = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Minimize recording controls"];
    if (minusImg != nil) {
        self.minimizeButton.image = minusImg;
    } else {
        self.minimizeButton.title = @"—";
    }
    self.minimizeButton.frame = NSMakeRect(382, 8, 26, 28);
    [glass addSubview:self.minimizeButton];

    // Cancel / Discard button
    self.cancelButton = [NSButton buttonWithTitle:@"" target:self action:@selector(cancelClicked:)];
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    self.cancelButton.toolTip = @"Cancel and discard recording";
    NSImage *xmark = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Cancel recording"];
    if (xmark != nil) {
        self.cancelButton.image = xmark;
    } else {
        self.cancelButton.title = @"✕";
    }
    self.cancelButton.frame = NSMakeRect(410, 8, 26, 28);
    [glass addSubview:self.cancelButton];

    // Create click-through region border overlay around screenRect
    CGFloat pad = 4.0;
    NSRect overlayRect = NSInsetRect(screenRect, -pad, -pad);
    NSPanel *regionWin = [[NSPanel alloc] initWithContentRect:overlayRect
                                                    styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    regionWin.floatingPanel = YES;
    regionWin.level = NSStatusWindowLevel - 1;
    regionWin.releasedWhenClosed = NO;
    regionWin.opaque = NO;
    regionWin.backgroundColor = [NSColor clearColor];
    regionWin.hasShadow = NO;
    regionWin.ignoresMouseEvents = YES;
    regionWin.hidesOnDeactivate = NO;
    regionWin.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary |
                                    NSWindowCollectionBehaviorStationary |
                                    NSWindowCollectionBehaviorIgnoresCycle);

    RecordingRegionBorderView *borderView = [[RecordingRegionBorderView alloc] initWithFrame:NSMakeRect(0, 0, overlayRect.size.width, overlayRect.size.height)];
    borderView.borderPadding = pad;
    regionWin.contentView = borderView;
    self.regionFrameWindow = regionWin;
    self.regionBorderView = borderView;

    [self.regionFrameWindow orderFrontRegardless];
    [self orderFrontRegardless];

    return self;
}

- (CGWindowID)lowestOverlayWindowID {
    if (self.regionFrameWindow != nil && self.regionFrameWindow.windowNumber > 0) {
        return (CGWindowID)self.regionFrameWindow.windowNumber;
    }
    if (self.windowNumber > 0) {
        return (CGWindowID)self.windowNumber;
    }
    return kCGNullWindowID;
}

- (void)updateElapsedSeconds:(NSTimeInterval)elapsed {
    NSInteger totalSeconds = (NSInteger)floor(MAX(0.0, elapsed));
    NSInteger mins = totalSeconds / 60;
    NSInteger secs = totalSeconds % 60;
    self.timerLabel.stringValue = [NSString stringWithFormat:@"%02ld:%02ld", (long)mins, (long)secs];
}

- (void)setPaused:(BOOL)paused {
    self.isPausedState = paused;
    self.recordingDot.layer.backgroundColor = (paused
        ? [NSColor colorWithSRGBRed:0.96 green:0.68 blue:0.18 alpha:1.0]
        : [CSTheme danger]).CGColor;
    self.pauseButton.title = paused ? @"Resume" : @"Pause";
    NSString *sym = paused ? @"play.fill" : @"pause.fill";
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:self.pauseButton.title];
    if (img != nil) {
        self.pauseButton.image = img;
    }
    self.regionBorderView.paused = paused;
    [self.regionBorderView setNeedsDisplay:YES];
}

- (void)pauseResumeClicked:(id)sender {
    if (self.onPauseResume != nil) {
        self.onPauseResume();
    }
}

- (void)stopClicked:(id)sender {
    if (self.onStop != nil) {
        self.onStop();
    }
}

- (void)cancelClicked:(id)sender {
    if (self.onCancel != nil) {
        self.onCancel();
    }
}

- (void)minimizeHUDClicked:(id)sender {
    self.isMinimizedHUD = !self.isMinimizedHUD;
    if (self.isMinimizedHUD) {
        self.expandedHUDFrame = self.frame;
        self.micPill.hidden = YES;
        self.smoothPill.hidden = YES;
        self.pauseButton.hidden = YES;
        self.stopButton.frame = NSMakeRect(92, 8, 62, 28);
        self.minimizeButton.frame = NSMakeRect(156, 8, 26, 28);
        self.cancelButton.frame = NSMakeRect(184, 8, 26, 28);
        NSImage *expandImg = [NSImage imageWithSystemSymbolName:@"arrow.up.left.and.arrow.down.right" accessibilityDescription:@"Expand recording controls"];
        if (expandImg != nil) {
            self.minimizeButton.image = expandImg;
        } else {
            self.minimizeButton.title = @"+";
        }
        self.minimizeButton.toolTip = @"Expand recording controls";
        self.regionFrameWindow.alphaValue = 0.0;
        CGFloat miniW = 220.0;
        CGFloat miniH = 44.0;
        CGFloat cornerX = NSMaxX(self.targetVisibleFrame) - miniW - 16.0;
        CGFloat cornerY = NSMinY(self.targetVisibleFrame) + 16.0;
        [self setFrame:NSMakeRect(cornerX, cornerY, miniW, miniH) display:YES animate:YES];
    } else {
        self.micPill.hidden = NO;
        self.smoothPill.hidden = NO;
        self.pauseButton.hidden = NO;
        self.stopButton.frame = NSMakeRect(312, 8, 66, 28);
        self.minimizeButton.frame = NSMakeRect(382, 8, 26, 28);
        self.cancelButton.frame = NSMakeRect(410, 8, 26, 28);
        NSImage *minusImg = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:@"Minimize recording controls"];
        if (minusImg != nil) {
            self.minimizeButton.image = minusImg;
        } else {
            self.minimizeButton.title = @"—";
        }
        self.minimizeButton.toolTip = @"Minimize recording controls to corner";
        self.regionFrameWindow.alphaValue = 1.0;
        [self setFrame:self.expandedHUDFrame display:YES animate:YES];
    }
}

- (void)cancelOperation:(id)sender {
    [self cancelClicked:sender];
}

- (void)dismissAllOverlays {
    self.onPauseResume = nil;
    self.onStop = nil;
    self.onCancel = nil;
    if (self.regionFrameWindow != nil) {
        [self.regionFrameWindow orderOut:nil];
        self.regionFrameWindow.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
        [self.regionFrameWindow close];
        self.regionFrameWindow = nil;
    }
    self.regionBorderView = nil;
    [self orderOut:nil];
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    [self close];
}

@end
