#import "LauncherWindow.h"
#import "CSTheme.h"
#import <malloc/malloc.h>

@interface LauncherWindow () <NSWindowDelegate>

@property (nonatomic, copy) LauncherActionBlock newCaptureBlock;
@property (nonatomic, copy) LauncherActionBlock delayedBlock;
@property (nonatomic, copy) LauncherActionBlock fullScreenBlock;
@property (nonatomic, copy) LauncherActionBlock grantBlock;
@property (nonatomic, copy) LauncherActionBlock checkBlock;
@property (nonatomic, copy) LauncherActionBlock restartBlock;
@property (nonatomic, copy) LauncherActionBlock resetBlock;

@property (nonatomic, strong) NSView *permissionCard;
@property (nonatomic, strong) NSView *statusDot;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *detailLabel;
@property (nonatomic, strong) NSButton *grantButton;
@property (nonatomic, strong) NSButton *checkButton;
@property (nonatomic, strong) NSButton *delayedButton;
@property (nonatomic) BOOL granted;

@end

@implementation LauncherWindow

- (instancetype)initWithNewCapture:(LauncherActionBlock)newCapture
                     delayedCapture:(LauncherActionBlock)delayed
                        fullScreen:(LauncherActionBlock)fullScreen
                   grantPermission:(LauncherActionBlock)grant
                     checkPermission:(LauncherActionBlock)check
                        restartBlock:(LauncherActionBlock)restart
                          resetBlock:(LauncherActionBlock)reset {
    NSRect contentRect = NSMakeRect(0, 0, 500, 420);
    self = [super initWithContentRect:contentRect
                            styleMask:(NSWindowStyleMaskTitled |
                                       NSWindowStyleMaskClosable |
                                       NSWindowStyleMaskMiniaturizable |
                                       NSWindowStyleMaskFullSizeContentView |
                                       NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil) {
        return nil;
    }

    self.title = @"Choxieshoot";
    self.titlebarAppearsTransparent = YES;
    self.titleVisibility = NSWindowTitleHidden;
    self.floatingPanel = NO;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.level = NSNormalWindowLevel;
    self.movableByWindowBackground = YES;
    self.releasedWhenClosed = NO;
    self.backgroundColor = [CSTheme surface];
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    self.delegate = self;
    [self enableTrafficLightMinimizeButton];

    _newCaptureBlock = [newCapture copy];
    _delayedBlock = [delayed copy];
    _fullScreenBlock = [fullScreen copy];
    _grantBlock = [grant copy];
    _checkBlock = [check copy];
    _restartBlock = [restart copy];
    _resetBlock = [reset copy];

    NSVisualEffectView *root = [[NSVisualEffectView alloc] initWithFrame:contentRect];
    root.material = NSVisualEffectMaterialUnderWindowBackground;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateActive;
    root.wantsLayer = YES;
    root.layer.backgroundColor = [CSTheme surface].CGColor;
    self.contentView = root;

    [self buildContentInView:root];
    [self updateScreenRecordingGranted:NO];
    return self;
}

- (NSTextField *)labelWithString:(NSString *)string
                            font:(NSFont *)font
                           color:(NSColor *)color
                           frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.textColor = color;
    label.frame = frame;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (NSButton *)actionButtonWithTitle:(NSString *)title symbol:(nullable NSString *)symbolName frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    if (symbolName != nil) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title];
        if (img != nil) {
            button.image = img;
            button.imagePosition = NSImageLeading;
        }
    }
    button.frame = frame;
    return button;
}

