#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import "AppDelegate.h"
#import "ScreenshotCapture.h"
#import "CanvasView.h"
#import "Annotation.h"
#import "TextRecognizer.h"
#import "SelectionWindow.h"
#import "CSShortcut.h"
#import "TextOptionsView.h"
#import "ColorInspectorView.h"
#import "VideoRecorder.h"
#import "RecordingControlWindow.h"
#import "VideoPreviewWindow.h"
#import "EditorWindow.h"
#import "VideoCropOverlayView.h"
#import "VideoEditorEngine.h"

static BOOL ImageLooksBlank(NSImage *image) {
    CGImageRef cg = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (cg == NULL) { return YES; }
    uint8_t px[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast);
    if (ctx != NULL) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), cg);
        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(space);
    return px[0] < 6 && px[1] < 6 && px[2] < 6;
}

static int RunCaptureTest(void) {
    @autoreleasepool {
        BOOL preflight = CGPreflightScreenCaptureAccess();
        NSImage *image = CaptureMainScreen();
        BOOL blank = image == nil ? YES : ImageLooksBlank(image);
        NSString *log = [NSString stringWithFormat:@"preflight=%d image=%@ size=%.0fx%.0f blank=%d\n",
                         preflight,
                         image == nil ? @"nil" : @"yes",
                         image.size.width, image.size.height,
                         blank];
        [log writeToFile:@"/tmp/choxieshoot-capturetest.log" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        printf("%s", log.UTF8String);
        return 0;
    }
}

static int RunSelfTest(void) {
    @autoreleasepool {
        NSImage *capture = CaptureMainScreen();
        if (capture == nil) {
            fprintf(stderr, "selftest: screen capture returned nil (Screen Recording permission missing?)\n");
            return 2;
        }

        NSData *tiff = [capture TIFFRepresentation];
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:@"/tmp/choxieshoot-selftest-capture.png" atomically:YES];
        printf("selftest: captured %.0fx%.0f pt (%.0fx%.0f px) -> /tmp/choxieshoot-selftest-capture.png\n",
               capture.size.width, capture.size.height,
               (double)rep.pixelsWide, (double)rep.pixelsHigh);

        // Exercise the annotation renderer on a synthetic canvas.
        CanvasView *canvas = [[CanvasView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
        canvas.backgroundImage = capture;

        Annotation *rect = [Annotation new];
        rect.toolType = ToolTypeRectangle;
        rect.color = [NSColor systemRedColor];
        rect.lineWidth = 4.0;
        rect.path = [NSBezierPath bezierPathWithRect:NSMakeRect(24, 24, 160, 100)];
        [canvas addAnnotation:rect];

        Annotation *arrow = [Annotation new];
        arrow.toolType = ToolTypeArrow;
        arrow.color = [NSColor systemBlueColor];
        arrow.lineWidth = 4.0;
        arrow.path = [NSBezierPath bezierPath];
        [canvas addAnnotation:arrow];

        Annotation *text = [Annotation new];
        text.toolType = ToolTypeText;
        text.color = [NSColor systemGreenColor];
        text.text = @"Choxieshoot selftest";
        text.textPosition = NSMakePoint(30, 160);
        [canvas addAnnotation:text];

        BOOL undoRedoOk = [canvas canUndo] && ![canvas canRedo];
        for (NSInteger i = 0; i < 3; i++) {
            [canvas undo];
        }
        undoRedoOk = undoRedoOk && ![canvas canUndo] && [canvas canRedo];
        for (NSInteger i = 0; i < 3; i++) {
            [canvas redo];
        }
        undoRedoOk = undoRedoOk && [canvas canUndo] && ![canvas canRedo];
        printf("selftest: undo/redo %s\n", undoRedoOk ? "ok" : "FAILED");

        NSImage *composite = [canvas renderCompositeImage];
        NSBitmapImageRep *compositeRep = [NSBitmapImageRep imageRepWithData:[composite TIFFRepresentation]];
        NSData *compositePNG = [compositeRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        BOOL ok = [compositePNG writeToFile:@"/tmp/choxieshoot-selftest-composite.png" atomically:YES];
        printf("selftest: composite %.0fx%.0f px -> /tmp/choxieshoot-selftest-composite.png (%s)\n",
               (double)compositeRep.pixelsWide, (double)compositeRep.pixelsHigh,
               ok ? "ok" : "failed");
        return ok ? 0 : 3;
    }
}

#import "EditorWindow.h"

static int RunUITest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        // Synthetic screenshot so the editor window can be built without capture.
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(640, 400)];
        [image lockFocus];
        [[NSColor colorWithSRGBRed:0.12 green:0.16 blue:0.22 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 400));
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(20, 340, 300, 24));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(80, 120, 640, 400)
                                                                  image:image];
        if (editor == nil) {
            fprintf(stderr, "uitest: editor window could not be created\n");
            return 2;
        }
        [editor makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [editor showToastForTesting:@"Copied 128 characters"];
        });

        // Also construct (but do not show) the selection overlay.
        SelectionWindow *selection = [[SelectionWindow alloc] initWithCompletion:^(NSRect rect) {
        } cancel:^{
        }];
        if (selection == nil) {
            fprintf(stderr, "uitest: selection window could not be created\n");
            return 3;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("uitest: editor window %.0fx%.0f created and shown\n",
                   editor.frame.size.width, editor.frame.size.height);
            [app terminate:nil];
        });

        [app run];
        return 0;
    }
}

