#import "ToolbarView.h"
#import "CSTheme.h"

static const CGFloat kToolSize = 26.0;
static const CGFloat kToolSpacing = 2.0;
static const CGFloat kActionSize = 27.0;
static const CGFloat kActionSpacing = 4.0;
static const CGFloat kMargin = 10.0;
static const CGFloat kSwatchSize = 14.0;
static const CGFloat kSwatchSpacing = 3.0;
static const CGFloat kCompactThreshold = 1110.0;

#pragma mark - Live Stroke Preview View

@interface CSStrokePreviewView : NSView
@property (nonatomic, strong) NSColor *strokeColor;
@property (nonatomic) CGFloat lineWidth;
@end

@implementation CSStrokePreviewView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _strokeColor = [NSColor systemRedColor];
        _lineWidth = 3.0;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat maxDiam = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) - 3.0;
    CGFloat diameter = MIN(MAX(self.lineWidth + 2.0, 3.5), maxDiam);
    NSRect dotRect = NSMakeRect(NSMidX(self.bounds) - diameter * 0.5,
                                NSMidY(self.bounds) - diameter * 0.5,
                                diameter,
                                diameter);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:dotRect];
    [(self.strokeColor ?: [CSTheme accent]) setFill];
    [circle fill];
    [[[NSColor whiteColor] colorWithAlphaComponent:0.55] setStroke];
    circle.lineWidth = 0.75;
    [circle stroke];
}

@end

#pragma mark - Animated OCR Loading View

@interface CSOCRLoadingView : NSView
@property (nonatomic, strong, nullable) NSTimer *animationTimer;
@property (nonatomic) NSTimeInterval startTime;
@property (nonatomic) BOOL animating;
- (void)startAnimating;
- (void)stopAnimating;
@end

@implementation CSOCRLoadingView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.wantsLayer = YES;
        self.hidden = YES;
    }
    return self;
}

- (void)dealloc {
    [_animationTimer invalidate];
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)startAnimating {
    if (self.animating) {
        return;
    }
    self.animating = YES;
    self.hidden = NO;
    self.startTime = [NSDate timeIntervalSinceReferenceDate];
    [self.animationTimer invalidate];
    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:(1.0 / 60.0) repeats:YES block:^(NSTimer * _Nonnull t) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || !strongSelf.animating) {
            [t invalidate];
            return;
        }
        [strongSelf setNeedsDisplay:YES];
    }];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.animationTimer = timer;
    [self setNeedsDisplay:YES];
}

- (void)stopAnimating {
    self.animating = NO;
    [self.animationTimer invalidate];
    self.animationTimer = nil;
    self.hidden = YES;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (!self.animating) {
        return;
    }

    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - self.startTime;
    NSPoint center = NSMakePoint(NSMidX(self.bounds), NSMidY(self.bounds));
    CGFloat radius = MIN(NSWidth(self.bounds), NSHeight(self.bounds)) * 0.5 - 4.5;
    if (radius < 4.0) {
        return;
    }

    NSColor *accent = [CSTheme accent];

    // 1. Subtle outer circular track
    NSBezierPath *track = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - radius,
                                                                            center.y - radius,
                                                                            radius * 2.0,
                                                                            radius * 2.0)];
    track.lineWidth = 1.75;
    [[accent colorWithAlphaComponent:0.20] setStroke];
    [track stroke];

    // 2. Indeterminate rotating arc with breathing sweep angle
    CGFloat baseAngle = (CGFloat)fmod(elapsed * 420.0, 360.0);
    CGFloat sweep = 95.0 + 55.0 * (0.5 + 0.5 * sin(elapsed * 4.8));
    CGFloat startAngle = -baseAngle;
    CGFloat endAngle = startAngle - sweep;

    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc appendBezierPathWithArcWithCenter:center
                                    radius:radius
                                startAngle:startAngle
                                  endAngle:endAngle
                                 clockwise:YES];
    arc.lineWidth = 2.1;
    arc.lineCapStyle = NSLineCapStyleRound;
    [accent setStroke];
    [arc stroke];

    // 3. Inner mini text lines + sweeping horizontal OCR scan beam
    CGFloat boxHalfW = 3.6;
    CGFloat boxHalfH = 3.2;
    for (NSInteger i = -1; i <= 1; i++) {
        CGFloat lineY = center.y + i * 2.2;
        CGFloat lineW = (i == 1) ? boxHalfW * 1.35 : boxHalfW * 1.85;
        NSRect lineRect = NSMakeRect(center.x - boxHalfW * 0.92, lineY - 0.55, lineW, 1.1);
        NSBezierPath *textLine = [NSBezierPath bezierPathWithRoundedRect:lineRect xRadius:0.55 yRadius:0.55];
        [[accent colorWithAlphaComponent:0.42] setFill];
        [textLine fill];
    }

    // Oscillating scan bar sweeping up and down across the mini text lines
    CGFloat scanPhase = 0.5 + 0.5 * sin(elapsed * 6.5);
    CGFloat scanY = (center.y - boxHalfH) + scanPhase * (boxHalfH * 2.0);
    NSRect glowRect = NSMakeRect(center.x - boxHalfW - 1.2, scanY - 1.4, (boxHalfW + 1.2) * 2.0, 2.8);
    NSBezierPath *glowBar = [NSBezierPath bezierPathWithRoundedRect:glowRect xRadius:1.4 yRadius:1.4];
    [[accent colorWithAlphaComponent:0.28] setFill];
    [glowBar fill];

    NSRect beamRect = NSMakeRect(center.x - boxHalfW - 0.8, scanY - 0.65, (boxHalfW + 0.8) * 2.0, 1.3);
    NSBezierPath *beamBar = [NSBezierPath bezierPathWithRoundedRect:beamRect xRadius:0.65 yRadius:0.65];
    [accent setFill];
    [beamBar fill];
}

