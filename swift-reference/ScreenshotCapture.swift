import Cocoa

enum ScreenshotCapture {

    /// Capture the given screen rectangle (points, global screen coordinates in AppKit space).
    /// Requires Screen Recording permission on macOS 10.15+; macOS prompts on first use.
    static func capture(rect: CGRect) -> NSImage? {
        // Convert from AppKit coordinates (bottom-left origin) to Core Graphics coordinates (top-left origin)
        let cgRect = appKitToCGRect(rect)
        
        // Best-resolution copy of the on-screen pixels in that rectangle.
        let imageOption: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let cgImage = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, imageOption) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: cgRect.size)
        return image
    }
    
    /// Convert an AppKit-screen-coordinate rect to Core Graphics coordinates.
    /// AppKit: origin at bottom-left of main screen, y grows upward.
    /// Core Graphics: origin at top-left of main screen, y grows downward.
    private static func appKitToCGRect(_ appKitRect: CGRect) -> CGRect {
        guard let primaryScreen = NSScreen.screens.first else {
            return appKitRect
        }
        let primaryHeight = primaryScreen.frame.height
        let cgY = primaryHeight - appKitRect.maxY
        return CGRect(x: appKitRect.minX, y: cgY, width: appKitRect.width, height: appKitRect.height)
    }
}