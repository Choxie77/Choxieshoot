#import <Cocoa/Cocoa.h>
#import "Annotation.h"

NS_ASSUME_NONNULL_BEGIN

@class ToolbarView;

@protocol ToolbarViewDelegate <NSObject>
- (void)toolbarView:(ToolbarView *)toolbar didSelectTool:(ToolType)tool;
- (void)toolbarView:(ToolbarView *)toolbar didSelectColor:(NSColor *)color;
- (void)toolbarView:(ToolbarView *)toolbar didChangeLineWidth:(CGFloat)width;
- (void)toolbarViewDidRequestUndo:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestRedo:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestCopyText:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestNewCapture:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestSave:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestCopy:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestShare:(ToolbarView *)toolbar;
- (void)toolbarViewDidRequestClose:(ToolbarView *)toolbar;
@optional
- (void)toolbarViewDidRequestMinimize:(ToolbarView *)toolbar;
- (void)toolbarView:(ToolbarView *)toolbar didChangePinnedOnTop:(BOOL)pinned;
- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeFilled:(BOOL)filled;
- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeDashed:(BOOL)dashed;
- (void)toolbarView:(ToolbarView *)toolbar didChangeShapeShadow:(BOOL)shadow;
@end

/// Modern glassmorphic editing bar with grouped tool capsules, circular swatches,
/// live stroke-size preview, style modifiers, and capture actions.
@interface ToolbarView : NSView

+ (BOOL)usesCompactLayoutForWidth:(CGFloat)width;
+ (CGFloat)preferredHeightForWidth:(CGFloat)width;

@property (nonatomic, weak, nullable) id<ToolbarViewDelegate> delegate;
@property (nonatomic) ToolType currentTool;
@property (nonatomic, strong) NSColor *currentColor;
@property (nonatomic) CGFloat currentLineWidth;
@property (nonatomic) BOOL shapeFilled;
@property (nonatomic) BOOL shapeDashed;
@property (nonatomic) BOOL shapeShadow;
@property (nonatomic) BOOL pinnedOnTop;
@property (nonatomic) BOOL canUndo;
@property (nonatomic) BOOL canRedo;

/// Shows a busy state on the OCR button while recognition runs.
@property (nonatomic, readonly, getter=isOCRBusy) BOOL ocrBusy;
- (void)setOCRBusy:(BOOL)busy;

/// Highlights the OCR button while the interactive text recognizer is open.
- (void)setOCRActive:(BOOL)active;

@end

NS_ASSUME_NONNULL_END
