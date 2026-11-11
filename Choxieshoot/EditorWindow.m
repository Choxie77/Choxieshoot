#import "EditorWindow.h"
#import "CanvasView.h"
#import "ToolbarView.h"
#import "TextRecognizer.h"
#import "CSTheme.h"
#import "ColorInspectorView.h"
#import "TextOptionsView.h"
#import "TextRecognizerView.h"
#import "ChoxieshootNotifications.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <malloc/malloc.h>

static const CGFloat kCanvasGap = 8.0;
static const CGFloat kHeaderHeight = 36.0;
static const CGFloat kMinContentWidth = 640.0;

@interface EditorWindow () <CanvasViewDelegate, ToolbarViewDelegate, TextRecognizerViewDelegate, NSWindowDelegate>

@property (nonatomic, strong) NSView *headerBar;
@property (nonatomic, strong) NSTextField *headerTitleLabel;
@property (nonatomic, strong) NSButton *headerPinButton;
@property (nonatomic, strong) NSButton *headerMinimizeButton;
@property (nonatomic, strong) NSButton *headerCancelButton;
@property (nonatomic, strong) CanvasView *canvasView;
@property (nonatomic, strong) ToolbarView *toolbarView;
@property (nonatomic, strong, nullable) ColorInspectorView *colorInspector;
@property (nonatomic, strong, nullable) TextOptionsView *textOptions;
@property (nonatomic, strong, nullable) TextRecognizerView *textRecognizerView;
@property (nonatomic, strong, nullable) CSTextRecognitionResult *ocrResult;
@property (nonatomic, strong, nullable) NSImage *screenshot;
@property (nonatomic, strong, nullable) NSTextField *toastField;
@property (nonatomic) CGFloat toolbarHeight;
@property (nonatomic) BOOL ocrInProgress;
@property (nonatomic) BOOL hasAnimatedIn;
@property (nonatomic) BOOL didCleanUp;

@end

@implementation EditorWindow

- (instancetype)initWithScreenRect:(NSRect)screenRect image:(NSImage *)image {
    self.screenshot = image;

    NSSize imageSize = image.size;
    NSScreen *targetScreen = [self screenContainingRect:screenRect];
    NSRect visible = targetScreen != nil ? targetScreen.visibleFrame : [NSScreen mainScreen].visibleFrame;

    CGFloat maxCanvasWidth = MAX(visible.size.width - 40.0, 200.0);
    CGFloat maxCanvasHeight = MAX(visible.size.height - 196.0, 120.0);
    CGFloat scale = 1.0;
    if (imageSize.width > 0) {
        scale = MIN(scale, maxCanvasWidth / imageSize.width);
    }
    if (imageSize.height > 0) {
        scale = MIN(scale, maxCanvasHeight / imageSize.height);
    }
    scale = MAX(scale, 0.05);

    NSSize displaySize = NSMakeSize(floor(imageSize.width * scale), floor(imageSize.height * scale));
    CGFloat minimumWidth = MIN(kMinContentWidth, MAX(visible.size.width - 20.0, 360.0));
    CGFloat contentWidth = MAX(displaySize.width, minimumWidth);
    CGFloat toolbarHeight = [ToolbarView preferredHeightForWidth:contentWidth];
    CGFloat contentHeight = displaySize.height + toolbarHeight + kCanvasGap + kHeaderHeight;

    CGFloat imageInset = (contentWidth - displaySize.width) / 2.0;
    CGFloat originX = screenRect.origin.x - imageInset;
    CGFloat originY = screenRect.origin.y - toolbarHeight - kCanvasGap;
    originX = MIN(MAX(originX, NSMinX(visible)), NSMaxX(visible) - contentWidth);
    originY = MIN(MAX(originY, NSMinY(visible)), NSMaxY(visible) - contentHeight);

    self = [super initWithContentRect:NSMakeRect(originX, originY, contentWidth, contentHeight)
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

    self.title = @"Choxieshoot Screenshot";
    self.miniwindowTitle = @"Screenshot";
    self.titlebarAppearsTransparent = YES;
    self.titleVisibility = NSWindowTitleHidden;
    self.floatingPanel = NO;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.toolbarHeight = toolbarHeight;
    self.releasedWhenClosed = NO;
    self.opaque = NO;
    self.backgroundColor = [CSTheme surface];
    self.hasShadow = YES;
    self.level = NSNormalWindowLevel;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    self.delegate = self;
    self.acceptsMouseMovedEvents = YES;
    [self enableTrafficLightMinimizeButton];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, contentHeight)];
    container.wantsLayer = YES;
    container.layer.backgroundColor = [CSTheme surface].CGColor;
    container.layer.cornerRadius = CSRadiusLarge;
    container.layer.masksToBounds = YES;
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.6].CGColor;
    self.contentView = container;

    self.headerBar = [[NSView alloc] initWithFrame:NSMakeRect(0, contentHeight - kHeaderHeight, contentWidth, kHeaderHeight)];
    self.headerBar.wantsLayer = YES;
    self.headerBar.layer.backgroundColor = [CSTheme controlSurface].CGColor;
    [container addSubview:self.headerBar];

    self.headerTitleLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"Choxieshoot  ·  %ld × %ld",
                                                          (long)lround(displaySize.width),
                                                          (long)lround(displaySize.height)]];
    self.headerTitleLabel.font = [NSFont monospacedDigitSystemFontOfSize:11.5 weight:NSFontWeightSemibold];
    self.headerTitleLabel.textColor = [CSTheme mutedText];
    [self.headerBar addSubview:self.headerTitleLabel];

    self.headerPinButton = [self headerButtonWithTitle:@"Pin"
                                                symbol:@"pin"
                                               tooltip:@"Keep Window on Top"
                                                action:@selector(headerPinClicked:)];
    [self.headerBar addSubview:self.headerPinButton];

    self.headerMinimizeButton = [self headerButtonWithTitle:@"Minimize"
                                                     symbol:@"minus"
                                                    tooltip:@"Minimize Window (⌘M)"
                                                     action:@selector(minimizeWindow:)];
    [self.headerBar addSubview:self.headerMinimizeButton];

    self.headerCancelButton = [self headerButtonWithTitle:@"Cancel"
                                                   symbol:@"xmark"
                                                  tooltip:@"Cancel & Close Window (Esc)"
                                                   action:@selector(cancelOperation:)];
    [self.headerBar addSubview:self.headerCancelButton];
    [self layoutHeaderBarForWidth:contentWidth displaySize:displaySize];

    self.canvasView = [[CanvasView alloc] initWithFrame:NSMakeRect(imageInset,
                                                                   toolbarHeight + kCanvasGap,
                                                                   displaySize.width,
                                                                   displaySize.height)];
    self.canvasView.backgroundImage = image;
    self.canvasView.delegate = self;
    self.canvasView.wantsLayer = YES;
    self.canvasView.layer.borderWidth = 1.0;
    self.canvasView.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.7].CGColor;
    [container addSubview:self.canvasView];

    self.toolbarView = [[ToolbarView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, toolbarHeight)];
    self.toolbarView.delegate = self;
    [container addSubview:self.toolbarView];

    [self makeFirstResponder:self.canvasView];
    return self;
}

