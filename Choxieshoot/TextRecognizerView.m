#import "TextRecognizerView.h"
#import "CSTheme.h"

@interface TextRecognizerView () <NSTextViewDelegate>

@property (nonatomic, strong, nullable, readwrite) CSTextRecognitionResult *result;
@property (nonatomic, copy) NSIndexSet *selectedIndexes;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSButton *selectAllButton;
@property (nonatomic, strong) NSButton *clearButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, strong) NSButton *selectionCopyButton;
@property (nonatomic, strong) NSButton *allCopyButton;
@property (nonatomic, strong) NSView *barcodeBar;
@property (nonatomic, strong) NSTextField *barcodeLabel;
@property (nonatomic, strong) NSButton *barcodeCopyButton;
@property (nonatomic, strong) NSButton *openBarcodeButton;
@property (nonatomic) BOOL draggingHeader;
@property (nonatomic) NSPoint dragStartInSuperview;
@property (nonatomic) NSPoint initialOrigin;

@end

@implementation TextRecognizerView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        _selectedIndexes = [NSIndexSet indexSet];
        [self build];
    }
    return self;
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

    NSVisualEffectView *glassBackdrop = [CSTheme glassViewWithFrame:self.bounds
                                                           material:NSVisualEffectMaterialHUDWindow
                                                       cornerRadius:CSRadiusLarge];
    glassBackdrop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:glassBackdrop];

    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);

    self.titleLabel = [NSTextField labelWithString:@"TEXT RECOGNIZER"];
    self.titleLabel.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold];
    self.titleLabel.textColor = [CSTheme accent];
    self.titleLabel.frame = NSMakeRect(12, height - 22, 120, 12);
    [self addSubview:self.titleLabel];

    self.statusLabel = [NSTextField labelWithString:@"No text"];
    self.statusLabel.font = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium];
    self.statusLabel.textColor = [CSTheme mutedText];
    self.statusLabel.alignment = NSTextAlignmentRight;
    self.statusLabel.frame = NSMakeRect(130, height - 23, width - 162, 14);
    [self addSubview:self.statusLabel];

    self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - 28, height - 26, 20, 20)];
    self.closeButton.bordered = NO;
    self.closeButton.bezelStyle = NSBezelStyleInline;
    NSImage *closeImage = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close Text Recognizer"];
    if (closeImage != nil) {
        self.closeButton.image = closeImage;
        self.closeButton.imagePosition = NSImageOnly;
    } else {
        self.closeButton.title = @"×";
    }
    self.closeButton.contentTintColor = [CSTheme mutedText];
    self.closeButton.toolTip = @"Close Text Recognizer";
    self.closeButton.target = self;
    self.closeButton.action = @selector(closeClicked:);
    [self addSubview:self.closeButton];

    self.hintLabel = [NSTextField labelWithString:@"Click blocks on image or highlight text:"];
    self.hintLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightRegular];
    self.hintLabel.textColor = [CSTheme mutedText];
    self.hintLabel.frame = NSMakeRect(12, height - 44, width - 134, 14);
    self.hintLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.hintLabel];

    self.selectAllButton = [self smallActionButtonWithTitle:@"All"
                                                    tooltip:@"Select all text blocks on screenshot"
                                                     action:@selector(selectAllBlocksClicked:)];
    self.selectAllButton.frame = NSMakeRect(width - 114, height - 46, 48, 18);
    [self addSubview:self.selectAllButton];

    self.clearButton = [self smallActionButtonWithTitle:@"Clear"
                                                tooltip:@"Deselect all blocks so you can pick individual blocks"
                                                 action:@selector(clearBlocksClicked:)];
    self.clearButton.frame = NSMakeRect(width - 62, height - 46, 50, 18);
    [self addSubview:self.clearButton];

    self.barcodeBar = [[NSView alloc] initWithFrame:NSMakeRect(12, height - 74, width - 24, 24)];
    self.barcodeBar.wantsLayer = YES;
    self.barcodeBar.layer.backgroundColor = [CSTheme selectedToolBackground].CGColor;
    self.barcodeBar.layer.cornerRadius = CSRadiusSmall;
    self.barcodeBar.layer.borderWidth = 1.0;
    self.barcodeBar.layer.borderColor = [[CSTheme accent] colorWithAlphaComponent:0.55].CGColor;
    self.barcodeBar.hidden = YES;

    self.barcodeLabel = [NSTextField labelWithString:@"QR:"];
    self.barcodeLabel.font = [NSFont monospacedSystemFontOfSize:10.0 weight:NSFontWeightMedium];
    self.barcodeLabel.textColor = [CSTheme text];
    self.barcodeLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.barcodeLabel.frame = NSMakeRect(8, 4, NSWidth(self.barcodeBar.bounds) - 106, 15);
    [self.barcodeBar addSubview:self.barcodeLabel];

    self.barcodeCopyButton = [self smallActionButtonWithTitle:@"Copy QR"
                                                      tooltip:@"Copy QR code / barcode payload to clipboard"
                                                       action:@selector(copyBarcodeClicked:)];
    self.barcodeCopyButton.frame = NSMakeRect(NSWidth(self.barcodeBar.bounds) - 96, 3, 50, 18);
    [self.barcodeBar addSubview:self.barcodeCopyButton];

    self.openBarcodeButton = [self smallActionButtonWithTitle:@"Open"
                                                      tooltip:@"Open QR code URL in default browser"
                                                       action:@selector(openBarcodeClicked:)];
    self.openBarcodeButton.frame = NSMakeRect(NSWidth(self.barcodeBar.bounds) - 44, 3, 38, 18);
    [self.barcodeBar addSubview:self.openBarcodeButton];
    [self addSubview:self.barcodeBar];

    NSRect scrollFrame = NSMakeRect(12, 46, width - 24, height - 98);
    self.scrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.hasHorizontalScroller = NO;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.wantsLayer = YES;
    self.scrollView.layer.cornerRadius = CSRadiusSmall;
    self.scrollView.layer.borderWidth = 1.0;
    self.scrollView.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.8].CGColor;
    self.scrollView.drawsBackground = YES;
    self.scrollView.backgroundColor = [CSTheme surface];

    NSSize contentSize = self.scrollView.contentSize;
    self.textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    self.textView.minSize = NSMakeSize(0.0, contentSize.height);
    self.textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.textView.verticallyResizable = YES;
    self.textView.horizontallyResizable = NO;
    self.textView.autoresizingMask = NSViewWidthSizable;
    self.textView.textContainer.containerSize = NSMakeSize(contentSize.width, CGFLOAT_MAX);
    self.textView.textContainer.widthTracksTextView = YES;
    self.textView.textContainerInset = NSMakeSize(6.0, 6.0);
    self.textView.drawsBackground = YES;
    self.textView.backgroundColor = [CSTheme surface];
    self.textView.richText = NO;
    self.textView.editable = YES;
    self.textView.selectable = YES;
    self.textView.allowsUndo = YES;
    self.textView.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    self.textView.textColor = [CSTheme text];
    self.textView.insertionPointColor = [CSTheme accent];
    self.textView.delegate = self;

    self.scrollView.documentView = self.textView;
    [self addSubview:self.scrollView];

    self.selectionCopyButton = [NSButton buttonWithTitle:@"Copy Selected"
                                                  target:self
                                                  action:@selector(copySelectionClicked:)];
    self.selectionCopyButton.bezelStyle = NSBezelStyleRounded;
    self.selectionCopyButton.controlSize = NSControlSizeSmall;
    self.selectionCopyButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    if (@available(macOS 11.0, *)) {
        self.selectionCopyButton.bezelColor = [CSTheme accent];
    }
    self.selectionCopyButton.frame = NSMakeRect(12, 12, width - 118, 26);
    self.selectionCopyButton.toolTip = @"Copy the highlighted text or selected blocks to the clipboard";
    [self addSubview:self.selectionCopyButton];

    self.allCopyButton = [NSButton buttonWithTitle:@"Copy All"
                                            target:self
                                            action:@selector(copyAllClicked:)];
    self.allCopyButton.bezelStyle = NSBezelStyleRounded;
    self.allCopyButton.controlSize = NSControlSizeSmall;
    self.allCopyButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.allCopyButton.frame = NSMakeRect(width - 100, 12, 88, 26);
    self.allCopyButton.toolTip = @"Copy all recognized text from the entire screenshot";
    [self addSubview:self.allCopyButton];
}

