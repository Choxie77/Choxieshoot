#import "TextOptionsView.h"
#import "CSTheme.h"

@interface TextOptionsView ()

@property (nonatomic, strong) NSVisualEffectView *glassBackdrop;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *hintLabel;

// Text controls
@property (nonatomic, strong) NSView *textGroup;
@property (nonatomic, strong) NSSlider *sizeSlider;
@property (nonatomic, strong) NSTextField *sizeValueLabel;
@property (nonatomic, strong) NSButton *boldCheckbox;
@property (nonatomic, strong) NSButton *backgroundCheckbox;

// Spotlight controls
@property (nonatomic, strong) NSView *spotlightGroup;
@property (nonatomic, strong) NSSegmentedControl *spotlightShapeSegment;
@property (nonatomic, strong) NSSlider *spotlightDimSlider;
@property (nonatomic, strong) NSTextField *spotlightDimValueLabel;
@property (nonatomic, strong) NSButton *spotlightFeatherCheckbox;

// Contextual segmented control (Redact / Arrow / Rect / Callout / Loupe)
@property (nonatomic, strong) NSView *contextGroup;
@property (nonatomic, strong) NSSegmentedControl *contextSegment;
@property (nonatomic, strong) NSSlider *loupeSlider;
@property (nonatomic, strong) NSTextField *loupeValueLabel;
@property (nonatomic) ToolType activeContextTool;

@property (nonatomic) BOOL updating;
@property (nonatomic) BOOL draggingHeader;
@property (nonatomic) NSPoint dragStartInSuperview;
@property (nonatomic) NSPoint initialOrigin;

@end

@implementation TextOptionsView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        [self build];
    }
    return self;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)build {
    self.wantsLayer = YES;
    self.layer.cornerRadius = CSRadiusLarge;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [CSTheme border].CGColor;
    self.layer.shadowColor = [NSColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.28;
    self.layer.shadowRadius = 12.0;
    self.layer.shadowOffset = CGSizeMake(0, -4);

    self.glassBackdrop = [CSTheme glassViewWithFrame:self.bounds
                                            material:NSVisualEffectMaterialHUDWindow
                                        cornerRadius:CSRadiusLarge];
    self.glassBackdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:self.glassBackdrop];

    self.titleLabel = [NSTextField labelWithString:@"TEXT OPTIONS"];
    self.titleLabel.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold];
    self.titleLabel.textColor = [CSTheme accent];
    self.titleLabel.frame = NSMakeRect(14, 134, 200, 13);
    [self addSubview:self.titleLabel];

    [self buildTextGroup];
    [self buildSpotlightGroup];
    [self buildContextGroup];

    self.hintLabel = [NSTextField labelWithString:@"Click canvas to type. Return commits;\nShift+Return adds line. Double-click edits."];
    self.hintLabel.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightRegular];
    self.hintLabel.textColor = [CSTheme mutedText];
    self.hintLabel.frame = NSMakeRect(14, 10, 206, 28);
    self.hintLabel.maximumNumberOfLines = 2;
    self.hintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self addSubview:self.hintLabel];
}

- (void)buildTextGroup {
    self.textGroup = [[NSView alloc] initWithFrame:NSMakeRect(0, 40, 234, 90)];
    [self addSubview:self.textGroup];

    NSTextField *sizeLabel = [NSTextField labelWithString:@"Size"];
    sizeLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    sizeLabel.textColor = [CSTheme mutedText];
    sizeLabel.frame = NSMakeRect(14, 62, 38, 14);
    [self.textGroup addSubview:sizeLabel];

    self.sizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(52, 59, 120, 20)];
    self.sizeSlider.minValue = 10;
    self.sizeSlider.maxValue = 72;
    self.sizeSlider.doubleValue = 18;
    self.sizeSlider.target = self;
    self.sizeSlider.action = @selector(sizeChanged:);
    [self.textGroup addSubview:self.sizeSlider];

    self.sizeValueLabel = [NSTextField labelWithString:@"18 pt"];
    self.sizeValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightSemibold];
    self.sizeValueLabel.textColor = [CSTheme text];
    self.sizeValueLabel.alignment = NSTextAlignmentRight;
    self.sizeValueLabel.frame = NSMakeRect(176, 62, 42, 14);
    [self.textGroup addSubview:self.sizeValueLabel];

    self.boldCheckbox = [NSButton checkboxWithTitle:@"Bold weight" target:self action:@selector(styleChanged:)];
    self.boldCheckbox.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    self.boldCheckbox.state = NSControlStateValueOn;
    self.boldCheckbox.frame = NSMakeRect(14, 32, 100, 20);
    [self.textGroup addSubview:self.boldCheckbox];

    self.backgroundCheckbox = [NSButton checkboxWithTitle:@"Pill backdrop" target:self action:@selector(styleChanged:)];
    self.backgroundCheckbox.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    self.backgroundCheckbox.state = NSControlStateValueOff;
    self.backgroundCheckbox.frame = NSMakeRect(116, 32, 108, 20);
    [self.textGroup addSubview:self.backgroundCheckbox];
}

