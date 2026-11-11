#import <Cocoa/Cocoa.h>
#import "Annotation.h"
#import "TextRecognizer.h"

NS_ASSUME_NONNULL_BEGIN

@class CanvasView;

@protocol CanvasViewDelegate <NSObject>
- (void)canvasViewDidChangeAnnotations:(CanvasView *)canvas;
- (void)canvasView:(CanvasView *)canvas didPickColor:(NSColor *)color;
- (void)canvasView:(CanvasView *)canvas didHoverColor:(NSColor *)color atPoint:(NSPoint)point;
@optional
- (void)canvasView:(CanvasView *)canvas didChangeLineWidth:(CGFloat)width;
- (void)canvasView:(CanvasView *)canvas didChangeSelectedOCRIndexes:(NSIndexSet *)selectedIndexes;
- (void)canvasView:(CanvasView *)canvas didResizeCanvasToImage:(NSImage *)image;
- (void)canvasView:(CanvasView *)canvas didSelectAnnotation:(nullable Annotation *)annotation;
@end

/// The editable screenshot surface: draws the captured image plus all
/// annotations and handles the drawing tools, object manipulation, and interactive OCR text blocks.
@interface CanvasView : NSView

@property (nonatomic, strong, nullable) NSImage *backgroundImage;
@property (nonatomic, readonly) NSMutableArray<Annotation *> *annotations;
@property (nonatomic) ToolType currentTool;
@property (nonatomic, strong) NSColor *currentColor;
@property (nonatomic) CGFloat currentLineWidth;
@property (nonatomic) BOOL shapeFilled;
@property (nonatomic) BOOL shapeDashed;
@property (nonatomic) BOOL shapeRounded;
@property (nonatomic) BOOL shapeShadow;
@property (nonatomic) BOOL arrowCurved;
@property (nonatomic) BOOL calloutSpeechBubble;

/// Spotlight configuration
@property (nonatomic) CSSpotlightShape spotlightShape;
@property (nonatomic) CGFloat spotlightDimOpacity;
@property (nonatomic) BOOL spotlightFeather;

/// Redact & Loupe configuration
@property (nonatomic) CSRedactMode redactMode;
@property (nonatomic) CGFloat loupeMagnification;

/// Text configuration
@property (nonatomic) CGFloat textFontSize;
@property (nonatomic) BOOL textBold;
@property (nonatomic) BOOL textBackground;

/// Selection state
@property (nonatomic) NSInteger selectedAnnotationIndex;
@property (nonatomic, readonly, nullable) Annotation *selectedAnnotation;

/// Eyedropper lock state (freezes hover colour updates so user can move cursor to copy buttons)
@property (nonatomic) BOOL colorPickerLocked;

@property (nonatomic, weak, nullable) id<CanvasViewDelegate> delegate;

/// Interactive OCR overlay state
@property (nonatomic) BOOL ocrMode;
@property (nonatomic, copy, nullable) NSArray<CSTextObservation *> *ocrObservations;
@property (nonatomic, copy, nullable) NSArray<CSBarcodeObservation *> *ocrBarcodes;
@property (nonatomic, copy) NSIndexSet *selectedOCRIndexes;

- (BOOL)canUndo;
- (BOOL)canRedo;
- (void)undo;
- (void)redo;
- (void)addAnnotation:(Annotation *)annotation;
- (void)deleteSelectedAnnotation;
- (void)clearSelection;
- (void)clearPreviewAnnotation;
- (void)cropToRect:(NSRect)cropRect;
- (NSInteger)nextCalloutNumber;
- (void)eraseAtPoint:(NSPoint)point;
- (nullable NSColor *)sampleColorAtPoint:(NSPoint)point;
- (BOOL)hasActiveTextEditor;
- (void)applyTextStyleToActiveEditor;
- (void)commitTextEditorIfNeeded;
- (void)beginTextEntryForTestingAtPoint:(NSPoint)point;
- (void)setTextEditorStringForTesting:(NSString *)text;
- (void)commitTextEditorForTesting;
- (NSImage *)renderCompositeImage;
- (void)tearDown;

@end

NS_ASSUME_NONNULL_END
