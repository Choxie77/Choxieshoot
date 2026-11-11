#import "ScreenshotCapture.h"
#import <CoreGraphics/CoreGraphics.h>

static CGRect CGRectsFromAppKitRect(NSRect nsRect) {
    // CGWindowListCreateImage expects global display coordinates:
    // origin at the top-left of the main display, y growing downwards.
    NSScreen *primary = [NSScreen screens].firstObject;
    if (primary == nil) {
        return NSRectToCGRect(nsRect);
    }
    CGFloat primaryHeight = primary.frame.size.height;
    CGFloat cgY = primaryHeight - NSMaxY(nsRect);
    return CGRectMake(NSMinX(nsRect), cgY, NSWidth(nsRect), NSHeight(nsRect));
}

static NSImage * _Nullable CaptureCGRect(CGRect cgRect, CGWindowID belowWindowID) {
    if (cgRect.size.width < 1.0 || cgRect.size.height < 1.0) {
        return nil;
    }
    CGWindowListOption listOption = (belowWindowID != kCGNullWindowID)
        ? kCGWindowListOptionOnScreenBelowWindow
        : kCGWindowListOptionOnScreenOnly;
    CGImageRef image = CGWindowListCreateImage(
        cgRect,
        listOption,
        belowWindowID,
        kCGWindowImageBestResolution | kCGWindowImageBoundsIgnoreFraming
    );
    if (image == NULL && belowWindowID != kCGNullWindowID) {
        image = CGWindowListCreateImage(
            cgRect,
            kCGWindowListOptionOnScreenOnly,
            kCGNullWindowID,
            kCGWindowImageBestResolution | kCGWindowImageBoundsIgnoreFraming
        );
    }
    if (image == NULL) {
        return nil;
    }
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:cgRect.size];
    CGImageRelease(image);
    return result;
}

NSImage * _Nullable CaptureScreenRectBelowWindow(NSRect screenRect, CGWindowID belowWindowID) {
    return CaptureCGRect(CGRectsFromAppKitRect(screenRect), belowWindowID);
}

NSImage * _Nullable CaptureScreenRect(NSRect screenRect) {
    return CaptureScreenRectBelowWindow(screenRect, kCGNullWindowID);
}

NSImage * _Nullable CaptureMainScreen(void) {
    NSScreen *mainScreen = [NSScreen mainScreen];
    if (mainScreen == nil) {
        return nil;
    }
    return CaptureScreenRect(mainScreen.frame);
}