@end

#pragma mark - Hover-aware icon button

@interface CSIconButton : NSButton
@property (nonatomic) BOOL hovered;
@property (nonatomic) BOOL busy;
@property (nonatomic, strong, nullable) NSColor *defaultTintColor;
@end

@implementation CSIconButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        self.bordered = NO;
        self.bezelStyle = NSBezelStyleInline;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 7.0;
        self.focusRingType = NSFocusRingTypeExterior;
    }
    return self;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in [self trackingAreas]) {
        if (area.owner == self && (area.options & NSTrackingMouseEnteredAndExited)) {
            [self removeTrackingArea:area];
        }
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                       options:(NSTrackingMouseEnteredAndExited |
                                                                NSTrackingActiveInKeyWindow |
                                                                NSTrackingInVisibleRect)
                                                         owner:self
                                                      userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    self.hovered = YES;
}

- (void)mouseExited:(NSEvent *)event {
    self.hovered = NO;
}

- (void)setHovered:(BOOL)hovered {
    _hovered = hovered;
    [self updateBackground];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.alphaValue = (self.isEnabled || busy) ? 1.0 : 0.35;
    [self updateBackground];
}

- (void)setState:(NSControlStateValue)state {
    [super setState:state];
    [self updateBackground];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alphaValue = (enabled || self.busy) ? 1.0 : 0.35;
    [self updateBackground];
}

- (void)updateBackground {
    if (self.layer == nil) {
        return;
    }
    NSColor *background = [NSColor clearColor];
    self.layer.borderWidth = 0.0;
    if (self.busy) {
        background = [CSTheme selectedToolBackground];
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [CSTheme selectedToolBorder].CGColor;
        self.contentTintColor = [CSTheme accent];
    } else if (self.isEnabled) {
        if (self.state == NSControlStateValueOn) {
            background = [CSTheme selectedToolBackground];
            self.layer.borderWidth = 1.0;
            self.layer.borderColor = [CSTheme selectedToolBorder].CGColor;
            self.contentTintColor = [CSTheme accent];
        } else if (self.hovered) {
            background = [CSTheme hoverBackground];
            self.contentTintColor = self.defaultTintColor ?: [CSTheme text];
        } else {
            self.contentTintColor = self.defaultTintColor;
        }
    }
    self.layer.backgroundColor = background.CGColor;
}

@end

#pragma mark - ToolbarView

@interface ToolbarView ()

@property (nonatomic, strong) NSVisualEffectView *backdropView;
@property (nonatomic, strong) NSView *toolsCapsule;
@property (nonatomic, strong) NSView *paletteCapsule;
@property (nonatomic, strong) NSView *actionsCapsule;

@property (nonatomic, strong) NSMutableArray<CSIconButton *> *toolButtons;
@property (nonatomic, strong) NSArray<NSNumber *> *toolOrder;
@property (nonatomic, strong) CSIconButton *fillButton;
@property (nonatomic, strong) CSIconButton *dashedButton;
@property (nonatomic, strong) CSIconButton *shadowButton;
@property (nonatomic, strong) NSMutableArray<NSButton *> *swatchButtons;
@property (nonatomic, strong) NSMutableArray<NSView *> *separators;
@property (nonatomic, strong) NSColorWell *colorWell;
@property (nonatomic, strong) NSTextField *colorLabel;
@property (nonatomic, strong) CSStrokePreviewView *strokePreview;
@property (nonatomic, strong) NSSlider *lineWidthSlider;
@property (nonatomic, strong) NSTextField *lineWidthLabel;
@property (nonatomic, strong) CSIconButton *undoButton;
@property (nonatomic, strong) CSIconButton *redoButton;
@property (nonatomic, strong) CSIconButton *ocrButton;
@property (nonatomic, strong) CSOCRLoadingView *ocrLoadingView;
@property (nonatomic, strong) CSIconButton *captureButton;
@property (nonatomic, strong) CSIconButton *duplicateButton;
@property (nonatomic, strong) CSIconButton *saveButton;
@property (nonatomic, strong) CSIconButton *shareButton;
@property (nonatomic, strong) CSIconButton *pinButton;
@property (nonatomic, strong) CSIconButton *minimizeButton;
@property (nonatomic, strong) CSIconButton *closeButton;
@property (nonatomic, strong) NSArray<NSColor *> *predefinedColors;
@property (nonatomic, strong) NSView *topBorder;
@property (nonatomic, strong) NSImage *ocrIdleImage;
@property (nonatomic, strong) NSString *ocrIdleTooltip;
@property (nonatomic, readwrite, getter=isOCRBusy) BOOL ocrBusy;
@property (nonatomic) BOOL ocrActive;