- (NSButton *)smallActionButtonWithTitle:(NSString *)title tooltip:(NSString *)tooltip action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleInline;
    button.controlSize = NSControlSizeMini;
    button.font = [NSFont systemFontOfSize:9.5 weight:NSFontWeightMedium];
    button.toolTip = tooltip;
    return button;
}

#pragma mark - Header dragging

- (void)mouseDown:(NSEvent *)event {
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    if (local.y >= NSHeight(self.bounds) - 48.0) {
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

#pragma mark - Updating state

- (void)updateWithResult:(CSTextRecognitionResult *)result
         selectedIndexes:(NSIndexSet *)selectedIndexes {
    self.result = result;
    [self updateBarcodeBar];
    [self updateSelectedIndexes:selectedIndexes];
}

- (void)updateBarcodeBar {
    CGFloat width = NSWidth(self.bounds);
    CGFloat height = NSHeight(self.bounds);
    CSBarcodeObservation *firstBarcode = self.result.barcodes.firstObject;
    if (firstBarcode != nil) {
        self.barcodeBar.hidden = NO;
        self.barcodeBar.frame = NSMakeRect(12, height - 74, width - 24, 24);
        NSString *prefix = self.result.barcodes.count > 1
            ? [NSString stringWithFormat:@"%@ (%lu): ", firstBarcode.symbology, (unsigned long)self.result.barcodes.count]
            : [NSString stringWithFormat:@"%@: ", firstBarcode.symbology];
        self.barcodeLabel.stringValue = [prefix stringByAppendingString:firstBarcode.payload];
        self.barcodeLabel.toolTip = firstBarcode.payload;
        BOOL canOpen = firstBarcode.isURL;
        self.openBarcodeButton.hidden = !canOpen;
        CGFloat barW = NSWidth(self.barcodeBar.bounds);
        if (canOpen) {
            self.openBarcodeButton.frame = NSMakeRect(barW - 44, 3, 38, 18);
            self.barcodeCopyButton.frame = NSMakeRect(barW - 96, 3, 48, 18);
            self.barcodeLabel.frame = NSMakeRect(8, 4, barW - 108, 15);
        } else {
            self.barcodeCopyButton.frame = NSMakeRect(barW - 56, 3, 50, 18);
            self.barcodeLabel.frame = NSMakeRect(8, 4, barW - 68, 15);
        }
        self.scrollView.frame = NSMakeRect(12, 46, width - 24, height - 126);
    } else {
        self.barcodeBar.hidden = YES;
        self.scrollView.frame = NSMakeRect(12, 46, width - 24, height - 98);
    }
}

- (BOOL)hasDetectedBarcodes {
    return self.result.barcodes.count > 0;
}

- (void)triggerCopyBarcode {
    [self copyBarcodeClicked:self.barcodeCopyButton];
}

- (void)copyBarcodeClicked:(NSButton *)sender {
    CSBarcodeObservation *first = self.result.barcodes.firstObject;
    if (first.payload.length == 0) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:first.payload forType:NSPasteboardTypeString];

    sender.title = @"Copied!";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf.barcodeCopyButton.title = @"Copy QR";
        }
    });
    [self.delegate textRecognizerView:self didCopyText:first.payload];
}

