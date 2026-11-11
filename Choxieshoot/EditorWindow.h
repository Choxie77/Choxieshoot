#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class EditorWindow;
@class CanvasView;

typedef void (^EditorWindowCloseBlock)(EditorWindow *window);

/// Editing window: header bar with window controls on top, captured screenshot in center, annotation toolbar below.
@interface EditorWindow : NSPanel

- (instancetype)initWithScreenRect:(NSRect)screenRect image:(NSImage *)image;

@property (nonatomic, copy, nullable) EditorWindowCloseBlock onClose;
@property (nonatomic) BOOL pinnedOnTop;
@property (nonatomic, strong, readonly) CanvasView *canvasView;
@property (nonatomic, readonly) BOOL ocrInProgress;

- (void)minimizeWindow:(nullable id)sender;

/// Writes the annotated composite as PNG (used by the save panel and by tests).
- (BOOL)saveCompositeToURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;

/// Exposed for automated tests; equivalent to pressing the toolbar buttons.
- (void)openTextRecognizerForTesting;
- (void)openTextRecognizerWithCompletion:(nullable void (^)(BOOL foundText))completion;
- (BOOL)isOCRBusyForTesting;
- (void)cancelTextRecognition;
- (void)toggleTextRecognizer;
- (void)selectOCRBlockIndexesForTesting:(NSIndexSet *)indexes;
- (void)selectOCRTextRangeForTesting:(NSRange)range;
- (void)copySelectedOCRTextForTesting;
- (void)copyDetectedBarcodeForTesting;
- (void)copyRecognizedTextForTesting;
- (void)copyImageForTesting;
- (void)showToastForTesting:(NSString *)message;
- (void)showColorInspectorForTesting:(NSColor *)color;
- (void)showTextToolForTesting;
- (void)addSampleTextForTesting;

@end

NS_ASSUME_NONNULL_END