static int RunDrawTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *background = [[NSImage alloc] initWithSize:NSMakeSize(500, 300)];
        [background lockFocus];
        [[NSColor colorWithSRGBRed:0.10 green:0.12 blue:0.16 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 500, 300));
        [background unlockFocus];

        CanvasView *canvas = [[CanvasView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
        canvas.backgroundImage = background;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.contentView = canvas;

        // 1. Verify window dragging is disabled on canvas and panels
        BOOL canvasCannotMove = ![canvas mouseDownCanMoveWindow];
        TextOptionsView *tov = [[TextOptionsView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        BOOL tovCannotMove = ![tov mouseDownCanMoveWindow];
        ColorInspectorView *civ = [[ColorInspectorView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        BOOL civCannotMove = ![civ mouseDownCanMoveWindow];
        BOOL windowMoveOk = canvasCannotMove && tovCannotMove && civCannotMove;

        NSEvent *(^eventAt)(NSEventType, NSPoint, NSEventModifierFlags) = ^NSEvent *(NSEventType type, NSPoint point, NSEventModifierFlags flags) {
            return [NSEvent mouseEventWithType:type
                                      location:point
                                 modifierFlags:flags
                                     timestamp:0
                                  windowNumber:window.windowNumber
                                       context:nil
                                   eventNumber:1
                                    clickCount:1
                                      pressure:1.0];
        };

        // 2. Pencil: single click dot
        canvas.currentTool = ToolTypePencil;
        canvas.currentColor = [NSColor systemRedColor];
        canvas.currentLineWidth = 4.0;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(20, 20), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(20, 20), 0)];
        BOOL pencilDotOk = canvas.canUndo;

        // 3. Line tool with Shift snap
        canvas.currentTool = ToolTypeLine;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(50, 50), NSEventModifierFlagShift)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(150, 58), NSEventModifierFlagShift)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(150, 58), NSEventModifierFlagShift)];
        BOOL lineOk = canvas.canUndo;

        // 4. Arrow tool: normal and short arrow
        canvas.currentTool = ToolTypeArrow;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(200, 50), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(260, 50), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(260, 50), 0)];
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(280, 50), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(288, 50), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(288, 50), 0)];
        BOOL arrowOk = canvas.canUndo;

        // 5. Rectangle tool: outline and filled
        canvas.currentTool = ToolTypeRectangle;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(50, 100), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(150, 200), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(150, 200), 0)];
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(200, 100), NSEventModifierFlagOption)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(300, 200), NSEventModifierFlagOption)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(300, 200), NSEventModifierFlagOption)];
        BOOL rectOk = canvas.canUndo;

        // 6. Ellipse tool: outline and filled
        canvas.currentTool = ToolTypeEllipse;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(320, 100), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(420, 200), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(420, 200), 0)];
        BOOL ellipseOk = canvas.canUndo;

        // 7. Marker tool: click dot and drag
        canvas.currentTool = ToolTypeMarker;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(30, 250), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(120, 250), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(120, 250), 0)];
        BOOL markerOk = canvas.canUndo;

        // 8. Eraser precision test
        while (canvas.canUndo) {
            [canvas undo];
        }
        BOOL (^hasRedPixel)(NSImage *) = ^BOOL(NSImage *image) {
            NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
            if (bitmap == nil) {
                return NO;
            }
            for (NSInteger y = 0; y < bitmap.pixelsHigh; y += 6) {
                for (NSInteger x = 0; x < bitmap.pixelsWide; x += 6) {
                    NSColor *color = [bitmap colorAtX:x y:y];
                    if (color.redComponent > 0.6 && color.greenComponent < 0.4) {
                        return YES;
                    }
                }
            }
            return NO;
        };

        canvas.currentTool = ToolTypeRectangle;
        canvas.currentLineWidth = 4.0;
        canvas.currentColor = [NSColor systemRedColor];
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(50, 50), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(200, 200), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(200, 200), 0)];
        BOOL hasRect = hasRedPixel([canvas renderCompositeImage]);

        // Empty center (125, 125) must NOT erase
        canvas.currentTool = ToolTypeEraser;
        canvas.currentLineWidth = 4.0;
        [canvas eraseAtPoint:NSMakePoint(125, 125)];
        BOOL centerNotErased = hasRedPixel([canvas renderCompositeImage]);

        // Left stroke at (50, 120) MUST erase
        [canvas eraseAtPoint:NSMakePoint(50, 120)];
        BOOL strokeErased = !hasRedPixel([canvas renderCompositeImage]);

        [canvas undo];
        BOOL restored = hasRedPixel([canvas renderCompositeImage]);

        // 9. Color picker sampling & click-to-lock freeze
        canvas.currentTool = ToolTypeColorPicker;
        NSColor *sampledAnn = [canvas sampleColorAtPoint:NSMakePoint(50, 120)];
        NSColor *srgbAnn = [sampledAnn colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        BOOL sampledAnnOk = srgbAnn && srgbAnn.redComponent > 0.8 && srgbAnn.greenComponent < 0.3;

        NSColor *sampledBg = [canvas sampleColorAtPoint:NSMakePoint(400, 250)];
        NSColor *srgbBg = [sampledBg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        BOOL sampledBgOk = srgbBg && srgbBg.redComponent < 0.2 && srgbBg.blueComponent > 0.1;

        // Click at red stroke (50, 120) should lock the picker so moving over dark background (400, 250) does NOT overwrite currentColor
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(50, 120), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(50, 120), 0)];
        BOOL pickerLocked = canvas.colorPickerLocked;
        [canvas mouseMoved:eventAt(NSEventTypeMouseMoved, NSMakePoint(400, 250), 0)];
        NSColor *afterMove = [canvas.currentColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        BOOL lockPreservedColor = pickerLocked && afterMove && afterMove.redComponent > 0.8 && afterMove.greenComponent < 0.3;
        sampledBgOk = sampledBgOk && lockPreservedColor;

        // 10. Numbered Callouts (1, 2, 3...) + undo/erase re-numbering
        canvas.currentTool = ToolTypeCallout;
        BOOL calloutStartOk = ([canvas nextCalloutNumber] == 1);
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(300, 80), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(300, 80), 0)];
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(340, 80), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(380, 120), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(380, 120), 0)];
        BOOL calloutIncOk = ([canvas nextCalloutNumber] == 3);
        [canvas undo];
        BOOL calloutUndoOk = ([canvas nextCalloutNumber] == 2);
        BOOL calloutOk = calloutStartOk && calloutIncOk && calloutUndoOk;

        // 11. Pixelate & Blur Redaction tool
        canvas.currentTool = ToolTypePixelate;
        canvas.currentLineWidth = 6.0;
        canvas.redactMode = CSRedactModePixelate;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(40, 40), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(160, 140), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(160, 140), 0)];
        canvas.redactMode = CSRedactModeBlur;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(170, 40), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(230, 100), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(230, 100), 0)];
        BOOL pixelateOk = canvas.canUndo && ([canvas renderCompositeImage] != nil);

        // 12. Spotlight dimming + shapes (Rounded, Circle, Pill) + feather & dim opacity
        canvas.shapeFilled = NO;
        canvas.currentTool = ToolTypeSpotlight;
        canvas.spotlightShape = CSSpotlightShapeEllipse;
        canvas.spotlightDimOpacity = 0.65;
        canvas.spotlightFeather = YES;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(220, 140), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(360, 240), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(360, 240), 0)];
        canvas.spotlightShape = CSSpotlightShapePill;
        NSImage *spotImage = [canvas renderCompositeImage];
        BOOL spotlightOk = (spotImage != nil && canvas.selectedAnnotation != nil);

        // 13. Curved Arrow, Magnifier Loupe & Select/Move/Delete
        canvas.currentTool = ToolTypeArrow;
        canvas.arrowCurved = YES;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(60, 180), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(180, 260), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(180, 260), 0)];

        canvas.currentTool = ToolTypeLoupe;
        canvas.loupeMagnification = 2.5;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(380, 180), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(450, 250), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(450, 250), 0)];

        canvas.currentTool = ToolTypeSelect;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(415, 215), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(425, 225), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(425, 225), 0)];
        BOOL selectLoupeOk = (canvas.selectedAnnotation != nil && canvas.selectedAnnotation.toolType == ToolTypeLoupe);
        [canvas deleteSelectedAnnotation];
        BOOL deleteSelectedOk = (canvas.selectedAnnotation == nil);

        // 14. Crop canvas + Undo restore
        canvas.currentTool = ToolTypeCrop;
        [canvas mouseDown:eventAt(NSEventTypeLeftMouseDown, NSMakePoint(20, 20), 0)];
        [canvas mouseDragged:eventAt(NSEventTypeLeftMouseDragged, NSMakePoint(260, 180), 0)];
        [canvas mouseUp:eventAt(NSEventTypeLeftMouseUp, NSMakePoint(260, 180), 0)];
        BOOL croppedSizeOk = (fabs(NSWidth(canvas.bounds) - 240.0) < 2.0 && fabs(NSHeight(canvas.bounds) - 160.0) < 2.0);
        [canvas undo];
        BOOL uncroppedSizeOk = (fabs(NSWidth(canvas.bounds) - 500.0) < 2.0 && fabs(NSHeight(canvas.bounds) - 300.0) < 2.0);
        BOOL cropOk = croppedSizeOk && uncroppedSizeOk;

        BOOL ok = windowMoveOk && pencilDotOk && lineOk && arrowOk && rectOk && ellipseOk &&
                  markerOk && hasRect && centerNotErased && strokeErased && restored &&
                  sampledAnnOk && sampledBgOk && calloutOk && pixelateOk && spotlightOk &&
                  selectLoupeOk && deleteSelectedOk && cropOk;

        printf("drawtest: windowMove=%d pencil=%d line=%d arrow=%d rect=%d ellipse=%d marker=%d "
               "eraserCenterSafe=%d eraserStroke=%d restore=%d colorAnn=%d colorBg=%d "
               "callout=%d pixelateBlur=%d spotlight=%d selectLoupe=%d delete=%d crop=%d -> %s\n",
               windowMoveOk, pencilDotOk, lineOk, arrowOk, rectOk, ellipseOk, markerOk,
               centerNotErased, strokeErased, restored, sampledAnnOk, sampledBgOk,
               calloutOk, pixelateOk, spotlightOk, selectLoupeOk, deleteSelectedOk, cropOk,
               ok ? "ok" : "FAILED");
        return ok ? 0 : 3;
    }
}

