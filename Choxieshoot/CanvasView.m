#import "CanvasView.h"
#import "CSTheme.h"
#import "CSColorFormatter.h"

typedef NS_ENUM(NSInteger, CSDragHandle) {
    CSDragHandleNone = 0,
    CSDragHandleMove,
    CSDragHandleStart,
    CSDragHandleEnd,
    CSDragHandleControl,
    CSDragHandleMinXMinY,
    CSDragHandleMaxXMinY,
    CSDragHandleMinXMaxY,
    CSDragHandleMaxXMaxY
};

@interface CSCanvasSnapshot : NSObject
@property (nonatomic, copy) NSArray<Annotation *> *annotations;
@property (nonatomic, strong, nullable) NSImage *backgroundImage;
@property (nonatomic) NSSize canvasSize;
@end

@implementation CSCanvasSnapshot
@end

@interface CanvasView () <NSTextViewDelegate>

@property (nonatomic, strong) NSMutableArray<Annotation *> *annotations;
@property (nonatomic, strong) NSMutableArray<CSCanvasSnapshot *> *history;
@property (nonatomic) NSInteger historyIndex;
@property (nonatomic, strong, nullable) Annotation *previewAnnotation;
@property (nonatomic) BOOL dragging;
@property (nonatomic) NSPoint dragStart;
@property (nonatomic) NSPoint lastErasePoint;
@property (nonatomic, strong, nullable) NSTextView *activeTextView;
@property (nonatomic, strong, nullable) NSView *activeTextContainer;
@property (nonatomic) CGFloat textTopY;
@property (nonatomic) BOOL committingText;
@property (nonatomic) NSInteger editingAnnotationIndex;
@property (nonatomic, strong, nullable) NSTrackingArea *mouseTrackingArea;
@property (nonatomic, strong, nullable) NSColor *hoverColor;
@property (nonatomic) NSPoint hoverPoint;
@property (nonatomic) BOOL showHover;
@property (nonatomic) CGFloat colorLockPulseProgress;
@property (nonatomic, strong, nullable) NSTimer *colorLockPulseTimer;
@property (nonatomic) BOOL erasedDuringDrag;
@property (nonatomic) NSInteger hoveredOCRIndex;
@property (nonatomic) BOOL ocrDraggingMarquee;
@property (nonatomic) NSPoint ocrDragStart;
@property (nonatomic) NSRect ocrMarqueeRect;
@property (nonatomic, copy, nullable) NSIndexSet *ocrSelectionAtDragStart;

// Object manipulation state
@property (nonatomic) CSDragHandle activeDragHandle;
@property (nonatomic) NSPoint lastManipulatePoint;
@property (nonatomic) NSRect initialManipulateBounds;
@property (nonatomic) BOOL manipulatedDuringDrag;

@end

@implementation CanvasView

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

- (void)commonInit {
    _annotations = [NSMutableArray array];
    CSCanvasSnapshot *initial = [[CSCanvasSnapshot alloc] init];
    initial.annotations = @[];
    initial.canvasSize = self.bounds.size;
    _history = [NSMutableArray arrayWithObject:initial];
    _historyIndex = 0;
    _currentTool = ToolTypePencil;
    _currentColor = [NSColor systemRedColor];
    _currentLineWidth = 3.0;
    _shapeFilled = NO;
    _shapeDashed = NO;
    _shapeRounded = NO;
    _shapeShadow = NO;
    _arrowCurved = NO;
    _calloutSpeechBubble = NO;
    _spotlightShape = CSSpotlightShapeRoundedRect;
    _spotlightDimOpacity = 0.58;
    _spotlightFeather = YES;
    _redactMode = CSRedactModePixelate;
    _loupeMagnification = 2.2;
    _textFontSize = 18.0;
    _textBold = YES;
    _textBackground = NO;
    _selectedAnnotationIndex = NSNotFound;
    _editingAnnotationIndex = NSNotFound;
    _selectedOCRIndexes = [NSIndexSet indexSet];
    _hoveredOCRIndex = NSNotFound;
    self.wantsLayer = YES;
}

- (void)tearDown {
    [self.colorLockPulseTimer invalidate];
    self.colorLockPulseTimer = nil;
    if (self.mouseTrackingArea != nil) {
        [self removeTrackingArea:self.mouseTrackingArea];
        self.mouseTrackingArea = nil;
    }
    [self cancelActiveTextEditor];
    _backgroundImage = nil;
    [self.history removeAllObjects];
    [_annotations removeAllObjects];
    self.previewAnnotation = nil;
    self.ocrObservations = nil;
    self.ocrBarcodes = nil;
    self.hoverColor = nil;
}

- (void)dealloc {
    [_colorLockPulseTimer invalidate];
}