- (void)buildContentInView:(NSView *)content {
    // Hero icon badge
    NSView *heroBadge = [[NSView alloc] initWithFrame:NSMakeRect(24, 336, 44, 44)];
    heroBadge.wantsLayer = YES;
    heroBadge.layer.backgroundColor = [CSTheme selectedToolBackground].CGColor;
    heroBadge.layer.cornerRadius = 12.0;
    heroBadge.layer.borderWidth = 1.0;
    heroBadge.layer.borderColor = [CSTheme selectedToolBorder].CGColor;
    NSImageView *heroIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(9, 9, 26, 26)];
    NSImage *camImg = [NSImage imageWithSystemSymbolName:@"camera.viewfinder" accessibilityDescription:@"Choxieshoot"];
    if (camImg != nil) {
        heroIcon.image = camImg;
        heroIcon.contentTintColor = [CSTheme accent];
    }
    [heroBadge addSubview:heroIcon];
    [content addSubview:heroBadge];

    NSTextField *heading = [self labelWithString:@"Capture. Annotate. Copy."
                                            font:[NSFont systemFontOfSize:22 weight:NSFontWeightBold]
                                           color:[CSTheme text]
                                           frame:NSMakeRect(80, 354, 396, 28)];
    [content addSubview:heading];

    NSTextField *subtitle = [self labelWithString:@"Fast, private screenshot & screen video studio for macOS — 100% local."
                                             font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                            color:[CSTheme mutedText]
                                            frame:NSMakeRect(80, 334, 396, 18)];
    [content addSubview:subtitle];

    // Top-right explicit Minimize and Cancel buttons alongside native macOS traffic lights
    NSButton *minimizeHeaderBtn = [self actionButtonWithTitle:@"Minimize"
                                                       symbol:@"minus"
                                                        frame:NSMakeRect(334, 386, 74, 24)
                                                       action:@selector(minimizeLauncherClicked:)];
    minimizeHeaderBtn.controlSize = NSControlSizeSmall;
    minimizeHeaderBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    minimizeHeaderBtn.toolTip = @"Minimize Window (⌘M)";
    [content addSubview:minimizeHeaderBtn];

    NSButton *closeHeaderBtn = [self actionButtonWithTitle:@"Cancel"
                                                    symbol:@"xmark"
                                                     frame:NSMakeRect(412, 386, 64, 24)
                                                    action:@selector(closeLauncherClicked:)];
    closeHeaderBtn.controlSize = NSControlSizeSmall;
    closeHeaderBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    closeHeaderBtn.toolTip = @"Close Window (Esc or ⌘W)";
    [content addSubview:closeHeaderBtn];

    self.permissionCard = [[NSView alloc] initWithFrame:NSMakeRect(24, 182, 452, 136)];
    self.permissionCard.wantsLayer = YES;
    self.permissionCard.layer.backgroundColor = [CSTheme pillSurface].CGColor;
    self.permissionCard.layer.cornerRadius = CSRadiusLarge;
    self.permissionCard.layer.borderWidth = 1.0;
    self.permissionCard.layer.borderColor = [CSTheme border].CGColor;
    [content addSubview:self.permissionCard];

    self.statusDot = [[NSView alloc] initWithFrame:NSMakeRect(18, 108, 10, 10)];
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 5.0;
    [self.permissionCard addSubview:self.statusDot];

    self.statusLabel = [self labelWithString:@"Screen Recording: checking…"
                                        font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                       color:[CSTheme text]
                                       frame:NSMakeRect(36, 104, 270, 18)];
    [self.permissionCard addSubview:self.statusLabel];

    self.detailLabel = [self labelWithString:@""
                                        font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                       color:[CSTheme mutedText]
                                       frame:NSMakeRect(18, 48, 286, 46)];
    self.detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.detailLabel.maximumNumberOfLines = 2;
    [self.permissionCard addSubview:self.detailLabel];

    self.grantButton = [self actionButtonWithTitle:@"Grant Access"
                                            symbol:nil
                                             frame:NSMakeRect(318, 98, 118, 28)
                                            action:@selector(grantClicked:)];
    [self.permissionCard addSubview:self.grantButton];

    self.checkButton = [self actionButtonWithTitle:@"Check Again"
                                            symbol:nil
                                             frame:NSMakeRect(318, 70, 118, 24)
                                            action:@selector(checkClicked:)];
    [self.permissionCard addSubview:self.checkButton];

    NSButton *restartButton = [self actionButtonWithTitle:@"Restart App"
                                                   symbol:nil
                                                    frame:NSMakeRect(318, 42, 118, 24)
                                                   action:@selector(restartClicked:)];
    [self.permissionCard addSubview:restartButton];

    NSButton *resetButton = [self actionButtonWithTitle:@"Reset Access"
                                                 symbol:nil
                                                  frame:NSMakeRect(318, 14, 118, 24)
                                                 action:@selector(resetClicked:)];
    [self.permissionCard addSubview:resetButton];

    NSButton *newButton = [self actionButtonWithTitle:@"Screenshot"
                                               symbol:@"viewfinder"
                                                frame:NSMakeRect(24, 124, 108, 36)
                                               action:@selector(newCaptureClicked:)];
    newButton.bezelColor = [CSTheme accent];
    newButton.keyEquivalent = @"\r";
    [content addSubview:newButton];

    NSButton *videoButton = [self actionButtonWithTitle:@"Record"
                                                 symbol:@"video.fill"
                                                  frame:NSMakeRect(138, 124, 92, 36)
                                                 action:@selector(recordVideoClicked:)];
    [content addSubview:videoButton];

    NSButton *editVideoButton = [self actionButtonWithTitle:@"Edit Video…"
                                                     symbol:@"folder.badge.gearshape"
                                                      frame:NSMakeRect(236, 124, 110, 36)
                                                     action:@selector(openVideoClicked:)];
    [content addSubview:editVideoButton];

    self.delayedButton = [self actionButtonWithTitle:@"3s Delay"
                                              symbol:@"timer"
                                               frame:NSMakeRect(352, 124, 76, 36)
                                              action:@selector(delayedClicked:)];
    [content addSubview:self.delayedButton];

    NSButton *fullButton = [self actionButtonWithTitle:@"Full"
                                                symbol:@"macwindow"
                                                 frame:NSMakeRect(434, 124, 42, 36)
                                                action:@selector(fullScreenClicked:)];
    [content addSubview:fullButton];

    NSView *shortcutsCard = [[NSView alloc] initWithFrame:NSMakeRect(24, 24, 452, 82)];
    shortcutsCard.wantsLayer = YES;
    shortcutsCard.layer.backgroundColor = [CSTheme pillSurface].CGColor;
    shortcutsCard.layer.cornerRadius = CSRadiusMedium;
    shortcutsCard.layer.borderWidth = 1.0;
    shortcutsCard.layer.borderColor = [CSTheme subtleBorder].CGColor;
    [content addSubview:shortcutsCard];

    NSTextField *hint = [self labelWithString:@"⌘⇧2 Capture / Stop Video  ·  Tab Toggle Photo/Video  ·  M Mic Audio  ·  ⇧⌘C OCR & QR"
                                         font:[NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightMedium]
                                        color:[CSTheme text]
                                        frame:NSMakeRect(14, 46, 424, 16)];
    [shortcutsCard addSubview:hint];

    NSTextField *tip = [self labelWithString:@"Pro tip: Cut & crop recorded videos in the Video Studio (or press ⌘O / drag any video into the app)."
                                        font:[NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular]
                                       color:[CSTheme mutedText]
                                       frame:NSMakeRect(14, 18, 424, 16)];
    [shortcutsCard addSubview:tip];
}