- (ColorInspectorView *)ensureColorInspector {
    if (_colorInspector == nil && self.contentView != nil) {
        CGFloat contentWidth = NSWidth(self.contentView.bounds);
        CGFloat contentHeight = NSHeight(self.contentView.bounds);
        NSSize displaySize = self.canvasView.frame.size;
        CGFloat imageInset = self.canvasView.frame.origin.x;
        CGFloat inspectorX = imageInset + displaySize.width - 240.0 - 10.0;
        inspectorX = MIN(MAX(inspectorX, 8.0), contentWidth - 248.0);
        CGFloat inspectorY = self.toolbarHeight + kCanvasGap + displaySize.height - 150.0 - 10.0;
        inspectorY = MIN(MAX(inspectorY, self.toolbarHeight + kCanvasGap + 8.0), contentHeight - kHeaderHeight - 158.0);
        _colorInspector = [[ColorInspectorView alloc] initWithFrame:NSMakeRect(inspectorX, inspectorY, 240.0, 150.0)];
        _colorInspector.hidden = YES;
        __weak typeof(self) weakSelf = self;
        _colorInspector.onToggleLock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            BOOL nextLocked = !strongSelf->_colorInspector.isLocked;
            if (nextLocked && strongSelf->_colorInspector.currentColor == nil) {
                return;
            }
            strongSelf.canvasView.colorPickerLocked = nextLocked;
            [strongSelf->_colorInspector setLocked:nextLocked animated:YES];
        };
        [self.contentView addSubview:_colorInspector];
    }
    return _colorInspector;
}

- (TextOptionsView *)ensureTextOptions {
    if (_textOptions == nil && self.contentView != nil) {
        CGFloat contentWidth = NSWidth(self.contentView.bounds);
        CGFloat contentHeight = NSHeight(self.contentView.bounds);
        NSSize displaySize = self.canvasView.frame.size;
        CGFloat imageInset = self.canvasView.frame.origin.x;
        CGFloat textX = imageInset + 10.0;
        textX = MIN(MAX(textX, 8.0), contentWidth - 238.0);
        CGFloat textY = self.toolbarHeight + kCanvasGap + displaySize.height - 160.0 - 10.0;
        textY = MIN(MAX(textY, self.toolbarHeight + kCanvasGap + 8.0), contentHeight - kHeaderHeight - 168.0);
        _textOptions = [[TextOptionsView alloc] initWithFrame:NSMakeRect(textX, textY, 230.0, 160.0)];
        _textOptions.hidden = YES;
        __weak typeof(self) weakSelf = self;
        _textOptions.onChange = ^(CGFloat fontSize, BOOL bold, BOOL background) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.textFontSize = fontSize;
            strongSelf.canvasView.textBold = bold;
            strongSelf.canvasView.textBackground = background;
            [strongSelf.canvasView applyTextStyleToActiveEditor];
        };
        _textOptions.onSpotlightChange = ^(CSSpotlightShape shape, CGFloat dimOpacity, BOOL feather) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.spotlightShape = shape;
            strongSelf.canvasView.spotlightDimOpacity = dimOpacity;
            strongSelf.canvasView.spotlightFeather = feather;
        };
        _textOptions.onRedactChange = ^(CSRedactMode mode) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.redactMode = mode;
        };
        _textOptions.onArrowChange = ^(BOOL curved) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.arrowCurved = curved;
        };
        _textOptions.onRectChange = ^(BOOL rounded) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.shapeRounded = rounded;
        };
        _textOptions.onCalloutChange = ^(BOOL speechBubble) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.calloutSpeechBubble = speechBubble;
        };
        _textOptions.onLoupeChange = ^(CGFloat magnification) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            strongSelf.canvasView.loupeMagnification = magnification;
        };
        [self.contentView addSubview:_textOptions];
    }
    return _textOptions;
}

