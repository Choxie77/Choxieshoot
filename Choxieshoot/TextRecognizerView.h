#import <Cocoa/Cocoa.h>
#import "TextRecognizer.h"

NS_ASSUME_NONNULL_BEGIN

@class TextRecognizerView;

@protocol TextRecognizerViewDelegate <NSObject>
- (void)textRecognizerView:(TextRecognizerView *)view didCopyText:(NSString *)text;
- (void)textRecognizerViewDidRequestSelectAllBlocks:(TextRecognizerView *)view;
- (void)textRecognizerViewDidRequestClearBlocks:(TextRecognizerView *)view;
- (void)textRecognizerViewDidRequestClose:(TextRecognizerView *)view;
@optional
- (void)textRecognizerView:(TextRecognizerView *)view didOpenBarcodeURL:(NSURL *)url;
@end

/// Interactive OCR inspector panel: lets the user inspect recognized text,
/// toggle text blocks on the screenshot, or highlight a specific text range
/// before pressing Copy. Also surfaces detected QR codes / barcodes with
/// one-click Copy and Open URL actions.
@interface TextRecognizerView : NSView

@property (nonatomic, weak, nullable) id<TextRecognizerViewDelegate> delegate;
@property (nonatomic, strong, nullable, readonly) CSTextRecognitionResult *result;

/// Loads the recognition result and updates the text editor with the selected observation indexes.
- (void)updateWithResult:(nullable CSTextRecognitionResult *)result
         selectedIndexes:(NSIndexSet *)selectedIndexes;

/// Updates only the selected observation indexes (e.g. after clicking or dragging blocks on the canvas).
- (void)updateSelectedIndexes:(NSIndexSet *)selectedIndexes;

/// Returns the text that will be copied by the primary Copy action (highlighted substring if any, otherwise active text).
- (NSString *)effectiveTextToCopy;

/// Programmatic helpers for testing partial selection, barcode actions, and copy actions.
- (void)setHighlightedRange:(NSRange)range;
- (void)triggerCopySelection;
- (void)triggerCopyAll;
- (void)triggerCopyBarcode;
- (BOOL)hasDetectedBarcodes;

@end

NS_ASSUME_NONNULL_END