@end

@implementation ToolbarView

+ (BOOL)usesCompactLayoutForWidth:(CGFloat)width {
    return width < kCompactThreshold;
}

+ (CGFloat)preferredHeightForWidth:(CGFloat)width {
    return [self usesCompactLayoutForWidth:width] ? 98.0 : 62.0;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self commonInit];
    }
    return self;
}

- (NSView *)makeCapsuleContainer {
    NSView *capsule = [[NSView alloc] initWithFrame:NSZeroRect];
    capsule.wantsLayer = YES;
    capsule.layer.backgroundColor = [CSTheme pillSurface].CGColor;
    capsule.layer.cornerRadius = 9.0;
    capsule.layer.borderWidth = 1.0;
    capsule.layer.borderColor = [CSTheme subtleBorder].CGColor;
    [self addSubview:capsule];
    return capsule;
}

- (void)commonInit {
    self.wantsLayer = YES;

    self.backdropView = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    self.backdropView.material = NSVisualEffectMaterialHeaderView;
    self.backdropView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.backdropView.state = NSVisualEffectStateActive;
    self.backdropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:self.backdropView];

    self.toolsCapsule = [self makeCapsuleContainer];
    self.paletteCapsule = [self makeCapsuleContainer];
    self.actionsCapsule = [self makeCapsuleContainer];

    _toolButtons = [NSMutableArray array];
    _swatchButtons = [NSMutableArray array];
    _separators = [NSMutableArray array];
    _predefinedColors = @[
        [NSColor colorWithSRGBRed:0.96 green:0.23 blue:0.27 alpha:1.0],
        [NSColor colorWithSRGBRed:1.00 green:0.58 blue:0.12 alpha:1.0],
        [NSColor colorWithSRGBRed:0.99 green:0.82 blue:0.16 alpha:1.0],
        [NSColor colorWithSRGBRed:0.20 green:0.82 blue:0.46 alpha:1.0],
        [NSColor colorWithSRGBRed:0.18 green:0.81 blue:0.73 alpha:1.0],
        [NSColor colorWithSRGBRed:0.22 green:0.56 blue:0.98 alpha:1.0],
        [NSColor colorWithSRGBRed:0.68 green:0.36 blue:0.96 alpha:1.0],
        [NSColor whiteColor]
    ];
    _toolOrder = @[
        @(ToolTypeSelect),
        @(ToolTypePencil),
        @(ToolTypeLine),
        @(ToolTypeArrow),
        @(ToolTypeRectangle),
        @(ToolTypeEllipse),
        @(ToolTypeMarker),
        @(ToolTypeText),
        @(ToolTypeCallout),
        @(ToolTypeSpotlight),
        @(ToolTypeLoupe),
        @(ToolTypePixelate),
        @(ToolTypeCrop),
        @(ToolTypeColorPicker),
        @(ToolTypeEraser)
    ];
    _currentTool = ToolTypePencil;
    _currentColor = [NSColor systemRedColor];
    _currentLineWidth = 3.0;

    self.topBorder = [[NSView alloc] initWithFrame:NSZeroRect];
    self.topBorder.wantsLayer = YES;
    self.topBorder.layer.backgroundColor = [CSTheme border].CGColor;
    [self addSubview:self.topBorder];

    for (NSInteger i = 0; i < 4; i++) {
        [self makeSeparator];
    }

    [self buildToolButtons];
    [self buildColorControls];
    [self buildWidthControls];
    [self buildActionButtons];
    [self updateToolButtons];
    [self updateColorSwatches];
}

#pragma mark - Building

- (CSIconButton *)iconButtonWithSymbol:(NSString *)symbolName
                               tooltip:(NSString *)tooltip
                                action:(SEL)action {
    CSIconButton *button = [[CSIconButton alloc] initWithFrame:NSZeroRect];
    button.imageScaling = NSImageScaleProportionallyDown;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:tooltip];
    if (image != nil) {
        NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                          weight:NSFontWeightMedium];
        button.image = [image imageWithSymbolConfiguration:cfg] ?: image;
        button.imagePosition = NSImageOnly;
    } else {
        button.title = [tooltip substringToIndex:MIN(1, tooltip.length)];
    }
    button.toolTip = tooltip;
    [button setAccessibilityLabel:tooltip];
    button.target = self;
    button.action = action;
    return button;
}