static int RunCopyTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(500, 300)];
        [image lockFocus];
        [[NSColor orangeColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 500, 300));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(100, 100, 500, 300) image:image];
        [editor makeKeyAndOrderFront:nil];
        [editor copyImageForTesting];

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSArray *images = [pasteboard readObjectsForClasses:@[[NSImage class]] options:nil];
        BOOL ok = images.count > 0;
        printf("copytest: pasteboard images=%lu -> %s\n", (unsigned long)images.count, ok ? "ok" : "FAILED");
        [editor close];
        return ok ? 0 : 4;
    }
}

static int RunSaveTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(500, 300)];
        [image lockFocus];
        [[NSColor colorWithSRGBRed:0.2 green:0.4 blue:0.6 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 500, 300));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(100, 100, 500, 300) image:image];
        [editor makeKeyAndOrderFront:nil];

        NSString *path = @"/tmp/choxieshoot-savetest.png";
        NSError *error = nil;
        BOOL wrote = [editor saveCompositeToURL:[NSURL fileURLWithPath:path] error:&error];
        NSData *data = [NSData dataWithContentsOfFile:path];
        BOOL pngSignature = data.length > 8 && ((const unsigned char *)data.bytes)[0] == 0x89 &&
                            ((const unsigned char *)data.bytes)[1] == 0x50;
        BOOL ok = wrote && data.length > 1000 && pngSignature;
        printf("savetest: wrote=%d bytes=%lu png=%d -> %s\n",
               wrote, (unsigned long)data.length, pngSignature, ok ? "ok" : "FAILED");
        [editor close];
        return ok ? 0 : 5;
    }
}

static int RunShortcutTest(void) {
    @autoreleasepool {
        NSArray<CSShortcut *> *shortcuts = @[
            [CSShortcut defaultShortcut],
            [CSShortcut shortcutWithKeyCode:kVK_ANSI_S modifiers:(controlKey | optionKey)],
            [CSShortcut shortcutWithKeyCode:kVK_F12 modifiers:0],
            [CSShortcut shortcutWithKeyCode:kVK_ANSI_X modifiers:(optionKey | cmdKey)]
        ];
        for (CSShortcut *shortcut in shortcuts) {
            printf("shortcuttest: %s valid=%d\n", shortcut.displayString.UTF8String, shortcut.isValid);
        }
        return 0;
    }
}

static int RunPreferencesUITest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [delegate showPreferencesForTesting];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("uitestprefs: preferences window shown\n");
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static int RunTextEditTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *background = [[NSImage alloc] initWithSize:NSMakeSize(500, 300)];
        [background lockFocus];
        [[NSColor colorWithSRGBRed:0.10 green:0.12 blue:0.16 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 500, 300));
        [background unlockFocus];
        CanvasView *canvas = [[CanvasView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
        canvas.backgroundImage = background;
        canvas.currentColor = [NSColor whiteColor];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.contentView = canvas;
        canvas.currentTool = ToolTypeText;
        [canvas beginTextEntryForTestingAtPoint:NSMakePoint(40, 240)];
        BOOL editorOpened = [canvas hasActiveTextEditor];
        [canvas setTextEditorStringForTesting:@"Text edit test\nsecond line"];
        [canvas commitTextEditorForTesting];
        BOOL committed = canvas.canUndo && ![canvas hasActiveTextEditor];
        printf("textedittest: editor=%d committed=%d -> %s\n",
               editorOpened, committed, (editorOpened && committed) ? "ok" : "FAILED");
        return (editorOpened && committed) ? 0 : 3;
    }
}