- (void)buildSpotlightGroup {
    self.spotlightGroup = [[NSView alloc] initWithFrame:NSMakeRect(0, 40, 234, 90)];
    self.spotlightGroup.hidden = YES;
    [self addSubview:self.spotlightGroup];

    self.spotlightShapeSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Rounded", @"Circle", @"Pill"]
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:@selector(spotlightChanged:)];
    self.spotlightShapeSegment.controlSize = NSControlSizeSmall;
    self.spotlightShapeSegment.selectedSegment = 0;
    self.spotlightShapeSegment.frame = NSMakeRect(14, 62, 202, 22);
    [self.spotlightGroup addSubview:self.spotlightShapeSegment];

    NSTextField *dimLabel = [NSTextField labelWithString:@"Dim"];
    dimLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    dimLabel.textColor = [CSTheme mutedText];
    dimLabel.frame = NSMakeRect(14, 34, 36, 14);
    [self.spotlightGroup addSubview:dimLabel];

    self.spotlightDimSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(50, 31, 120, 20)];
    self.spotlightDimSlider.minValue = 0.25;
    self.spotlightDimSlider.maxValue = 0.85;
    self.spotlightDimSlider.doubleValue = 0.58;
    self.spotlightDimSlider.target = self;
    self.spotlightDimSlider.action = @selector(spotlightChanged:);
    [self.spotlightGroup addSubview:self.spotlightDimSlider];

    self.spotlightDimValueLabel = [NSTextField labelWithString:@"58%"];
    self.spotlightDimValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightSemibold];
    self.spotlightDimValueLabel.textColor = [CSTheme text];
    self.spotlightDimValueLabel.alignment = NSTextAlignmentRight;
    self.spotlightDimValueLabel.frame = NSMakeRect(174, 34, 42, 14);
    [self.spotlightGroup addSubview:self.spotlightDimValueLabel];

    self.spotlightFeatherCheckbox = [NSButton checkboxWithTitle:@"Soft feather & glow rim"
                                                         target:self
                                                         action:@selector(spotlightChanged:)];
    self.spotlightFeatherCheckbox.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    self.spotlightFeatherCheckbox.state = NSControlStateValueOn;
    self.spotlightFeatherCheckbox.frame = NSMakeRect(14, 6, 196, 20);
    [self.spotlightGroup addSubview:self.spotlightFeatherCheckbox];
}

- (void)buildContextGroup {
    self.contextGroup = [[NSView alloc] initWithFrame:NSMakeRect(0, 40, 234, 90)];
    self.contextGroup.hidden = YES;
    [self addSubview:self.contextGroup];

    self.contextSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Option 1", @"Option 2"]
                                                            trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                  target:self
                                                                  action:@selector(contextSegmentChanged:)];
    self.contextSegment.controlSize = NSControlSizeSmall;
    self.contextSegment.selectedSegment = 0;
    self.contextSegment.frame = NSMakeRect(14, 54, 202, 24);
    [self.contextGroup addSubview:self.contextSegment];

    self.loupeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(14, 52, 152, 20)];
    self.loupeSlider.minValue = 1.5;
    self.loupeSlider.maxValue = 4.0;
    self.loupeSlider.doubleValue = 2.2;
    self.loupeSlider.target = self;
    self.loupeSlider.action = @selector(loupeSliderChanged:);
    self.loupeSlider.hidden = YES;
    [self.contextGroup addSubview:self.loupeSlider];

    self.loupeValueLabel = [NSTextField labelWithString:@"2.2×"];
    self.loupeValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold];
    self.loupeValueLabel.textColor = [CSTheme text];
    self.loupeValueLabel.alignment = NSTextAlignmentRight;
    self.loupeValueLabel.frame = NSMakeRect(172, 55, 44, 15);
    self.loupeValueLabel.hidden = YES;
    [self.contextGroup addSubview:self.loupeValueLabel];
}

#pragma mark - Header dragging