- (void)setBackgroundImage:(NSImage *)backgroundImage {
    _backgroundImage = backgroundImage;
    if (self.history.count == 1 && self.historyIndex == 0 && self.history[0].annotations.count == 0) {
        self.history[0].backgroundImage = backgroundImage;
        self.history[0].canvasSize = self.bounds.size;
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return NO;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (void)resetCursorRects {
    [super resetCursorRects];
    NSCursor *cursor = [NSCursor crosshairCursor];
    if (self.ocrMode) {
        cursor = [NSCursor pointingHandCursor];
    } else if (self.currentTool == ToolTypeText) {
        cursor = [NSCursor IBeamCursor];
    } else if (self.currentTool == ToolTypeSelect) {
        cursor = [NSCursor arrowCursor];
    }
    [self addCursorRect:self.bounds cursor:cursor];
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = event.scrollingDeltaY;
    if (fabs(delta) > 0.1) {
        CGFloat step = (delta > 0) ? 1.0 : -1.0;
        CGFloat newWidth = MIN(MAX(self.currentLineWidth + step, 1.0), 20.0);
        if (newWidth != self.currentLineWidth) {
            self.currentLineWidth = newWidth;
            if ([self.delegate respondsToSelector:@selector(canvasView:didChangeLineWidth:)]) {
                [(id)self.delegate canvasView:self didChangeLineWidth:newWidth];
            }
            [self setNeedsDisplay:YES];
        }
    } else {
        [super scrollWheel:event];
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.mouseTrackingArea != nil) {
        [self removeTrackingArea:self.mouseTrackingArea];
    }
    self.mouseTrackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                          options:(NSTrackingMouseMoved |
                                                                   NSTrackingMouseEnteredAndExited |
                                                                   NSTrackingActiveInKeyWindow |
                                                                   NSTrackingInVisibleRect)
                                                            owner:self
                                                         userInfo:nil];
    [self addTrackingArea:self.mouseTrackingArea];
}

#pragma mark - Selection & Style Propagation

- (Annotation *)selectedAnnotation {
    if (self.selectedAnnotationIndex != NSNotFound &&
        self.selectedAnnotationIndex >= 0 &&
        self.selectedAnnotationIndex < (NSInteger)self.annotations.count) {
        return self.annotations[self.selectedAnnotationIndex];
    }
    return nil;
}

- (void)setSelectedAnnotationIndex:(NSInteger)selectedAnnotationIndex {
    if (_selectedAnnotationIndex == selectedAnnotationIndex) {
        return;
    }
    _selectedAnnotationIndex = selectedAnnotationIndex;
    if ([self.delegate respondsToSelector:@selector(canvasView:didSelectAnnotation:)]) {
        [self.delegate canvasView:self didSelectAnnotation:self.selectedAnnotation];
    }
    [self setNeedsDisplay:YES];
}

- (void)clearSelection {
    self.selectedAnnotationIndex = NSNotFound;
}

- (void)clearPreviewAnnotation {
    self.previewAnnotation = nil;
    self.dragging = NO;
    [self setNeedsDisplay:YES];
}

- (void)deleteSelectedAnnotation {
    if (self.selectedAnnotationIndex != NSNotFound &&
        self.selectedAnnotationIndex >= 0 &&
        self.selectedAnnotationIndex < (NSInteger)self.annotations.count) {
        [_annotations removeObjectAtIndex:(NSUInteger)self.selectedAnnotationIndex];
        self.selectedAnnotationIndex = NSNotFound;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setCurrentColor:(NSColor *)currentColor {
    _currentColor = currentColor;
    if (self.activeTextView != nil) {
        [self applyTextStyleToActiveEditor];
    }
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil) {
        sel.color = (sel.toolType == ToolTypeMarker)
            ? [currentColor colorWithAlphaComponent:0.35]
            : currentColor;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setCurrentLineWidth:(CGFloat)currentLineWidth {
    _currentLineWidth = currentLineWidth;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil) {
        sel.lineWidth = (sel.toolType == ToolTypeMarker) ? currentLineWidth * 3.0 : currentLineWidth;
        [self rebuildGeometryForAnnotation:sel];
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setShapeFilled:(BOOL)shapeFilled {
    _shapeFilled = shapeFilled;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && (sel.toolType == ToolTypeRectangle || sel.toolType == ToolTypeEllipse)) {
        sel.filled = shapeFilled;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setShapeDashed:(BOOL)shapeDashed {
    _shapeDashed = shapeDashed;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil) {
        sel.dashed = shapeDashed;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setShapeRounded:(BOOL)shapeRounded {
    _shapeRounded = shapeRounded;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && sel.toolType == ToolTypeRectangle) {
        sel.cornerRadius = shapeRounded ? MAX(8.0, sel.lineWidth * 2.5) : 0.0;
        [self rebuildGeometryForAnnotation:sel];
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setShapeShadow:(BOOL)shapeShadow {
    _shapeShadow = shapeShadow;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil) {
        sel.hasShadow = shapeShadow;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setArrowCurved:(BOOL)arrowCurved {
    _arrowCurved = arrowCurved;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && sel.toolType == ToolTypeArrow) {
        sel.curved = arrowCurved;
        if (arrowCurved && !sel.hasCustomControlPoint) {
            sel.controlPoint = [self defaultControlPointFrom:sel.startPoint to:sel.endPoint];
        }
        [self rebuildGeometryForAnnotation:sel];
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setSpotlightShape:(CSSpotlightShape)spotlightShape {
    _spotlightShape = spotlightShape;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && sel.toolType == ToolTypeSpotlight) {
        sel.spotlightShape = spotlightShape;
        [self recordSnapshot];
    } else {
        // Also update the most recent spotlight if we are currently in Spotlight mode
        for (NSInteger i = (NSInteger)self.annotations.count - 1; i >= 0; i--) {
            if (self.annotations[i].toolType == ToolTypeSpotlight) {
                self.annotations[i].spotlightShape = spotlightShape;
                [self recordSnapshot];
                break;
            }
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)setSpotlightDimOpacity:(CGFloat)spotlightDimOpacity {
    _spotlightDimOpacity = MIN(MAX(spotlightDimOpacity, 0.20), 0.88);
    for (Annotation *ann in self.annotations) {
        if (ann.toolType == ToolTypeSpotlight) {
            ann.spotlightDimOpacity = _spotlightDimOpacity;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)setSpotlightFeather:(BOOL)spotlightFeather {
    _spotlightFeather = spotlightFeather;
    for (Annotation *ann in self.annotations) {
        if (ann.toolType == ToolTypeSpotlight) {
            ann.spotlightFeather = spotlightFeather;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)setRedactMode:(CSRedactMode)redactMode {
    _redactMode = redactMode;
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && sel.toolType == ToolTypePixelate) {
        sel.redactMode = redactMode;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

- (void)setLoupeMagnification:(CGFloat)loupeMagnification {
    _loupeMagnification = MIN(MAX(loupeMagnification, 1.5), 4.0);
    Annotation *sel = self.selectedAnnotation;
    if (sel != nil && sel.toolType == ToolTypeLoupe) {
        sel.loupeMagnification = _loupeMagnification;
        [self recordSnapshot];
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Undo / redo history

- (BOOL)canUndo {
    return self.historyIndex > 0;
}

- (BOOL)canRedo {
    return self.historyIndex + 1 < (NSInteger)self.history.count;
}

- (void)recordSnapshot {
    while ((NSInteger)self.history.count > self.historyIndex + 1) {
        [self.history removeLastObject];
    }
    NSMutableArray<Annotation *> *copiedAnnotations = [NSMutableArray arrayWithCapacity:self.annotations.count];
    for (Annotation *ann in self.annotations) {
        [copiedAnnotations addObject:[ann copy]];
    }
    CSCanvasSnapshot *snap = [[CSCanvasSnapshot alloc] init];
    snap.annotations = copiedAnnotations;
    snap.backgroundImage = self.backgroundImage;
    snap.canvasSize = self.bounds.size;
    [self.history addObject:snap];
    static const NSUInteger kMaxUndoHistory = 25;
    while (self.history.count > kMaxUndoHistory) {
        [self.history removeObjectAtIndex:0];
    }
    self.historyIndex = (NSInteger)self.history.count - 1;
    [self.delegate canvasViewDidChangeAnnotations:self];
}

- (void)restoreHistoryAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.history.count) {
        return;
    }
    self.historyIndex = index;
    CSCanvasSnapshot *snap = self.history[index];
    NSMutableArray<Annotation *> *restored = [NSMutableArray arrayWithCapacity:snap.annotations.count];
    for (Annotation *ann in snap.annotations) {
        [restored addObject:[ann copy]];
    }
    self.annotations = restored;
    if (self.selectedAnnotationIndex >= (NSInteger)self.annotations.count) {
        self.selectedAnnotationIndex = NSNotFound;
    }
    BOOL imageChanged = (snap.backgroundImage != nil && snap.backgroundImage != _backgroundImage) ||
                        (!NSEqualSizes(snap.canvasSize, NSZeroSize) && !NSEqualSizes(snap.canvasSize, self.bounds.size));
    if (snap.backgroundImage != nil) {
        _backgroundImage = snap.backgroundImage;
    }
    if (imageChanged && !NSEqualSizes(snap.canvasSize, NSZeroSize)) {
        [self setFrameSize:snap.canvasSize];
        if ([self.delegate respondsToSelector:@selector(canvasView:didResizeCanvasToImage:)] && _backgroundImage != nil) {
            [self.delegate canvasView:self didResizeCanvasToImage:_backgroundImage];
        }
    }
    [self setNeedsDisplay:YES];
    [self.delegate canvasViewDidChangeAnnotations:self];
}

- (void)undo {
    if (!self.canUndo) {
        return;
    }
    [self restoreHistoryAtIndex:self.historyIndex - 1];
}

- (void)redo {
    if (!self.canRedo) {
        return;
    }
    [self restoreHistoryAtIndex:self.historyIndex + 1];
}

- (void)addAnnotation:(Annotation *)annotation {
    [_annotations addObject:annotation];
    [self recordSnapshot];
    [self setNeedsDisplay:YES];
}

#pragma mark - Tool state

- (void)setOcrMode:(BOOL)ocrMode {
    if (_ocrMode == ocrMode) {
        return;
    }
    _ocrMode = ocrMode;
    self.hoveredOCRIndex = NSNotFound;
    self.ocrDraggingMarquee = NO;
    if (ocrMode) {
        [self commitActiveTextEditor];
        self.previewAnnotation = nil;
        self.dragging = NO;
        self.showHover = NO;
        self.selectedAnnotationIndex = NSNotFound;
    }
    [self.window invalidateCursorRectsForView:self];
    [self setNeedsDisplay:YES];
}

- (void)setOcrObservations:(NSArray<CSTextObservation *> *)ocrObservations {
    _ocrObservations = [ocrObservations copy];
    self.hoveredOCRIndex = NSNotFound;
    [self setNeedsDisplay:YES];
}

- (void)setOcrBarcodes:(NSArray<CSBarcodeObservation *> *)ocrBarcodes {
    _ocrBarcodes = [ocrBarcodes copy];
    [self setNeedsDisplay:YES];
}

- (NSInteger)nextCalloutNumber {
    NSInteger maxNum = 0;
    for (Annotation *ann in self.annotations) {
        if (ann.toolType == ToolTypeCallout && !ann.speechBubble && ann.calloutNumber > maxNum) {
            maxNum = ann.calloutNumber;
        }
    }
    return maxNum + 1;
}

- (void)cropToRect:(NSRect)cropRect {
    NSRect clamped = NSIntersectionRect(NSIntegralRect(cropRect), self.bounds);
    if (NSWidth(clamped) < 16.0 || NSHeight(clamped) < 16.0 || self.backgroundImage == nil) {
        return;
    }

    CGImageRef cgImage = [self.backgroundImage CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (cgImage == NULL) {
        return;
    }

    CGFloat scaleX = (CGFloat)CGImageGetWidth(cgImage) / MAX(NSWidth(self.bounds), 1.0);
    CGFloat scaleY = (CGFloat)CGImageGetHeight(cgImage) / MAX(NSHeight(self.bounds), 1.0);
    CGFloat pixelX = round(clamped.origin.x * scaleX);
    CGFloat pixelY = round((NSHeight(self.bounds) - NSMaxY(clamped)) * scaleY);
    CGFloat pixelW = MAX(round(clamped.size.width * scaleX), 1.0);
    CGFloat pixelH = MAX(round(clamped.size.height * scaleY), 1.0);
    CGRect cgCropRect = CGRectIntersection(CGRectMake(pixelX, pixelY, pixelW, pixelH),
                                           CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)));
    if (CGRectIsEmpty(cgCropRect)) {
        return;
    }

    CGImageRef croppedCG = CGImageCreateWithImageInRect(cgImage, cgCropRect);
    if (croppedCG == NULL) {
        return;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:croppedCG];
    CGImageRelease(croppedCG);
    rep.size = clamped.size;
    NSImage *croppedImage = [[NSImage alloc] initWithSize:clamped.size];
    [croppedImage addRepresentation:rep];

    if (self.historyIndex >= 0 && self.historyIndex < (NSInteger)self.history.count) {
        CSCanvasSnapshot *curr = self.history[self.historyIndex];
        if (curr.backgroundImage == nil) {
            curr.backgroundImage = _backgroundImage;
        }
        if (NSEqualSizes(curr.canvasSize, NSZeroSize)) {
            curr.canvasSize = self.bounds.size;
        }
    }

    for (Annotation *ann in self.annotations) {
        [ann translateByX:-clamped.origin.x y:-clamped.origin.y];
    }

    _backgroundImage = croppedImage;
    [self setFrameSize:clamped.size];
    [self recordSnapshot];
    self.currentTool = ToolTypeSelect;
    if ([self.delegate respondsToSelector:@selector(canvasView:didResizeCanvasToImage:)]) {
        [self.delegate canvasView:self didResizeCanvasToImage:croppedImage];
    }
    [self setNeedsDisplay:YES];
}

- (void)setSelectedOCRIndexes:(NSIndexSet *)selectedOCRIndexes {
    _selectedOCRIndexes = [selectedOCRIndexes copy] ?: [NSIndexSet indexSet];
    [self setNeedsDisplay:YES];
}

- (void)setCurrentTool:(ToolType)currentTool {
    if (_currentTool == currentTool) {
        return;
    }
    [self commitActiveTextEditor];
    self.previewAnnotation = nil;
    self.dragging = NO;
    self.showHover = NO;
    self.colorPickerLocked = NO;
    if (currentTool != ToolTypeSelect && currentTool != ToolTypeSpotlight) {
        self.selectedAnnotationIndex = NSNotFound;
    }
    _currentTool = currentTool;
    [self updateTrackingAreas];
    [self.window invalidateCursorRectsForView:self];
    [self setNeedsDisplay:YES];
}

- (void)setColorPickerLocked:(BOOL)colorPickerLocked {
    _colorPickerLocked = colorPickerLocked;
    [self.colorLockPulseTimer invalidate];
    self.colorLockPulseTimer = nil;
    if (colorPickerLocked) {
        self.colorLockPulseProgress = 0.001;
        __weak typeof(self) weakSelf = self;
        self.colorLockPulseTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
                                                                   repeats:YES
                                                                     block:^(NSTimer *timer) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                [timer invalidate];
                return;
            }
            strongSelf.colorLockPulseProgress += (1.0 / 22.0);
            if (strongSelf.colorLockPulseProgress >= 1.0) {
                strongSelf.colorLockPulseProgress = 0.0;
                [timer invalidate];
                strongSelf.colorLockPulseTimer = nil;
            }
            [strongSelf setNeedsDisplay:YES];
        }];
    } else {
        self.colorLockPulseProgress = 0.0;
    }
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    if (self.backgroundImage != nil) {
        [self.backgroundImage drawInRect:self.bounds
                                fromRect:NSZeroRect
                               operation:NSCompositingOperationCopy
                                fraction:1.0];
    } else {
        [[NSColor darkGrayColor] setFill];
        NSRectFill(self.bounds);
    }

    [self drawAllAnnotationsIncludingPreview:YES];

    if (self.selectedAnnotation != nil && !self.ocrMode) {
        [self drawSelectionHandlesForAnnotation:self.selectedAnnotation];
    }

    if (self.previewAnnotation != nil && self.previewAnnotation.toolType == ToolTypeCrop) {
        [self drawCropPreview:self.previewAnnotation];
    }

    if (self.currentTool == ToolTypeEraser && (self.dragging || self.showHover)) {
        [self drawEraserCursorAtPoint:self.lastErasePoint];
    }

    if (self.currentTool == ToolTypeColorPicker && (self.showHover || self.colorPickerLocked) && self.hoverColor != nil) {
        [self drawColorPickerLoupeAtPoint:self.hoverPoint color:self.hoverColor];
    }

    if (self.ocrMode) {
        [self drawOCROverlay];
    }

    [self drawSizeBadge];
}

- (void)drawAllAnnotationsIncludingPreview:(BOOL)includePreview {
    // 1. Draw pixelate / blur redaction annotations first so they redact the underlying screenshot
    for (Annotation *annotation in self.annotations) {
        if (annotation.toolType == ToolTypePixelate) {
            [self drawPixelateAnnotation:annotation isPreview:NO];
        }
    }
    if (includePreview && self.previewAnnotation != nil && self.previewAnnotation.toolType == ToolTypePixelate) {
        [self drawPixelateAnnotation:self.previewAnnotation isPreview:YES];
    }

    // 2. Draw spotlight dimming layer (if any spotlights exist)
    NSMutableArray<Annotation *> *spotlights = [NSMutableArray array];
    for (Annotation *annotation in self.annotations) {
        if (annotation.toolType == ToolTypeSpotlight && NSWidth(annotation.path.bounds) >= 2.0 && NSHeight(annotation.path.bounds) >= 2.0) {
            [spotlights addObject:annotation];
        }
    }
    if (includePreview && self.previewAnnotation != nil && self.previewAnnotation.toolType == ToolTypeSpotlight &&
        NSWidth(self.previewAnnotation.path.bounds) >= 2.0 && NSHeight(self.previewAnnotation.path.bounds) >= 2.0) {
        [spotlights addObject:self.previewAnnotation];
    }
    if (spotlights.count > 0) {
        [self drawSpotlightAnnotations:spotlights];
    }

    // 3. Draw all remaining annotations in order (skipping one currently being edited as text)
    for (NSInteger i = 0; i < (NSInteger)self.annotations.count; i++) {
        if (includePreview && i == self.editingAnnotationIndex && self.activeTextView != nil) {
            continue;
        }
        Annotation *annotation = self.annotations[i];
        if (annotation.toolType != ToolTypePixelate && annotation.toolType != ToolTypeSpotlight && annotation.toolType != ToolTypeCrop) {
            [self drawAnnotation:annotation];
        }
    }
    if (includePreview && self.previewAnnotation != nil &&
        self.previewAnnotation.toolType != ToolTypePixelate &&
        self.previewAnnotation.toolType != ToolTypeSpotlight &&
        self.previewAnnotation.toolType != ToolTypeCrop) {
        [self drawAnnotation:self.previewAnnotation];
    }
}

- (void)drawOCROverlay {
    [[[NSColor blackColor] colorWithAlphaComponent:0.18] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    NSInteger count = (NSInteger)self.ocrObservations.count;
    for (NSInteger i = 0; i < count; i++) {
        CSTextObservation *obs = self.ocrObservations[i];
        NSRect box = [obs rectInBounds:self.bounds];
        BOOL selected = [self.selectedOCRIndexes containsIndex:(NSUInteger)i];
        BOOL hovered = (self.hoveredOCRIndex == i);

        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:box xRadius:4.0 yRadius:4.0];
        if (selected) {
            [[[CSTheme accent] colorWithAlphaComponent:0.24] setFill];
            [pill fill];
            [[CSTheme accent] setStroke];
            pill.lineWidth = 2.0;
            [pill stroke];

            CGFloat badgeSize = 14.0;
            NSRect badgeRect = NSMakeRect(NSMaxX(box) - badgeSize * 0.65,
                                          NSMaxY(box) - badgeSize * 0.65,
                                          badgeSize,
                                          badgeSize);
            NSBezierPath *badgeCircle = [NSBezierPath bezierPathWithOvalInRect:badgeRect];
            [[CSTheme accent] setFill];
            [badgeCircle fill];
            [[NSColor whiteColor] setStroke];
            badgeCircle.lineWidth = 1.0;
            [badgeCircle stroke];

            NSBezierPath *check = [NSBezierPath bezierPath];
            [check moveToPoint:NSMakePoint(NSMinX(badgeRect) + 3.5, NSMidY(badgeRect) - 0.5)];
            [check lineToPoint:NSMakePoint(NSMidX(badgeRect) - 0.5, NSMinY(badgeRect) + 3.5)];
            [check lineToPoint:NSMakePoint(NSMaxX(badgeRect) - 3.2, NSMaxY(badgeRect) - 3.8)];
            check.lineWidth = 1.6;
            check.lineCapStyle = NSLineCapStyleRound;
            check.lineJoinStyle = NSLineJoinStyleRound;
            [[CSTheme onAccent] setStroke];
            [check stroke];
        } else if (hovered) {
            [[[CSTheme accent] colorWithAlphaComponent:0.15] setFill];
            [pill fill];
            [[[CSTheme accent] colorWithAlphaComponent:0.9] setStroke];
            pill.lineWidth = 1.5;
            [pill stroke];
        } else {
            [[[NSColor whiteColor] colorWithAlphaComponent:0.08] setFill];
            [pill fill];
            CGFloat dashes[2] = {3.0, 2.0};
            [pill setLineDash:dashes count:2 phase:0];
            [[[CSTheme accent] colorWithAlphaComponent:0.65] setStroke];
            pill.lineWidth = 1.2;
            [pill stroke];
        }
    }

    if (self.ocrDraggingMarquee && !NSIsEmptyRect(self.ocrMarqueeRect)) {
        NSBezierPath *marquee = [NSBezierPath bezierPathWithRoundedRect:self.ocrMarqueeRect xRadius:3.0 yRadius:3.0];
        [[[CSTheme accent] colorWithAlphaComponent:0.18] setFill];
        [marquee fill];
        [[CSTheme accent] setStroke];
        marquee.lineWidth = 1.5;
        [marquee stroke];
    }

    for (CSBarcodeObservation *barcode in self.ocrBarcodes) {
        NSRect box = [barcode rectInBounds:self.bounds];
        NSBezierPath *qrBox = [NSBezierPath bezierPathWithRoundedRect:box xRadius:6.0 yRadius:6.0];
        [[[CSTheme accent] colorWithAlphaComponent:0.20] setFill];
        [qrBox fill];
        [[CSTheme accent] setStroke];
        qrBox.lineWidth = 2.0;
        [qrBox stroke];

        NSString *tag = barcode.symbology ?: @"QR";
        NSDictionary *tagAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [CSTheme onAccent]
        };
        NSSize tagSize = [tag sizeWithAttributes:tagAttrs];
        NSRect tagRect = NSMakeRect(NSMinX(box), NSMaxY(box) - tagSize.height - 4.0,
                                    tagSize.width + 8.0, tagSize.height + 4.0);
        NSBezierPath *tagPill = [NSBezierPath bezierPathWithRoundedRect:tagRect xRadius:3.0 yRadius:3.0];
        [[CSTheme accent] setFill];
        [tagPill fill];
        [tag drawAtPoint:NSMakePoint(NSMinX(tagRect) + 4.0, NSMinY(tagRect) + 2.0) withAttributes:tagAttrs];
    }
}

- (NSInteger)hitOCRIndexAtPoint:(NSPoint)point {
    for (NSInteger i = (NSInteger)self.ocrObservations.count - 1; i >= 0; i--) {
        NSRect box = [self.ocrObservations[i] rectInBounds:self.bounds];
        if (NSPointInRect(point, NSInsetRect(box, -2.0, -2.0))) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)drawAnnotation:(Annotation *)annotation {
    if (annotation.toolType == ToolTypeLoupe) {
        [self drawLoupeAnnotation:annotation];
        return;
    }
    if (annotation.toolType == ToolTypeCallout) {
        [self drawCalloutAnnotation:annotation];
        return;
    }
    if (annotation.toolType == ToolTypeText) {
        if (annotation.text.length > 0) {
            [self drawTextAnnotation:annotation];
        }
        return;
    }

    NSBezierPath *path = [annotation.path copy];
    path.lineWidth = annotation.lineWidth;
    path.lineCapStyle = NSLineCapStyleRound;
    path.lineJoinStyle = NSLineJoinStyleRound;

    if (annotation.dashed && (annotation.toolType == ToolTypeLine ||
                              annotation.toolType == ToolTypeRectangle ||
                              annotation.toolType == ToolTypeEllipse ||
                              annotation.toolType == ToolTypeArrow)) {
        CGFloat dashLen = MAX(6.0, annotation.lineWidth * 2.4);
        CGFloat gapLen = MAX(4.0, annotation.lineWidth * 1.6);
        CGFloat pattern[2] = {dashLen, gapLen};
        [path setLineDash:pattern count:2 phase:0];
    }

    [NSGraphicsContext saveGraphicsState];
    if (annotation.hasShadow && annotation.toolType != ToolTypeMarker) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.38];
        shadow.shadowBlurRadius = 6.0;
        shadow.shadowOffset = NSMakeSize(0, -2.0);
        [shadow set];
    }

    [annotation.color setStroke];
    [annotation.color setFill];

    switch (annotation.toolType) {
        case ToolTypePencil:
        case ToolTypeLine:
        case ToolTypeMarker:
            [path stroke];
            break;

        case ToolTypeArrow:
            [self drawArrowAnnotation:annotation];
            break;

        case ToolTypeRectangle:
        case ToolTypeEllipse:
            if (annotation.filled) {
                [path fill];
            } else {
                [path stroke];
            }
            break;

        default:
            [path stroke];
            break;
    }
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawArrowAnnotation:(Annotation *)annotation {
    NSPoint start = annotation.startPoint;
    NSPoint end = annotation.endPoint;
    if (NSEqualPoints(start, NSZeroPoint) && NSEqualPoints(end, NSZeroPoint)) {
        [annotation.path fill];
        [annotation.path stroke];
        return;
    }
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat length = hypot(dx, dy);
    if (length < 0.001) {
        return;
    }
    CGFloat lineWidth = MAX(annotation.lineWidth, 1.5);
    CGFloat headLength = MAX(14.0, lineWidth * 4.4);
    CGFloat headWidth = MAX(11.0, lineWidth * 3.4);
    if (headLength > length * 0.72) {
        headLength = MAX(length * 0.72, 4.0);
        headWidth = headLength * 0.82;
    }

    NSPoint tangentDir;
    NSBezierPath *shaft = [NSBezierPath bezierPath];
    shaft.lineWidth = lineWidth;
    shaft.lineCapStyle = NSLineCapStyleRound;
    shaft.lineJoinStyle = NSLineJoinStyleRound;
    if (annotation.dashed) {
        CGFloat pattern[2] = {MAX(6.0, lineWidth * 2.2), MAX(4.0, lineWidth * 1.5)};
        [shaft setLineDash:pattern count:2 phase:0];
    }

    if (annotation.curved) {
        NSPoint ctrl = annotation.hasCustomControlPoint
            ? annotation.controlPoint
            : [self defaultControlPointFrom:start to:end];
        CGFloat tx = end.x - ctrl.x;
        CGFloat ty = end.y - ctrl.y;
        CGFloat tlen = hypot(tx, ty);
        if (tlen < 0.001) {
            tx = dx;
            ty = dy;
            tlen = length;
        }
        tangentDir = NSMakePoint(tx / tlen, ty / tlen);
        NSPoint shaftEnd = NSMakePoint(end.x - tangentDir.x * headLength * 0.65,
                                       end.y - tangentDir.y * headLength * 0.65);
        [shaft moveToPoint:start];
        NSPoint cp1 = NSMakePoint(start.x + (2.0 / 3.0) * (ctrl.x - start.x),
                                  start.y + (2.0 / 3.0) * (ctrl.y - start.y));
        NSPoint cp2 = NSMakePoint(shaftEnd.x + (2.0 / 3.0) * (ctrl.x - shaftEnd.x),
                                  shaftEnd.y + (2.0 / 3.0) * (ctrl.y - shaftEnd.y));
        [shaft curveToPoint:shaftEnd controlPoint1:cp1 controlPoint2:cp2];
    } else {
        tangentDir = NSMakePoint(dx / length, dy / length);
        NSPoint shaftEnd = NSMakePoint(end.x - tangentDir.x * headLength * 0.65,
                                       end.y - tangentDir.y * headLength * 0.65);
        [shaft moveToPoint:start];
        [shaft lineToPoint:shaftEnd];
    }

    [shaft stroke];

    // Swept-back concave arrowhead
    NSPoint base = NSMakePoint(end.x - tangentDir.x * headLength, end.y - tangentDir.y * headLength);
    NSPoint notch = NSMakePoint(end.x - tangentDir.x * (headLength * 0.76), end.y - tangentDir.y * (headLength * 0.76));
    NSPoint left = NSMakePoint(base.x - tangentDir.y * headWidth * 0.5, base.y + tangentDir.x * headWidth * 0.5);
    NSPoint right = NSMakePoint(base.x + tangentDir.y * headWidth * 0.5, base.y - tangentDir.x * headWidth * 0.5);

    NSBezierPath *head = [NSBezierPath bezierPath];
    [head moveToPoint:end];
    [head lineToPoint:left];
    [head lineToPoint:notch];
    [head lineToPoint:right];
    [head closePath];
    head.lineJoinStyle = NSLineJoinStyleRound;
    head.lineWidth = MAX(1.2, lineWidth * 0.35);
    [head fill];
    [head stroke];
}

- (void)drawLoupeAnnotation:(Annotation *)annotation {
    NSRect rect = annotation.path.bounds;
    if (NSWidth(rect) < 8.0 || NSHeight(rect) < 8.0) {
        return;
    }
    CGFloat zoom = MAX(annotation.loupeMagnification, 1.5);
    NSBezierPath *clipPath = [NSBezierPath bezierPathWithOvalInRect:rect];

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.45];
    shadow.shadowBlurRadius = 10.0;
    shadow.shadowOffset = NSMakeSize(0, -3.0);
    [shadow set];
    [[NSColor colorWithWhite:0.1 alpha:0.95] setFill];
    [clipPath fill];
    [NSGraphicsContext restoreGraphicsState];

    [NSGraphicsContext saveGraphicsState];
    [clipPath addClip];

    if (self.backgroundImage != nil) {
        NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
        NSSize srcSize = NSMakeSize(NSWidth(rect) / zoom, NSHeight(rect) / zoom);
        NSRect srcBoundsRect = NSMakeRect(center.x - srcSize.width * 0.5,
                                          center.y - srcSize.height * 0.5,
                                          srcSize.width,
                                          srcSize.height);
        // Map from view bounds to backgroundImage coordinate space
        CGFloat scaleX = self.backgroundImage.size.width / MAX(NSWidth(self.bounds), 1.0);
        CGFloat scaleY = self.backgroundImage.size.height / MAX(NSHeight(self.bounds), 1.0);
        NSRect imgFromRect = NSMakeRect(srcBoundsRect.origin.x * scaleX,
                                        srcBoundsRect.origin.y * scaleY,
                                        srcBoundsRect.size.width * scaleX,
                                        srcBoundsRect.size.height * scaleY);
        [self.backgroundImage drawInRect:rect
                                fromRect:imgFromRect
                               operation:NSCompositingOperationSourceOver
                                fraction:1.0];
    }

    // Subtle glass lens sheen in upper half
    NSBezierPath *sheen = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMinX(rect) + NSWidth(rect) * 0.1,
                                                                            NSMidY(rect) + NSHeight(rect) * 0.05,
                                                                            NSWidth(rect) * 0.8,
                                                                            NSHeight(rect) * 0.42)];
    [[[NSColor whiteColor] colorWithAlphaComponent:0.12] setFill];
    [sheen fill];
    [NSGraphicsContext restoreGraphicsState];

    // Outer & inner lens rings
    NSBezierPath *outerRing = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, -1.0, -1.0)];
    outerRing.lineWidth = MAX(2.5, annotation.lineWidth * 0.85);
    [(annotation.color ?: [NSColor whiteColor]) setStroke];
    [outerRing stroke];

    NSBezierPath *innerRing = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, 1.5, 1.5)];
    innerRing.lineWidth = 1.5;
    [[[NSColor whiteColor] colorWithAlphaComponent:0.85] setStroke];
    [innerRing stroke];
}

- (void)drawPixelateAnnotation:(Annotation *)annotation isPreview:(BOOL)isPreview {
    NSRect rect = NSIntersectionRect(annotation.path.bounds, self.bounds);
    if (NSWidth(rect) < 2.0 || NSHeight(rect) < 2.0) {
        return;
    }
    CGImageRef cgImage = [self.backgroundImage CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (cgImage == NULL) {
        [[NSColor darkGrayColor] setFill];
        NSRectFill(rect);
        return;
    }

    size_t imgW = CGImageGetWidth(cgImage);
    size_t imgH = CGImageGetHeight(cgImage);
    if (imgW == 0 || imgH == 0) {
        return;
    }

    CGFloat scaleX = (CGFloat)imgW / MAX(NSWidth(self.bounds), 1.0);
    CGFloat scaleY = (CGFloat)imgH / MAX(NSHeight(self.bounds), 1.0);

    NSInteger padPx = (annotation.redactMode == CSRedactModeBlur)
        ? (NSInteger)MAX(4.0, round(annotation.lineWidth * 2.2 * scaleX)) + 2
        : 2;
    NSInteger cropMinX = MAX(0, (NSInteger)floor(NSMinX(rect) * scaleX) - padPx);
    NSInteger cropMinY = MAX(0, (NSInteger)floor((NSHeight(self.bounds) - NSMaxY(rect)) * scaleY) - padPx);
    NSInteger cropMaxX = MIN((NSInteger)imgW, (NSInteger)ceil(NSMaxX(rect) * scaleX) + padPx);
    NSInteger cropMaxY = MIN((NSInteger)imgH, (NSInteger)ceil((NSHeight(self.bounds) - NSMinY(rect)) * scaleY) + padPx);
    size_t cropW = (size_t)MAX(1, cropMaxX - cropMinX);
    size_t cropH = (size_t)MAX(1, cropMaxY - cropMinY);

    CGImageRef subImage = CGImageCreateWithImageInRect(cgImage, CGRectMake(cropMinX, cropMinY, cropW, cropH));
    if (subImage == NULL) {
        return;
    }

    size_t bytesPerRow = cropW * 4;
    uint8_t *buf = (uint8_t *)calloc(cropH, bytesPerRow);
    if (buf == NULL) {
        CGImageRelease(subImage);
        return;
    }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef bmp = CGBitmapContextCreate(buf, cropW, cropH, 8, bytesPerRow, cs, kCGImageAlphaPremultipliedLast);
    if (bmp != NULL) {
        CGContextDrawImage(bmp, CGRectMake(0, 0, cropW, cropH), subImage);
        CGContextRelease(bmp);
    }
    CGColorSpaceRelease(cs);
    CGImageRelease(subImage);

    if (annotation.redactMode == CSRedactModeBlur) {
        // Smooth Frosted Blur sampling over a local neighborhood kernel
        CGFloat step = 3.0;
        NSInteger radiusPx = (NSInteger)MAX(4.0, round(annotation.lineWidth * 2.2 * scaleX));
        NSInteger stride = MAX(1, radiusPx / 3);
        [NSGraphicsContext saveGraphicsState];
        NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0];
        [clip addClip];
        for (CGFloat y = NSMinY(rect); y < NSMaxY(rect); y += step) {
            CGFloat bh = MIN(step + 0.5, NSMaxY(rect) - y);
            for (CGFloat x = NSMinX(rect); x < NSMaxX(rect); x += step) {
                CGFloat bw = MIN(step + 0.5, NSMaxX(rect) - x);
                NSPoint samplePt = NSMakePoint(x + bw * 0.5, y + bh * 0.5);
                NSInteger cx = (NSInteger)lround(samplePt.x * scaleX) - cropMinX;
                NSInteger cy = (NSInteger)lround((NSHeight(self.bounds) - samplePt.y) * scaleY) - cropMinY;
                NSInteger sumR = 0, sumG = 0, sumB = 0, count = 0;
                for (NSInteger dy = -radiusPx; dy <= radiusPx; dy += stride) {
                    NSInteger py = MIN(MAX(cy + dy, 0), (NSInteger)cropH - 1);
                    for (NSInteger dx = -radiusPx; dx <= radiusPx; dx += stride) {
                        NSInteger px = MIN(MAX(cx + dx, 0), (NSInteger)cropW - 1);
                        size_t off = (size_t)py * bytesPerRow + (size_t)px * 4;
                        sumR += buf[off];
                        sumG += buf[off + 1];
                        sumB += buf[off + 2];
                        count++;
                    }
                }
                if (count > 0) {
                    [[NSColor colorWithSRGBRed:(sumR / (CGFloat)count) / 255.0
                                         green:(sumG / (CGFloat)count) / 255.0
                                          blue:(sumB / (CGFloat)count) / 255.0
                                         alpha:1.0] setFill];
                    NSRectFill(NSMakeRect(x, y, bw, bh));
                }
            }
        }
        [NSGraphicsContext restoreGraphicsState];
    } else {
        CGFloat blockSize = MAX(6.0, round(annotation.lineWidth * 2.5));
        for (CGFloat y = NSMinY(rect); y < NSMaxY(rect); y += blockSize) {
            CGFloat bh = MIN(blockSize, NSMaxY(rect) - y);
            for (CGFloat x = NSMinX(rect); x < NSMaxX(rect); x += blockSize) {
                CGFloat bw = MIN(blockSize, NSMaxX(rect) - x);
                NSPoint samplePt = NSMakePoint(x + bw * 0.5, y + bh * 0.5);
                NSInteger px = MIN(MAX((NSInteger)lround(samplePt.x * scaleX) - cropMinX, 0), (NSInteger)cropW - 1);
                NSInteger py = MIN(MAX((NSInteger)lround((NSHeight(self.bounds) - samplePt.y) * scaleY) - cropMinY, 0), (NSInteger)cropH - 1);
                size_t offset = (size_t)py * bytesPerRow + (size_t)px * 4;
                CGFloat r = buf[offset] / 255.0;
                CGFloat g = buf[offset + 1] / 255.0;
                CGFloat b = buf[offset + 2] / 255.0;
                [[NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0] setFill];
                NSRectFill(NSMakeRect(x, y, bw, bh));
            }
        }
    }

    free(buf);

    if (isPreview) {
        NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0];
        CGFloat dashes[2] = {4.0, 3.0};
        [border setLineDash:dashes count:2 phase:0];
        border.lineWidth = 1.5;
        [[CSTheme accent] setStroke];
        [border stroke];
    }
}

- (NSBezierPath *)spotlightPathForAnnotation:(Annotation *)spot inset:(CGFloat)inset {
    NSRect rect = NSInsetRect(spot.path.bounds, inset, inset);
    if (NSWidth(rect) < 1.0 || NSHeight(rect) < 1.0) {
        return [NSBezierPath bezierPath];
    }
    switch (spot.spotlightShape) {
        case CSSpotlightShapeEllipse:
            return [NSBezierPath bezierPathWithOvalInRect:rect];
        case CSSpotlightShapePill: {
            CGFloat r = MIN(NSWidth(rect), NSHeight(rect)) * 0.5;
            return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:r yRadius:r];
        }
        case CSSpotlightShapeRoundedRect:
        default: {
            CGFloat r = MIN(10.0, MIN(NSWidth(rect), NSHeight(rect)) * 0.2);
            return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:r yRadius:r];
        }
    }
}

- (void)drawSpotlightAnnotations:(NSArray<Annotation *> *)spotlights {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (ctx == NULL) {
        return;
    }

    Annotation *firstSpot = spotlights.firstObject;
    CGFloat dimAlpha = firstSpot.spotlightDimOpacity > 0.05 ? firstSpot.spotlightDimOpacity : self.spotlightDimOpacity;

    CGContextSaveGState(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL);

    [[[NSColor blackColor] colorWithAlphaComponent:dimAlpha] setFill];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    // Punch out spotlight holes with optional multi-step feathered soft edge
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationOut);
    for (Annotation *spot in spotlights) {
        if (spot.spotlightFeather) {
            // Soft outer feather bands (gradually clearing the dim layer around the cutout)
            const int steps = 6;
            for (int s = steps; s >= 1; s--) {
                CGFloat expand = -((CGFloat)s * 2.2);
                CGFloat stepAlpha = 0.14 * (1.0 - (CGFloat)(s - 1) / (CGFloat)steps);
                [[[NSColor blackColor] colorWithAlphaComponent:stepAlpha] setFill];
                NSBezierPath *featherBand = [self spotlightPathForAnnotation:spot inset:expand];
                [featherBand fill];
            }
        }
        [[NSColor blackColor] setFill];
        NSBezierPath *hole = [self spotlightPathForAnnotation:spot inset:0.0];
        [hole fill];
    }

    CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);

    // Draw luminous border & soft outer glow around each spotlight
    for (Annotation *spot in spotlights) {
        NSColor *rimColor = spot.color ?: [CSTheme accent];
        NSBezierPath *ring = [self spotlightPathForAnnotation:spot inset:0.0];

        if (spot.spotlightFeather) {
            [NSGraphicsContext saveGraphicsState];
            NSShadow *glow = [[NSShadow alloc] init];
            glow.shadowColor = [rimColor colorWithAlphaComponent:0.55];
            glow.shadowBlurRadius = 10.0;
            glow.shadowOffset = NSZeroSize;
            [glow set];
            ring.lineWidth = MAX(2.0, spot.lineWidth * 0.65);
            [[rimColor colorWithAlphaComponent:0.92] setStroke];
            [ring stroke];
            [NSGraphicsContext restoreGraphicsState];

            // Crisp inner highlight hairline
            NSBezierPath *inner = [self spotlightPathForAnnotation:spot inset:1.0];
            inner.lineWidth = 1.0;
            [[[NSColor whiteColor] colorWithAlphaComponent:0.55] setStroke];
            [inner stroke];
        } else {
            ring.lineWidth = MAX(1.8, spot.lineWidth * 0.6);
            [rimColor setStroke];
            [ring stroke];
        }
    }
}