- (TextRecognizerView *)ensureTextRecognizerView {
    if (_textRecognizerView == nil && self.contentView != nil) {
        CGFloat contentWidth = NSWidth(self.contentView.bounds);
        CGFloat contentHeight = NSHeight(self.contentView.bounds);
        NSSize displaySize = self.canvasView.frame.size;
        CGFloat imageInset = self.canvasView.frame.origin.x;
        CGFloat ocrWidth = MIN(310.0, MAX(240.0, contentWidth - 16.0));
        CGFloat ocrHeight = MIN(220.0, MAX(150.0, displaySize.height - 16.0));
        CGFloat ocrX = imageInset + displaySize.width - ocrWidth - 10.0;
        ocrX = MIN(MAX(ocrX, 8.0), contentWidth - ocrWidth - 8.0);
        CGFloat ocrY = self.toolbarHeight + kCanvasGap + displaySize.height - ocrHeight - 10.0;
        ocrY = MIN(MAX(ocrY, self.toolbarHeight + kCanvasGap + 8.0), contentHeight - kHeaderHeight - ocrHeight - 8.0);
        _textRecognizerView = [[TextRecognizerView alloc] initWithFrame:NSMakeRect(ocrX, ocrY, ocrWidth, ocrHeight)];
        _textRecognizerView.delegate = self;
        _textRecognizerView.hidden = YES;
        [self.contentView addSubview:_textRecognizerView];
    }
    return _textRecognizerView;
}

- (NSButton *)headerButtonWithTitle:(NSString *)title
                             symbol:(NSString *)symbolName
                            tooltip:(NSString *)tooltip
                             action:(SEL)action {
    NSButton *btn = [NSButton buttonWithTitle:title target:self action:action];
    btn.bezelStyle = NSBezelStyleRounded;
    btn.controlSize = NSControlSizeSmall;
    btn.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    btn.toolTip = tooltip;
    NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:title];
    if (img != nil) {
        NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:10.5
                                                                                          weight:NSFontWeightSemibold];
        btn.image = [img imageWithSymbolConfiguration:cfg] ?: img;
        btn.imagePosition = NSImageLeading;
    }
    return btn;
}

- (void)layoutHeaderBarForWidth:(CGFloat)contentWidth displaySize:(NSSize)displaySize {
    self.headerTitleLabel.stringValue = [NSString stringWithFormat:@"Choxieshoot  ·  %ld × %ld",
                                         (long)lround(displaySize.width),
                                         (long)lround(displaySize.height)];
    self.headerTitleLabel.frame = NSMakeRect(78.0, 8.0, MAX(120.0, contentWidth - 330.0), 18.0);
    CGFloat rightX = contentWidth - 10.0;
    self.headerCancelButton.frame = NSMakeRect(rightX - 72.0, 5.0, 72.0, 24.0);
    rightX -= 76.0;
    self.headerMinimizeButton.frame = NSMakeRect(rightX - 82.0, 5.0, 82.0, 24.0);
    rightX -= 86.0;
    self.headerPinButton.frame = NSMakeRect(rightX - 60.0, 5.0, 60.0, 24.0);
}

- (void)headerPinClicked:(id)sender {
    [self setPinnedOnTop:!self.pinnedOnTop];
}

- (void)enableTrafficLightMinimizeButton {
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    if (miniBtn != nil) {
        miniBtn.enabled = YES;
        miniBtn.target = self;
        miniBtn.action = @selector(minimizeWindow:);
    }
}

- (void)orderFrontRegardless {
    [super orderFrontRegardless];
    [self enableTrafficLightMinimizeButton];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self enableTrafficLightMinimizeButton];
}

- (void)setPinnedOnTop:(BOOL)pinnedOnTop {
    _pinnedOnTop = pinnedOnTop;
    self.floatingPanel = pinnedOnTop;
    self.level = pinnedOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
    [self enableTrafficLightMinimizeButton];
    self.toolbarView.pinnedOnTop = pinnedOnTop;
    self.headerPinButton.title = pinnedOnTop ? @"Pinned" : @"Pin";
    NSString *sym = pinnedOnTop ? @"pin.fill" : @"pin";
    NSImage *img = [NSImage imageWithSystemSymbolName:sym accessibilityDescription:self.headerPinButton.title];
    if (img != nil) {
        NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:10.5
                                                                                          weight:NSFontWeightSemibold];
        self.headerPinButton.image = [img imageWithSymbolConfiguration:cfg] ?: img;
    }
    [self showToast:pinnedOnTop ? @"Pinned on top of other windows" : @"Unpinned — normal window order" duration:1.5];
}

- (void)minimizeWindow:(nullable id)sender {
    [self.canvasView commitTextEditorIfNeeded];
    if (self.miniwindowImage == nil && self.screenshot != nil) {
        NSSize src = self.screenshot.size;
        CGFloat scale = MIN(128.0 / MAX(src.width, 1.0), 128.0 / MAX(src.height, 1.0));
        NSSize thumbSize = NSMakeSize(MAX(16.0, round(src.width * scale)), MAX(16.0, round(src.height * scale)));
        NSImage *thumb = [[NSImage alloc] initWithSize:thumbSize];
        [thumb lockFocus];
        [self.screenshot drawInRect:NSMakeRect(0, 0, thumbSize.width, thumbSize.height)
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationCopy
                           fraction:1.0];
        [thumb unlockFocus];
        self.miniwindowImage = thumb;
    }
    self.floatingPanel = NO;
    self.level = NSNormalWindowLevel;
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    [super miniaturize:sender];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
    self.miniwindowImage = nil;
}

- (void)performMiniaturize:(nullable id)sender {
    [self minimizeWindow:sender];
}

- (void)miniaturize:(nullable id)sender {
    [self minimizeWindow:sender];
}

- (void)makeKeyAndOrderFront:(id)sender {
    [super makeKeyAndOrderFront:sender];
    [self enableTrafficLightMinimizeButton];
    if (!self.hasAnimatedIn) {
        self.hasAnimatedIn = YES;
        self.alphaValue = 1.0;
    }
}

- (NSScreen *)screenContainingRect:(NSRect)rect {
    NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(center, screen.frame)) {
            return screen;
        }
    }
    return [NSScreen mainScreen];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