static NSString *ToolTypeShortcutName(ToolType type) {
    switch (type) {
        case ToolTypeSelect:     return @"Select, Move & Resize (V or ⌘-drag)";
        case ToolTypePencil:     return @"Smooth Freehand Pencil (P)";
        case ToolTypeLine:       return @"Line (L)";
        case ToolTypeArrow:      return @"Arrow — Straight or Curved (A)";
        case ToolTypeRectangle:  return @"Rectangle / Rounded Box (R)";
        case ToolTypeEllipse:    return @"Ellipse / Circle (E)";
        case ToolTypeMarker:     return @"Highlighter (H)";
        case ToolTypeText:       return @"Text Annotation (T)";
        case ToolTypePixelate:   return @"Redact — Pixelate or Blur (B)";
        case ToolTypeCallout:    return @"Step Badge / Speech Callout (N)";
        case ToolTypeSpotlight:  return @"Spotlight Focus (S)";
        case ToolTypeLoupe:      return @"Magnifier Loupe (Z)";
        case ToolTypeCrop:       return @"Crop Canvas (K)";
        case ToolTypeColorPicker:return @"Colour Picker & Inspector (C)";
        case ToolTypeEraser:     return @"Eraser (X)";
    }
    return @"Tool";
}

- (void)buildToolButtons {
    for (NSNumber *num in self.toolOrder) {
        ToolType tool = (ToolType)num.integerValue;
        NSString *name = ToolTypeShortcutName(tool);
        CSIconButton *button = [self iconButtonWithSymbol:ToolTypeSymbolName(tool)
                                                  tooltip:name
                                                   action:@selector(toolClicked:)];
        [button setButtonType:NSButtonTypePushOnPushOff];
        button.tag = tool;
        [self addSubview:button];
        [self.toolButtons addObject:button];
    }

    self.fillButton = [self iconButtonWithSymbol:@"square.fill"
                                         tooltip:@"Fill Shapes (F or hold ⌥)"
                                          action:@selector(fillClicked:)];
    [self.fillButton setButtonType:NSButtonTypePushOnPushOff];
    self.fillButton.state = NSControlStateValueOff;
    [self addSubview:self.fillButton];

    self.dashedButton = [self iconButtonWithSymbol:@"line.diagonal.arrow"
                                           tooltip:@"Dashed Stroke / Curved Arrow"
                                            action:@selector(dashedClicked:)];
    NSImage *dashImg = [NSImage imageWithSystemSymbolName:@"ellipsis" accessibilityDescription:@"Dashed Stroke"];
    if (dashImg != nil) {
        self.dashedButton.image = dashImg;
    }
    [self.dashedButton setButtonType:NSButtonTypePushOnPushOff];
    self.dashedButton.state = NSControlStateValueOff;
    [self addSubview:self.dashedButton];

    self.shadowButton = [self iconButtonWithSymbol:@"square.filled.on.square"
                                           tooltip:@"Drop Shadow on Annotations (W)"
                                            action:@selector(shadowClicked:)];
    NSImage *shadowImg = [self dropShadowIconImage];
    if (shadowImg != nil) {
        self.shadowButton.image = shadowImg;
    }
    [self.shadowButton setButtonType:NSButtonTypePushOnPushOff];
    self.shadowButton.state = NSControlStateValueOff;
    [self addSubview:self.shadowButton];
}

- (NSImage *)dropShadowIconImage {
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *img = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        // Offset shadow behind (bottom-right)
        NSRect shadowRect = NSMakeRect(4.5, 2.0, 10.5, 10.5);
        NSBezierPath *shadowPath = [NSBezierPath bezierPathWithRoundedRect:shadowRect xRadius:2.2 yRadius:2.2];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.40] setFill];
        [shadowPath fill];

        // Foreground square (top-left)
        NSRect frontRect = NSMakeRect(2.0, 4.5, 10.5, 10.5);
        NSBezierPath *frontPath = [NSBezierPath bezierPathWithRoundedRect:frontRect xRadius:2.2 yRadius:2.2];
        
        [NSGraphicsContext saveGraphicsState];
        [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositingOperationClear];
        [[NSColor clearColor] set];
        [frontPath fill];
        [NSGraphicsContext restoreGraphicsState];

        [[NSColor blackColor] setStroke];
        frontPath.lineWidth = 1.4;
        [frontPath stroke];

        return YES;
    }];
    [img setTemplate:YES];
    return img;
}

- (NSView *)makeSeparator {
    NSView *separator = [[NSView alloc] initWithFrame:NSZeroRect];
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [CSTheme border].CGColor;
    [self addSubview:separator];
    [self.separators addObject:separator];
    return separator;
}

- (void)buildColorControls {
    self.colorLabel = [NSTextField labelWithString:@"Color"];
    self.colorLabel.font = [NSFont systemFontOfSize:10];
    self.colorLabel.textColor = [CSTheme mutedText];
    [self addSubview:self.colorLabel];

    self.colorWell = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    self.colorWell.color = self.currentColor;
    self.colorWell.target = self;
    self.colorWell.action = @selector(colorChanged:);
    self.colorWell.toolTip = @"Custom colour";
    [self.colorWell setAccessibilityLabel:@"Custom colour"];
    [self addSubview:self.colorWell];

    for (NSInteger index = 0; index < (NSInteger)self.predefinedColors.count; index++) {
        NSColor *color = self.predefinedColors[index];
        NSButton *swatch = [[NSButton alloc] initWithFrame:NSZeroRect];
        swatch.bordered = NO;
        swatch.title = @"";
        swatch.tag = index;
        swatch.target = self;
        swatch.action = @selector(swatchClicked:);
        swatch.wantsLayer = YES;
        swatch.layer.backgroundColor = color.CGColor;
        swatch.layer.cornerRadius = kSwatchSize * 0.5;
        swatch.layer.borderWidth = 1.0;
        swatch.layer.borderColor = [CSTheme border].CGColor;
        swatch.toolTip = [NSString stringWithFormat:@"Color %ld", (long)(index + 1)];
        [swatch setAccessibilityLabel:swatch.toolTip];
        [self addSubview:swatch];
        [self.swatchButtons addObject:swatch];
    }
}