- (void)drawCalloutAnnotation:(Annotation *)annotation {
    if (annotation.speechBubble) {
        [self drawSpeechBubbleAnnotation:annotation];
        return;
    }

    CGFloat radius = MAX(13.0, 10.0 + annotation.lineWidth * 0.85);
    NSPoint center = annotation.startPoint;
    NSPoint target = annotation.endPoint;
    NSColor *fillColor = annotation.color ?: [NSColor systemRedColor];

    CGFloat dist = hypot(target.x - center.x, target.y - center.y);
    if (dist > radius + 6.0) {
        CGFloat ux = (target.x - center.x) / dist;
        CGFloat uy = (target.y - center.y) / dist;
        NSPoint edgeStart = NSMakePoint(center.x + ux * radius, center.y + uy * radius);
        Annotation *tempArrow = [Annotation new];
        tempArrow.toolType = ToolTypeArrow;
        tempArrow.startPoint = edgeStart;
        tempArrow.endPoint = target;
        tempArrow.lineWidth = MAX(2.5, annotation.lineWidth);
        tempArrow.color = fillColor;
        [NSGraphicsContext saveGraphicsState];
        NSShadow *arrowShadow = [[NSShadow alloc] init];
        arrowShadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.32];
        arrowShadow.shadowBlurRadius = 4.0;
        arrowShadow.shadowOffset = NSMakeSize(0, -1.5);
        [arrowShadow set];
        [fillColor setFill];
        [fillColor setStroke];
        [self drawArrowAnnotation:tempArrow];
        [NSGraphicsContext restoreGraphicsState];
    }

    NSRect badgeRect = NSMakeRect(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0);
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.42];
    shadow.shadowBlurRadius = 5.0;
    shadow.shadowOffset = NSMakeSize(0, -1.8);
    [shadow set];

    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:badgeRect];
    [fillColor setFill];
    [circle fill];
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor whiteColor] setStroke];
    circle.lineWidth = 2.0;
    [circle stroke];

    NSColor *srgb = [fillColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat lum = srgb != nil ? (0.299 * srgb.redComponent + 0.587 * srgb.greenComponent + 0.114 * srgb.blueComponent) : 0.0;
    NSColor *textColor = (lum > 0.68) ? [NSColor blackColor] : [NSColor whiteColor];

    NSString *numStr = [NSString stringWithFormat:@"%ld", (long)MAX(annotation.calloutNumber, 1)];
    CGFloat fontSize = round(radius * (numStr.length > 1 ? 0.95 : 1.10));
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightBold],
        NSForegroundColorAttributeName: textColor
    };
    NSSize textSize = [numStr sizeWithAttributes:attrs];
    NSPoint textPt = NSMakePoint(center.x - textSize.width * 0.5, center.y - textSize.height * 0.5);
    [numStr drawAtPoint:textPt withAttributes:attrs];
}