- (void)setDelaySeconds:(NSInteger)seconds {
    self.delayedButton.title = [NSString stringWithFormat:@"%ld-Sec Delay", (long)seconds];
}

- (void)updateScreenRecordingGranted:(BOOL)granted {
    self.granted = granted;
    self.statusDot.layer.backgroundColor = (granted ? [NSColor systemGreenColor] : [NSColor systemRedColor]).CGColor;
    self.statusLabel.stringValue = granted ? @"Screen Recording: granted" : @"Screen Recording: not granted";
    self.detailLabel.stringValue = granted
        ? @"Ready to capture. You can revoke this at any time in System Settings."
        : @"Enable Choxieshoot in System Settings → Privacy & Security → Screen Recording, then relaunch Choxieshoot.";
    self.grantButton.title = granted ? @"Open Settings" : @"Grant Access";
}

- (void)focusPermissions {
    self.permissionCard.layer.borderWidth = 2.0;
    self.permissionCard.layer.borderColor = [CSTheme accent].CGColor;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.permissionCard.layer.borderWidth = 1.0;
        self.permissionCard.layer.borderColor = [CSTheme border].CGColor;
    });
}

- (void)newCaptureClicked:(id)sender {
    if (self.newCaptureBlock != nil) {
        self.newCaptureBlock();
    }
}