static int RunTextUITest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(860, 520)];
        [image lockFocus];
        [[NSColor colorWithSRGBRed:0.10 green:0.12 blue:0.16 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 860, 520));
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(40, 40, 300, 24));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(80, 120, 860, 520) image:image];
        [editor makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [editor showTextToolForTesting];
            [editor addSampleTextForTesting];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("uitesttext: editor window %.0fx%.0f with text panel and sample text\n",
                   editor.frame.size.width, editor.frame.size.height);
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static int RunColorUITest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(860, 520)];
        [image lockFocus];
        [[NSColor colorWithSRGBRed:0.10 green:0.12 blue:0.16 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 860, 520));
        [[NSColor colorWithSRGBRed:0.85 green:0.22 blue:0.24 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(40, 300, 260, 160));
        [[NSColor colorWithSRGBRed:0.20 green:0.62 blue:0.92 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(340, 300, 260, 160));
        [[NSColor colorWithSRGBRed:0.30 green:0.78 blue:0.52 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(640, 300, 180, 160));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(80, 120, 860, 520) image:image];
        [editor makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [editor showColorInspectorForTesting:[NSColor colorWithSRGBRed:0.85 green:0.22 blue:0.24 alpha:1.0]];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("uitestcolor: editor window %.0fx%.0f with color inspector shown\n",
                   editor.frame.size.width, editor.frame.size.height);
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static int RunWideUITest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1000, 420)];
        [image lockFocus];
        [[NSColor colorWithSRGBRed:0.14 green:0.18 blue:0.24 alpha:1.0] setFill];
        NSRectFill(NSMakeRect(0, 0, 1000, 420));
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(24, 360, 420, 22));
        [image unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(80, 160, 1000, 420) image:image];
        [editor makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("uitestwide: editor window %.0fx%.0f created and shown\n",
                   editor.frame.size.width, editor.frame.size.height);
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static int RunFlowTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [delegate captureTestRect:NSMakeRect(120, 180, 520, 340)];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("flowtest: captured region and opened editor\n");
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static NSImage *GenerateQRImage(NSString *payload, CGFloat size) {
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    [filter setValue:[payload dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *output = filter.outputImage;
    if (output == nil) {
        return nil;
    }
    CGRect extent = CGRectIntegral(output.extent);
    CGFloat scale = size / MAX(CGRectGetWidth(extent), CGRectGetHeight(extent));
    CIImage *scaled = [output imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    CIContext *ciCtx = [CIContext contextWithOptions:nil];
    CGImageRef cgImg = [ciCtx createCGImage:scaled fromRect:scaled.extent];
    if (cgImg == nil) {
        return nil;
    }
    NSImage *nsImg = [[NSImage alloc] initWithCGImage:cgImg size:NSMakeSize(size, size)];
    CGImageRelease(cgImg);
    return nsImg;
}

static int RunOCRFlowTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        NSImage *qrImg = GenerateQRImage(@"https://choxieshoot.local/qr", 110.0);
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(560, 240)];
        [image lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 560, 240));
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:30 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor blackColor]
        };
        [@"Clipboard OCR 98765" drawAtPoint:NSMakePoint(24, 120) withAttributes:attributes];
        [@"second line" drawAtPoint:NSMakePoint(24, 70) withAttributes:attributes];
        if (qrImg != nil) {
            [qrImg drawInRect:NSMakeRect(420, 65, 110, 110)
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0];
        }
        [image unlockFocus];

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:@"SENTINEL_UNTOUCHED" forType:NSPasteboardTypeString];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(120, 160, 560, 240)
                                                                  image:image];
        [editor makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];

        // 1. Open interactive text recognizer (should NOT overwrite clipboard automatically)
        __block BOOL wasBusyAtStart = NO;
        [editor openTextRecognizerWithCompletion:^(BOOL foundText) {
            BOOL busyClearedOnFinish = ![editor isOCRBusyForTesting];
            NSString *beforeCopy = [pasteboard stringForType:NSPasteboardTypeString];
            BOOL notAutoCopied = [beforeCopy isEqualToString:@"SENTINEL_UNTOUCHED"];

            // 2. Select only block index 1 ("second line") and press Copy
            [editor selectOCRBlockIndexesForTesting:[NSIndexSet indexSetWithIndex:1]];
            [editor copySelectedOCRTextForTesting];
            NSString *singleBlockCopy = [pasteboard stringForType:NSPasteboardTypeString];
            BOOL blockSelectOK = [singleBlockCopy containsString:@"second"] && ![singleBlockCopy containsString:@"98765"];

            // 3. Select all blocks, highlight first 9 chars ("Clipboard"), and press Copy
            [editor selectOCRBlockIndexesForTesting:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
            [editor selectOCRTextRangeForTesting:NSMakeRange(0, 9)];
            [editor copySelectedOCRTextForTesting];
            NSString *rangeCopy = [pasteboard stringForType:NSPasteboardTypeString];
            BOOL rangeSelectOK = [rangeCopy isEqualToString:@"Clipboard"];

            // 4. Copy detected QR code payload with one-click action
            [editor copyDetectedBarcodeForTesting];
            NSString *qrCopy = [pasteboard stringForType:NSPasteboardTypeString];
            BOOL qrCopyOK = [qrCopy isEqualToString:@"https://choxieshoot.local/qr"];

            printf("ocrflowtest: busyAnim=%d->%d notAutoCopied=%d singleBlock='%s'(%d) rangeCopy='%s'(%d) qrCopy='%s'(%d)\n",
                   wasBusyAtStart, !busyClearedOnFinish,
                   notAutoCopied,
                   singleBlockCopy.UTF8String ?: "(nil)", blockSelectOK,
                   rangeCopy.UTF8String ?: "(nil)", rangeSelectOK,
                   qrCopy.UTF8String ?: "(nil)", qrCopyOK);
            BOOL ok = foundText && wasBusyAtStart && busyClearedOnFinish && notAutoCopied && blockSelectOK && rangeSelectOK && qrCopyOK;
            printf("ocrflowtest: %s\n", ok ? "ok" : "FAILED");
            [NSApp terminate:nil];
            exit(ok ? 0 : 4);
        }];
        wasBusyAtStart = [editor isOCRBusyForTesting];
        [app run];
        return 0;
    }
}

static int RunOverlayTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [delegate startAreaSelectionForTesting];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            printf("overlaytest: selection overlay shown for ~3s\n");
            [app terminate:nil];
        });
        [app run];
        return 0;
    }
}

static int RunOCRTest(void) {
    @autoreleasepool {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(560, 220)];
        [image lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 560, 220));
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:34 weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor blackColor]
        };
        [@"Choxieshoot OCR test" drawAtPoint:NSMakePoint(30, 130) withAttributes:attributes];
        [@"Order #12345" drawAtPoint:NSMakePoint(30, 70) withAttributes:attributes];
        [image unlockFocus];

        NSError *error = nil;
        NSString *text = [TextRecognizer recognizeTextInImageSync:image error:&error];
        if (text == nil) {
            fprintf(stderr, "ocrselftest: FAILED: %s\n", error.localizedDescription.UTF8String ?: "unknown error");
            return 2;
        }
        printf("ocrselftest recognized: %s\n", [[text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "] UTF8String]);
        BOOL ok = [text containsString:@"Choxieshoot"] || [text containsString:@"12345"];
        printf("ocrselftest: %s\n", ok ? "ok" : "unexpected text");

        // Two-column ordering: band grouping should keep each visual line
        // left-to-right rather than interleaving observations arbitrarily.
        NSImage *columns = [[NSImage alloc] initWithSize:NSMakeSize(720, 280)];
        [columns lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 720, 280));
        NSDictionary *colAttributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: [NSColor blackColor]
        };
        [@"left top" drawAtPoint:NSMakePoint(30, 180) withAttributes:colAttributes];
        [@"right top" drawAtPoint:NSMakePoint(390, 180) withAttributes:colAttributes];
        [@"left bottom" drawAtPoint:NSMakePoint(30, 90) withAttributes:colAttributes];
        [@"right bottom" drawAtPoint:NSMakePoint(390, 90) withAttributes:colAttributes];
        [columns unlockFocus];
        NSString *columnText = [TextRecognizer recognizeTextInImageSync:columns error:NULL];
        NSRange leftRange = [columnText rangeOfString:@"left top"];
        NSRange rightRange = [columnText rangeOfString:@"right top"];
        BOOL orderOK = leftRange.location != NSNotFound && rightRange.location != NSNotFound &&
                       leftRange.location < rightRange.location;
        printf("ocrselftest: two-column order %s (%s)\n",
               orderOK ? "ok" : "FAILED",
               [columnText stringByReplacingOccurrencesOfString:@"\n" withString:@" | "].UTF8String ?: "");

        NSImage *blank = [[NSImage alloc] initWithSize:NSMakeSize(320, 200)];
        [blank lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 320, 200));
        [blank unlockFocus];
        NSString *blankText = [TextRecognizer recognizeTextInImageSync:blank error:NULL];
        BOOL blankOK = blankText.length == 0;
        printf("ocrselftest: no-text screenshot %s (%lu chars)\n",
               blankOK ? "ok" : "unexpected text", (unsigned long)blankText.length);

        NSImage *capture = CaptureMainScreen();
        if (capture != nil) {
            NSError *captureError = nil;
            NSString *captureText = [TextRecognizer recognizeTextInImageSync:capture error:&captureError];
            NSString *flat = [captureText stringByReplacingOccurrencesOfString:@"\n" withString:@" | "];
            if (flat.length > 160) {
                flat = [[flat substringToIndex:160] stringByAppendingString:@"…"];
            }
            printf("ocrselftest: screen capture OCR (%lu chars): %s\n",
                   (unsigned long)captureText.length, flat.UTF8String ?: "(none)");
        } else {
            printf("ocrselftest: screen capture unavailable, skipped integration sample\n");
        }
        return (ok && blankOK) ? 0 : 3;
    }
}