- (void)mouseDown:(NSEvent *)event {
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    if (local.y >= NSHeight(self.bounds) - 34.0) {
        self.draggingHeader = YES;
        self.dragStartInSuperview = [self.superview convertPoint:event.locationInWindow fromView:nil];
        self.initialOrigin = self.frame.origin;
        return;
    }
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.draggingHeader || self.superview == nil) {
        [super mouseDragged:event];
        return;
    }
    NSPoint current = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = current.x - self.dragStartInSuperview.x;
    CGFloat dy = current.y - self.dragStartInSuperview.y;
    NSRect superBounds = self.superview.bounds;
    CGFloat newX = MIN(MAX(self.initialOrigin.x + dx, 6.0), MAX(6.0, NSWidth(superBounds) - NSWidth(self.frame) - 6.0));
    CGFloat newY = MIN(MAX(self.initialOrigin.y + dy, 6.0), MAX(6.0, NSHeight(superBounds) - NSHeight(self.frame) - 6.0));
    [self setFrameOrigin:NSMakePoint(newX, newY)];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.draggingHeader) {
        self.draggingHeader = NO;
        return;
    }
    [super mouseUp:event];
}

#pragma mark - Modes

- (void)setFontSize:(CGFloat)fontSize bold:(BOOL)bold background:(BOOL)background {
    self.updating = YES;
    self.titleLabel.stringValue = @"TEXT OPTIONS";
    self.textGroup.hidden = NO;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = YES;
    self.sizeSlider.doubleValue = fontSize;
    self.sizeValueLabel.stringValue = [NSString stringWithFormat:@"%ld pt", (long)lround(fontSize)];
    self.boldCheckbox.state = bold ? NSControlStateValueOn : NSControlStateValueOff;
    self.backgroundCheckbox.state = background ? NSControlStateValueOn : NSControlStateValueOff;
    self.hintLabel.stringValue = @"Click canvas to type. Return commits;\nShift+Return adds line. Double-click edits.";
    self.updating = NO;
}

- (void)configureForSpotlightShape:(CSSpotlightShape)shape dimOpacity:(CGFloat)dimOpacity feather:(BOOL)feather {
    self.updating = YES;
    self.titleLabel.stringValue = @"SPOTLIGHT FOCUS";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = NO;
    self.contextGroup.hidden = YES;
    self.spotlightShapeSegment.selectedSegment = (NSInteger)shape;
    self.spotlightDimSlider.doubleValue = dimOpacity;
    self.spotlightDimValueLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)lround(dimOpacity * 100.0)];
    self.spotlightFeatherCheckbox.state = feather ? NSControlStateValueOn : NSControlStateValueOff;
    self.hintLabel.stringValue = @"Drag to highlight multiple areas.\nClick an existing spotlight to move or resize.";
    self.updating = NO;
}

- (void)configureForRedactMode:(CSRedactMode)mode {
    self.updating = YES;
    self.activeContextTool = ToolTypePixelate;
    self.titleLabel.stringValue = @"REDACTION STYLE";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = NO;
    self.contextSegment.hidden = NO;
    self.loupeSlider.hidden = YES;
    self.loupeValueLabel.hidden = YES;
    [self.contextSegment setLabel:@"Mosaic Pixelate" forSegment:0];
    [self.contextSegment setLabel:@"Frosted Blur" forSegment:1];
    self.contextSegment.selectedSegment = (NSInteger)mode;
    self.hintLabel.stringValue = @"Drag over sensitive text or faces.\nStroke width adjusts mosaic/blur strength.";
    self.updating = NO;
}

- (void)configureForArrowCurved:(BOOL)curved {
    self.updating = YES;
    self.activeContextTool = ToolTypeArrow;
    self.titleLabel.stringValue = @"ARROW STYLE";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = NO;
    self.contextSegment.hidden = NO;
    self.loupeSlider.hidden = YES;
    self.loupeValueLabel.hidden = YES;
    [self.contextSegment setLabel:@"Straight" forSegment:0];
    [self.contextSegment setLabel:@"Curved Arc" forSegment:1];
    self.contextSegment.selectedSegment = curved ? 1 : 0;
    self.hintLabel.stringValue = @"Hold Shift to snap angles.\nSelect an arrow to drag its curve handle.";
    self.updating = NO;
}

