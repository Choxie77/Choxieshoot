#import "ColorInspectorView.h"
#import "CSColorFormatter.h"
#import "CSTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface ColorInspectorView ()

@property (nonatomic, strong) NSVisualEffectView *glassBackdrop;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSButton *lockStatusButton;
@property (nonatomic, strong) NSView *swatch;
@property (nonatomic, strong) NSTextField *hexLabel;
@property (nonatomic, strong) NSTextField *rgbLabel;
@property (nonatomic, strong) NSTextField *hsbLabel;
@property (nonatomic, strong) NSTextField *hslLabel;
@property (nonatomic, strong) NSButton *hexCopyButton;
@property (nonatomic, strong) NSButton *rgbCopyButton;
@property (nonatomic, strong, nullable, readwrite) NSColor *currentColor;
@property (nonatomic, readwrite) BOOL isLocked;
@property (nonatomic) BOOL draggingHeader;
@property (nonatomic) NSPoint dragStartInSuperview;
@property (nonatomic) NSPoint initialOrigin;

@end

@implementation ColorInspectorView

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

    self.titleLabel = [NSTextField labelWithString:@"COLOR INSPECTOR"];
    self.titleLabel.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold];
    self.titleLabel.textColor = [CSTheme accent];
    self.titleLabel.frame = NSMakeRect(14, 128, 130, 12);
    [self addSubview:self.titleLabel];

    self.lockStatusButton = [NSButton buttonWithTitle:@"CLICK TO LOCK" target:self action:@selector(lockBadgeClicked:)];
    self.lockStatusButton.bordered = NO;
    self.lockStatusButton.wantsLayer = YES;
    self.lockStatusButton.layer.cornerRadius = 5.0;
    self.lockStatusButton.layer.borderWidth = 1.0;
    self.lockStatusButton.font = [NSFont systemFontOfSize:8.5 weight:NSFontWeightBold];
    self.lockStatusButton.frame = NSMakeRect(138, 124, 90, 18);
    [self addSubview:self.lockStatusButton];

    self.swatch = [[NSView alloc] initWithFrame:NSMakeRect(14, 62, 50, 50)];
    self.swatch.wantsLayer = YES;
    self.swatch.layer.cornerRadius = 10.0;
    self.swatch.layer.borderWidth = 1.5;
    self.swatch.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.65].CGColor;
    self.swatch.layer.backgroundColor = [[NSColor clearColor] CGColor];
    [self addSubview:self.swatch];

    self.hexLabel = [self valueLabelWithFrame:NSMakeRect(72, 108, 156, 18)
                                         font:[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightBold]];
    self.rgbLabel = [self valueLabelWithFrame:NSMakeRect(72, 90, 156, 14)
                                         font:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium]];
    self.hsbLabel = [self valueLabelWithFrame:NSMakeRect(72, 74, 156, 14)
                                         font:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular]];
    self.hslLabel = [self valueLabelWithFrame:NSMakeRect(72, 58, 156, 14)
                                         font:[NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular]];

    self.hexCopyButton = [self copyButtonWithTitle:@"Copy HEX" action:@selector(copyHex:)];
    self.hexCopyButton.frame = NSMakeRect(14, 14, 102, 26);
    if (@available(macOS 11.0, *)) {
        self.hexCopyButton.bezelColor = [CSTheme accent];
    }
    self.rgbCopyButton = [self copyButtonWithTitle:@"Copy RGB" action:@selector(copyRGB:)];
    self.rgbCopyButton.frame = NSMakeRect(124, 14, 102, 26);
    [self addSubview:self.hexCopyButton];
    [self addSubview:self.rgbCopyButton];

    [self updateLockUI];
    [self updateWithColor:nil];
}

- (void)lockBadgeClicked:(id)sender {
    if (self.onToggleLock != nil) {
        self.onToggleLock();
    } else if (self.isLocked) {
        [self setLocked:NO animated:YES];
    }
}

- (void)updateLockUI {
    if (self.isLocked) {
        self.lockStatusButton.title = @"🔒 LOCKED";
        self.lockStatusButton.contentTintColor = [CSTheme onAccent];
        self.lockStatusButton.layer.backgroundColor = [CSTheme accent].CGColor;
        self.lockStatusButton.layer.borderColor = [CSTheme accent].CGColor;
        self.layer.borderWidth = 1.8;
        self.layer.borderColor = [CSTheme accent].CGColor;
        self.swatch.layer.borderWidth = 2.2;
        self.swatch.layer.borderColor = [CSTheme accent].CGColor;
    } else {
        self.lockStatusButton.title = @"CLICK TO LOCK";
        self.lockStatusButton.contentTintColor = [CSTheme mutedText];
        self.lockStatusButton.layer.backgroundColor = [CSTheme pillSurface].CGColor;
        self.lockStatusButton.layer.borderColor = [CSTheme border].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [CSTheme border].CGColor;
        self.swatch.layer.borderWidth = 1.5;
        self.swatch.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.65].CGColor;
    }
}