static int RunVideoTest(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        // 1. Verify SelectionWindow mode and microphone toggling
        SelectionWindow *sel = [[SelectionWindow alloc]
            initWithInitialMode:CSCaptureModeScreenshot
               recordMicrophone:NO
                 modeCompletion:^(NSRect screenRect, CSCaptureMode mode, BOOL recordMicrophone) {}
                         cancel:^{}];
        BOOL modeInitOK = (sel.captureMode == CSCaptureModeScreenshot && !sel.recordMicrophone);
        sel.captureMode = CSCaptureModeVideo;
        sel.recordMicrophone = YES;
        BOOL modeToggleOK = (sel.captureMode == CSCaptureModeVideo && sel.recordMicrophone);
        [sel close];

        // 2. Verify RecordingControlWindow + VideoRecorder lifecycle (start, pause, resume, stop)
        NSRect testRect = NSMakeRect(120, 160, 480, 320);
        RecordingControlWindow *hud = [[RecordingControlWindow alloc] initWithRecordedScreenRect:testRect
                                                                                recordMicrophone:NO];
        VideoRecorder *recorder = [[VideoRecorder alloc] initWithScreenRect:testRect
                                                           recordMicrophone:NO
                                                       excludeAboveWindowID:hud.lowestOverlayWindowID];
        NSError *startErr = nil;
        BOOL started = [recorder startRecordingWithError:&startErr];
        if (!started) {
            fprintf(stderr, "videotest: startRecording failed: %s\n", startErr.localizedDescription.UTF8String ?: "unknown");
            [hud dismissAllOverlays];
            return 2;
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [recorder pauseRecording];
            [hud setPaused:YES];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.50 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [recorder resumeRecording];
            [hud setPaused:NO];
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.95 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [hud dismissAllOverlays];
            [recorder stopRecordingWithCompletion:^(NSURL * _Nullable outputURL, NSError * _Nullable error) {
                if (outputURL == nil || error != nil) {
                    fprintf(stderr, "videotest: stopRecording failed: %s\n", error.localizedDescription.UTF8String ?: "nil url");
                    exit(3);
                }

                NSData *mp4Data = [NSData dataWithContentsOfURL:outputURL];
                BOOL hasFtyp = NO;
                if (mp4Data.length >= 12) {
                    const unsigned char *bytes = (const unsigned char *)mp4Data.bytes;
                    hasFtyp = (bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p');
                }

                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:outputURL options:nil];
                NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                BOOL hasVideoTrack = (videoTracks.count > 0);

                // 3. Verify VideoPreviewWindow save & copy
                VideoPreviewWindow *preview = [[VideoPreviewWindow alloc] initWithScreenRect:testRect videoURL:outputURL];
                [preview makeKeyAndOrderFront:nil];
                [preview copyVideoForTesting];

                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]] options:nil];
                BOOL copyOK = (urls.count > 0);

                NSURL *savedURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest.mp4"];
                NSError *saveErr = nil;
                BOOL saveOK = [preview saveVideoToURL:savedURL error:&saveErr];

                // Verify saving to destination without extension appends .mp4
                NSURL *noExtURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest-autoext"];
                NSURL *expectedAppendedURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest-autoext.mp4"];
                [[NSFileManager defaultManager] removeItemAtURL:expectedAppendedURL error:nil];
                NSError *autoExtErr = nil;
                BOOL autoExtOK = [preview saveVideoToURL:noExtURL error:&autoExtErr];
                BOOL fileWithExtExists = [[NSFileManager defaultManager] fileExistsAtPath:expectedAppendedURL.path];

                // Verify toolbar buttons do not overlap
                BOOL buttonsNoOverlap = YES;
                NSMutableArray<NSButton *> *toolbarButtons = [NSMutableArray array];
                for (NSView *v in preview.contentView.subviews) {
                    for (NSView *sub in v.subviews) {
                        if ([sub isKindOfClass:[NSButton class]]) {
                            [toolbarButtons addObject:(NSButton *)sub];
                        }
                    }
                }
                for (NSUInteger i = 0; i < toolbarButtons.count; i++) {
                    for (NSUInteger j = i + 1; j < toolbarButtons.count; j++) {
                        NSButton *b1 = toolbarButtons[i];
                        NSButton *b2 = toolbarButtons[j];
                        if (!b1.isHiddenOrHasHiddenAncestor && !b2.isHiddenOrHasHiddenAncestor) {
                            NSRect r1 = [b1 convertRect:b1.bounds toView:preview.contentView];
                            NSRect r2 = [b2 convertRect:b2.bounds toView:preview.contentView];
                            if (NSIntersectsRect(r1, r2)) {
                                buttonsNoOverlap = NO;
                                fprintf(stderr, "videotest warning: button overlap: '%s' and '%s'\n",
                                        b1.title.UTF8String, b2.title.UTF8String);
                            }
                        }
                    }
                }

                // 4. Verify Video Cutting (Trimming) & Spatial Cropping
                [preview setTrimStart:0.1 end:0.7];
                [preview setCropPixelRect:CGRectMake(20, 20, 320, 240)];

                NSURL *editedURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest-edited.mp4"];
                [[NSFileManager defaultManager] removeItemAtURL:editedURL error:nil];
                NSError *editErr = nil;
                BOOL editSaveOK = [preview saveVideoToURL:editedURL error:&editErr];

                AVURLAsset *editedAsset = [AVURLAsset URLAssetWithURL:editedURL options:nil];
                NSArray<AVAssetTrack *> *editedTracks = [editedAsset tracksWithMediaType:AVMediaTypeVideo];
                BOOL editedHasVideo = (editedTracks.count > 0);
                CGSize editedSize = CGSizeZero;
                if (editedHasVideo) {
                    AVAssetTrack *t = editedTracks.firstObject;
                    editedSize = CGSizeApplyAffineTransform(t.naturalSize, t.preferredTransform);
                }
                Float64 editedDur = CMTimeGetSeconds(editedAsset.duration);
                BOOL cropDimensionsOK = (fabs(editedSize.width) == 320 && fabs(editedSize.height) == 240);
                BOOL trimDurationOK = (editedDur > 0.3 && editedDur < 0.9);

                // 5. Verify Advanced Cropper: Center Crop and Swap Orientation
                [preview centerCropClicked:nil];
                CGRect centeredCrop = preview.cropPixelRect;
                BOOL centerCropOK = (centeredCrop.size.width == 320 && centeredCrop.size.height == 240);

                [preview swapOrientationClicked:nil];
                CGRect swappedCrop = preview.cropPixelRect;
                BOOL swapAspectOK = (swappedCrop.size.width == 240 && swappedCrop.size.height == 320);

                // Reset back to 320x240 for remaining tests
                [preview setCropPixelRect:CGRectMake(20, 20, 320, 240)];

                // 6. Verify Video Rotation (90° CW)
                [preview setRotationDegrees:90];
                NSURL *rotatedURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest-rotated.mp4"];
                [[NSFileManager defaultManager] removeItemAtURL:rotatedURL error:nil];
                BOOL rotSaveOK = [preview saveVideoToURL:rotatedURL error:nil];

                AVURLAsset *rotAsset = [AVURLAsset URLAssetWithURL:rotatedURL options:nil];
                NSArray<AVAssetTrack *> *rotTracks = [rotAsset tracksWithMediaType:AVMediaTypeVideo];
                CGSize rotSize = CGSizeZero;
                if (rotTracks.count > 0) {
                    rotSize = CGSizeApplyAffineTransform(rotTracks.firstObject.naturalSize, rotTracks.firstObject.preferredTransform);
                }
                BOOL rotationOK = rotSaveOK && (fabs(rotSize.width) == 240 && fabs(rotSize.height) == 320);

                // 7. Verify Playback Speed (1.5x) and Audio Muting
                [preview setRotationDegrees:0];
                [preview setPlaybackSpeed:1.5];
                [preview setAudioMuted:YES];

                NSURL *speedMuteURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest-speedmute.mp4"];
                [[NSFileManager defaultManager] removeItemAtURL:speedMuteURL error:nil];
                BOOL speedMuteSaveOK = [preview saveVideoToURL:speedMuteURL error:nil];

                AVURLAsset *speedAsset = [AVURLAsset URLAssetWithURL:speedMuteURL options:nil];
                Float64 speedDur = CMTimeGetSeconds(speedAsset.duration);
                NSArray<AVAssetTrack *> *audioTracks = [speedAsset tracksWithMediaType:AVMediaTypeAudio];
                BOOL speedOK = speedMuteSaveOK && (speedDur > 0.25 && speedDur < 0.60);
                BOOL muteOK = speedMuteSaveOK && (audioTracks.count == 0);

                // 8. Verify Animated GIF Export
                NSURL *gifURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest.gif"];
                [[NSFileManager defaultManager] removeItemAtURL:gifURL error:nil];
                BOOL gifSaveOK = [preview saveGifToURL:gifURL error:nil];

                NSData *gifData = [NSData dataWithContentsOfURL:gifURL];
                BOOL gifValid = NO;
                if (gifData.length >= 6) {
                    const char *header = (const char *)gifData.bytes;
                    gifValid = (strncmp(header, "GIF89a", 6) == 0 || strncmp(header, "GIF87a", 6) == 0);
                }
                BOOL gifOK = gifSaveOK && gifValid && (gifData.length > 500);

                // 9. Verify Still Frame Capture
                NSImage *stillFrame = [preview currentFrameImage];
                BOOL frameCaptureOK = (stillFrame != nil && stillFrame.size.width >= 100 && stillFrame.size.height >= 100);

                // 10. Verify reloading video in editor
                BOOL reloadOK = [preview loadVideoURL:editedURL];

                [preview close];

                BOOL allOK = modeInitOK && modeToggleOK && started && hasFtyp && hasVideoTrack && copyOK && saveOK && autoExtOK && fileWithExtExists && buttonsNoOverlap && editSaveOK && cropDimensionsOK && trimDurationOK && centerCropOK && swapAspectOK && rotationOK && speedOK && muteOK && gifOK && frameCaptureOK && reloadOK;
                printf("videotest: modeToggle=%d started=%d bytes=%lu ftyp=%d videoTrack=%d copy=%d save=%d autoExt=%d noOverlap=%d cutCropSave=%d cropSize=%.0fx%.0f dur=%.2fs centerCrop=%d swapAspect=%d rotation=%d (%.0fx%.0f) speed=%.2fs mute=%d gif=%d (%lu bytes) frame=%d (%.0fx%.0f) reload=%d -> %s\n",
                       (modeInitOK && modeToggleOK), started, (unsigned long)mp4Data.length,
                       hasFtyp, hasVideoTrack, copyOK, saveOK, (autoExtOK && fileWithExtExists), buttonsNoOverlap,
                       editSaveOK, fabs(editedSize.width), fabs(editedSize.height), editedDur,
                       centerCropOK, swapAspectOK, rotationOK, fabs(rotSize.width), fabs(rotSize.height),
                       speedDur, muteOK, gifOK, (unsigned long)gifData.length,
                       frameCaptureOK, stillFrame.size.width, stillFrame.size.height,
                       reloadOK,
                       allOK ? "ok" : "FAILED");
                exit(allOK ? 0 : 4);
            }];
        });

        [app run];
        return 0;
    }
}