#pragma mark - Keyboard

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return [super performKeyEquivalent:event];
    }
    if (event.keyCode == 53) { // Escape
        if (self.canvasView.ocrMode) {
            [self closeTextRecognizer];
            return YES;
        }
        if (self.canvasView.currentTool == ToolTypeColorPicker && self.canvasView.colorPickerLocked) {
            self.canvasView.colorPickerLocked = NO;
            [self.colorInspector setLocked:NO animated:YES];
            return YES;
        }
        if ([self.firstResponder isKindOfClass:[NSTextView class]]) {
            return [super performKeyEquivalent:event];
        }
        [self close];
        return YES;
    }
    // Never steal shortcuts while the user is editing a canvas text annotation.
    if ([self.firstResponder isKindOfClass:[NSTextView class]] && !self.canvasView.ocrMode) {
        return [super performKeyEquivalent:event];
    }
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
        NSString *key = [[event.charactersIgnoringModifiers lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([key isEqualToString:@"s"] && !shift) {
            [self saveImage];
            return YES;
        }
        if ([key isEqualToString:@"c"] && !shift) {
            if (self.canvasView.ocrMode) {
                [self.textRecognizerView triggerCopySelection];
            } else {
                [self copyImage];
            }
            return YES;
        }
        if ([key isEqualToString:@"c"] && shift) {
            [self toggleTextRecognizer];
            return YES;
        }
        if ([key isEqualToString:@"z"] && shift) {
            if ([self.firstResponder isKindOfClass:[NSTextView class]]) {
                return [super performKeyEquivalent:event];
            }
            [self redo];
            return YES;
        }
        if ([key isEqualToString:@"z"]) {
            if ([self.firstResponder isKindOfClass:[NSTextView class]]) {
                return [super performKeyEquivalent:event];
            }
            [self undo];
            return YES;
        }
        if ([key isEqualToString:@"n"]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:ChoxieshootNewCaptureNotification object:nil];
            return YES;
        }
        if ([key isEqualToString:@"m"] && !shift) {
            [self minimizeWindow:nil];
            return YES;
        }
        if ([key isEqualToString:@"w"] && !shift) {
            [self.canvasView commitTextEditorIfNeeded];
            [self close];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)selectTool:(ToolType)tool {
    self.toolbarView.currentTool = tool;
    [self toolbarView:self.toolbarView didSelectTool:tool];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        if (self.ocrInProgress) {
            [self cancelTextRecognition];
            return;
        }
        if (self.canvasView.currentTool == ToolTypeCrop) {
            [self.canvasView clearPreviewAnnotation];
            [self selectTool:ToolTypeSelect];
            return;
        }
        if (self.canvasView.ocrMode) {
            [self closeTextRecognizer];
            return;
        }
        if (self.canvasView.currentTool == ToolTypeColorPicker && self.canvasView.colorPickerLocked) {
            self.canvasView.colorPickerLocked = NO;
            [self.colorInspector setLocked:NO animated:YES];
            return;
        }
        if (self.canvasView.selectedAnnotation != nil) {
            [self.canvasView clearSelection];
            return;
        }
        [self close];
        return;
    }
    if ([self.firstResponder isKindOfClass:[NSTextView class]]) {
        [super keyDown:event];
        return;
    }
    if ((event.keyCode == 51 || event.keyCode == 117) && self.canvasView.selectedAnnotation != nil) {
        [self.canvasView deleteSelectedAnnotation];
        [self showToast:@"Deleted annotation" duration:1.3];
        return;
    }

    NSString *chars = [event.charactersIgnoringModifiers lowercaseString];
    if (chars.length == 1) {
        unichar ch = [chars characterAtIndex:0];
        ToolType selected = -1;
        switch (ch) {
            case 'v': selected = ToolTypeSelect; break;
            case 'p': selected = ToolTypePencil; break;
            case 'l': selected = ToolTypeLine; break;
            case 'a': selected = ToolTypeArrow; break;
            case 'r': selected = ToolTypeRectangle; break;
            case 'e': selected = ToolTypeEllipse; break;
            case 'h':
            case 'm': selected = ToolTypeMarker; break;
            case 't': selected = ToolTypeText; break;
            case 'b': selected = ToolTypePixelate; break;
            case 'n': selected = ToolTypeCallout; break;
            case 's': selected = ToolTypeSpotlight; break;
            case 'z': selected = ToolTypeLoupe; break;
            case 'k': selected = ToolTypeCrop; break;
            case 'i':
            case 'c': selected = ToolTypeColorPicker; break;
            case 'x':
            case 'd': selected = ToolTypeEraser; break;
            case 'f': {
                BOOL nextFilled = !self.canvasView.shapeFilled;
                self.canvasView.shapeFilled = nextFilled;
                self.toolbarView.shapeFilled = nextFilled;
                [self showToast:nextFilled ? @"Shape fill: On" : @"Shape fill: Off" duration:1.4];
                return;
            }
            case 'w': {
                BOOL nextShadow = !self.canvasView.shapeShadow;
                self.canvasView.shapeShadow = nextShadow;
                self.toolbarView.shapeShadow = nextShadow;
                [self showToast:nextShadow ? @"Drop shadow: On" : @"Drop shadow: Off" duration:1.4];
                return;
            }
            case 'o':
                [self toggleTextRecognizer];
                return;
            case '[': {
                CGFloat w = MAX(self.canvasView.currentLineWidth - 1.0, 1.0);
                self.canvasView.currentLineWidth = w;
                self.toolbarView.currentLineWidth = w;
                return;
            }
            case ']': {
                CGFloat w = MIN(self.canvasView.currentLineWidth + 1.0, 20.0);
                self.canvasView.currentLineWidth = w;
                self.toolbarView.currentLineWidth = w;
                return;
            }
            default: break;
        }
        if (selected != -1) {
            [self selectTool:selected];
            return;
        }
    }
    [super keyDown:event];
}

- (void)cancelOperation:(id)sender {
    [self close];
}

#pragma mark - Actions

- (void)undo {
    [self.canvasView undo];
    [self refreshUndoState];
}

- (void)redo {
    [self.canvasView redo];
    [self refreshUndoState];
}