- (void)drawSpeechBubbleAnnotation:(Annotation *)annotation {
    NSColor *accentColor = annotation.color ?: [NSColor systemRedColor];
    NSString *display = annotation.text.length > 0 ? annotation.text : [NSString stringWithFormat:@"Note #%ld", (long)MAX(annotation.calloutNumber, 1)];
    NSFont *font = [NSFont systemFontOfSize:MAX(annotation.fontSize, 13.0) weight:NSFontWeightSemibold];

    NSColor *srgb = [accentColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat lum = srgb != nil ? (0.299 * srgb.redComponent + 0.587 * srgb.greenComponent + 0.114 * srgb.blueComponent) : 0.0;
    NSColor *textColor = (lum > 0.68) ? [NSColor blackColor] : [NSColor whiteColor];

    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textColor
    };
    NSSize textSize = [display sizeWithAttributes:attrs];
    CGFloat padX = 12.0;
    CGFloat padY = 8.0;
    CGFloat boxW = MAX(textSize.width + padX * 2.0, 56.0);
    CGFloat boxH = MAX(textSize.height + padY * 2.0, 32.0);
    NSRect bubbleRect = NSMakeRect(annotation.startPoint.x - boxW * 0.5,
                                   annotation.startPoint.y - boxH * 0.5,
                                   boxW,
                                   boxH);

    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.38];
    shadow.shadowBlurRadius = 7.0;
    shadow.shadowOffset = NSMakeSize(0, -2.0);
    [shadow set];

    // Draw tail if endPoint is outside bubbleRect
    NSPoint center = NSMakePoint(NSMidX(bubbleRect), NSMidY(bubbleRect));
    NSPoint tip = annotation.endPoint;
    if (!NSPointInRect(tip, NSInsetRect(bubbleRect, -6.0, -6.0))) {
        CGFloat dx = tip.x - center.x;
        CGFloat dy = tip.y - center.y;
        CGFloat dist = hypot(dx, dy);
        if (dist > 1.0) {
            CGFloat nx = -dy / dist;
            CGFloat ny = dx / dist;
            CGFloat baseHalf = 8.0;
            NSBezierPath *tail = [NSBezierPath bezierPath];
            [tail moveToPoint:NSMakePoint(center.x + nx * baseHalf, center.y + ny * baseHalf)];
            [tail lineToPoint:tip];
            [tail lineToPoint:NSMakePoint(center.x - nx * baseHalf, center.y - ny * baseHalf)];
            [tail closePath];
            [accentColor setFill];
            [tail fill];
        }
    }

    NSBezierPath *bubble = [NSBezierPath bezierPathWithRoundedRect:bubbleRect xRadius:8.0 yRadius:8.0];
    [accentColor setFill];
    [bubble fill];
    [NSGraphicsContext restoreGraphicsState];

    [[[NSColor whiteColor] colorWithAlphaComponent:0.9] setStroke];
    bubble.lineWidth = 1.5;
    [bubble stroke];

    [display drawAtPoint:NSMakePoint(NSMinX(bubbleRect) + (boxW - textSize.width) * 0.5,
                                     NSMinY(bubbleRect) + (boxH - textSize.height) * 0.5)
          withAttributes:attrs];
}