static int RunCropEditTest(void) {
    @autoreleasepool {
        printf("--- Starting CropEditTest ---\n");

        // 1. VideoCropOverlayView: test single click and degenerate drag resilience
        VideoCropOverlayView *overlay = [[VideoCropOverlayView alloc] initWithFrame:NSMakeRect(0, 0, 640, 360)
                                                                  videoNaturalSize:NSMakeSize(1280, 720)];
        overlay.cropActive = YES;
        CGRect fullRect = overlay.pixelCropRect;
        BOOL initFullOK = (fullRect.size.width == 1280 && fullRect.size.height == 720);

        // Simulate single click at (50, 50) outside any handle
        NSEvent *downEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                location:NSMakePoint(50, 50)
                                           modifierFlags:0
                                               timestamp:0
                                            windowNumber:0
                                                 context:nil
                                             eventNumber:1
                                              clickCount:1
                                                pressure:1.0];
        [overlay mouseDown:downEvent];

        // Immediate mouseUp without drag: previously this collapsed the crop box to a 32x32 speck!
        NSEvent *upEvent = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                              location:NSMakePoint(50, 50)
                                         modifierFlags:0
                                             timestamp:0
                                          windowNumber:0
                                               context:nil
                                           eventNumber:2
                                            clickCount:1
                                              pressure:0.0];
        [overlay mouseUp:upEvent];

        CGRect afterClickRect = overlay.pixelCropRect;
        BOOL singleClickRestored = (afterClickRect.size.width == 1280 && afterClickRect.size.height == 720);

        // Set an explicit crop box (e.g. 640x360)
        [overlay setPixelCropRect:CGRectMake(100, 100, 640, 360)];
        CGRect setCrop = overlay.pixelCropRect;
        BOOL cropSetOK = (setCrop.size.width == 640 && setCrop.size.height == 360);

        // Simulate tiny jitter click (less than 4% dimension)
        [overlay mouseDown:downEvent];
        [overlay mouseUp:upEvent];
        CGRect afterJitterRect = overlay.pixelCropRect;
        BOOL jitterRestored = (afterJitterRect.size.width == 640 && afterJitterRect.size.height == 360);

        // 2. CanvasView: test preview annotation clearing and tool switching on crop
        CanvasView *canvas = [[CanvasView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(500, 400)];
        [img lockFocus];
        [[NSColor blueColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 500, 400));
        [img unlockFocus];
        canvas.backgroundImage = img;

        Annotation *realAnn = [[Annotation alloc] init];
        realAnn.toolType = ToolTypeRectangle;
        realAnn.path = [NSBezierPath bezierPathWithRect:NSMakeRect(10, 10, 50, 50)];
        [canvas addAnnotation:realAnn];
        BOOL hasReal = (canvas.annotations.count == 1);

        canvas.currentTool = ToolTypeCrop;
        [canvas clearPreviewAnnotation];
        BOOL clearPreviewOK = (canvas.annotations.count == 1);

        // Perform crop
        [canvas cropToRect:NSMakeRect(20, 20, 300, 200)];
        BOOL toolSwitchedToSelect = (canvas.currentTool == ToolTypeSelect);

        BOOL allOK = initFullOK && singleClickRestored && cropSetOK && jitterRestored && hasReal && clearPreviewOK && toolSwitchedToSelect;
        printf("cropedittest: initFull=%d singleClickRestored=%d cropSet=%d jitterRestored=%d hasReal=%d clearPreview=%d toolSwitched=%d -> %s\n",
               initFullOK, singleClickRestored, cropSetOK, jitterRestored, hasReal, clearPreviewOK, toolSwitchedToSelect,
               allOK ? "ok" : "FAILED");
        return allOK ? 0 : 1;
    }
}