- (void)buildWidthControls {
    self.strokePreview = [[CSStrokePreviewView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
    self.strokePreview.strokeColor = self.currentColor;
    self.strokePreview.lineWidth = self.currentLineWidth;
    [self addSubview:self.strokePreview];

    self.lineWidthLabel = [NSTextField labelWithString:@"3px"];
    self.lineWidthLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium];
    self.lineWidthLabel.textColor = [CSTheme mutedText];
    self.lineWidthLabel.alignment = NSTextAlignmentRight;
    [self addSubview:self.lineWidthLabel];

    self.lineWidthSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    self.lineWidthSlider.minValue = 1.0;
    self.lineWidthSlider.maxValue = 20.0;
    self.lineWidthSlider.doubleValue = self.currentLineWidth;
    self.lineWidthSlider.target = self;
    self.lineWidthSlider.action = @selector(lineWidthChanged:);
    self.lineWidthSlider.toolTip = @"Stroke width ([ and ] or scroll wheel)";
    [self.lineWidthSlider setAccessibilityLabel:@"Stroke width"];
    [self addSubview:self.lineWidthSlider];
}

- (void)buildActionButtons {
    self.undoButton = [self iconButtonWithSymbol:@"arrow.uturn.backward" tooltip:@"Undo (⌘Z)" action:@selector(undoClicked:)];
    self.redoButton = [self iconButtonWithSymbol:@"arrow.uturn.forward" tooltip:@"Redo (⇧⌘Z)" action:@selector(redoClicked:)];
    self.ocrButton = [self iconButtonWithSymbol:@"text.viewfinder" tooltip:@"Recognize & Select Text — OCR (⇧⌘C)" action:@selector(copyTextClicked:)];
    [self.ocrButton setButtonType:NSButtonTypePushOnPushOff];
    self.ocrButton.defaultTintColor = [CSTheme accent];
    self.ocrButton.contentTintColor = [CSTheme accent];
    self.ocrLoadingView = [[CSOCRLoadingView alloc] initWithFrame:NSMakeRect(0, 0, kActionSize, kActionSize)];
    self.ocrLoadingView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.ocrButton addSubview:self.ocrLoadingView];
    self.captureButton = [self iconButtonWithSymbol:@"camera.viewfinder" tooltip:@"New Screenshot (⌘N)" action:@selector(newCaptureClicked:)];
    self.ocrIdleImage = self.ocrButton.image;
    self.ocrIdleTooltip = self.ocrButton.toolTip;
    self.duplicateButton = [self iconButtonWithSymbol:@"doc.on.doc" tooltip:@"Copy Image (⌘C)" action:@selector(copyClicked:)];
    self.saveButton = [self iconButtonWithSymbol:@"square.and.arrow.down" tooltip:@"Save PNG (⌘S)" action:@selector(saveClicked:)];
    self.shareButton = [self iconButtonWithSymbol:@"square.and.arrow.up" tooltip:@"Share…" action:@selector(shareClicked:)];
    self.pinButton = [self iconButtonWithSymbol:@"pin" tooltip:@"Keep Window on Top" action:@selector(pinClicked:)];
    [self.pinButton setButtonType:NSButtonTypePushOnPushOff];
    self.pinButton.state = NSControlStateValueOff;
    self.minimizeButton = [self iconButtonWithSymbol:@"minus" tooltip:@"Minimize Window (⌘M)" action:@selector(minimizeClicked:)];
    self.closeButton = [self iconButtonWithSymbol:@"xmark" tooltip:@"Cancel / Close (Esc)" action:@selector(closeClicked:)];
    self.closeButton.defaultTintColor = [CSTheme danger];
    self.closeButton.contentTintColor = [CSTheme danger];

    for (CSIconButton *button in @[self.undoButton, self.redoButton, self.ocrButton,
                                   self.duplicateButton, self.saveButton, self.shareButton,
                                   self.captureButton, self.pinButton, self.minimizeButton,
                                   self.closeButton]) {
        [self addSubview:button];
    }
    self.undoButton.enabled = NO;
    self.redoButton.enabled = NO;
}

#pragma mark - OCR busy state