- (void)refreshUndoState {
    self.toolbarView.canUndo = [self.canvasView canUndo];
    self.toolbarView.canRedo = [self.canvasView canRedo];
}

- (void)saveImage {
    [self.canvasView commitTextEditorIfNeeded];
    [NSApp activateIgnoringOtherApps:YES];
    [self makeKeyAndOrderFront:nil];
    NSSavePanel *panel = [NSSavePanel savePanel];
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypePNG];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"png"];
#pragma clang diagnostic pop
    }
    panel.nameFieldStringValue = [NSString stringWithFormat:@"Choxieshoot %@.png", [self timestampString]];
    panel.canCreateDirectories = YES;

    // Users often want the file and the clipboard copy in one action.
    NSButton *copyCheckbox = [NSButton checkboxWithTitle:@"Also copy to clipboard"
                                                  target:nil
                                                  action:nil];
    copyCheckbox.state = NSControlStateValueOff;
    panel.accessoryView = copyCheckbox;

    [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL == nil) {
            return;
        }
        NSError *error = nil;
        BOOL alsoCopy = copyCheckbox.state == NSControlStateValueOn;
        if (![self saveCompositeToURL:panel.URL error:&error]) {
            [self showError:[NSString stringWithFormat:@"Could not save the image: %@", error.localizedDescription]];
            return;
        }
        if (alsoCopy) {
            BOOL copied = [self copyImageToPasteboard];
            [self showToast:copied
                ? [NSString stringWithFormat:@"Saved & copied %@", panel.URL.lastPathComponent]
                : [NSString stringWithFormat:@"Saved %@ (clipboard copy failed)", panel.URL.lastPathComponent]
                duration:2.4];
        } else {
            [self showToast:[NSString stringWithFormat:@"Saved %@", panel.URL.lastPathComponent] duration:2.2];
        }
    }];
}

- (BOOL)saveCompositeToURL:(NSURL *)url error:(NSError **)error {
    NSImage *image = [self.canvasView renderCompositeImage];
    NSData *pngData = [self pngDataFromImage:image];
    if (pngData == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"Choxieshoot"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"The image could not be encoded as PNG."}];
        }
        return NO;
    }
    return [pngData writeToURL:url options:NSDataWritingAtomic error:error];
}

- (BOOL)copyImageToPasteboard {
    NSImage *image = [self.canvasView renderCompositeImage];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    return [pasteboard writeObjects:@[image]];
}

- (void)copyImage {
    [self.canvasView commitTextEditorIfNeeded];
    if ([self copyImageToPasteboard]) {
        [self showToast:@"Image copied to clipboard" duration:1.8];
    } else {
        [self showError:@"Could not copy the image to the clipboard."];
    }
}

- (void)copyImageForTesting {
    [self copyImage];
}

- (void)cancelTextRecognition {
    if (!self.ocrInProgress) {
        return;
    }
    self.ocrInProgress = NO;
    [self.toolbarView setOCRBusy:NO];
    [self showToast:@"Text recognition cancelled" duration:1.5];
}

- (void)toggleTextRecognizer {
    if (self.ocrInProgress) {
        [self cancelTextRecognition];
        return;
    }
    if (self.canvasView.ocrMode) {
        [self closeTextRecognizer];
    } else {
        [self openTextRecognizerWithCompletion:nil];
    }
}

- (void)closeTextRecognizer {
    self.canvasView.ocrMode = NO;
    _textRecognizerView.hidden = YES;
    [self.toolbarView setOCRActive:NO];
    [self makeFirstResponder:self.canvasView];
}

- (void)presentOCRResult:(CSTextRecognitionResult *)result {
    self.ocrResult = result;
    NSIndexSet *allIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, result.observations.count)];
    self.canvasView.ocrObservations = result.observations;
    self.canvasView.ocrBarcodes = result.barcodes;
    self.canvasView.selectedOCRIndexes = allIndexes;
    self.canvasView.ocrMode = YES;
    _colorInspector.hidden = YES;
    _textOptions.hidden = YES;
    [self.toolbarView setOCRActive:YES];

    TextRecognizerView *ocrView = [self ensureTextRecognizerView];
    [ocrView updateWithResult:result selectedIndexes:allIndexes];
    ocrView.hidden = NO;
    if (result.barcodes.count > 0 && result.observations.count > 0) {
        [self showToast:[NSString stringWithFormat:@"Found %lu text %@ & %lu QR/barcode — select and press Copy",
                         (unsigned long)result.observations.count,
                         result.observations.count == 1 ? @"block" : @"blocks",
                         (unsigned long)result.barcodes.count]
               duration:2.8];
    } else if (result.barcodes.count > 0) {
        [self showToast:[NSString stringWithFormat:@"Found %lu QR/barcode: %@",
                         (unsigned long)result.barcodes.count,
                         result.barcodes.firstObject.payload]
               duration:2.8];
    } else {
        [self showToast:[NSString stringWithFormat:@"Found %lu text %@ — select what you need and press Copy",
                         (unsigned long)result.observations.count,
                         result.observations.count == 1 ? @"block" : @"blocks"]
               duration:2.6];
    }
}