static int RunExportTimeoutTest(void) {
    @autoreleasepool {
        printf("--- Starting ExportTimeoutTest ---\n");

        // Verify test video exists or create one
        NSURL *testVideoURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-videotest.mp4"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:testVideoURL.path]) {
            RunVideoTest();
        }

        // 1. Test active cancellation of VideoEditorEngine exportVideoAtURL
        NSURL *cancelVideoURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-test-cancel.mp4"];
        [[NSFileManager defaultManager] removeItemAtURL:cancelVideoURL error:nil];

        dispatch_semaphore_t sema1 = dispatch_semaphore_create(0);
        __block BOOL cancelVideoCompleted = NO;
        __block BOOL cancelVideoSucceeded = YES;
        __block NSError *cancelVideoErr = nil;

        AVAssetExportSession *session = [VideoEditorEngine exportVideoAtURL:testVideoURL
                                                              trimStartTime:0.0
                                                                trimEndTime:0.5
                                                                   cropRect:CGRectMake(10, 10, 200, 150)
                                                                   rotation:0
                                                              playbackSpeed:1.0
                                                                  muteAudio:NO
                                                             destinationURL:cancelVideoURL
                                                            progressHandler:nil
                                                            completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                                                 completion:^(BOOL success, NSError * _Nullable error) {
            cancelVideoCompleted = YES;
            cancelVideoSucceeded = success;
            cancelVideoErr = error;
            dispatch_semaphore_signal(sema1);
        }];

        // Immediately cancel export
        [session cancelExport];
        dispatch_semaphore_wait(sema1, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));

        BOOL videoCancelOK = cancelVideoCompleted && !cancelVideoSucceeded &&
            (cancelVideoErr != nil && cancelVideoErr.code == NSUserCancelledError);
        BOOL videoFileCleaned = ![[NSFileManager defaultManager] fileExistsAtPath:cancelVideoURL.path];

        // 2. Test active cancellation of VideoEditorEngine exportGifAtURL
        NSURL *cancelGifURL = [NSURL fileURLWithPath:@"/tmp/choxieshoot-test-cancel.gif"];
        [[NSFileManager defaultManager] removeItemAtURL:cancelGifURL error:nil];

        dispatch_semaphore_t sema2 = dispatch_semaphore_create(0);
        __block BOOL cancelGifCompleted = NO;
        __block BOOL cancelGifSucceeded = YES;
        __block NSError *cancelGifErr = nil;

        void (^cancelBlock)(void) = [VideoEditorEngine exportGifAtURL:testVideoURL
                                                        trimStartTime:0.0
                                                          trimEndTime:0.5
                                                             cropRect:CGRectMake(10, 10, 200, 150)
                                                             rotation:0
                                                        playbackSpeed:1.0
                                                                  fps:15.0
                                                       destinationURL:cancelGifURL
                                                      progressHandler:nil
                                                      completionQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                                                           completion:^(BOOL success, NSError * _Nullable error) {
            cancelGifCompleted = YES;
            cancelGifSucceeded = success;
            cancelGifErr = error;
            dispatch_semaphore_signal(sema2);
        }];

        if (cancelBlock) {
            cancelBlock();
        }
        dispatch_semaphore_wait(sema2, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));

        BOOL gifCancelOK = cancelGifCompleted && !cancelGifSucceeded &&
            (cancelGifErr != nil && cancelGifErr.code == NSUserCancelledError);
        BOOL gifFileCleaned = ![[NSFileManager defaultManager] fileExistsAtPath:cancelGifURL.path];

        // 3. Test VideoPreviewWindow cancellation and HUD dismissal
        VideoPreviewWindow *preview = [[VideoPreviewWindow alloc] initWithScreenRect:NSMakeRect(50, 50, 600, 400)
                                                                           videoURL:testVideoURL];
        [preview makeKeyAndOrderFront:nil];

        BOOL notExportingInitial = !preview.isExporting;
        [preview showExportHUDWithTitle:@"Testing HUD…"];
        BOOL hudVisible = (preview.exportHUDView != nil);

        [preview cancelActiveExport];
        BOOL hudDismissed = (preview.exportHUDView == nil) && !preview.isExporting;

        // Test close during simulated export
        [preview showExportHUDWithTitle:@"Closing During Export…"];
        [preview close];
        BOOL closeCancelledOK = !preview.isExporting && (preview.exportHUDView == nil);

        BOOL allOK = videoCancelOK && videoFileCleaned && gifCancelOK && gifFileCleaned &&
                     notExportingInitial && hudVisible && hudDismissed && closeCancelledOK;
        printf("exporttimeouttest: videoCancel=%d videoCleaned=%d gifCancel=%d gifCleaned=%d notExportingInit=%d hudVisible=%d hudDismissed=%d closeCancelled=%d -> %s\n",
               videoCancelOK, videoFileCleaned, gifCancelOK, gifFileCleaned,
               notExportingInitial, hudVisible, hudDismissed, closeCancelledOK,
               allOK ? "ok" : "FAILED");
        return allOK ? 0 : 2;
    }
}

