#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CSVideoCropAspect) {
    CSVideoCropAspectFreeform = 0,
    CSVideoCropAspectOriginal = 1,
    CSVideoCropAspect16_9     = 2,
    CSVideoCropAspect4_3      = 3,
    CSVideoCropAspect1_1      = 4,
    CSVideoCropAspect9_16     = 5
};

/// Interactive spatial crop overlay positioned above the video player view.
@interface VideoCropOverlayView : NSView

@property (nonatomic) NSSize videoNaturalSize;
@property (nonatomic) BOOL cropActive;
@property (nonatomic) CSVideoCropAspect aspectPreset;

/// Normalized crop rectangle in range [0, 1] relative to video bounds (origin top-left).
@property (nonatomic) CGRect normalizedCropRect;

/// Callback invoked whenever the crop rectangle is adjusted.
@property (nonatomic, copy, nullable) void (^onCropChanged)(CGRect pixelCropRect);

- (instancetype)initWithFrame:(NSRect)frame videoNaturalSize:(NSSize)videoNaturalSize;

/// Returns the crop rectangle in original video pixel coordinates, snapped to even dimensions.
- (CGRect)pixelCropRect;

/// Sets the crop rectangle from source video pixel coordinates.
- (void)setPixelCropRect:(CGRect)pixelRect;

/// Resets the crop rectangle to the full video dimensions.
- (void)resetToFullVideo;

/// Returns YES if the current crop differs meaningfully from the full video frame.
- (BOOL)isCropped;

/// Computes the letterboxed / pillarboxed display frame of the video inside this view's bounds.
- (NSRect)videoDisplayRect;

@end

NS_ASSUME_NONNULL_END