- (void)setLocked:(BOOL)locked animated:(BOOL)animated {
    _isLocked = locked;
    [self updateLockUI];
    if (animated) {
        [self playLockAnimation:locked];
    }
}

- (void)playLockAnimation:(BOOL)locking {
    // 1. Swatch & HEX label scale pulse
    CAKeyframeAnimation *pop = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    if (locking) {
        pop.values = @[@1.0, @1.16, @0.96, @1.03, @1.0];
        pop.keyTimes = @[@0.0, @0.32, @0.65, @0.85, @1.0];
        pop.duration = 0.34;
    } else {
        pop.values = @[@1.0, @0.94, @1.0];
        pop.keyTimes = @[@0.0, @0.45, @1.0];
        pop.duration = 0.20;
    }
    pop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.swatch.layer addAnimation:pop forKey:@"lockPop"];
    [self.lockStatusButton.layer addAnimation:pop forKey:@"badgePop"];

    if (locking) {
        // 2. Expanding shockwave ring from the colour swatch
        CALayer *ring = [CALayer layer];
        NSRect swatchFrame = self.swatch.frame;
        ring.frame = swatchFrame;
        ring.cornerRadius = 10.0;
        ring.borderWidth = 2.5;
        ring.borderColor = [CSTheme accent].CGColor;
        ring.backgroundColor = [NSColor clearColor].CGColor;
        [self.layer addSublayer:ring];

        CABasicAnimation *boundsAnim = [CABasicAnimation animationWithKeyPath:@"bounds"];
        boundsAnim.fromValue = [NSValue valueWithRect:NSMakeRect(0, 0, NSWidth(swatchFrame), NSHeight(swatchFrame))];
        boundsAnim.toValue = [NSValue valueWithRect:NSMakeRect(0, 0, NSWidth(swatchFrame) + 24.0, NSHeight(swatchFrame) + 24.0)];

        CABasicAnimation *cornerAnim = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        cornerAnim.fromValue = @(10.0);
        cornerAnim.toValue = @(18.0);

        CABasicAnimation *fadeAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fadeAnim.fromValue = @(0.95);
        fadeAnim.toValue = @(0.0);

        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[boundsAnim, cornerAnim, fadeAnim];
        group.duration = 0.38;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        group.removedOnCompletion = NO;
        group.fillMode = kCAFillModeForwards;
        [ring addAnimation:group forKey:@"ringRipple"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.40 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [ring removeFromSuperlayer];
        });
    }
}

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

- (NSTextField *)valueLabelWithFrame:(NSRect)frame font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:@"—"];
    label.font = font;
    label.textColor = [CSTheme text];
    label.frame = frame;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:label];
    return label;
}

- (NSButton *)copyButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightSemibold];
    return button;
}

- (void)updateWithColor:(NSColor *)color {
    self.currentColor = color;
    BOOL hasColor = color != nil;
    self.hexCopyButton.enabled = hasColor;
    self.rgbCopyButton.enabled = hasColor;

    if (!hasColor) {
        self.swatch.layer.backgroundColor = [[NSColor clearColor] CGColor];
        self.hexLabel.stringValue = @"Hover the image";
        self.rgbLabel.stringValue = @"Click to lock colour";
        self.hsbLabel.stringValue = @"";
        self.hslLabel.stringValue = @"";
        return;
    }

    self.swatch.layer.backgroundColor = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]].CGColor;
    self.hexLabel.stringValue = [CSColorFormatter hexStringFromColor:color];
    self.rgbLabel.stringValue = [CSColorFormatter rgbStringFromColor:color];
    self.hsbLabel.stringValue = [CSColorFormatter hsbStringFromColor:color];
    self.hslLabel.stringValue = [CSColorFormatter hslStringFromColor:color];
}

- (void)copyHex:(NSButton *)sender {
    if (self.currentColor == nil) {
        return;
    }
    [self copyString:[CSColorFormatter hexStringFromColor:self.currentColor] button:sender restoreTitle:@"Copy HEX"];
}

- (void)copyRGB:(NSButton *)sender {
    if (self.currentColor == nil) {
        return;
    }
    [self copyString:[CSColorFormatter rgbStringFromColor:self.currentColor] button:sender restoreTitle:@"Copy RGB"];
}

- (void)copyString:(NSString *)string button:(NSButton *)button restoreTitle:(NSString *)restoreTitle {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:string forType:NSPasteboardTypeString];

    button.title = @"Copied!";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        button.title = restoreTitle;
    });
}

@end