- (void)openTextRecognizerWithCompletion:(nullable void (^)(BOOL foundText))completion {
    [self.canvasView commitTextEditorIfNeeded];
    if (self.ocrInProgress) {
        return;
    }
    if (self.screenshot == nil) {
        [self showToast:@"No screenshot to read" duration:2.0];
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSTimeInterval minLoadingDuration = (completion != nil) ? 0.16 : 0.48;
    NSTimeInterval startedAt = [NSDate timeIntervalSinceReferenceDate];

    self.ocrInProgress = YES;
    [self.toolbarView setOCRBusy:YES];
    [self showToast:@"Recognizing text & QR codes…" duration:8.0];

    __weak typeof(self) weakSelf = self;
    void (^finishRecognition)(CSTextRecognitionResult * _Nullable, NSError * _Nullable) = ^(CSTextRecognitionResult * _Nullable result, NSError * _Nullable error) {
        NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - startedAt;
        NSTimeInterval remaining = MAX(0.0, minLoadingDuration - elapsed);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil || !strongSelf.ocrInProgress) {
                return;
            }
            strongSelf.ocrInProgress = NO;
            [strongSelf.toolbarView setOCRBusy:NO];

            if (error != nil) {
                [strongSelf showToast:[NSString stringWithFormat:@"Text recognition failed: %@", error.localizedDescription]
                             duration:3.0];
                if (completion != nil) {
                    completion(NO);
                }
                return;
            }
            NSString *trimmed = [result.fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ((trimmed.length == 0 || result.observations.count == 0) && result.barcodes.count == 0) {
                [strongSelf showToast:@"No text or QR codes found in the screenshot" duration:2.4];
                if (completion != nil) {
                    completion(NO);
                }
                return;
            }
            [strongSelf presentOCRResult:result];
            if (completion != nil) {
                completion(YES);
            }
        });
    };

    if (self.ocrResult != nil && (self.ocrResult.observations.count > 0 || self.ocrResult.barcodes.count > 0)) {
        finishRecognition(self.ocrResult, nil);
        return;
    }

    [TextRecognizer recognizeObservationsInImage:self.screenshot completion:^(CSTextRecognitionResult *result, NSError *error) {
        finishRecognition(result, error);
    }];
}

- (BOOL)isOCRBusyForTesting {
    return self.toolbarView.isOCRBusy;
}

- (void)openTextRecognizerForTesting {
    [self openTextRecognizerWithCompletion:nil];
}

- (void)selectOCRBlockIndexesForTesting:(NSIndexSet *)indexes {
    self.canvasView.selectedOCRIndexes = indexes;
    [[self ensureTextRecognizerView] updateSelectedIndexes:indexes];
}

- (void)selectOCRTextRangeForTesting:(NSRange)range {
    [[self ensureTextRecognizerView] setHighlightedRange:range];
}

- (void)copySelectedOCRTextForTesting {
    [[self ensureTextRecognizerView] triggerCopySelection];
}

- (void)copyDetectedBarcodeForTesting {
    [[self ensureTextRecognizerView] triggerCopyBarcode];
}

- (void)copyRecognizedTextForTesting {
    __weak typeof(self) weakSelf = self;
    [self openTextRecognizerWithCompletion:^(BOOL foundText) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (foundText) {
            [[strongSelf ensureTextRecognizerView] triggerCopySelection];
        }
    }];
}

- (void)shareImage {
    [self.canvasView commitTextEditorIfNeeded];
    NSImage *image = [self.canvasView renderCompositeImage];
    NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[image]];
    [picker showRelativeToRect:self.toolbarView.bounds
                        ofView:self.toolbarView
                 preferredEdge:NSRectEdgeMinY];
}

- (NSData *)pngDataFromImage:(NSImage *)image {
    if (image == nil) {
        return nil;
    }
    __block NSData *pngData = nil;
    @autoreleasepool {
        NSBitmapImageRep *rep = nil;
        for (NSImageRep *candidate in image.representations) {
            if ([candidate isKindOfClass:[NSBitmapImageRep class]]) {
                rep = (NSBitmapImageRep *)candidate;
                break;
            }
        }
        if (rep == nil) {
            CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
            if (cg != NULL) {
                rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
            }
        }
        if (rep != nil) {
            pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        }
    }
    return pngData;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Choxieshoot";
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self completionHandler:nil];
}

- (void)showToast:(NSString *)message duration:(NSTimeInterval)duration {
    [self.toastField removeFromSuperview];

    NSTextField *label = [NSTextField labelWithString:message];
    label.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    label.textColor = [CSTheme toastText];
    label.alignment = NSTextAlignmentCenter;
    label.wantsLayer = YES;
    label.layer.backgroundColor = [CSTheme toastBackground].CGColor;
    label.layer.cornerRadius = CSRadiusSmall;
    label.layer.masksToBounds = NO;
    label.layer.shadowColor = [NSColor blackColor].CGColor;
    label.layer.shadowOpacity = 0.25;
    label.layer.shadowRadius = 6.0;
    label.layer.shadowOffset = CGSizeMake(0, -1);

    [label sizeToFit];
    CGFloat width = label.frame.size.width + 26.0;
    CGFloat height = label.frame.size.height + 12.0;
    NSRect bounds = self.contentView.bounds;
    CGFloat maxWidth = MAX(NSWidth(bounds) - 40.0, 160.0);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    if (width > maxWidth) {
        width = maxWidth;
    }
    label.frame = NSMakeRect((NSWidth(bounds) - width) / 2.0,
                             self.toolbarHeight + kCanvasGap + 16.0,
                             width, height);
    label.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin;
    [self.contentView addSubview:label];
    self.toastField = label;

    label.alphaValue = 0.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.16;
        label.animator.alphaValue = 1.0;
    } completionHandler:nil];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.toastField != label) {
            return;
        }
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.22;
            label.animator.alphaValue = 0.0;
        } completionHandler:^{
            [label removeFromSuperview];
            if (strongSelf.toastField == label) {
                strongSelf.toastField = nil;
            }
        }];
    });
}

- (void)showToastForTesting:(NSString *)message {
    [self showToast:message duration:3.0];
}

- (void)showColorInspectorForTesting:(NSColor *)color {
    [self closeTextRecognizer];
    self.toolbarView.currentTool = ToolTypeColorPicker;
    self.canvasView.currentTool = ToolTypeColorPicker;
    self.canvasView.colorPickerLocked = YES;
    ColorInspectorView *inspector = [self ensureColorInspector];
    inspector.hidden = NO;
    _textOptions.hidden = YES;
    [inspector updateWithColor:color];
    [inspector setLocked:YES animated:YES];
}