- (void)setOCRBusy:(BOOL)busy {
    _ocrBusy = busy;
    if (busy) {
        self.ocrButton.busy = YES;
        self.ocrButton.enabled = NO;
        self.ocrButton.image = nil;
        self.ocrButton.toolTip = @"Recognizing text…";
        self.ocrLoadingView.frame = self.ocrButton.bounds;
        [self.ocrLoadingView startAnimating];
    } else {
        [self.ocrLoadingView stopAnimating];
        self.ocrButton.busy = NO;
        self.ocrButton.enabled = YES;
        self.ocrButton.image = self.ocrIdleImage;
        self.ocrButton.toolTip = self.ocrIdleTooltip;
        self.ocrButton.state = self.ocrActive ? NSControlStateValueOn : NSControlStateValueOff;
        self.ocrButton.contentTintColor = [CSTheme accent];
    }
}

- (void)setOCRActive:(BOOL)active {
    _ocrActive = active;
    self.ocrButton.state = active ? NSControlStateValueOn : NSControlStateValueOff;
    self.ocrButton.contentTintColor = [CSTheme accent];
    [self updateToolButtons];
}

#pragma mark - Layout

- (void)layout {
    [super layout];
    [self repositionSubviews];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self repositionSubviews];
}

- (void)repositionSubviews {
    CGFloat height = NSHeight(self.bounds);
    CGFloat width = NSWidth(self.bounds);
    if (height <= 0 || width <= 0) {
        return;
    }

    self.backdropView.frame = self.bounds;
    self.topBorder.frame = NSMakeRect(0, height - 1.0, width, 1.0);

    BOOL compact = [ToolbarView usesCompactLayoutForWidth:width];
    for (NSView *separator in self.separators) {
        separator.hidden = YES;
    }
    self.colorLabel.hidden = YES;

    if (!compact) {
        [self layoutSingleRowWithHeight:height width:width];
    } else {
        [self layoutTwoRowsWithHeight:height width:width];
    }
    self.ocrLoadingView.frame = self.ocrButton.bounds;
}

- (void)layoutSingleRowWithHeight:(CGFloat)height width:(CGFloat)width {
    CGFloat x = kMargin + 4.0;
    CGFloat toolY = floor((height - kToolSize) / 2.0);
    CGFloat toolsStart = x - 4.0;

    for (CSIconButton *button in self.toolButtons) {
        button.frame = NSMakeRect(x, toolY, kToolSize, kToolSize);
        x += kToolSize + kToolSpacing;
    }

    x += 2.0;
    self.fillButton.frame = NSMakeRect(x, toolY, kToolSize, kToolSize);
    x += kToolSize + kToolSpacing;
    self.dashedButton.frame = NSMakeRect(x, toolY, kToolSize, kToolSize);
    x += kToolSize + kToolSpacing;
    self.shadowButton.frame = NSMakeRect(x, toolY, kToolSize, kToolSize);
    x += kToolSize + 4.0;

    self.toolsCapsule.frame = NSMakeRect(toolsStart, floor((height - 34.0) / 2.0), x - toolsStart, 34.0);
    x += 8.0;

    CGFloat paletteStart = x;
    x += 6.0;
    self.colorWell.frame = NSMakeRect(x, floor((height - 22.0) / 2.0), 22.0, 22.0);
    x += 25.0;

    for (NSButton *swatch in self.swatchButtons) {
        swatch.frame = NSMakeRect(x, floor((height - kSwatchSize) / 2.0), kSwatchSize, kSwatchSize);
        x += kSwatchSize + kSwatchSpacing;
    }

    x += 4.0;
    self.strokePreview.frame = NSMakeRect(x, floor((height - 20.0) / 2.0), 20.0, 20.0);
    x += 20.0;
    self.lineWidthLabel.frame = NSMakeRect(x, floor((height - 14.0) / 2.0), 25.0, 14.0);
    x += 27.0;
    self.lineWidthSlider.frame = NSMakeRect(x, floor((height - 20.0) / 2.0), 54.0, 20.0);
    x += 60.0;

    self.paletteCapsule.frame = NSMakeRect(paletteStart, floor((height - 34.0) / 2.0), x - paletteStart, 34.0);

    // Actions are right aligned
    CGFloat right = width - kMargin - 4.0;
    NSArray<CSIconButton *> *ordered = @[self.closeButton, self.minimizeButton, self.pinButton,
                                        self.captureButton, self.shareButton,
                                        self.saveButton, self.duplicateButton, self.ocrButton,
                                        self.redoButton, self.undoButton];
    CGFloat actionsEnd = right + 4.0;
    for (CSIconButton *button in ordered) {
        button.frame = NSMakeRect(right - kActionSize, floor((height - kActionSize) / 2.0), kActionSize, kActionSize);
        right -= kActionSize + kActionSpacing;
    }
    CGFloat actionsStart = right + kActionSpacing - 4.0;
    self.actionsCapsule.frame = NSMakeRect(actionsStart, floor((height - 34.0) / 2.0), actionsEnd - actionsStart, 34.0);
}