- (void)drawSelectionHandlesForAnnotation:(Annotation *)annotation {
    CGFloat handleRadius = 4.5;
    NSColor *accent = [CSTheme accent];

    void (^drawHandleAt)(NSPoint, NSColor *) = ^(NSPoint pt, NSColor *fill) {
        NSRect hr = NSMakeRect(pt.x - handleRadius, pt.y - handleRadius, handleRadius * 2.0, handleRadius * 2.0);
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:hr];
        [fill setFill];
        [circle fill];
        [[NSColor whiteColor] setStroke];
        circle.lineWidth = 1.5;
        [circle stroke];
    };

    if (annotation.toolType == ToolTypeLine || annotation.toolType == ToolTypeArrow ||
        (annotation.toolType == ToolTypeCallout && !annotation.speechBubble)) {
        NSBezierPath *guide = [NSBezierPath bezierPath];
        [guide moveToPoint:annotation.startPoint];
        if (annotation.toolType == ToolTypeArrow && annotation.curved) {
            NSPoint ctrl = annotation.hasCustomControlPoint
                ? annotation.controlPoint
                : [self defaultControlPointFrom:annotation.startPoint to:annotation.endPoint];
            [guide lineToPoint:ctrl];
            [guide lineToPoint:annotation.endPoint];
            CGFloat dashes[2] = {3.0, 3.0};
            [guide setLineDash:dashes count:2 phase:0];
            [[accent colorWithAlphaComponent:0.65] setStroke];
            guide.lineWidth = 1.0;
            [guide stroke];
            drawHandleAt(ctrl, [NSColor systemYellowColor]);
        }
        drawHandleAt(annotation.startPoint, accent);
        drawHandleAt(annotation.endPoint, accent);
        return;
    }

    NSRect bounds = [annotation selectionBounds];
    if (NSIsEmptyRect(bounds)) {
        return;
    }
    NSRect frameRect = NSInsetRect(bounds, -3.0, -3.0);
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:frameRect xRadius:4.0 yRadius:4.0];
    CGFloat dashes[2] = {4.0, 3.0};
    [box setLineDash:dashes count:2 phase:0];
    box.lineWidth = 1.2;
    [[accent colorWithAlphaComponent:0.85] setStroke];
    [box stroke];

    drawHandleAt(NSMakePoint(NSMinX(frameRect), NSMinY(frameRect)), accent);
    drawHandleAt(NSMakePoint(NSMaxX(frameRect), NSMinY(frameRect)), accent);
    drawHandleAt(NSMakePoint(NSMinX(frameRect), NSMaxY(frameRect)), accent);
    drawHandleAt(NSMakePoint(NSMaxX(frameRect), NSMaxY(frameRect)), accent);
}

- (void)drawCropPreview:(Annotation *)cropAnnotation {
    NSRect cropRect = NSIntersectionRect(cropAnnotation.path.bounds, self.bounds);
    if (NSWidth(cropRect) < 2.0 || NSHeight(cropRect) < 2.0) {
        return;
    }
    NSBezierPath *dimPath = [NSBezierPath bezierPathWithRect:self.bounds];
    [dimPath appendBezierPathWithRect:cropRect];
    [dimPath setWindingRule:NSWindingRuleEvenOdd];
    [[[NSColor blackColor] colorWithAlphaComponent:0.52] setFill];
    [dimPath fill];

    // Rule-of-thirds subtle grid inside crop area
    NSBezierPath *grid = [NSBezierPath bezierPath];
    for (int i = 1; i <= 2; i++) {
        CGFloat gx = NSMinX(cropRect) + NSWidth(cropRect) * (i / 3.0);
        CGFloat gy = NSMinY(cropRect) + NSHeight(cropRect) * (i / 3.0);
        [grid moveToPoint:NSMakePoint(gx, NSMinY(cropRect))];
        [grid lineToPoint:NSMakePoint(gx, NSMaxY(cropRect))];
        [grid moveToPoint:NSMakePoint(NSMinX(cropRect), gy)];
        [grid lineToPoint:NSMakePoint(NSMaxX(cropRect), gy)];
    }
    grid.lineWidth = 0.75;
    [[[NSColor whiteColor] colorWithAlphaComponent:0.28] setStroke];
    [grid stroke];

    NSBezierPath *border = [NSBezierPath bezierPathWithRect:cropRect];
    border.lineWidth = 1.8;
    [[CSTheme accent] setStroke];
    [border stroke];

    NSString *sizeStr = [NSString stringWithFormat:@"Crop %ld × %ld",
                         (long)lround(NSWidth(cropRect)), (long)lround(NSHeight(cropRect))];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [CSTheme badgeText]
    };
    NSSize ts = [sizeStr sizeWithAttributes:attrs];
    NSRect pill = NSMakeRect(NSMinX(cropRect) + 6.0, NSMinY(cropRect) + 6.0, ts.width + 12.0, ts.height + 6.0);
    NSBezierPath *pillPath = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:4.0 yRadius:4.0];
    [[CSTheme badgeBackground] setFill];
    [pillPath fill];
    [sizeStr drawAtPoint:NSMakePoint(NSMinX(pill) + 6.0, NSMinY(pill) + 3.0) withAttributes:attrs];
}

- (void)drawEraserCursorAtPoint:(NSPoint)point {
    CGFloat radius = MAX(self.currentLineWidth * 2.0, 6.0);
    NSRect circleRect = NSMakeRect(point.x - radius, point.y - radius, radius * 2.0, radius * 2.0);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:circleRect];

    [[NSColor colorWithWhite:0.0 alpha:0.6] setStroke];
    circle.lineWidth = 2.0;
    [circle stroke];

    CGFloat dashes[2] = {3.0, 3.0};
    [circle setLineDash:dashes count:2 phase:0];
    circle.lineWidth = 1.0;
    [[NSColor whiteColor] setStroke];
    [circle stroke];
}

- (void)drawColorPickerLoupeAtPoint:(NSPoint)point color:(NSColor *)color {
    CGFloat radius = 16.0;
    NSPoint center = NSMakePoint(point.x + 20.0, point.y + 20.0);
    if (center.x + radius > NSMaxX(self.bounds) - 4.0) {
        center.x = point.x - 20.0;
    }
    if (center.y + radius > NSMaxY(self.bounds) - 4.0) {
        center.y = point.y - 20.0;
    }

    if (self.colorLockPulseProgress > 0.0) {
        CGFloat t = self.colorLockPulseProgress;
        CGFloat ease = 1.0 - pow(1.0 - t, 3.0);
        CGFloat pulseRadius = 6.0 + ease * 28.0;
        NSRect pulseRect = NSMakeRect(point.x - pulseRadius, point.y - pulseRadius, pulseRadius * 2.0, pulseRadius * 2.0);
        NSBezierPath *pulseRing = [NSBezierPath bezierPathWithOvalInRect:pulseRect];
        [[[CSTheme accent] colorWithAlphaComponent:(1.0 - ease) * 0.9] setStroke];
        pulseRing.lineWidth = 2.5 * (1.0 - ease * 0.5);
        [pulseRing stroke];

        CGFloat loupePulse = radius + ease * 14.0;
        NSRect loupePulseRect = NSMakeRect(center.x - loupePulse, center.y - loupePulse, loupePulse * 2.0, loupePulse * 2.0);
        NSBezierPath *loupePulsePath = [NSBezierPath bezierPathWithOvalInRect:loupePulseRect];
        [[[CSTheme accent] colorWithAlphaComponent:(1.0 - ease) * 0.85] setStroke];
        loupePulsePath.lineWidth = 2.2 * (1.0 - ease * 0.5);
        [loupePulsePath stroke];
    }

    CGFloat scale = 1.0;
    if (self.colorLockPulseProgress > 0.0 && self.colorLockPulseProgress < 0.5) {
        scale = 1.0 + 0.18 * sin(self.colorLockPulseProgress * 2.0 * M_PI);
    }
    CGFloat r = radius * scale;
    NSRect circleRect = NSMakeRect(center.x - r, center.y - r, r * 2.0, r * 2.0);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:circleRect];
    [color setFill];
    [circle fill];

    if (self.colorPickerLocked) {
        [[CSTheme accent] setStroke];
        circle.lineWidth = 2.6;
        [circle stroke];
    } else {
        [[NSColor whiteColor] setStroke];
        circle.lineWidth = 2.2;
        [circle stroke];
    }

    NSBezierPath *outerRing = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(circleRect, -1.0, -1.0)];
    [[NSColor colorWithWhite:0.0 alpha:0.45] setStroke];
    outerRing.lineWidth = 1.0;
    [outerRing stroke];

    if (self.colorPickerLocked) {
        NSRect pinRingRect = NSMakeRect(point.x - 5.5, point.y - 5.5, 11.0, 11.0);
        NSBezierPath *pinRing = [NSBezierPath bezierPathWithOvalInRect:pinRingRect];
        [[CSTheme accent] setStroke];
        pinRing.lineWidth = 1.8;
        [pinRing stroke];
    }

    NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 1.8, point.y - 1.8, 3.6, 3.6)];
    [[NSColor whiteColor] setFill];
    [dot fill];
    [[NSColor blackColor] setStroke];
    dot.lineWidth = 0.6;
    [dot stroke];
}

- (void)drawSizeBadge {
    if (self.backgroundImage == nil) {
        return;
    }
    NSSize imageSize = self.backgroundImage.size;
    CGFloat displayScale = NSWidth(self.bounds) / MAX(imageSize.width, 1.0);
    NSString *label = [NSString stringWithFormat:@"%ld × %ld",
                       (long)lround(imageSize.width), (long)lround(imageSize.height)];
    if (displayScale < 0.995) {
        label = [label stringByAppendingFormat:@"  ·  %ld%%", (long)lround(displayScale * 100)];
    }

    NSDictionary *badgeAttributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    NSSize textSize = [label sizeWithAttributes:badgeAttributes];
    NSRect badge = NSMakeRect(NSMaxX(self.bounds) - textSize.width - 20.0,
                              NSMinY(self.bounds) + 10.0,
                              textSize.width + 12.0,
                              textSize.height + 6.0);
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:badge xRadius:6.0 yRadius:6.0];
    [[[NSColor colorWithSRGBRed:0.07 green:0.08 blue:0.10 alpha:1.0] colorWithAlphaComponent:0.78] setFill];
    [background fill];
    [[[CSTheme accent] colorWithAlphaComponent:0.45] setStroke];
    background.lineWidth = 1.0;
    [background stroke];
    [label drawAtPoint:NSMakePoint(NSMinX(badge) + 6.0, NSMinY(badge) + 3.0) withAttributes:badgeAttributes];
}

#pragma mark - Hit testing & Handle Manipulation

- (CSDragHandle)hitHandleForAnnotation:(Annotation *)annotation atPoint:(NSPoint)point {
    if (annotation == nil) {
        return CSDragHandleNone;
    }
    CGFloat hitRadius = 7.5;
    if (annotation.toolType == ToolTypeLine || annotation.toolType == ToolTypeArrow ||
        (annotation.toolType == ToolTypeCallout && !annotation.speechBubble)) {
        if (hypot(point.x - annotation.startPoint.x, point.y - annotation.startPoint.y) <= hitRadius) {
            return CSDragHandleStart;
        }
        if (hypot(point.x - annotation.endPoint.x, point.y - annotation.endPoint.y) <= hitRadius) {
            return CSDragHandleEnd;
        }
        if (annotation.toolType == ToolTypeArrow && annotation.curved) {
            NSPoint ctrl = annotation.hasCustomControlPoint
                ? annotation.controlPoint
                : [self defaultControlPointFrom:annotation.startPoint to:annotation.endPoint];
            if (hypot(point.x - ctrl.x, point.y - ctrl.y) <= hitRadius) {
                return CSDragHandleControl;
            }
        }
        return CSDragHandleNone;
    }

    NSRect bounds = [annotation selectionBounds];
    if (NSIsEmptyRect(bounds)) {
        return CSDragHandleNone;
    }
    NSRect frameRect = NSInsetRect(bounds, -3.0, -3.0);
    if (hypot(point.x - NSMinX(frameRect), point.y - NSMinY(frameRect)) <= hitRadius) {
        return CSDragHandleMinXMinY;
    }
    if (hypot(point.x - NSMaxX(frameRect), point.y - NSMinY(frameRect)) <= hitRadius) {
        return CSDragHandleMaxXMinY;
    }
    if (hypot(point.x - NSMinX(frameRect), point.y - NSMaxY(frameRect)) <= hitRadius) {
        return CSDragHandleMinXMaxY;
    }
    if (hypot(point.x - NSMaxX(frameRect), point.y - NSMaxY(frameRect)) <= hitRadius) {
        return CSDragHandleMaxXMaxY;
    }
    return CSDragHandleNone;
}

- (NSInteger)hitAnnotationIndexAtPoint:(NSPoint)point {
    for (NSInteger i = (NSInteger)self.annotations.count - 1; i >= 0; i--) {
        Annotation *ann = self.annotations[i];
        if ([self annotation:ann isHitByPoint:point radius:5.0]) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)applyRect:(NSRect)newRect toAnnotation:(Annotation *)annotation {
    NSRect clamped = NSMakeRect(newRect.origin.x,
                                newRect.origin.y,
                                MAX(newRect.size.width, 6.0),
                                MAX(newRect.size.height, 6.0));
    annotation.startPoint = clamped.origin;
    annotation.endPoint = NSMakePoint(NSMaxX(clamped), NSMaxY(clamped));
    [self rebuildGeometryForAnnotation:annotation];
}

- (void)rebuildGeometryForAnnotation:(Annotation *)annotation {
    NSPoint start = annotation.startPoint;
    NSPoint end = annotation.endPoint;
    NSRect rect = NSMakeRect(MIN(start.x, end.x), MIN(start.y, end.y),
                             fabs(end.x - start.x), fabs(end.y - start.y));
    switch (annotation.toolType) {
        case ToolTypeLine: {
            NSBezierPath *path = [NSBezierPath bezierPath];
            [path moveToPoint:start];
            [path lineToPoint:end];
            annotation.path = path;
            break;
        }
        case ToolTypeArrow:
            annotation.path = [self arrowPathFromPoint:start toPoint:end lineWidth:annotation.lineWidth];
            break;
        case ToolTypeRectangle: {
            if (annotation.cornerRadius > 0.5) {
                CGFloat r = MIN(annotation.cornerRadius, MIN(NSWidth(rect), NSHeight(rect)) * 0.5);
                annotation.path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:r yRadius:r];
            } else {
                annotation.path = [NSBezierPath bezierPathWithRect:rect];
            }
            break;
        }
        case ToolTypePixelate:
        case ToolTypeSpotlight:
        case ToolTypeCrop:
            annotation.path = [NSBezierPath bezierPathWithRect:rect];
            break;
        case ToolTypeEllipse:
        case ToolTypeLoupe:
            annotation.path = [NSBezierPath bezierPathWithOvalInRect:rect];
            break;
        case ToolTypeCallout: {
            CGFloat radius = MAX(13.0, 10.0 + annotation.lineWidth * 0.85);
            NSRect badgeRect = NSMakeRect(start.x - radius, start.y - radius, radius * 2.0, radius * 2.0);
            NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:badgeRect];
            if (hypot(end.x - start.x, end.y - start.y) > radius + 6.0) {
                [path appendBezierPath:[self arrowPathFromPoint:start toPoint:end lineWidth:MAX(2.5, annotation.lineWidth)]];
            }
            annotation.path = path;
            break;
        }
        default:
            break;
    }
}