static int RunOCRCancelTest(void) {
    @autoreleasepool {
        printf("--- Starting OCRCancelTest ---\n");
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(400, 300)];
        [img lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 400, 300));
        [@"Sample text for cancellation test" drawAtPoint:NSMakePoint(20, 150) withAttributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:18.0]
        }];
        [img unlockFocus];

        EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:NSMakeRect(100, 100, 500, 400) image:img];
        [editor makeKeyAndOrderFront:nil];

        // 1. Start OCR and cancel via cancelTextRecognition
        [editor openTextRecognizerWithCompletion:nil];
        BOOL ocrStarted = [editor ocrInProgress];

        [editor cancelTextRecognition];
        BOOL ocrCancelled = ![editor ocrInProgress];

        // 2. Start OCR and cancel via toggleTextRecognizer (clicking OCR button again)
        [editor openTextRecognizerWithCompletion:nil];
        BOOL ocrStarted2 = [editor ocrInProgress];
        [editor toggleTextRecognizer];
        BOOL ocrToggleCancelled = ![editor ocrInProgress];

        // 3. Start OCR and cancel via Escape key event
        [editor openTextRecognizerWithCompletion:nil];
        NSEvent *escEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSZeroPoint
                                        modifierFlags:0
                                            timestamp:0
                                         windowNumber:editor.windowNumber
                                              context:nil
                                           characters:@"\e"
                          charactersIgnoringModifiers:@"\e"
                                            isARepeat:NO
                                              keyCode:53];
        [editor keyDown:escEvent];
        BOOL escCancelledOCR = ![editor ocrInProgress];
        BOOL windowStillVisible = editor.isVisible;

        // 4. In crop tool mode, Escape key switches tool to Select instead of closing window
        editor.canvasView.currentTool = ToolTypeCrop;
        [editor keyDown:escEvent];
        BOOL cropCancelledToSelect = (editor.canvasView.currentTool == ToolTypeSelect);
        BOOL windowStillOpenAfterCropEsc = editor.isVisible;

        [editor close];
        BOOL closedCleanly = !editor.isVisible && ![editor ocrInProgress];

        BOOL allOK = ocrStarted && ocrCancelled && ocrStarted2 && ocrToggleCancelled &&
                     escCancelledOCR && windowStillVisible && cropCancelledToSelect && windowStillOpenAfterCropEsc && closedCleanly;
        printf("ocrcanceltest: ocrStarted=%d ocrCancelled=%d toggleCancel=%d escCancel=%d winVisible=%d cropEscSelect=%d winOpen=%d closedClean=%d -> %s\n",
               ocrStarted, ocrCancelled, ocrToggleCancelled, escCancelledOCR, windowStillVisible,
               cropCancelledToSelect, windowStillOpenAfterCropEsc, closedCleanly,
               allOK ? "ok" : "FAILED");
        return allOK ? 0 : 3;
    }
}

static int RunSelectionCancelTest(void) {
    @autoreleasepool {
        printf("--- Starting SelectionCancelTest ---\n");

        __block BOOL cancelInvoked = NO;
        SelectionWindow *sel = [[SelectionWindow alloc]
            initWithInitialMode:CSCaptureModeScreenshot
               recordMicrophone:NO
                 modeCompletion:^(NSRect screenRect, CSCaptureMode mode, BOOL recordMicrophone) {}
                         cancel:^{
            cancelInvoked = YES;
        }];

        BOOL cancelNotYetInvoked = !cancelInvoked;

        // Directly close the SelectionWindow without dragging (simulates user pressing Escape, or window close)
        [sel close];

        BOOL cancelInvokedOnClose = cancelInvoked;

        BOOL allOK = cancelNotYetInvoked && cancelInvokedOnClose;
        printf("selectioncanceltest: initNotCancelled=%d cancelInvokedOnClose=%d -> %s\n",
               cancelNotYetInvoked, cancelInvokedOnClose,
               allOK ? "ok" : "FAILED");
        return allOK ? 0 : 4;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 2 && strcmp(argv[1], "--ocr-worker") == 0) {
            NSString *imagePath = [NSString stringWithUTF8String:argv[2]];
            return [TextRecognizer runOCRWorkerWithImagePath:imagePath];
        }
        if (argc > 1 && strncmp(argv[1], "--", 2) == 0) {
            setenv("CS_TEST_MODE", "1", 1);
        }
        if (argc > 1 && strcmp(argv[1], "--selftest") == 0) {
            return RunSelfTest();
        }
        if (argc > 1 && strcmp(argv[1], "--capturetest") == 0) {
            return RunCaptureTest();
        }
        if (argc > 1 && strcmp(argv[1], "--uitest") == 0) {
            return RunUITest();
        }
        if (argc > 1 && strcmp(argv[1], "--overlaytest") == 0) {
            return RunOverlayTest();
        }
        if (argc > 1 && strcmp(argv[1], "--flowtest") == 0) {
            return RunFlowTest();
        }
        if (argc > 1 && strcmp(argv[1], "--ocrselftest") == 0) {
            return RunOCRTest();
        }
        if (argc > 1 && strcmp(argv[1], "--ocrflowtest") == 0) {
            return RunOCRFlowTest();
        }
        if (argc > 1 && strcmp(argv[1], "--drawtest") == 0) {
            return RunDrawTest();
        }
        if (argc > 1 && strcmp(argv[1], "--copytest") == 0) {
            return RunCopyTest();
        }
        if (argc > 1 && strcmp(argv[1], "--savetest") == 0) {
            return RunSaveTest();
        }
        if (argc > 1 && strcmp(argv[1], "--uitestwide") == 0) {
            return RunWideUITest();
        }
        if (argc > 1 && strcmp(argv[1], "--uitestcolor") == 0) {
            return RunColorUITest();
        }
        if (argc > 1 && strcmp(argv[1], "--uitesttext") == 0) {
            return RunTextUITest();
        }
        if (argc > 1 && strcmp(argv[1], "--textedittest") == 0) {
            return RunTextEditTest();
        }
        if (argc > 1 && strcmp(argv[1], "--shortcuttest") == 0) {
            return RunShortcutTest();
        }
        if (argc > 1 && strcmp(argv[1], "--uitestprefs") == 0) {
            return RunPreferencesUITest();
        }
        if (argc > 1 && strcmp(argv[1], "--videotest") == 0) {
            return RunVideoTest();
        }
        if (argc > 1 && strcmp(argv[1], "--cropedittest") == 0) {
            return RunCropEditTest();
        }
        if (argc > 1 && strcmp(argv[1], "--exporttimeouttest") == 0) {
            return RunExportTimeoutTest();
        }
        if (argc > 1 && strcmp(argv[1], "--ocrcanceltest") == 0) {
            return RunOCRCancelTest();
        }
        if (argc > 1 && strcmp(argv[1], "--selectioncanceltest") == 0) {
            return RunSelectionCancelTest();
        }
        if (argc > 2 && strcmp(argv[1], "--edit-video") == 0) {
            NSString *videoPath = [NSString stringWithUTF8String:argv[2]];
            NSURL *url = [NSURL fileURLWithPath:videoPath];
            NSApplication *app = [NSApplication sharedApplication];
            AppDelegate *delegate = [[AppDelegate alloc] init];
            app.delegate = delegate;
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [delegate openVideoPreviewWithURL:url screenRect:NSMakeRect(100, 100, 800, 600)];
            });
            [app run];
            return 0;
        }

        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