- (void)layoutTwoRowsWithHeight:(CGFloat)height width:(CGFloat)width {
    CGFloat topRowCenter = height - 29.0;
    CGFloat bottomRowCenter = 25.0;

    // Top row: all drawing tools + style modifiers centered in a sleek capsule
    NSInteger count = self.toolButtons.count + 3;
    CGFloat toolsContentW = count * kToolSize + (count - 1) * kToolSpacing + 4.0;
    CGFloat topX = MAX(kMargin + 4.0, floor((width - toolsContentW) / 2.0));
    CGFloat toolsStart = topX - 5.0;
    CGFloat toolY = floor(topRowCenter - kToolSize / 2.0);

    for (CSIconButton *button in self.toolButtons) {
        button.frame = NSMakeRect(topX, toolY, kToolSize, kToolSize);
        topX += kToolSize + kToolSpacing;
    }
    topX += 2.0;
    self.fillButton.frame = NSMakeRect(topX, toolY, kToolSize, kToolSize);
    topX += kToolSize + kToolSpacing;
    self.dashedButton.frame = NSMakeRect(topX, toolY, kToolSize, kToolSize);
    topX += kToolSize + kToolSpacing;
    self.shadowButton.frame = NSMakeRect(topX, toolY, kToolSize, kToolSize);
    topX += kToolSize + 5.0;

    self.toolsCapsule.frame = NSMakeRect(toolsStart, floor(topRowCenter - 17.0), topX - toolsStart, 34.0);

    // Bottom row: Palette capsule on left + Actions capsule on right
    NSArray<CSIconButton *> *ordered = @[self.undoButton, self.redoButton, self.ocrButton,
                                        self.duplicateButton, self.saveButton, self.shareButton,
                                        self.captureButton, self.pinButton, self.minimizeButton,
                                        self.closeButton];
    CGFloat actionsW = ordered.count * kActionSize + (ordered.count - 1) * kActionSpacing + 10.0;
    CGFloat swatchesW = self.swatchButtons.count * (kSwatchSize + kSwatchSpacing);
    CGFloat paletteW = 12.0 + 24.0 + swatchesW + 4.0 + 20.0 + 26.0 + 58.0 + 8.0;
    CGFloat totalBottomW = paletteW + 10.0 + actionsW;
    CGFloat bx = MAX(kMargin, floor((width - totalBottomW) / 2.0));

    CGFloat paletteStart = bx;
    bx += 6.0;
    self.colorWell.frame = NSMakeRect(bx, floor(bottomRowCenter - 11.0), 22.0, 22.0);
    bx += 25.0;
    for (NSButton *swatch in self.swatchButtons) {
        swatch.frame = NSMakeRect(bx, floor(bottomRowCenter - kSwatchSize / 2.0), kSwatchSize, kSwatchSize);
        bx += kSwatchSize + kSwatchSpacing;
    }
    bx += 2.0;
    self.strokePreview.frame = NSMakeRect(bx, floor(bottomRowCenter - 10.0), 20.0, 20.0);
    bx += 20.0;
    self.lineWidthLabel.frame = NSMakeRect(bx, floor(bottomRowCenter - 7.0), 25.0, 14.0);
    bx += 27.0;
    self.lineWidthSlider.frame = NSMakeRect(bx, floor(bottomRowCenter - 10.0), 56.0, 20.0);
    bx += 62.0;
    self.paletteCapsule.frame = NSMakeRect(paletteStart, floor(bottomRowCenter - 17.0), bx - paletteStart, 34.0);

    bx += 10.0;
    CGFloat actionsStart = bx;
    bx += 5.0;
    CGFloat actionY = floor(bottomRowCenter - kActionSize / 2.0);
    for (CSIconButton *button in ordered) {
        button.frame = NSMakeRect(bx, actionY, kActionSize, kActionSize);
        bx += kActionSize + kActionSpacing;
    }
    bx += 5.0 - kActionSpacing;
    self.actionsCapsule.frame = NSMakeRect(actionsStart, floor(bottomRowCenter - 17.0), bx - actionsStart, 34.0);
}

#pragma mark - State

- (void)setCurrentTool:(ToolType)currentTool {
    _currentTool = currentTool;
    [self updateToolButtons];
}

- (void)setCurrentColor:(NSColor *)currentColor {
    _currentColor = currentColor ?: [NSColor systemRedColor];
    self.colorWell.color = _currentColor;
    self.strokePreview.strokeColor = _currentColor;
    [self.strokePreview setNeedsDisplay:YES];
    [self updateColorSwatches];
}

- (void)setCurrentLineWidth:(CGFloat)currentLineWidth {
    _currentLineWidth = currentLineWidth;
    self.lineWidthSlider.doubleValue = currentLineWidth;
    self.lineWidthLabel.stringValue = [NSString stringWithFormat:@"%ldpx", (long)lround(currentLineWidth)];
    self.strokePreview.lineWidth = currentLineWidth;
    [self.strokePreview setNeedsDisplay:YES];
}

- (void)setShapeFilled:(BOOL)shapeFilled {
    _shapeFilled = shapeFilled;
    self.fillButton.state = shapeFilled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setShapeDashed:(BOOL)shapeDashed {
    _shapeDashed = shapeDashed;
    self.dashedButton.state = shapeDashed ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setShapeShadow:(BOOL)shapeShadow {
    _shapeShadow = shapeShadow;
    self.shadowButton.state = shapeShadow ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)setPinnedOnTop:(BOOL)pinnedOnTop {
    _pinnedOnTop = pinnedOnTop;
    self.pinButton.state = pinnedOnTop ? NSControlStateValueOn : NSControlStateValueOff;
    NSString *sym = pinnedOnTop ? @"pin.fill" : @"pin";
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:@"Keep Window on Top"];
    if (img != nil) {
        NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:13.0
                                                                                          weight:NSFontWeightMedium];
        self.pinButton.image = [img imageWithSymbolConfiguration:cfg] ?: img;
    }
}