- (NSPoint)defaultControlPointFrom:(NSPoint)start to:(NSPoint)end {
    NSPoint mid = NSMakePoint((start.x + end.x) * 0.5, (start.y + end.y) * 0.5);
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat dist = hypot(dx, dy);
    if (dist < 1.0) {
        return mid;
    }
    CGFloat offset = MIN(MAX(dist * 0.24, 18.0), 80.0);
    return NSMakePoint(mid.x - (dy / dist) * offset, mid.y + (dx / dist) * offset);
}

#pragma mark - Mouse

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.ocrMode) {
        NSInteger hovered = [self hitOCRIndexAtPoint:point];
        if (hovered != self.hoveredOCRIndex) {
            self.hoveredOCRIndex = hovered;
            [self setNeedsDisplay:YES];
        }
        return;
    }
    if (self.currentTool == ToolTypeColorPicker) {
        if (self.colorPickerLocked) {
            return;
        }
        NSColor *color = [self sampleColorAtPoint:point];
        if (color != nil) {
            NSPoint oldPt = self.hoverPoint;
            BOOL hadHover = self.showHover;
            self.hoverColor = color;
            self.hoverPoint = point;
            self.showHover = YES;
            [self.delegate canvasView:self didHoverColor:color atPoint:point];
            if (hadHover) {
                [self setNeedsDisplayInRect:NSInsetRect(NSMakeRect(oldPt.x, oldPt.y, 0, 0), -52.0, -52.0)];
            }
            [self setNeedsDisplayInRect:NSInsetRect(NSMakeRect(point.x, point.y, 0, 0), -52.0, -52.0)];
        }
    } else if (self.currentTool == ToolTypeEraser) {
        NSPoint oldPt = self.lastErasePoint;
        BOOL hadHover = self.showHover;
        CGFloat r = MAX(self.currentLineWidth * 2.0, 6.0) + 6.0;
        self.lastErasePoint = point;
        self.showHover = YES;
        if (hadHover) {
            [self setNeedsDisplayInRect:NSInsetRect(NSMakeRect(oldPt.x, oldPt.y, 0, 0), -r, -r)];
        }
        [self setNeedsDisplayInRect:NSInsetRect(NSMakeRect(point.x, point.y, 0, 0), -r, -r)];
    }
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    self.showHover = NO;
    if (self.ocrMode && self.hoveredOCRIndex != NSNotFound) {
        self.hoveredOCRIndex = NSNotFound;
        [self setNeedsDisplay:YES];
    }
    if (self.currentTool == ToolTypeEraser || self.currentTool == ToolTypeColorPicker) {
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.ocrMode) {
        self.ocrDragStart = point;
        self.ocrDraggingMarquee = NO;
        self.ocrMarqueeRect = NSZeroRect;
        self.ocrSelectionAtDragStart = [self.selectedOCRIndexes copy];
        return;
    }
    self.dragStart = point;
    self.lastErasePoint = point;
    self.erasedDuringDrag = NO;
    self.activeDragHandle = CSDragHandleNone;
    self.manipulatedDuringDrag = NO;

    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL option = (event.modifierFlags & NSEventModifierFlagOption) != 0;
    BOOL command = (event.modifierFlags & NSEventModifierFlagCommand) != 0;

    // Check if interacting with an active selection handle or if in Select / Command-drag / Spotlight adjustment mode
    if (self.selectedAnnotation != nil) {
        CSDragHandle handle = [self hitHandleForAnnotation:self.selectedAnnotation atPoint:point];
        if (handle != CSDragHandleNone) {
            self.activeDragHandle = handle;
            self.lastManipulatePoint = point;
            self.initialManipulateBounds = [self.selectedAnnotation selectionBounds];
            self.dragging = YES;
            return;
        }
    }

    if (self.currentTool == ToolTypeSelect || command ||
        (self.currentTool == ToolTypeSpotlight && [self hitAnnotationIndexAtPoint:point] != NSNotFound &&
         self.annotations[[self hitAnnotationIndexAtPoint:point]].toolType == ToolTypeSpotlight)) {
        NSInteger hitIdx = [self hitAnnotationIndexAtPoint:point];
        if (hitIdx != NSNotFound) {
            self.selectedAnnotationIndex = hitIdx;
            Annotation *hitAnn = self.annotations[hitIdx];
            if (event.clickCount == 2 && (hitAnn.toolType == ToolTypeText || (hitAnn.toolType == ToolTypeCallout && hitAnn.speechBubble))) {
                [self beginEditingExistingAnnotationAtIndex:hitIdx];
                return;
            }
            CSDragHandle handle = [self hitHandleForAnnotation:hitAnn atPoint:point];
            self.activeDragHandle = (handle != CSDragHandleNone) ? handle : CSDragHandleMove;
            self.lastManipulatePoint = point;
            self.initialManipulateBounds = [hitAnn selectionBounds];
            self.dragging = YES;
            [self setNeedsDisplay:YES];
            return;
        } else if (self.currentTool == ToolTypeSelect || command) {
            self.selectedAnnotationIndex = NSNotFound;
            [self setNeedsDisplay:YES];
            return;
        }
    }

    self.selectedAnnotationIndex = NSNotFound;

    switch (self.currentTool) {
        case ToolTypeSelect:
            break;

        case ToolTypePencil:
        case ToolTypeMarker: {
            Annotation *annotation = [Annotation new];
            annotation.toolType = self.currentTool;
            annotation.color = (self.currentTool == ToolTypeMarker)
                ? [self.currentColor colorWithAlphaComponent:0.35]
                : self.currentColor;
            annotation.lineWidth = (self.currentTool == ToolTypeMarker)
                ? self.currentLineWidth * 3.0
                : self.currentLineWidth;
            annotation.hasShadow = self.shapeShadow && (self.currentTool == ToolTypePencil);
            [annotation.points addObject:[NSValue valueWithPoint:point]];
            [annotation rebuildSmoothPathFromPoints];
            self.previewAnnotation = annotation;
            self.dragging = YES;
            break;
        }

        case ToolTypeLine:
        case ToolTypeArrow:
        case ToolTypeRectangle:
        case ToolTypeEllipse:
        case ToolTypePixelate:
        case ToolTypeSpotlight:
        case ToolTypeLoupe:
        case ToolTypeCrop: {
            Annotation *annotation = [Annotation new];
            annotation.toolType = self.currentTool;
            annotation.color = self.currentColor;
            annotation.lineWidth = self.currentLineWidth;
            annotation.filled = (self.shapeFilled != option);
            annotation.dashed = self.shapeDashed;
            annotation.hasShadow = self.shapeShadow;
            annotation.cornerRadius = (self.currentTool == ToolTypeRectangle && self.shapeRounded)
                ? MAX(8.0, self.currentLineWidth * 2.5)
                : 0.0;
            annotation.curved = (self.currentTool == ToolTypeArrow) && self.arrowCurved;
            annotation.spotlightShape = self.spotlightShape;
            annotation.spotlightDimOpacity = self.spotlightDimOpacity;
            annotation.spotlightFeather = self.spotlightFeather;
            annotation.redactMode = self.redactMode;
            annotation.loupeMagnification = self.loupeMagnification;
            annotation.startPoint = point;
            annotation.endPoint = point;
            self.previewAnnotation = annotation;
            self.dragging = YES;
            [self updatePreviewToPoint:point shift:shift option:option];
            break;
        }

        case ToolTypeCallout: {
            Annotation *annotation = [Annotation new];
            annotation.toolType = ToolTypeCallout;
            annotation.color = self.currentColor;
            annotation.lineWidth = self.currentLineWidth;
            annotation.speechBubble = self.calloutSpeechBubble;
            annotation.calloutNumber = [self nextCalloutNumber];
            annotation.fontSize = self.textFontSize;
            annotation.startPoint = point;
            annotation.endPoint = point;
            self.previewAnnotation = annotation;
            self.dragging = YES;
            [self updatePreviewToPoint:point shift:shift option:option];
            break;
        }

        case ToolTypeText:
            if (self.activeTextView != nil) {
                [self commitActiveTextEditor];
            } else {
                [self beginTextEntryAtPoint:point];
            }
            break;

        case ToolTypeColorPicker: {
            NSColor *color = [self sampleColorAtPoint:point];
            if (color != nil) {
                self.currentColor = color;
                self.hoverColor = color;
                self.hoverPoint = point;
                self.showHover = YES;
                self.colorPickerLocked = YES;
                [self.delegate canvasView:self didPickColor:color];
            }
            break;
        }

        case ToolTypeEraser:
            self.dragging = YES;
            [self eraseAtPoint:point recordSnapshot:NO];
            break;
    }

    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.ocrMode) {
        if (hypot(point.x - self.ocrDragStart.x, point.y - self.ocrDragStart.y) >= 4.0) {
            self.ocrDraggingMarquee = YES;
            self.ocrMarqueeRect = NSMakeRect(MIN(self.ocrDragStart.x, point.x),
                                             MIN(self.ocrDragStart.y, point.y),
                                             fabs(point.x - self.ocrDragStart.x),
                                             fabs(point.y - self.ocrDragStart.y));
            BOOL additive = (event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0;
            NSMutableIndexSet *next = additive && self.ocrSelectionAtDragStart != nil
                ? [self.ocrSelectionAtDragStart mutableCopy]
                : [NSMutableIndexSet indexSet];
            for (NSUInteger i = 0; i < self.ocrObservations.count; i++) {
                NSRect box = [self.ocrObservations[i] rectInBounds:self.bounds];
                if (NSIntersectsRect(box, self.ocrMarqueeRect)) {
                    [next addIndex:i];
                }
            }
            self.selectedOCRIndexes = next;
            if ([self.delegate respondsToSelector:@selector(canvasView:didChangeSelectedOCRIndexes:)]) {
                [self.delegate canvasView:self didChangeSelectedOCRIndexes:self.selectedOCRIndexes];
            }
            [self setNeedsDisplay:YES];
        }
        return;
    }

    if (self.activeDragHandle != CSDragHandleNone && self.selectedAnnotation != nil) {
        Annotation *ann = self.selectedAnnotation;
        CGFloat dx = point.x - self.lastManipulatePoint.x;
        CGFloat dy = point.y - self.lastManipulatePoint.y;
        self.lastManipulatePoint = point;
        self.manipulatedDuringDrag = YES;

        switch (self.activeDragHandle) {
            case CSDragHandleMove:
                [ann translateByX:dx y:dy];
                break;
            case CSDragHandleStart:
                ann.startPoint = point;
                [self rebuildGeometryForAnnotation:ann];
                break;
            case CSDragHandleEnd:
                ann.endPoint = point;
                [self rebuildGeometryForAnnotation:ann];
                break;
            case CSDragHandleControl:
                ann.controlPoint = point;
                ann.hasCustomControlPoint = YES;
                [self rebuildGeometryForAnnotation:ann];
                break;
            case CSDragHandleMinXMinY: {
                NSRect b = [ann selectionBounds];
                NSRect next = NSMakeRect(MIN(point.x, NSMaxX(b) - 8.0),
                                         MIN(point.y, NSMaxY(b) - 8.0),
                                         MAX(NSMaxX(b) - point.x, 8.0),
                                         MAX(NSMaxY(b) - point.y, 8.0));
                [self applyRect:next toAnnotation:ann];
                break;
            }
            case CSDragHandleMaxXMinY: {
                NSRect b = [ann selectionBounds];
                NSRect next = NSMakeRect(NSMinX(b),
                                         MIN(point.y, NSMaxY(b) - 8.0),
                                         MAX(point.x - NSMinX(b), 8.0),
                                         MAX(NSMaxY(b) - point.y, 8.0));
                [self applyRect:next toAnnotation:ann];
                break;
            }
            case CSDragHandleMinXMaxY: {
                NSRect b = [ann selectionBounds];
                NSRect next = NSMakeRect(MIN(point.x, NSMaxX(b) - 8.0),
                                         NSMinY(b),
                                         MAX(NSMaxX(b) - point.x, 8.0),
                                         MAX(point.y - NSMinY(b), 8.0));
                [self applyRect:next toAnnotation:ann];
                break;
            }
            case CSDragHandleMaxXMaxY: {
                NSRect b = [ann selectionBounds];
                NSRect next = NSMakeRect(NSMinX(b),
                                         NSMinY(b),
                                         MAX(point.x - NSMinX(b), 8.0),
                                         MAX(point.y - NSMinY(b), 8.0));
                [self applyRect:next toAnnotation:ann];
                break;
            }
            default:
                break;
        }
        [self setNeedsDisplay:YES];
        return;
    }

    self.lastErasePoint = point;

    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL option = (event.modifierFlags & NSEventModifierFlagOption) != 0;

    switch (self.currentTool) {
        case ToolTypePencil:
        case ToolTypeMarker: {
            if (self.previewAnnotation != nil) {
                NSPoint lastPt = [self.previewAnnotation.points.lastObject pointValue];
                if (hypot(point.x - lastPt.x, point.y - lastPt.y) >= 1.5) {
                    [self.previewAnnotation.points addObject:[NSValue valueWithPoint:point]];
                    [self.previewAnnotation rebuildSmoothPathFromPoints];
                }
            }
            break;
        }

        case ToolTypeLine:
        case ToolTypeArrow:
        case ToolTypeRectangle:
        case ToolTypeEllipse:
        case ToolTypePixelate:
        case ToolTypeCallout:
        case ToolTypeSpotlight:
        case ToolTypeLoupe:
        case ToolTypeCrop:
            [self updatePreviewToPoint:point shift:shift option:option];
            break;

        case ToolTypeEraser:
            [self eraseAtPoint:point recordSnapshot:NO];
            break;

        case ToolTypeColorPicker: {
            NSColor *color = [self sampleColorAtPoint:point];
            if (color != nil) {
                self.currentColor = color;
                self.hoverColor = color;
                self.hoverPoint = point;
                self.showHover = YES;
                self.colorPickerLocked = YES;
                [self.delegate canvasView:self didPickColor:color];
            }
            break;
        }

        default:
            break;
    }

    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.ocrMode) {
        if (self.ocrDraggingMarquee) {
            self.ocrDraggingMarquee = NO;
            self.ocrMarqueeRect = NSZeroRect;
            [self setNeedsDisplay:YES];
            return;
        }
        NSInteger hitIndex = [self hitOCRIndexAtPoint:point];
        NSUInteger totalCount = self.ocrObservations.count;
        NSMutableIndexSet *next = [self.selectedOCRIndexes mutableCopy] ?: [NSMutableIndexSet indexSet];
        BOOL modifierToggle = (event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) != 0;

        if (hitIndex != NSNotFound) {
            if (!modifierToggle && totalCount > 1 && next.count == totalCount) {
                [next removeAllIndexes];
                [next addIndex:(NSUInteger)hitIndex];
            } else if ([next containsIndex:(NSUInteger)hitIndex]) {
                [next removeIndex:(NSUInteger)hitIndex];
            } else {
                [next addIndex:(NSUInteger)hitIndex];
            }
        } else if (!modifierToggle) {
            if (next.count > 0) {
                [next removeAllIndexes];
            } else if (totalCount > 0) {
                [next addIndexesInRange:NSMakeRange(0, totalCount)];
            }
        }

        self.selectedOCRIndexes = next;
        if ([self.delegate respondsToSelector:@selector(canvasView:didChangeSelectedOCRIndexes:)]) {
            [self.delegate canvasView:self didChangeSelectedOCRIndexes:self.selectedOCRIndexes];
        }
        [self setNeedsDisplay:YES];
        return;
    }

    if (self.activeDragHandle != CSDragHandleNone) {
        self.activeDragHandle = CSDragHandleNone;
        self.dragging = NO;
        if (self.manipulatedDuringDrag) {
            [self recordSnapshot];
            self.manipulatedDuringDrag = NO;
        }
        [self setNeedsDisplay:YES];
        return;
    }

    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    BOOL option = (event.modifierFlags & NSEventModifierFlagOption) != 0;

    switch (self.currentTool) {
        case ToolTypePencil:
        case ToolTypeMarker: {
            Annotation *finished = self.previewAnnotation;
            self.previewAnnotation = nil;
            if (finished != nil) {
                if (finished.points.count <= 1) {
                    [finished.points addObject:[NSValue valueWithPoint:point]];
                }
                [finished rebuildSmoothPathFromPoints];
                [finished.points removeAllObjects];
                [self addAnnotation:finished];
            }
            break;
        }

        case ToolTypeLine:
        case ToolTypeArrow:
        case ToolTypeRectangle:
        case ToolTypeEllipse:
        case ToolTypePixelate:
        case ToolTypeCallout:
        case ToolTypeSpotlight:
        case ToolTypeLoupe: {
            [self updatePreviewToPoint:point shift:shift option:option];
            Annotation *finished = self.previewAnnotation;
            self.previewAnnotation = nil;
            if (finished != nil && [self shouldCommitPreview:finished atPoint:point]) {
                [self addAnnotation:finished];
                if (finished.toolType == ToolTypeSpotlight) {
                    self.selectedAnnotationIndex = (NSInteger)self.annotations.count - 1;
                }
                if (finished.toolType == ToolTypeCallout && finished.speechBubble) {
                    [self beginEditingExistingAnnotationAtIndex:(NSInteger)self.annotations.count - 1];
                }
            }
            break;
        }

        case ToolTypeCrop: {
            [self updatePreviewToPoint:point shift:shift option:option];
            Annotation *cropPreview = self.previewAnnotation;
            self.previewAnnotation = nil;
            if (cropPreview != nil && [self shouldCommitPreview:cropPreview atPoint:point]) {
                [self cropToRect:cropPreview.path.bounds];
            }
            break;
        }

        case ToolTypeEraser: {
            if (self.erasedDuringDrag) {
                [self recordSnapshot];
                self.erasedDuringDrag = NO;
            }
            break;
        }

        default:
            break;
    }

    self.dragging = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)shouldCommitPreview:(Annotation *)annotation atPoint:(NSPoint)point {
    switch (annotation.toolType) {
        case ToolTypePencil:
        case ToolTypeMarker:
            return YES;
        case ToolTypeLine:
            return hypot(point.x - self.dragStart.x, point.y - self.dragStart.y) >= 2.0;
        case ToolTypeArrow:
            return hypot(point.x - self.dragStart.x, point.y - self.dragStart.y) >= 4.0;
        case ToolTypeRectangle:
        case ToolTypeEllipse:
        case ToolTypePixelate:
        case ToolTypeSpotlight:
            return annotation.path.bounds.size.width >= 2.0 && annotation.path.bounds.size.height >= 2.0;
        case ToolTypeLoupe: {
            if (annotation.path.bounds.size.width < 12.0 || annotation.path.bounds.size.height < 12.0) {
                // Single click creates a default 110x110 magnifier loupe centered at point
                NSRect defaultRect = NSMakeRect(point.x - 55.0, point.y - 55.0, 110.0, 110.0);
                annotation.startPoint = defaultRect.origin;
                annotation.endPoint = NSMakePoint(NSMaxX(defaultRect), NSMaxY(defaultRect));
                annotation.path = [NSBezierPath bezierPathWithOvalInRect:defaultRect];
            }
            return YES;
        }
        case ToolTypeCrop:
            return annotation.path.bounds.size.width >= 16.0 && annotation.path.bounds.size.height >= 16.0;
        case ToolTypeCallout:
            return YES;
        default:
            return YES;
    }
}