- (void)showTextToolForTesting {
    [self closeTextRecognizer];
    self.toolbarView.currentTool = ToolTypeText;
    self.canvasView.currentTool = ToolTypeText;
    TextOptionsView *opts = [self ensureTextOptions];
    opts.hidden = NO;
    _colorInspector.hidden = YES;
    [opts setFontSize:self.canvasView.textFontSize
                 bold:self.canvasView.textBold
           background:self.canvasView.textBackground];
}

- (void)addSampleTextForTesting {
    self.canvasView.textFontSize = 26.0;
    self.canvasView.textBold = YES;
    self.canvasView.textBackground = YES;
    Annotation *annotation = [Annotation new];
    annotation.toolType = ToolTypeText;
    annotation.color = [NSColor whiteColor];
    annotation.lineWidth = 0;
    annotation.text = @"Hello from Choxieshoot\nMulti-line text with a background";
    annotation.textPosition = NSMakePoint(40, 360);
    annotation.fontSize = 26.0;
    annotation.bold = YES;
    annotation.textBackground = YES;
    NSFont *font = [NSFont systemFontOfSize:26 weight:NSFontWeightBold];
    CGFloat maxWidth = 0;
    NSArray *lines = [annotation.text componentsSeparatedByString:@"\n"];
    NSDictionary *attributes = @{NSFontAttributeName: font,
                                 NSForegroundColorAttributeName: [NSColor whiteColor]};
    for (NSString *line in lines) {
        maxWidth = MAX(maxWidth, [line sizeWithAttributes:attributes].width);
    }
    annotation.path = [NSBezierPath bezierPathWithRect:NSMakeRect(40, 360 - 32.0 * lines.count,
                                                                  maxWidth, 32.0 * lines.count)];
    [self.canvasView addAnnotation:annotation];
}

- (NSString *)timestampString {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark - CanvasViewDelegate

- (void)canvasViewDidChangeAnnotations:(CanvasView *)canvas {
    [self refreshUndoState];
}

- (void)canvasView:(CanvasView *)canvas didPickColor:(NSColor *)color {
    self.toolbarView.currentColor = color;
    ColorInspectorView *inspector = [self ensureColorInspector];
    [inspector updateWithColor:color];
    [inspector setLocked:YES animated:YES];
}

- (void)canvasView:(CanvasView *)canvas didHoverColor:(NSColor *)color atPoint:(NSPoint)point {
    ColorInspectorView *inspector = [self ensureColorInspector];
    if (!inspector.isLocked) {
        [inspector updateWithColor:color];
    }
}

- (void)canvasView:(CanvasView *)canvas didChangeLineWidth:(CGFloat)width {
    self.toolbarView.currentLineWidth = width;
}

- (void)canvasView:(CanvasView *)canvas didChangeSelectedOCRIndexes:(NSIndexSet *)selectedIndexes {
    [_textRecognizerView updateSelectedIndexes:selectedIndexes];
}

- (void)canvasView:(CanvasView *)canvas didResizeCanvasToImage:(NSImage *)image {
    self.screenshot = image;
    self.ocrResult = nil;
    if (self.canvasView.ocrMode) {
        [self closeTextRecognizer];
    }
    [self selectTool:ToolTypeSelect];

    NSSize displaySize = self.canvasView.bounds.size;
    NSScreen *targetScreen = [self screenContainingRect:self.frame];
    NSRect visible = targetScreen != nil ? targetScreen.visibleFrame : [NSScreen mainScreen].visibleFrame;
    CGFloat minimumWidth = MIN(kMinContentWidth, MAX(visible.size.width - 20.0, 360.0));
    CGFloat contentWidth = MAX(displaySize.width, minimumWidth);
    CGFloat toolbarHeight = [ToolbarView preferredHeightForWidth:contentWidth];
    CGFloat contentHeight = displaySize.height + toolbarHeight + kCanvasGap + kHeaderHeight;
    self.toolbarHeight = toolbarHeight;

    CGFloat imageInset = floor((contentWidth - displaySize.width) / 2.0);
    NSRect oldFrame = self.frame;
    CGFloat originX = MIN(MAX(oldFrame.origin.x, NSMinX(visible)), NSMaxX(visible) - contentWidth);
    CGFloat originY = MIN(MAX(oldFrame.origin.y, NSMinY(visible)), NSMaxY(visible) - contentHeight);

    [self setFrame:NSMakeRect(originX, originY, contentWidth, contentHeight) display:YES animate:NO];
    self.contentView.frame = NSMakeRect(0, 0, contentWidth, contentHeight);
    self.headerBar.frame = NSMakeRect(0, contentHeight - kHeaderHeight, contentWidth, kHeaderHeight);
    [self layoutHeaderBarForWidth:contentWidth displaySize:displaySize];
    self.canvasView.frame = NSMakeRect(imageInset, toolbarHeight + kCanvasGap, displaySize.width, displaySize.height);
    self.toolbarView.frame = NSMakeRect(0, 0, contentWidth, toolbarHeight);

    [self showToast:[NSString stringWithFormat:@"Canvas %ld × %ld",
                     (long)lround(displaySize.width), (long)lround(displaySize.height)]
           duration:1.8];
}

#pragma mark - TextRecognizerViewDelegate

- (void)textRecognizerView:(TextRecognizerView *)view didCopyText:(NSString *)text {
    [self showToast:[NSString stringWithFormat:@"Copied %lu characters", (unsigned long)text.length]
           duration:2.0];
}

- (void)textRecognizerViewDidRequestSelectAllBlocks:(TextRecognizerView *)view {
    NSUInteger count = self.ocrResult.observations.count;
    NSIndexSet *all = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, count)];
    self.canvasView.selectedOCRIndexes = all;
    [self.textRecognizerView updateSelectedIndexes:all];
}

