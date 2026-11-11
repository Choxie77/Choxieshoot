#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Capture the region of the screen described by an AppKit screen rectangle
/// (bottom-left origin, global screen coordinates).
/// Returns nil when the system refuses to hand back pixels.
NSImage * _Nullable CaptureScreenRect(NSRect screenRect);

/// Capture the region of the screen strictly below a given window (e.g. SelectionWindow)
/// so the overlay does not need to order out and risk switching active Spaces before capture.
NSImage * _Nullable CaptureScreenRectBelowWindow(NSRect screenRect, CGWindowID belowWindowID);

/// Capture the full main display (used by the --selftest mode).
NSImage * _Nullable CaptureMainScreen(void);

NS_ASSUME_NONNULL_END