- (void)fillClicked:(CSIconButton *)sender {
    _shapeFilled = (sender.state == NSControlStateValueOn);
    if ([self.delegate respondsToSelector:@selector(toolbarView:didChangeShapeFilled:)]) {
        [self.delegate toolbarView:self didChangeShapeFilled:_shapeFilled];
    }
}

- (void)dashedClicked:(CSIconButton *)sender {
    _shapeDashed = (sender.state == NSControlStateValueOn);
    if ([self.delegate respondsToSelector:@selector(toolbarView:didChangeShapeDashed:)]) {
        [self.delegate toolbarView:self didChangeShapeDashed:_shapeDashed];
    }
}

- (void)shadowClicked:(CSIconButton *)sender {
    _shapeShadow = (sender.state == NSControlStateValueOn);
    if ([self.delegate respondsToSelector:@selector(toolbarView:didChangeShapeShadow:)]) {
        [self.delegate toolbarView:self didChangeShapeShadow:_shapeShadow];
    }
}

- (void)setCanUndo:(BOOL)canUndo {
    _canUndo = canUndo;
    self.undoButton.enabled = canUndo;
}

- (void)setCanRedo:(BOOL)canRedo {
    _canRedo = canRedo;
    self.redoButton.enabled = canRedo;
}

- (void)updateToolButtons {
    for (CSIconButton *button in self.toolButtons) {
        button.state = (!self.ocrActive && button.tag == self.currentTool) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)updateColorSwatches {
    NSInteger index = 0;
    NSColor *curr = [self.currentColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    for (NSButton *swatch in self.swatchButtons) {
        if (index >= (NSInteger)self.predefinedColors.count) {
            break;
        }
        NSColor *swatchColor = [self.predefinedColors[index] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        BOOL selected = NO;
        if (curr != nil && swatchColor != nil) {
            selected = (fabs(curr.redComponent - swatchColor.redComponent) < 0.08 &&
                        fabs(curr.greenComponent - swatchColor.greenComponent) < 0.08 &&
                        fabs(curr.blueComponent - swatchColor.blueComponent) < 0.08);
        }
        swatch.layer.borderWidth = selected ? 2.2 : 1.0;
        swatch.layer.borderColor = (selected ? [NSColor whiteColor] : [CSTheme border]).CGColor;
        index++;
    }
}

#pragma mark - Actions

- (void)toolClicked:(CSIconButton *)sender {
    self.currentTool = (ToolType)sender.tag;
    [self.delegate toolbarView:self didSelectTool:self.currentTool];
}

- (void)colorChanged:(NSColorWell *)sender {
    self.currentColor = sender.color;
    [self.delegate toolbarView:self didSelectColor:sender.color];
}

- (void)swatchClicked:(NSButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.predefinedColors.count) {
        return;
    }
    NSColor *color = self.predefinedColors[sender.tag];
    self.currentColor = color;
    [self.delegate toolbarView:self didSelectColor:color];
}

- (void)lineWidthChanged:(NSSlider *)sender {
    self.currentLineWidth = (CGFloat)sender.doubleValue;
    [self.delegate toolbarView:self didChangeLineWidth:self.currentLineWidth];
}

- (void)undoClicked:(id)sender {
    [self.delegate toolbarViewDidRequestUndo:self];
}

- (void)redoClicked:(id)sender {
    [self.delegate toolbarViewDidRequestRedo:self];
}

- (void)copyTextClicked:(id)sender {
    [self.delegate toolbarViewDidRequestCopyText:self];
}

- (void)newCaptureClicked:(id)sender {
    [self.delegate toolbarViewDidRequestNewCapture:self];
}

- (void)saveClicked:(id)sender {
    [self.delegate toolbarViewDidRequestSave:self];
}

- (void)copyClicked:(id)sender {
    [self.delegate toolbarViewDidRequestCopy:self];
}

- (void)shareClicked:(id)sender {
    [self.delegate toolbarViewDidRequestShare:self];
}

- (void)pinClicked:(CSIconButton *)sender {
    BOOL nextPinned = (sender.state == NSControlStateValueOn);
    self.pinnedOnTop = nextPinned;
    if ([self.delegate respondsToSelector:@selector(toolbarView:didChangePinnedOnTop:)]) {
        [self.delegate toolbarView:self didChangePinnedOnTop:nextPinned];
    }
}

- (void)minimizeClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(toolbarViewDidRequestMinimize:)]) {
        [self.delegate toolbarViewDidRequestMinimize:self];
    }
}

- (void)closeClicked:(id)sender {
    [self.delegate toolbarViewDidRequestClose:self];
}

@end