- (void)configureForRectangleRounded:(BOOL)rounded {
    self.updating = YES;
    self.activeContextTool = ToolTypeRectangle;
    self.titleLabel.stringValue = @"RECTANGLE CORNERS";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = NO;
    self.contextSegment.hidden = NO;
    self.loupeSlider.hidden = YES;
    self.loupeValueLabel.hidden = YES;
    [self.contextSegment setLabel:@"Sharp Corners" forSegment:0];
    [self.contextSegment setLabel:@"Rounded Box" forSegment:1];
    self.contextSegment.selectedSegment = rounded ? 1 : 0;
    self.hintLabel.stringValue = @"Hold Option (⌥) or press F to fill.\nHold Shift for a perfect square.";
    self.updating = NO;
}

- (void)configureForCalloutSpeechBubble:(BOOL)speechBubble {
    self.updating = YES;
    self.activeContextTool = ToolTypeCallout;
    self.titleLabel.stringValue = @"CALLOUT STYLE";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = NO;
    self.contextSegment.hidden = NO;
    self.loupeSlider.hidden = YES;
    self.loupeValueLabel.hidden = YES;
    [self.contextSegment setLabel:@"Step Badge (1,2…)" forSegment:0];
    [self.contextSegment setLabel:@"Speech Bubble" forSegment:1];
    self.contextSegment.selectedSegment = speechBubble ? 1 : 0;
    self.hintLabel.stringValue = @"Click to place or drag to add a pointer tail.\nSpeech bubbles open an inline label editor.";
    self.updating = NO;
}

- (void)configureForLoupeMagnification:(CGFloat)magnification {
    self.updating = YES;
    self.activeContextTool = ToolTypeLoupe;
    self.titleLabel.stringValue = @"MAGNIFIER LOUPE";
    self.textGroup.hidden = YES;
    self.spotlightGroup.hidden = YES;
    self.contextGroup.hidden = NO;
    self.contextSegment.hidden = YES;
    self.loupeSlider.hidden = NO;
    self.loupeValueLabel.hidden = NO;
    self.loupeSlider.doubleValue = magnification;
    self.loupeValueLabel.stringValue = [NSString stringWithFormat:@"%.1f×", magnification];
    self.hintLabel.stringValue = @"Click or drag to place a zoom lens.\nUse Select (V) to reposition or resize.";
    self.updating = NO;
}

#pragma mark - Actions

- (void)sizeChanged:(NSSlider *)sender {
    self.sizeValueLabel.stringValue = [NSString stringWithFormat:@"%ld pt", (long)lround(sender.doubleValue)];
    [self notifyChange];
}

- (void)styleChanged:(id)sender {
    [self notifyChange];
}

- (void)notifyChange {
    if (self.updating || self.onChange == nil) {
        return;
    }
    self.onChange((CGFloat)self.sizeSlider.doubleValue,
                  self.boldCheckbox.state == NSControlStateValueOn,
                  self.backgroundCheckbox.state == NSControlStateValueOn);
}

- (void)spotlightChanged:(id)sender {
    if (self.updating) {
        return;
    }
    CGFloat dim = (CGFloat)self.spotlightDimSlider.doubleValue;
    self.spotlightDimValueLabel.stringValue = [NSString stringWithFormat:@"%ld%%", (long)lround(dim * 100.0)];
    if (self.onSpotlightChange != nil) {
        self.onSpotlightChange((CSSpotlightShape)self.spotlightShapeSegment.selectedSegment,
                               dim,
                               self.spotlightFeatherCheckbox.state == NSControlStateValueOn);
    }
}

- (void)contextSegmentChanged:(NSSegmentedControl *)sender {
    if (self.updating) {
        return;
    }
    NSInteger idx = sender.selectedSegment;
    switch (self.activeContextTool) {
        case ToolTypePixelate:
            if (self.onRedactChange != nil) {
                self.onRedactChange((CSRedactMode)idx);
            }
            break;
        case ToolTypeArrow:
            if (self.onArrowChange != nil) {
                self.onArrowChange(idx == 1);
            }
            break;
        case ToolTypeRectangle:
            if (self.onRectChange != nil) {
                self.onRectChange(idx == 1);
            }
            break;
        case ToolTypeCallout:
            if (self.onCalloutChange != nil) {
                self.onCalloutChange(idx == 1);
            }
            break;
        default:
            break;
    }
}

- (void)loupeSliderChanged:(NSSlider *)sender {
    if (self.updating) {
        return;
    }
    CGFloat mag = (CGFloat)sender.doubleValue;
    self.loupeValueLabel.stringValue = [NSString stringWithFormat:@"%.1f×", mag];
    if (self.onLoupeChange != nil) {
        self.onLoupeChange(mag);
    }
}

@end