- (NSPoint)constrainedPoint:(NSPoint)point fromStart:(NSPoint)start tool:(ToolType)tool shift:(BOOL)shift {
    if (tool == ToolTypeLoupe && !shift) {
        // Loupe defaults to circular unless Shift is held to make an oval
        CGFloat dx = point.x - start.x;
        CGFloat dy = point.y - start.y;
        CGFloat side = MAX(fabs(dx), fabs(dy));
        return NSMakePoint(start.x + (dx >= 0 ? side : -side),
                           start.y + (dy >= 0 ? side : -side));
    }
    if (!shift) {
        return point;
    }
    CGFloat dx = point.x - start.x;
    CGFloat dy = point.y - start.y;
    if (tool == ToolTypeLine || tool == ToolTypeArrow || tool == ToolTypeCallout) {
        CGFloat angle = atan2(dy, dx);
        CGFloat snapped = round(angle / (M_PI / 4.0)) * (M_PI / 4.0);
        CGFloat dist = hypot(dx, dy);
        return NSMakePoint(start.x + dist * cos(snapped), start.y + dist * sin(snapped));
    } else if (tool == ToolTypeRectangle || tool == ToolTypeEllipse || tool == ToolTypePixelate ||
               tool == ToolTypeSpotlight || tool == ToolTypeCrop) {
        CGFloat side = MAX(fabs(dx), fabs(dy));
        return NSMakePoint(start.x + (dx >= 0 ? side : -side),
                           start.y + (dy >= 0 ? side : -side));
    }
    return point;
}

- (void)updatePreviewToPoint:(NSPoint)point shift:(BOOL)shift option:(BOOL)option {
    Annotation *annotation = self.previewAnnotation;
    if (annotation == nil) {
        return;
    }
    NSPoint start = self.dragStart;
    NSPoint end = [self constrainedPoint:point fromStart:start tool:self.currentTool shift:shift];
    annotation.filled = (self.shapeFilled != option);
    annotation.startPoint = start;
    annotation.endPoint = end;
    if (annotation.toolType == ToolTypeArrow && annotation.curved && !annotation.hasCustomControlPoint) {
        annotation.controlPoint = [self defaultControlPointFrom:start to:end];
    }
    [self rebuildGeometryForAnnotation:annotation];
}

- (void)updatePreviewToPoint:(NSPoint)point {
    [self updatePreviewToPoint:point shift:NO option:NO];
}

#pragma mark - Shape helpers

- (NSBezierPath *)arrowPathFromPoint:(NSPoint)start toPoint:(NSPoint)end lineWidth:(CGFloat)lineWidth {
    NSBezierPath *path = [NSBezierPath bezierPath];
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat length = sqrt(dx * dx + dy * dy);
    if (length < 0.001) {
        return path;
    }
    CGFloat ux = dx / length;
    CGFloat uy = dy / length;

    CGFloat headLength = MAX(14.0, lineWidth * 4.5);
    CGFloat headWidth = MAX(10.0, lineWidth * 3.5);
    if (headLength > length * 0.75) {
        headLength = MAX(length * 0.75, 4.0);
        headWidth = headLength * 0.8;
    }

    NSPoint shaftEnd = NSMakePoint(end.x - ux * headLength * 0.7, end.y - uy * headLength * 0.7);
    [path moveToPoint:start];
    [path lineToPoint:shaftEnd];

    NSPoint base = NSMakePoint(end.x - ux * headLength, end.y - uy * headLength);
    NSPoint left = NSMakePoint(base.x - uy * headWidth / 2.0, base.y + ux * headWidth / 2.0);
    NSPoint right = NSMakePoint(base.x + uy * headWidth / 2.0, base.y - ux * headWidth / 2.0);
    [path moveToPoint:end];
    [path lineToPoint:left];
    [path lineToPoint:right];
    [path closePath];

    return path;
}

#pragma mark - Eraser & Hit Testing