- (void)openBarcodeClicked:(NSButton *)sender {
    CSBarcodeObservation *first = self.result.barcodes.firstObject;
    if (!first.isURL) {
        return;
    }
    NSString *trimmed = [first.payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:trimmed];
    if (url == nil) {
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:url];
    if ([self.delegate respondsToSelector:@selector(textRecognizerView:didOpenBarcodeURL:)]) {
        [self.delegate textRecognizerView:self didOpenBarcodeURL:url];
    }
}

- (void)updateSelectedIndexes:(NSIndexSet *)selectedIndexes {
    self.selectedIndexes = selectedIndexes ?: [NSIndexSet indexSet];
    NSString *composed = [self.result textForObservationIndexes:self.selectedIndexes] ?: @"";
    self.textView.string = composed;
    [self.textView setSelectedRange:NSMakeRange(0, 0)];
    [self refreshControls];
}

- (void)refreshControls {
    NSUInteger totalBlocks = self.result.observations.count;
    NSUInteger selectedBlocks = self.selectedIndexes.count;
    NSRange highlighted = self.textView.selectedRange;
    NSString *editorText = self.textView.string ?: @"";
    NSString *trimmedEditor = [editorText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (highlighted.length > 0 && NSMaxRange(highlighted) <= editorText.length) {
        NSString *sub = [[editorText substringWithRange:highlighted]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu chars highlighted", (unsigned long)sub.length];
        self.selectionCopyButton.title = [NSString stringWithFormat:@"Copy Highlighted (%lu)", (unsigned long)sub.length];
        self.selectionCopyButton.enabled = sub.length > 0;
    } else {
        if (totalBlocks > 0) {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu/%lu blocks · %lu chars",
                                            (unsigned long)selectedBlocks,
                                            (unsigned long)totalBlocks,
                                            (unsigned long)trimmedEditor.length];
        } else {
            self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu chars", (unsigned long)trimmedEditor.length];
        }
        if (selectedBlocks > 0 && selectedBlocks < totalBlocks) {
            self.selectionCopyButton.title = [NSString stringWithFormat:@"Copy Selected (%lu %@)",
                                              (unsigned long)selectedBlocks,
                                              selectedBlocks == 1 ? @"block" : @"blocks"];
        } else {
            self.selectionCopyButton.title = @"Copy Text";
        }
        self.selectionCopyButton.enabled = trimmedEditor.length > 0;
    }

    NSString *fullTrimmed = [self.result.fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.allCopyButton.enabled = fullTrimmed.length > 0;
    self.selectAllButton.enabled = (totalBlocks > 0 && selectedBlocks < totalBlocks);
    self.clearButton.enabled = (selectedBlocks > 0);
}

#pragma mark - NSTextViewDelegate

- (void)textViewDidChangeSelection:(NSNotification *)notification {
    if (notification.object == self.textView) {
        [self refreshControls];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.textView) {
        [self refreshControls];
    }
}

#pragma mark - Copy & selection actions

- (NSString *)effectiveTextToCopy {
    NSString *editorText = self.textView.string ?: @"";
    NSRange highlighted = self.textView.selectedRange;
    if (highlighted.length > 0 && NSMaxRange(highlighted) <= editorText.length) {
        NSString *sub = [editorText substringWithRange:highlighted];
        NSString *trimmedSub = [sub stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmedSub.length > 0) {
            return trimmedSub;
        }
    }
    return [editorText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)setHighlightedRange:(NSRange)range {
    NSString *editorText = self.textView.string ?: @"";
    NSRange safeRange = NSIntersectionRange(range, NSMakeRange(0, editorText.length));
    [self.textView setSelectedRange:safeRange];
    [self refreshControls];
}

- (void)triggerCopySelection {
    [self copySelectionClicked:self.selectionCopyButton];
}

- (void)triggerCopyAll {
    [self copyAllClicked:self.allCopyButton];
}

- (void)copySelectionClicked:(NSButton *)sender {
    NSString *toCopy = [self effectiveTextToCopy];
    if (toCopy.length == 0) {
        return;
    }
    [self writeToPasteboard:toCopy flashButton:sender];
}

- (void)copyAllClicked:(NSButton *)sender {
    NSString *full = [self.result.fullText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (full.length == 0) {
        return;
    }
    [self writeToPasteboard:full flashButton:sender];
}

- (void)writeToPasteboard:(NSString *)string flashButton:(NSButton *)button {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:string forType:NSPasteboardTypeString];

    button.title = @"Copied!";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (button == strongSelf.allCopyButton) {
            button.title = @"Copy All";
        } else {
            [strongSelf refreshControls];
        }
    });

    [self.delegate textRecognizerView:self didCopyText:string];
}

- (void)selectAllBlocksClicked:(id)sender {
    [self.delegate textRecognizerViewDidRequestSelectAllBlocks:self];
}

- (void)clearBlocksClicked:(id)sender {
    [self.delegate textRecognizerViewDidRequestClearBlocks:self];
}

- (void)closeClicked:(id)sender {
    [self.delegate textRecognizerViewDidRequestClose:self];
}

@end