- (void)textRecognizerViewDidRequestClearBlocks:(TextRecognizerView *)view {
    NSIndexSet *empty = [NSIndexSet indexSet];
    self.canvasView.selectedOCRIndexes = empty;
    [self.textRecognizerView updateSelectedIndexes:empty];
}

- (void)textRecognizerViewDidRequestClose:(TextRecognizerView *)view {
    [self closeTextRecognizer];
}

#pragma mark - ToolbarViewDelegate

- (void)toolbarView:(ToolbarView *)toolbar didSelectTool:(ToolType)tool {
    if (self.canvasView.ocrMode) {
        [self closeTextRecognizer];
    }
    self.canvasView.currentTool = tool;
    BOOL sampling = (tool == ToolTypeColorPicker);
    if (sampling) {
        ColorInspectorView *inspector = [self ensureColorInspector];
        inspector.hidden = NO;
        self.canvasView.colorPickerLocked = NO;
        [inspector setLocked:NO animated:NO];
        [inspector updateWithColor:nil];
    } else {
        _colorInspector.hidden = YES;
    }

    switch (tool) {
        case ToolTypeText: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts setFontSize:self.canvasView.textFontSize
                         bold:self.canvasView.textBold
                   background:self.canvasView.textBackground];
            break;
        }
        case ToolTypeSpotlight: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForSpotlightShape:self.canvasView.spotlightShape
                                  dimOpacity:self.canvasView.spotlightDimOpacity
                                     feather:self.canvasView.spotlightFeather];
            break;
        }
        case ToolTypePixelate: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForRedactMode:self.canvasView.redactMode];
            break;
        }
        case ToolTypeArrow: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForArrowCurved:self.canvasView.arrowCurved];
            break;
        }
        case ToolTypeRectangle: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForRectangleRounded:self.canvasView.shapeRounded];
            break;
        }
        case ToolTypeCallout: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForCalloutSpeechBubble:self.canvasView.calloutSpeechBubble];
            break;
        }
        case ToolTypeLoupe: {
            TextOptionsView *opts = [self ensureTextOptions];
            opts.hidden = NO;
            [opts configureForLoupeMagnification:self.canvasView.loupeMagnification];
            break;
        }
        default:
            _textOptions.hidden = YES;
            break;
    }
    [self makeFirstResponder:self.canvasView];
}

- (void)toolbarView:(ToolbarView *)toolbar didSelectColor:(NSColor *)color {
    self.canvasView.currentColor = color;
}

- (void)toolbarView:(ToolbarView *)toolbar didChangeLineWidth:(CGFloat)width {
    self.canvasView.currentLineWidth = width;
}

- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeFilled:(BOOL)filled {
    self.canvasView.shapeFilled = filled;
}

- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeDashed:(BOOL)dashed {
    self.canvasView.shapeDashed = dashed;
}

- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeShadow:(BOOL)shadow {
    self.canvasView.shapeShadow = shadow;
}

- (void)toolbarViewDidRequestUndo:(ToolbarView *)toolbar {
    [self undo];
}

- (void)toolbarViewDidRequestRedo:(ToolbarView *)toolbar {
    [self redo];
}

- (void)toolbarViewDidRequestCopyText:(ToolbarView *)toolbar {
    [self toggleTextRecognizer];
}

- (void)toolbarViewDidRequestNewCapture:(ToolbarView *)toolbar {
    [[NSNotificationCenter defaultCenter] postNotificationName:ChoxieshootNewCaptureNotification object:nil];
}

- (void)toolbarViewDidRequestSave:(ToolbarView *)toolbar {
    [self saveImage];
}

- (void)toolbarViewDidRequestCopy:(ToolbarView *)toolbar {
    [self copyImage];
}

- (void)toolbarViewDidRequestShare:(ToolbarView *)toolbar {
    [self shareImage];
}

- (void)toolbarView:(ToolbarView *)toolbar didChangePinnedOnTop:(BOOL)pinned {
    [self setPinnedOnTop:pinned];
}

- (void)toolbarViewDidRequestMinimize:(ToolbarView *)toolbar {
    [self minimizeWindow:toolbar];
}

- (void)toolbarViewDidRequestClose:(ToolbarView *)toolbar {
    [self.canvasView commitTextEditorIfNeeded];
    [self close];
}

#pragma mark - NSWindowDelegate & Cleanup

- (void)performCleanupOnClose {
    if (self.didCleanUp) {
        return;
    }
    self.didCleanUp = YES;
    self.ocrInProgress = NO;

    [self.toastField removeFromSuperview];
    self.toastField = nil;

    [self.canvasView tearDown];
    self.canvasView.delegate = nil;
    self.toolbarView.delegate = nil;
    _textRecognizerView.delegate = nil;
    _colorInspector.onToggleLock = nil;
    _textOptions.onChange = nil;
    _textOptions.onSpotlightChange = nil;
    _textOptions.onRedactChange = nil;
    _textOptions.onArrowChange = nil;
    _textOptions.onRectChange = nil;
    _textOptions.onCalloutChange = nil;
    _textOptions.onLoupeChange = nil;

    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    miniBtn.target = nil;
    self.headerPinButton.target = nil;
    self.headerMinimizeButton.target = nil;
    self.headerCancelButton.target = nil;

    self.screenshot = nil;
    self.ocrResult = nil;
    self.miniwindowImage = nil;
    self.canvasView = nil;
    self.toolbarView = nil;
    self.colorInspector = nil;
    self.textOptions = nil;
    self.textRecognizerView = nil;
    self.headerBar = nil;
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];

    EditorWindowCloseBlock closeBlock = self.onClose;
    self.onClose = nil;
    if (closeBlock != nil) {
        closeBlock(self);
    }
    malloc_zone_pressure_relief(NULL, 0);
}

- (void)close {
    [self orderOut:nil];
    [self performCleanupOnClose];
    [super close];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self performCleanupOnClose];
}

@end