static CGPathRef CGPathCreateFromNSBezierPath(NSBezierPath *path) {
    CGMutablePathRef cgPath = CGPathCreateMutable();
    NSInteger count = [path elementCount];
    NSPoint points[3];
    for (NSInteger i = 0; i < count; i++) {
        NSBezierPathElement element = [path elementAtIndex:i associatedPoints:points];
        switch (element) {
            case NSBezierPathElementMoveTo:
                CGPathMoveToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
            case NSBezierPathElementLineTo:
                CGPathAddLineToPoint(cgPath, NULL, points[0].x, points[0].y);
                break;
            case NSBezierPathElementCurveTo:
                CGPathAddCurveToPoint(cgPath, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
                break;
            case NSBezierPathElementClosePath:
                CGPathCloseSubpath(cgPath);
                break;
            default:
                break;
        }
    }
    return cgPath;
}

- (BOOL)annotation:(Annotation *)annotation isHitByPoint:(NSPoint)point radius:(CGFloat)radius {
    if (annotation.toolType == ToolTypeText || annotation.toolType == ToolTypePixelate ||
        annotation.toolType == ToolTypeSpotlight || annotation.toolType == ToolTypeLoupe) {
        NSRect box = NSInsetRect(annotation.path.bounds, -radius, -radius);
        return NSPointInRect(point, box);
    }
    if (annotation.toolType == ToolTypeCallout) {
        if (annotation.speechBubble) {
            NSRect box = NSMakeRect(annotation.startPoint.x - 45, annotation.startPoint.y - 24, 90, 48);
            return NSPointInRect(point, NSInsetRect(box, -radius, -radius));
        }
        CGFloat badgeRadius = MAX(13.0, 10.0 + annotation.lineWidth * 0.85) + radius;
        if (hypot(point.x - annotation.startPoint.x, point.y - annotation.startPoint.y) <= badgeRadius) {
            return YES;
        }
        return [annotation.path containsPoint:point];
    }

    if (annotation.filled) {
        return [annotation.path containsPoint:point];
    }

    CGPathRef cgPath = CGPathCreateFromNSBezierPath(annotation.path);
    if (cgPath == NULL) {
        return NO;
    }
    CGFloat strokeWidth = MAX(annotation.lineWidth, 2.0) + radius * 2.0;
    CGPathRef stroked = CGPathCreateCopyByStrokingPath(cgPath, NULL, strokeWidth,
                                                       kCGLineCapRound, kCGLineJoinRound, 10.0);
    CGPathRelease(cgPath);
    if (stroked == NULL) {
        return NO;
    }
    CGPoint cgPoint = CGPointMake(point.x, point.y);
    BOOL hit = CGPathContainsPoint(stroked, NULL, cgPoint, false);
    CGPathRelease(stroked);
    return hit;
}

- (void)eraseAtPoint:(NSPoint)point {
    [self eraseAtPoint:point recordSnapshot:YES];
}

- (void)eraseAtPoint:(NSPoint)point recordSnapshot:(BOOL)recordSnapshot {
    CGFloat radius = MAX(self.currentLineWidth * 2.0, 6.0);
    NSMutableArray<Annotation *> *kept = [NSMutableArray array];
    BOOL removedAny = NO;
    for (NSInteger i = (NSInteger)self.annotations.count - 1; i >= 0; i--) {
        Annotation *annotation = self.annotations[i];
        if (!removedAny && [self annotation:annotation isHitByPoint:point radius:radius]) {
            removedAny = YES;
        } else {
            [kept insertObject:annotation atIndex:0];
        }
    }
    if (removedAny) {
        self.annotations = kept;
        self.selectedAnnotationIndex = NSNotFound;
        self.erasedDuringDrag = YES;
        if (recordSnapshot) {
            [self recordSnapshot];
        }
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Colour sampling

- (NSColor *)sampleColorAtPoint:(NSPoint)point {
    for (NSInteger i = (NSInteger)self.annotations.count - 1; i >= 0; i--) {
        Annotation *annotation = self.annotations[i];
        if ([self annotation:annotation isHitByPoint:point radius:2.0]) {
            return annotation.color;
        }
    }

    if (self.backgroundImage == nil) {
        return nil;
    }
    CGImageRef cgImage = [self.backgroundImage CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (cgImage == NULL) {
        return nil;
    }
    CGFloat scaleX = (CGFloat)CGImageGetWidth(cgImage) / MAX(NSWidth(self.bounds), 1.0);
    CGFloat scaleY = (CGFloat)CGImageGetHeight(cgImage) / MAX(NSHeight(self.bounds), 1.0);
    NSInteger px = (NSInteger)lround(point.x * scaleX);
    NSInteger py = (NSInteger)lround((NSHeight(self.bounds) - point.y) * scaleY);
    if (px < 0 || py < 0 || px >= (NSInteger)CGImageGetWidth(cgImage) || py >= (NSInteger)CGImageGetHeight(cgImage)) {
        return nil;
    }

    CGImageRef crop = CGImageCreateWithImageInRect(cgImage, CGRectMake(px, py, 1, 1));
    if (crop == NULL) {
        return nil;
    }
    uint8_t pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    if (context != NULL) {
        CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), crop);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(crop);

    return [NSColor colorWithSRGBRed:pixel[0] / 255.0
                               green:pixel[1] / 255.0
                                blue:pixel[2] / 255.0
                               alpha:1.0];
}

#pragma mark - Text tool

- (NSFont *)textFontForSize:(CGFloat)size bold:(BOOL)bold {
    return bold ? [NSFont systemFontOfSize:size weight:NSFontWeightBold]
                : [NSFont systemFontOfSize:size weight:NSFontWeightRegular];
}

- (NSDictionary *)textAttributesForFont:(NSFont *)font color:(NSColor *)color {
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.60];
    shadow.shadowBlurRadius = 2.0;
    shadow.shadowOffset = NSMakeSize(0, -1);
    return @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSShadowAttributeName: shadow
    };
}

- (CGFloat)lineHeightForFont:(NSFont *)font {
    return ceil(font.ascender - font.descender + font.leading);
}

- (void)drawTextAnnotation:(Annotation *)annotation {
    NSFont *font = [self textFontForSize:annotation.fontSize bold:annotation.bold];
    NSDictionary *attributes = [self textAttributesForFont:font color:annotation.color];
    NSArray<NSString *> *lines = [annotation.text componentsSeparatedByString:@"\n"];
    CGFloat lineHeight = [self lineHeightForFont:font];
    CGFloat maxWidth = 0;
    for (NSString *line in lines) {
        maxWidth = MAX(maxWidth, [line sizeWithAttributes:attributes].width);
    }
    CGFloat totalHeight = lineHeight * lines.count;
    NSPoint position = annotation.textPosition;

    if (annotation.textBackground) {
        NSRect background = NSMakeRect(position.x - 8.0, position.y - totalHeight - 5.0,
                                       maxWidth + 16.0, totalHeight + 10.0);
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:background xRadius:6.0 yRadius:6.0];
        [[[NSColor colorWithSRGBRed:0.08 green:0.09 blue:0.12 alpha:1.0] colorWithAlphaComponent:0.62] setFill];
        [path fill];
        [[[NSColor whiteColor] colorWithAlphaComponent:0.18] setStroke];
        path.lineWidth = 1.0;
        [path stroke];
    }

    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *line = lines[i];
        CGFloat y = position.y - (i + 1) * lineHeight;
        [line drawAtPoint:NSMakePoint(position.x, y) withAttributes:attributes];
    }
}

- (BOOL)hasActiveTextEditor {
    return self.activeTextView != nil;
}

- (void)commitTextEditorIfNeeded {
    [self commitActiveTextEditor];
}

- (void)beginTextEntryForTestingAtPoint:(NSPoint)point {
    [self beginTextEntryAtPoint:point];
}

- (void)setTextEditorStringForTesting:(NSString *)text {
    self.activeTextView.string = text;
    [self resizeTextEditor];
}

- (void)commitTextEditorForTesting {
    [self commitActiveTextEditor];
}

- (void)beginEditingExistingAnnotationAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.annotations.count) {
        return;
    }
    Annotation *ann = self.annotations[index];
    self.editingAnnotationIndex = index;
    NSPoint pt = (ann.toolType == ToolTypeCallout && ann.speechBubble)
        ? NSMakePoint(ann.startPoint.x - 40.0, ann.startPoint.y + 16.0)
        : ann.textPosition;
    [self beginTextEntryAtPoint:pt initialText:ann.text ?: @""];
}

- (void)beginTextEntryAtPoint:(NSPoint)point {
    self.editingAnnotationIndex = NSNotFound;
    [self beginTextEntryAtPoint:point initialText:@""];
}

- (void)beginTextEntryAtPoint:(NSPoint)point initialText:(NSString *)initialText {
    [self commitActiveTextEditor];

    CGFloat x = MIN(MAX(point.x, 4.0), MAX(4.0, NSWidth(self.bounds) - 40.0));
    self.textTopY = MIN(MAX(point.y, 30.0), NSHeight(self.bounds) - 8.0);

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(x, self.textTopY - 34.0, 190.0, 34.0)];
    container.wantsLayer = YES;
    container.layer.cornerRadius = 7.0;
    container.layer.borderWidth = 1.5;
    container.layer.borderColor = [CSTheme accent].CGColor;
    container.layer.shadowColor = [NSColor blackColor].CGColor;
    container.layer.shadowOpacity = 0.28;
    container.layer.shadowRadius = 8.0;
    container.layer.shadowOffset = CGSizeMake(0, -2);
    [self addSubview:container];

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(7, 7, 176, 20)];
    textView.drawsBackground = NO;
    textView.richText = NO;
    textView.allowsUndo = YES;
    textView.font = [self textFontForSize:self.textFontSize bold:self.textBold];
    textView.textColor = self.currentColor;
    textView.insertionPointColor = self.currentColor;
    textView.textContainerInset = NSZeroSize;
    textView.textContainer.lineFragmentPadding = 0;
    textView.string = initialText ?: @"";
    textView.delegate = (id<NSTextViewDelegate>)self;
    [container addSubview:textView];

    self.activeTextContainer = container;
    self.activeTextView = textView;
    [self applyTextStyleToActiveEditor];
    [self resizeTextEditor];
    [self.window makeFirstResponder:textView];
}

- (void)applyTextStyleToActiveEditor {
    NSTextView *textView = self.activeTextView;
    NSView *container = self.activeTextContainer;
    if (textView == nil || container == nil) {
        return;
    }
    NSColor *textColor = self.currentColor ?: [NSColor systemRedColor];
    textView.font = [self textFontForSize:self.textFontSize bold:self.textBold];
    textView.textColor = textColor;
    textView.insertionPointColor = textColor;

    if (self.textBackground) {
        container.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.58].CGColor;
        container.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.45].CGColor;
    } else {
        container.layer.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.28].CGColor;
        container.layer.borderColor = [CSTheme accent].CGColor;
    }
    [self resizeTextEditor];
}

- (void)resizeTextEditor {
    NSTextView *textView = self.activeTextView;
    NSView *container = self.activeTextContainer;
    if (textView == nil || container == nil) {
        return;
    }
    NSLayoutManager *layoutManager = textView.layoutManager;
    NSTextContainer *textContainer = textView.textContainer;
    CGFloat maxWidth = MAX(180.0, NSWidth(self.bounds) - 20.0);
    textContainer.containerSize = NSMakeSize(maxWidth - 14.0, CGFLOAT_MAX);
    textContainer.widthTracksTextView = NO;
    [layoutManager ensureLayoutForTextContainer:textContainer];
    NSRect used = [layoutManager usedRectForTextContainer:textContainer];
    CGFloat width = MIN(MAX(used.size.width + 24.0, 180.0), maxWidth);
    CGFloat height = MIN(MAX(used.size.height + 16.0, 34.0), 260.0);
    CGFloat x = container.frame.origin.x;
    container.frame = NSMakeRect(x, self.textTopY - height, width, height);
    textView.frame = NSMakeRect(7, 7, width - 14, height - 14);
    textContainer.containerSize = NSMakeSize(width - 14, MAX(height - 14, 20));
    textView.needsDisplay = YES;
}

- (void)commitActiveTextEditor {
    if (self.activeTextView == nil) {
        return;
    }
    self.committingText = YES;
    NSString *text = self.activeTextView.string;
    NSView *container = self.activeTextContainer;
    NSTextView *textView = self.activeTextView;
    NSInteger editingIdx = self.editingAnnotationIndex;
    self.editingAnnotationIndex = NSNotFound;
    self.activeTextView = nil;
    self.activeTextContainer = nil;
    [textView removeFromSuperview];
    [container removeFromSuperview];
    self.committingText = NO;

    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (editingIdx != NSNotFound && editingIdx >= 0 && editingIdx < (NSInteger)self.annotations.count) {
        Annotation *existing = self.annotations[editingIdx];
        if (trimmed.length > 0) {
            existing.text = text;
            [self recordSnapshot];
        }
        [self setNeedsDisplay:YES];
        [self.window makeFirstResponder:self];
        return;
    }

    if (trimmed.length == 0) {
        [self.window makeFirstResponder:self];
        return;
    }

    Annotation *annotation = [Annotation new];
    annotation.toolType = ToolTypeText;
    annotation.color = self.currentColor;
    annotation.lineWidth = 0;
    annotation.text = text;
    annotation.fontSize = self.textFontSize;
    annotation.bold = self.textBold;
    annotation.textBackground = self.textBackground;
    annotation.textPosition = NSMakePoint(container.frame.origin.x, self.textTopY);

    NSFont *font = [self textFontForSize:annotation.fontSize bold:annotation.bold];
    NSDictionary *attributes = [self textAttributesForFont:font color:annotation.color];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    CGFloat maxWidth = 0;
    for (NSString *line in lines) {
        maxWidth = MAX(maxWidth, [line sizeWithAttributes:attributes].width);
    }
    CGFloat totalHeight = [self lineHeightForFont:font] * lines.count;
    annotation.path = [NSBezierPath bezierPathWithRect:NSMakeRect(annotation.textPosition.x,
                                                                  annotation.textPosition.y - totalHeight,
                                                                  MAX(maxWidth, 1.0),
                                                                  MAX(totalHeight, 1.0))];
    [self addAnnotation:annotation];
    [self.window makeFirstResponder:self];
}

- (void)cancelActiveTextEditor {
    if (self.activeTextView == nil) {
        return;
    }
    self.committingText = YES;
    NSTextView *textView = self.activeTextView;
    NSView *container = self.activeTextContainer;
    self.editingAnnotationIndex = NSNotFound;
    self.activeTextView = nil;
    self.activeTextContainer = nil;
    [textView removeFromSuperview];
    [container removeFromSuperview];
    self.committingText = NO;
    [self setNeedsDisplay:YES];
    [self.window makeFirstResponder:self];
}

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object == self.activeTextView) {
        [self resizeTextEditor];
    }
}

- (void)textDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.activeTextView && !self.committingText) {
        [self commitActiveTextEditor];
    }
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (textView != self.activeTextView) {
        return NO;
    }
    if (commandSelector == @selector(insertNewline:)) {
        BOOL shift = ([NSApp currentEvent].modifierFlags & NSEventModifierFlagShift) != 0;
        if (shift) {
            [textView insertNewline:nil];
        } else {
            [self commitActiveTextEditor];
        }
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self cancelActiveTextEditor];
        return YES;
    }
    return NO;
}

#pragma mark - Rendering the final image

- (NSImage *)renderCompositeImage {
    CGImageRef bgImage = NULL;
    if (self.backgroundImage != nil) {
        bgImage = [self.backgroundImage CGImageForProposedRect:NULL context:NULL hints:NULL];
    }

    NSInteger pixelWidth = bgImage != NULL ? (NSInteger)CGImageGetWidth(bgImage) : (NSInteger)self.bounds.size.width;
    NSInteger pixelHeight = bgImage != NULL ? (NSInteger)CGImageGetHeight(bgImage) : (NSInteger)self.bounds.size.height;
    pixelWidth = MAX(pixelWidth, 1);
    pixelHeight = MAX(pixelHeight, 1);

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:pixelWidth
                                                                    pixelsHigh:pixelHeight
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0
                                                                  bitsPerPixel:0];
    if (rep == nil) {
        return [[NSImage alloc] initWithSize:self.bounds.size];
    }

    NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphicsContext];

    CGContextRef ctx = graphicsContext.CGContext;
    CGFloat scale = (CGFloat)pixelWidth / MAX(NSWidth(self.bounds), 1.0);
    CGContextScaleCTM(ctx, scale, scale);

    if (self.backgroundImage != nil) {
        [self.backgroundImage drawInRect:self.bounds
                                fromRect:NSZeroRect
                               operation:NSCompositingOperationCopy
                                fraction:1.0];
    }

    [self drawAllAnnotationsIncludingPreview:NO];

    [NSGraphicsContext restoreGraphicsState];

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(pixelWidth, pixelHeight)];
    [image addRepresentation:rep];
    return image;
}

@end