- (void)recordVideoClicked:(id)sender {
    if (self.recordVideoBlock != nil) {
        self.recordVideoBlock();
    }
}

- (void)openVideoClicked:(id)sender {
    if (self.openVideoBlock != nil) {
        self.openVideoBlock();
    }
}

- (void)delayedClicked:(id)sender {
    if (self.delayedBlock != nil) {
        self.delayedBlock();
    }
}

- (void)fullScreenClicked:(id)sender {
    if (self.fullScreenBlock != nil) {
        self.fullScreenBlock();
    }
}

- (void)grantClicked:(id)sender {
    if (self.grantBlock != nil) {
        self.grantBlock();
    }
}

- (void)checkClicked:(id)sender {
    if (self.checkBlock != nil) {
        self.checkBlock();
    }
}

- (void)restartClicked:(id)sender {
    if (self.restartBlock != nil) {
        self.restartBlock();
    }
}

- (void)resetClicked:(id)sender {
    if (self.resetBlock != nil) {
        self.resetBlock();
    }
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (void)enableTrafficLightMinimizeButton {
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    if (miniBtn != nil) {
        miniBtn.enabled = YES;
        miniBtn.target = self;
        miniBtn.action = @selector(minimizeLauncherClicked:);
    }
}

- (void)makeKeyAndOrderFront:(id)sender {
    [super makeKeyAndOrderFront:sender];
    [self enableTrafficLightMinimizeButton];
}

- (void)orderFrontRegardless {
    [super orderFrontRegardless];
    [self enableTrafficLightMinimizeButton];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self enableTrafficLightMinimizeButton];
}

- (void)minimizeLauncherClicked:(id)sender {
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    [super miniaturize:sender];
}

- (void)performMiniaturize:(id)sender {
    [self minimizeLauncherClicked:sender];
}

- (void)closeLauncherClicked:(id)sender {
    [self close];
}

- (void)close {
    [self orderOut:nil];
    self.newCaptureBlock = nil;
    self.delayedBlock = nil;
    self.fullScreenBlock = nil;
    self.grantBlock = nil;
    self.checkBlock = nil;
    self.restartBlock = nil;
    self.resetBlock = nil;
    self.recordVideoBlock = nil;
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    miniBtn.target = nil;
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    LauncherActionBlock closeBlock = self.onClose;
    self.onClose = nil;
    [super close];
    if (closeBlock != nil) {
        closeBlock();
    }
    malloc_zone_pressure_relief(NULL, 0);
}

- (void)windowWillClose:(NSNotification *)notification {
    LauncherActionBlock closeBlock = self.onClose;
    self.onClose = nil;
    if (closeBlock != nil) {
        closeBlock();
    }
}

- (void)cancelOperation:(id)sender {
    [self closeLauncherClicked:sender];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown) {
        if (event.keyCode == 53) { // Escape
            [self closeLauncherClicked:nil];
            return YES;
        }
        if (event.modifierFlags & NSEventModifierFlagCommand) {
            NSString *key = [[event.charactersIgnoringModifiers lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([key isEqualToString:@"w"]) {
                [self closeLauncherClicked:nil];
                return YES;
            }
            if ([key isEqualToString:@"m"]) {
                [self minimizeLauncherClicked:nil];
                return YES;
            }
        }
    }
    return [super performKeyEquivalent:event];
}

@end
