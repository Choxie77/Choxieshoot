#import "AppDelegate.h"
#import "SelectionWindow.h"
#import "EditorWindow.h"
#import "ScreenshotCapture.h"
#import "LauncherWindow.h"
#import "ChoxieshootNotifications.h"
#import "PreferencesWindow.h"
#import "ChoxieshootPreferences.h"
#import "VideoRecorder.h"
#import "RecordingControlWindow.h"
#import "VideoPreviewWindow.h"

#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <unistd.h>
#import <malloc/malloc.h>

NSNotificationName const ChoxieshootNewCaptureNotification = @"ChoxieshootNewCaptureNotification";

static AppDelegate *gAppDelegate = nil;
static EventHotKeyRef gHotKeyRef = NULL;

static OSStatus ChoxieshootHotKeyHandler(EventHandlerCallRef nextHandler,
                                         EventRef event,
                                         void *userData) {
    (void)nextHandler;
    (void)event;
    (void)userData;
    dispatch_async(dispatch_get_main_queue(), ^{
        [gAppDelegate handleHotkey];
    });
    return noErr;
}

static BOOL CGImageHasOpaquePixels(CGImageRef cgImage) {
    if (cgImage == NULL) {
        return NO;
    }
    size_t w = CGImageGetWidth(cgImage);
    size_t h = CGImageGetHeight(cgImage);
    if (w == 0 || h == 0) {
        return NO;
    }
    uint8_t pixels[8 * 8 * 4];
    memset(pixels, 0, sizeof(pixels));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 8, 8, 8, 8 * 4, space, kCGImageAlphaPremultipliedLast);
    if (context != NULL) {
        CGContextDrawImage(context, CGRectMake(0, 0, 8, 8), cgImage);
        CGContextRelease(context);
    }
    CGColorSpaceRelease(space);
    for (int i = 0; i < 64; i++) {
        if (pixels[i * 4 + 3] > 16) {
            return YES;
        }
    }
    return NO;
}

static void ResetTCCScreenCaptureForApp(void) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/tccutil";
    task.arguments = @[@"reset", @"ScreenCapture", @"com.choxieshoot.app"];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
    }
}

@interface AppDelegate () <PreferencesWindowDelegate>

@property (nonatomic, strong, nullable) NSStatusItem *statusItem;
@property (nonatomic, strong, nullable) NSMenuItem *delayedMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *stopVideoMenuItem;
@property (nonatomic, strong, nullable) PreferencesWindow *preferencesWindow;
@property (nonatomic, strong, nullable) SelectionWindow *selectionWindow;
@property (nonatomic, strong) NSMutableArray<EditorWindow *> *editingWindows;
@property (nonatomic, strong) NSMutableArray<VideoPreviewWindow *> *videoPreviewWindows;
@property (nonatomic, strong, nullable) VideoRecorder *activeVideoRecorder;
@property (nonatomic, strong, nullable) RecordingControlWindow *recordingControlWindow;
@property (nonatomic, strong, nullable) LauncherWindow *launcher;
@property (nonatomic) BOOL isSelecting;
@property (nonatomic) BOOL captureVerified;
@property (nonatomic) NSTimeInterval lastProbeTime;
@property (nonatomic) BOOL lastProbeResult;
@property (nonatomic, strong) NSMutableArray<NSWindow *> *hiddenEditors;
@property (nonatomic) BOOL preferencesWasVisible;

@end

@implementation AppDelegate

- (instancetype)init {
    if ((self = [super init])) {
        _editingWindows = [NSMutableArray array];
        _videoPreviewWindows = [NSMutableArray array];
        _hiddenEditors = [NSMutableArray array];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    gAppDelegate = self;
    BOOL testMode = getenv("CS_TEST_MODE") != NULL;
    if (!testMode) {
        [self setupMainMenu];
    }
    if ([self boolForKey:CSShowMenuBarIconKey defaultValue:YES]) {
        [self setupStatusItem];
    }
    [self registerGlobalHotkey];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNewCaptureNotification:)
                                                 name:ChoxieshootNewCaptureNotification
                                               object:nil];

    if (!testMode && [self boolForKey:CSShowLauncherKey defaultValue:YES]) {
        [self showLauncher];
    }
    if (!testMode && [[NSUserDefaults standardUserDefaults] boolForKey:@"CSAutoRequestOnLaunch"]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSAutoRequestOnLaunch"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            CGRequestScreenCaptureAccess();
            [self openScreenRecordingSettings];
            self.lastProbeTime = 0;
            [self.launcher updateScreenRecordingGranted:[self screenRecordingGranted]];
        });
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    if (self.editorCount == 0 && !self.isSelecting) {
        [self showLauncher];
    } else {
        BOOL anyOnActiveSpace = NO;
        for (EditorWindow *editor in self.editingWindows) {
            if (editor.isMiniaturized) {
                [editor deminiaturize:nil];
                anyOnActiveSpace = YES;
            } else if (editor.isOnActiveSpace) {
                [editor orderFrontRegardless];
                [editor makeKeyAndOrderFront:nil];
                anyOnActiveSpace = YES;
            }
        }
        for (VideoPreviewWindow *preview in self.videoPreviewWindows) {
            if (preview.isMiniaturized) {
                [preview deminiaturize:nil];
                anyOnActiveSpace = YES;
            } else if (preview.isOnActiveSpace) {
                [preview orderFrontRegardless];
                [preview makeKeyAndOrderFront:nil];
                anyOnActiveSpace = YES;
            }
        }
        if (!anyOnActiveSpace) {
            [self showLauncher];
        }
    }
    return YES;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    self.lastProbeTime = 0;
    if (self.launcher != nil && self.launcher.isVisible) {
        [self.launcher updateScreenRecordingGranted:[self screenRecordingGranted]];
    }
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
    NSMenu *menu = [[NSMenu alloc] init];
    if (self.activeVideoRecorder != nil && self.activeVideoRecorder.isRecording) {
        NSMenuItem *stopItem = [[NSMenuItem alloc] initWithTitle:@"Stop Video Recording" action:@selector(stopVideoRecording:) keyEquivalent:@""];
        stopItem.target = self;
        [menu addItem:stopItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    NSMenuItem *newItem = [[NSMenuItem alloc] initWithTitle:@"New Screenshot" action:@selector(takeScreenshot:) keyEquivalent:@""];
    newItem.target = self;
    [menu addItem:newItem];
    NSMenuItem *videoItem = [[NSMenuItem alloc] initWithTitle:@"Record Video…" action:@selector(takeVideoRecording:) keyEquivalent:@""];
    videoItem.target = self;
    [menu addItem:videoItem];
    NSMenuItem *editVideoItem = [[NSMenuItem alloc] initWithTitle:@"Open Video to Edit…" action:@selector(openVideoToEdit:) keyEquivalent:@""];
    editVideoItem.target = self;
    [menu addItem:editVideoItem];
    NSMenuItem *delayedItem = [[NSMenuItem alloc] initWithTitle:@"New Screenshot in 3 Seconds" action:@selector(takeDelayedScreenshot:) keyEquivalent:@""];
    delayedItem.target = self;
    [menu addItem:delayedItem];
    NSMenuItem *fullItem = [[NSMenuItem alloc] initWithTitle:@"Capture Full Screen" action:@selector(captureFullScreen:) keyEquivalent:@""];
    fullItem.target = self;
    [menu addItem:fullItem];
    NSMenuItem *fullVideoItem = [[NSMenuItem alloc] initWithTitle:@"Record Full Screen Video" action:@selector(recordFullScreenVideo:) keyEquivalent:@""];
    fullVideoItem.target = self;
    [menu addItem:fullVideoItem];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show Choxieshoot" action:@selector(showLauncher:) keyEquivalent:@""];
    showItem.target = self;
    [menu addItem:showItem];
    return menu;
}

- (NSInteger)editorCount {
    return (NSInteger)(self.editingWindows.count + self.videoPreviewWindows.count);
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults boolForKey:key];
}

- (NSInteger)delaySeconds {
    NSInteger seconds = [[NSUserDefaults standardUserDefaults] integerForKey:CSDelaySecondsKey];
    return seconds > 0 ? seconds : 3;
}

- (void)applyGeneralSettings {
    BOOL showMenuBar = [self boolForKey:CSShowMenuBarIconKey defaultValue:YES];
    if (showMenuBar && self.statusItem == nil) {
        [self setupStatusItem];
    } else if (!showMenuBar && self.statusItem != nil) {
        self.statusItem.menu = nil;
        [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
        self.statusItem = nil;
        self.delayedMenuItem = nil;
    }
    [self updateDelayedMenuTitle];
    [self.launcher setDelaySeconds:[self delaySeconds]];
}

- (void)updateDelayedMenuTitle {
    self.delayedMenuItem.title = [NSString stringWithFormat:@"Take Screenshot in %ld Seconds", (long)[self delaySeconds]];
}

#pragma mark - Main menu

- (NSMenuItem *)menuItemWithTitle:(NSString *)title action:(SEL)action key:(NSString *)key target:(id)target {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = target;
    return item;
}

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Choxieshoot"];
    [appMenu addItem:[self menuItemWithTitle:@"About Choxieshoot" action:@selector(showAbout:) key:@"" target:self]];
    [appMenu addItem:[self menuItemWithTitle:@"Preferences…" action:@selector(showPreferences:) key:@"," target:self]];
    [appMenu addItem:[self menuItemWithTitle:@"Permissions…" action:@selector(showPermissions:) key:@"" target:self]];
    [appMenu addItem:[self menuItemWithTitle:@"Restart Choxieshoot" action:@selector(relaunchChoxieshoot:) key:@"" target:self]];
    [appMenu addItem:[self menuItemWithTitle:@"Reset Screen Recording Permission…" action:@selector(resetScreenRecordingPermission:) key:@"" target:self]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[self menuItemWithTitle:@"Hide Choxieshoot" action:@selector(hide:) key:@"h" target:NSApp]];
    [appMenu addItem:[self menuItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) key:@"h" target:NSApp]];
    NSMenuItem *showAll = [self menuItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) key:@"" target:NSApp];
    showAll.keyEquivalentModifierMask = NSEventModifierFlagOption | NSEventModifierFlagCommand;
    [appMenu addItem:showAll];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[self menuItemWithTitle:@"Quit Choxieshoot" action:@selector(terminate:) key:@"q" target:NSApp]];
    appItem.submenu = appMenu;

    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItem:[self menuItemWithTitle:@"New Screenshot" action:@selector(takeScreenshot:) key:@"n" target:self]];
    [fileMenu addItem:[self menuItemWithTitle:@"Record Video…" action:@selector(takeVideoRecording:) key:@"r" target:self]];
    [fileMenu addItem:[self menuItemWithTitle:@"Open Video to Edit…" action:@selector(openVideoToEdit:) key:@"o" target:self]];
    [fileMenu addItem:[self menuItemWithTitle:@"New Screenshot in 3 Seconds" action:@selector(takeDelayedScreenshot:) key:@"" target:self]];
    [fileMenu addItem:[self menuItemWithTitle:@"Capture Full Screen" action:@selector(captureFullScreen:) key:@"" target:self]];
    [fileMenu addItem:[self menuItemWithTitle:@"Record Full Screen Video" action:@selector(recordFullScreenVideo:) key:@"" target:self]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self menuItemWithTitle:@"Close" action:@selector(performClose:) key:@"w" target:nil]];
    fileItem.submenu = fileMenu;

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItem:[self menuItemWithTitle:@"Undo" action:@selector(undo:) key:@"z" target:nil]];
    NSMenuItem *redo = [self menuItemWithTitle:@"Redo" action:@selector(redo:) key:@"z" target:nil];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:redo];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[self menuItemWithTitle:@"Cut" action:@selector(cut:) key:@"x" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Copy" action:@selector(copy:) key:@"c" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Paste" action:@selector(paste:) key:@"v" target:nil]];
    [editMenu addItem:[self menuItemWithTitle:@"Select All" action:@selector(selectAll:) key:@"a" target:nil]];
    editItem.submenu = editMenu;

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItem:[self menuItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) key:@"m" target:nil]];
    [windowMenu addItem:[self menuItemWithTitle:@"Zoom" action:@selector(performZoom:) key:@"" target:nil]];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItem:[self menuItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) key:@"" target:NSApp]];
    windowItem.submenu = windowMenu;

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

#pragma mark - Launcher and permissions

- (NSScreen *)activeScreenForMouse {
    NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(mouse, screen.frame)) {
            return screen;
        }
    }
    return [NSScreen mainScreen] ?: [NSScreen screens].firstObject;
}

- (BOOL)probeWindowsInList:(NSArray<NSDictionary *> *)windows
                 onScreen:(BOOL)onScreen
               launcherCG:(CGRect)launcherCG
             haveLauncher:(BOOL)haveLauncher
        testedAnyCandidate:(BOOL *)testedAnyCandidate {
    pid_t myPID = getpid();
    for (NSDictionary *window in windows) {
        NSNumber *ownerPID = window[(id)kCGWindowOwnerPID];
        NSNumber *layer = window[(id)kCGWindowLayer];
        NSNumber *alpha = window[(id)kCGWindowAlpha];
        NSNumber *windowIDNum = window[(id)kCGWindowNumber];
        if (ownerPID == nil || ownerPID.intValue == myPID) {
            continue;
        }
        if (layer.intValue != 0 || alpha.doubleValue < 0.05) {
            continue;
        }
        CGRect bounds = CGRectZero;
        NSDictionary *boundsDict = window[(id)kCGWindowBounds];
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &bounds)) {
            continue;
        }
        if (bounds.size.width < 120 || bounds.size.height < 120) {
            continue;
        }
        if (testedAnyCandidate != NULL) {
            *testedAnyCandidate = YES;
        }

        // First try capturing that window directly by ID (works across Spaces and unoccluded by our launcher).
        if (windowIDNum != nil && windowIDNum.unsignedIntValue != kCGNullWindowID) {
            CGWindowID wid = (CGWindowID)windowIDNum.unsignedIntValue;
            CGRect centerProbe = CGRectMake(CGRectGetMidX(bounds) - 32.0, CGRectGetMidY(bounds) - 32.0, 64.0, 64.0);
            CGImageRef directImg = CGWindowListCreateImage(
                centerProbe,
                kCGWindowListOptionIncludingWindow,
                wid,
                kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);
            if (directImg != NULL) {
                BOOL opaque = CGImageHasOpaquePixels(directImg);
                CGImageRelease(directImg);
                if (opaque) {
                    return YES;
                }
            }
            CGRect cornerProbe = CGRectMake(bounds.origin.x,
                                            bounds.origin.y,
                                            MIN(bounds.size.width, 64.0),
                                            MIN(bounds.size.height, 64.0));
            CGImageRef cornerImg = CGWindowListCreateImage(
                cornerProbe,
                kCGWindowListOptionIncludingWindow,
                wid,
                kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);
            if (cornerImg != NULL) {
                BOOL opaque = CGImageHasOpaquePixels(cornerImg);
                CGImageRelease(cornerImg);
                if (opaque) {
                    return YES;
                }
            }
        }

        if (!onScreen) {
            continue;
        }

        CGRect probes[2] = {
            CGRectMake(bounds.origin.x + 8, bounds.origin.y + 8, 64, 64),
            CGRectMake(CGRectGetMaxX(bounds) - 72, CGRectGetMaxY(bounds) - 72, 64, 64)
        };
        for (int i = 0; i < 2; i++) {
            if (haveLauncher && CGRectIntersectsRect(probes[i], launcherCG)) {
                continue;
            }
            CGImageRef cgImage = CGWindowListCreateImage(
                probes[i],
                kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
                kCGNullWindowID,
                kCGWindowImageNominalResolution);
            if (cgImage == NULL) {
                continue;
            }
            BOOL opaque = CGImageHasOpaquePixels(cgImage);
            CGImageRelease(cgImage);
            if (opaque) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)screenCaptureProbe {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastProbeTime < 3.0) {
        return self.lastProbeResult;
    }
    self.lastProbeTime = now;

    __block BOOL probeSucceeded = NO;
    @autoreleasepool {
        NSScreen *screen = [NSScreen mainScreen] ?: [NSScreen screens].firstObject;
        if (screen == nil) {
            self.lastProbeResult = NO;
            return NO;
        }

        NSRect launcherCG = NSZeroRect;
        BOOL haveLauncher = (self.launcher != nil && self.launcher.isVisible);
        if (haveLauncher) {
            NSRect f = self.launcher.frame;
            launcherCG = NSMakeRect(NSMinX(f), NSHeight(screen.frame) - NSMaxY(f), NSWidth(f), NSHeight(f));
        }

        BOOL testedAnyCandidate = NO;

        // 1. Check windows on the currently active Desktop Space.
        NSArray<NSDictionary *> *onScreenWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
            kCGNullWindowID));
        if ([self probeWindowsInList:onScreenWindows
                            onScreen:YES
                          launcherCG:launcherCG
                        haveLauncher:haveLauncher
                   testedAnyCandidate:&testedAnyCandidate]) {
            probeSucceeded = YES;
        }

        // 2. If the current Desktop Space has no other app windows (e.g. an empty Desktop
        // or a Space where only Choxieshoot is open), check windows across all Desktop Spaces.
        if (!probeSucceeded) {
            NSArray<NSDictionary *> *allWindows = CFBridgingRelease(CGWindowListCopyWindowInfo(
                kCGWindowListExcludeDesktopElements,
                kCGNullWindowID));
            if ([self probeWindowsInList:allWindows
                                onScreen:NO
                              launcherCG:launcherCG
                            haveLauncher:haveLauncher
                       testedAnyCandidate:&testedAnyCandidate]) {
                probeSucceeded = YES;
            }
        }

        // 3. If there are no third-party layer-0 windows open on any Desktop Space, probe
        // the macOS Menu Bar / Dock window (excluding desktop wallpaper) so an empty Desktop
        // is never misdiagnosed as lacking Screen Recording permission.
        if (!probeSucceeded && !testedAnyCandidate) {
            pid_t myPID = getpid();
            for (NSDictionary *window in onScreenWindows) {
                NSNumber *ownerPID = window[(id)kCGWindowOwnerPID];
                NSNumber *windowIDNum = window[(id)kCGWindowNumber];
                if (ownerPID == nil || ownerPID.intValue == myPID || windowIDNum == nil) {
                    continue;
                }
                CGRect bounds = CGRectZero;
                NSDictionary *boundsDict = window[(id)kCGWindowBounds];
                CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict, &bounds);
                CGRect sampleRect = CGRectIsEmpty(bounds)
                    ? CGRectNull
                    : CGRectMake(bounds.origin.x, bounds.origin.y, MIN(bounds.size.width, 64.0), MIN(bounds.size.height, 24.0));
                CGImageRef sysImg = CGWindowListCreateImage(
                    sampleRect,
                    kCGWindowListOptionIncludingWindow,
                    (CGWindowID)windowIDNum.unsignedIntValue,
                    kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);
                if (sysImg != NULL) {
                    BOOL opaque = CGImageHasOpaquePixels(sysImg);
                    CGImageRelease(sysImg);
                    if (opaque) {
                        probeSucceeded = YES;
                        break;
                    }
                }
            }
        }
    }

    self.lastProbeResult = probeSucceeded;
    return probeSucceeded;
}

- (BOOL)screenRecordingGranted {
    // CGPreflight can return false for ad-hoc/relocated builds even when the
    // system toggle is on and capture works. A real non-blank capture probe is
    // stronger evidence than that API.
    if (CGPreflightScreenCaptureAccess()) {
        return YES;
    }
    if (self.captureVerified) {
        return YES;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CSCaptureVerified"]) {
        if ([self screenCaptureProbe]) {
            self.captureVerified = YES;
            return YES;
        }
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSCaptureVerified"];
    }
    if ([self screenCaptureProbe]) {
        self.captureVerified = YES;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CSCaptureVerified"];
        return YES;
    }
    return NO;
}

- (void)showLauncher:(nullable id)sender {
    [self showLauncher];
}

- (void)showLauncher {
    if (self.launcher == nil) {
        __weak typeof(self) weakSelf = self;
        LauncherWindow *launcher = [[LauncherWindow alloc]
            initWithNewCapture:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf takeScreenshot:nil];
            }
            delayedCapture:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf takeDelayedScreenshot:nil];
            }
            fullScreen:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf captureFullScreen:nil];
            }
            grantPermission:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf grantScreenRecordingPermission];
            }
            checkPermission:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf checkScreenRecordingPermission];
            }
            restartBlock:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf relaunchChoxieshoot:nil];
            }
            resetBlock:^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                [strongSelf resetScreenRecordingPermission:nil];
            }];
        launcher.recordVideoBlock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf takeVideoRecording:nil];
        };
        launcher.openVideoBlock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf openVideoToEdit:nil];
        };
        launcher.onClose = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            LauncherWindow *closing = strongSelf.launcher;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.launcher == closing) {
                    strongSelf.launcher = nil;
                }
            });
        };
        self.launcher = launcher;
    }
    [self.launcher setDelaySeconds:[self delaySeconds]];
    [self.launcher updateScreenRecordingGranted:[self screenRecordingGranted]];
    if (self.launcher.isMiniaturized) {
        [self.launcher deminiaturize:nil];
    }
    if (self.launcher.isVisible && !self.launcher.isOnActiveSpace) {
        [self.launcher orderOut:nil];
    }
    NSScreen *activeScreen = [self activeScreenForMouse];
    if (activeScreen != nil && !self.launcher.isVisible) {
        NSRect vis = activeScreen.visibleFrame;
        NSRect wFrame = self.launcher.frame;
        NSPoint origin = NSMakePoint(floor(NSMidX(vis) - NSWidth(wFrame) / 2.0),
                                     floor(NSMidY(vis) - NSHeight(wFrame) / 2.0));
        [self.launcher setFrameOrigin:origin];
    } else if (!self.launcher.isVisible) {
        [self.launcher center];
    }
    self.launcher.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    [self.launcher orderFrontRegardless];
    [self.launcher makeKeyAndOrderFront:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.launcher.collectionBehavior = NSWindowCollectionBehaviorDefault;
    });
}

- (void)showLauncherForPermission {
    static BOOL requestedThisRun = NO;
    [self showLauncher];
    [self.launcher focusPermissions];
    // Ask the system once per run; the card stays up so the user can finish in
    // Settings and hit Check Again.
    if (!requestedThisRun) {
        requestedThisRun = YES;
        CGRequestScreenCaptureAccess();
    }
}

- (void)grantScreenRecordingPermission {
    self.lastProbeTime = 0;
    if (![self screenRecordingGranted]) {
        self.captureVerified = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSCaptureVerified"];
        // Clear any stale ad-hoc signature entry from an earlier build so macOS
        // registers the currently running binary in System Settings.
        ResetTCCScreenCaptureForApp();
    }
    CGRequestScreenCaptureAccess();
    [self openScreenRecordingSettings];
    self.lastProbeTime = 0;
    [self.launcher updateScreenRecordingGranted:[self screenRecordingGranted]];
}

- (void)resetScreenRecordingPermission:(id)sender {
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Reset Screen Recording permission?";
    confirm.informativeText = @"This removes Choxieshoot from the Screen Recording list, restarts it, and opens System Settings so you can enable it cleanly. Use this if the toggle is on but Choxieshoot still says it is not granted.";
    confirm.alertStyle = NSAlertStyleWarning;
    [confirm addButtonWithTitle:@"Reset & Restart"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    self.captureVerified = NO;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSCaptureVerified"];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CSAutoRequestOnLaunch"];
    ResetTCCScreenCaptureForApp();
    [self relaunchChoxieshoot:nil];
}

- (void)checkScreenRecordingPermission {
    self.lastProbeTime = 0;
    BOOL granted = [self screenRecordingGranted];
    [self.launcher updateScreenRecordingGranted:granted];
    if (granted) {
        return;
    }
    // macOS applies Screen Recording changes only after the process restarts.
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restart Choxieshoot to apply Screen Recording";
    alert.informativeText = @"If you have already enabled Choxieshoot in System Settings → Privacy & Security → Screen Recording, click Restart Now. macOS only applies this permission to a newly launched process.\n\nIf the toggle was already on from an older build, click Grant Access (or Reset Access) first so macOS updates the permission for this build.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"Restart Now"];
    [alert addButtonWithTitle:@"Later"];
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [self relaunchChoxieshoot:nil];
    }
}

- (void)relaunchChoxieshoot:(id)sender {
    NSURL *bundleURL = [[NSBundle mainBundle] bundleURL];
    if (bundleURL == nil) {
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:bundleURL
                                          configuration:configuration
                                      completionHandler:^(NSRunningApplication *app, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }];
}

- (void)openScreenRecordingSettings {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)showPermissions:(id)sender {
    [self showLauncher];
    [self.launcher focusPermissions];
}

- (void)hideLauncher {
    if (self.launcher != nil && !self.launcher.isMiniaturized) {
        LauncherWindow *closing = self.launcher;
        self.launcher = nil;
        [closing close];
    }
}

- (void)hideEditorsForCapture {
    [self.hiddenEditors removeAllObjects];
    for (EditorWindow *editor in self.editingWindows) {
        if (editor.isVisible && editor.isOnActiveSpace) {
            [editor orderOut:nil];
            [self.hiddenEditors addObject:editor];
        }
    }
    for (VideoPreviewWindow *preview in self.videoPreviewWindows) {
        if (preview.isVisible && preview.isOnActiveSpace) {
            [preview orderOut:nil];
            [self.hiddenEditors addObject:preview];
        }
    }
    self.preferencesWasVisible = (self.preferencesWindow != nil &&
                                  self.preferencesWindow.isVisible &&
                                  self.preferencesWindow.isOnActiveSpace);
    if (self.preferencesWasVisible) {
        [self.preferencesWindow orderOut:nil];
    }
}

- (void)restoreEditorsAfterCaptureToFront:(BOOL)toFront {
    for (NSWindow *editor in self.hiddenEditors) {
        if (toFront) {
            [editor orderFront:nil];
        } else {
            [editor orderBack:nil];
        }
    }
    [self.hiddenEditors removeAllObjects];
    if (self.preferencesWasVisible && toFront) {
        [self.preferencesWindow orderFront:nil];
    }
    self.preferencesWasVisible = NO;
}

#pragma mark - Status item

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"camera.viewfinder"
                              accessibilityDescription:@"Choxieshoot"];
    if (icon != nil) {
        icon.template = YES;
        button.image = icon;
    } else {
        button.title = @"CS";
    }

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *stopVideoItem = [self menuItemWithTitle:@"Stop Video Recording" action:@selector(stopVideoRecording:) key:@"" target:self];
    stopVideoItem.hidden = YES;
    self.stopVideoMenuItem = stopVideoItem;
    [menu addItem:stopVideoItem];
    [menu addItem:[self menuItemWithTitle:@"Show Choxieshoot" action:@selector(showLauncher:) key:@"" target:self]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Take Screenshot" action:@selector(takeScreenshot:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Record Video…" action:@selector(takeVideoRecording:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Open Video to Edit…" action:@selector(openVideoToEdit:) key:@"" target:self]];
    NSMenuItem *delayedItem = [self menuItemWithTitle:[NSString stringWithFormat:@"Take Screenshot in %ld Seconds", (long)[self delaySeconds]]
                                               action:@selector(takeDelayedScreenshot:)
                                                  key:@""
                                               target:self];
    self.delayedMenuItem = delayedItem;
    [menu addItem:delayedItem];
    [menu addItem:[self menuItemWithTitle:@"Capture Full Screen" action:@selector(captureFullScreen:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Record Full Screen Video" action:@selector(recordFullScreenVideo:) key:@"" target:self]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Preferences…" action:@selector(showPreferences:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Permissions…" action:@selector(showPermissions:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Restart Choxieshoot" action:@selector(relaunchChoxieshoot:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"Reset Screen Recording Permission…" action:@selector(resetScreenRecordingPermission:) key:@"" target:self]];
    [menu addItem:[self menuItemWithTitle:@"About Choxieshoot" action:@selector(showAbout:) key:@"" target:self]];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Quit Choxieshoot" action:@selector(terminate:) key:@"q" target:NSApp]];
    self.statusItem.menu = menu;
}

#pragma mark - Global hotkey (Cmd+Shift+2)

- (void)registerGlobalHotkey {
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    static BOOL handlerInstalled = NO;
    if (!handlerInstalled) {
        InstallEventHandler(GetApplicationEventTarget(),
                            NewEventHandlerUPP(ChoxieshootHotKeyHandler),
                            1,
                            &eventType,
                            (__bridge void *)self,
                            NULL);
        handlerInstalled = YES;
    }

    CSShortcut *shortcut = [CSShortcut savedShortcut];
    if (![self registerHotkey:shortcut]) {
        [self registerHotkey:[CSShortcut defaultShortcut]];
    }
}

- (BOOL)registerHotkey:(CSShortcut *)shortcut {
    if (gHotKeyRef != NULL) {
        UnregisterEventHotKey(gHotKeyRef);
        gHotKeyRef = NULL;
    }
    if (shortcut == nil) {
        return NO;
    }
    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'CHXS';
    hotKeyID.id = 1;
    OSStatus status = RegisterEventHotKey((UInt32)shortcut.keyCode,
                                          shortcut.carbonModifiers,
                                          hotKeyID,
                                          GetApplicationEventTarget(),
                                          0,
                                          &gHotKeyRef);
    if (status != noErr) {
        gHotKeyRef = NULL;
        return NO;
    }
    return YES;
}

- (void)handleHotkey {
    if (self.activeVideoRecorder != nil && self.activeVideoRecorder.isRecording) {
        [self stopVideoRecording:nil];
        return;
    }
    [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
}

- (void)startAreaSelectionForTesting {
    [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
}

- (void)startVideoSelectionForTesting {
    [self startAreaSelectionWithMode:CSCaptureModeVideo];
}

- (void)captureTestRect:(NSRect)rect {
    [self captureAndEditScreenRect:rect belowWindowID:kCGNullWindowID];
}

- (void)handleNewCaptureNotification:(NSNotification *)notification {
    [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
}

- (void)takeScreenshot:(id)sender {
    [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
}

- (void)takeVideoRecording:(id)sender {
    [self startAreaSelectionWithMode:CSCaptureModeVideo];
}

- (void)takeDelayedScreenshot:(id)sender {
    [self hideLauncher];
    NSInteger seconds = [self delaySeconds];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
    });
}

- (void)captureFullScreen:(id)sender {
    NSScreen *screen = [self activeScreenForMouse];
    if (screen == nil) {
        return;
    }
    CGWindowID belowID = (self.launcher != nil && self.launcher.isVisible && self.launcher.windowNumber > 0)
        ? (CGWindowID)self.launcher.windowNumber
        : kCGNullWindowID;
    [self hideLauncher];
    [self hideEditorsForCapture];
    [self captureAndEditScreenRect:screen.frame belowWindowID:belowID];
    [self restoreEditorsAfterCaptureToFront:NO];
}

- (void)recordFullScreenVideo:(id)sender {
    NSScreen *screen = [self activeScreenForMouse];
    if (screen == nil) {
        return;
    }
    [self hideLauncher];
    BOOL recordMic = [self boolForKey:CSRecordMicrophoneKey defaultValue:NO];
    [self startVideoRecordingForRect:screen.frame recordMicrophone:recordMic];
}

#pragma mark - Capture & Video Recording flow

- (void)startAreaSelection {
    [self startAreaSelectionWithMode:CSCaptureModeScreenshot];
}

- (void)startAreaSelectionWithMode:(CSCaptureMode)initialMode {
    if (self.isSelecting) {
        return;
    }
    if (self.activeVideoRecorder != nil && self.activeVideoRecorder.isRecording) {
        [self stopVideoRecording:nil];
        return;
    }
    self.isSelecting = YES;
    [self hideLauncher];
    [self hideEditorsForCapture];

    BOOL savedMic = [self boolForKey:CSRecordMicrophoneKey defaultValue:NO];
    __weak typeof(self) weakSelf = self;
    SelectionWindow *window = [[SelectionWindow alloc]
        initWithInitialMode:initialMode
           recordMicrophone:savedMic
             modeCompletion:^(NSRect screenRect, CSCaptureMode mode, BOOL recordMicrophone) {
                 __strong typeof(weakSelf) strongSelf = weakSelf;
                 if (strongSelf == nil) {
                     return;
                 }
                 strongSelf.isSelecting = NO;
                 [[NSUserDefaults standardUserDefaults] setBool:recordMicrophone forKey:CSRecordMicrophoneKey];
                 CGWindowID selectionWindowID = (strongSelf.selectionWindow != nil && strongSelf.selectionWindow.windowNumber > 0)
                     ? (CGWindowID)strongSelf.selectionWindow.windowNumber
                     : kCGNullWindowID;
                 dispatch_async(dispatch_get_main_queue(), ^{
                     strongSelf.selectionWindow = nil;
                 });
                 if (mode == CSCaptureModeVideo) {
                     [strongSelf restoreEditorsAfterCaptureToFront:NO];
                     [strongSelf startVideoRecordingForRect:screenRect recordMicrophone:recordMicrophone];
                 } else {
                     [strongSelf captureAndEditScreenRect:screenRect belowWindowID:selectionWindowID];
                     [strongSelf restoreEditorsAfterCaptureToFront:NO];
                 }
             }
                     cancel:^{
                         __strong typeof(weakSelf) strongSelf = weakSelf;
                         if (strongSelf == nil) {
                             return;
                         }
                         strongSelf.isSelecting = NO;
                         dispatch_async(dispatch_get_main_queue(), ^{
                             strongSelf.selectionWindow = nil;
                         });
                         [strongSelf restoreEditorsAfterCaptureToFront:YES];
                     }];

    self.selectionWindow = window;
    [window orderFrontRegardless];
    [window makeKeyAndOrderFront:nil];
}

- (void)updateStatusItemForRecording:(BOOL)recording {
    self.stopVideoMenuItem.hidden = !recording;
    if (self.statusItem != nil && self.statusItem.button != nil) {
        NSString *symbol = recording ? @"record.circle.fill" : @"camera.viewfinder";
        NSImage *icon = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:@"Choxieshoot"];
        if (icon != nil) {
            icon.template = !recording;
            self.statusItem.button.image = icon;
            self.statusItem.button.contentTintColor = recording ? [NSColor systemRedColor] : nil;
        }
    }
}

- (void)startVideoRecordingForRect:(NSRect)screenRect recordMicrophone:(BOOL)recordMicrophone {
    BOOL testMode = getenv("CS_TEST_MODE") != NULL;
    self.lastProbeTime = 0;
    BOOL granted = [self screenRecordingGranted];
    if (!testMode && !granted) {
        self.captureVerified = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSCaptureVerified"];
        [self showLauncherForPermission];
        return;
    }
    self.captureVerified = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CSCaptureVerified"];
    [self.launcher updateScreenRecordingGranted:YES];

    __weak typeof(self) weakSelf = self;
    void (^beginBlock)(BOOL) = ^(BOOL micGranted) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        BOOL useMic = recordMicrophone && micGranted;
        RecordingControlWindow *hud = [[RecordingControlWindow alloc] initWithRecordedScreenRect:screenRect
                                                                                recordMicrophone:useMic];
        VideoRecorder *recorder = [[VideoRecorder alloc] initWithScreenRect:screenRect
                                                           recordMicrophone:useMic
                                                       excludeAboveWindowID:hud.lowestOverlayWindowID];
        recorder.onDurationUpdate = ^(NSTimeInterval elapsed) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            [innerSelf.recordingControlWindow updateElapsedSeconds:elapsed];
        };
        hud.onPauseResume = ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf.activeVideoRecorder == nil) {
                return;
            }
            if (innerSelf.activeVideoRecorder.isPaused) {
                [innerSelf.activeVideoRecorder resumeRecording];
                [innerSelf.recordingControlWindow setPaused:NO];
            } else {
                [innerSelf.activeVideoRecorder pauseRecording];
                [innerSelf.recordingControlWindow setPaused:YES];
            }
        };
        hud.onStop = ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            [innerSelf stopVideoRecording:nil];
        };
        hud.onCancel = ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            [innerSelf cancelVideoRecording:nil];
        };

        NSError *startErr = nil;
        if (![recorder startRecordingWithError:&startErr]) {
            [hud dismissAllOverlays];
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Could not start video recording";
            alert.informativeText = startErr.localizedDescription ?: @"Unknown error";
            [alert runModal];
            return;
        }

        strongSelf.recordingControlWindow = hud;
        strongSelf.activeVideoRecorder = recorder;
        [strongSelf updateStatusItemForRecording:YES];
    };

    if (recordMicrophone) {
        [VideoRecorder requestMicrophoneAccessIfNeeded:beginBlock];
    } else {
        beginBlock(NO);
    }
}

- (void)stopVideoRecording:(nullable id)sender {
    VideoRecorder *recorder = self.activeVideoRecorder;
    RecordingControlWindow *hud = self.recordingControlWindow;
    self.activeVideoRecorder = nil;
    self.recordingControlWindow = nil;
    [self updateStatusItemForRecording:NO];
    [hud dismissAllOverlays];

    if (recorder == nil) {
        return;
    }

    NSRect recordedRect = recorder.screenRect;
    __weak typeof(self) weakSelf = self;
    [recorder stopRecordingWithCompletion:^(NSURL * _Nullable outputURL, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (outputURL == nil) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Video recording failed";
            alert.informativeText = error.localizedDescription ?: @"Could not finalize MP4 file.";
            [alert runModal];
            return;
        }
        [strongSelf openVideoPreviewWithURL:outputURL screenRect:recordedRect];
    }];
}

- (void)cancelVideoRecording:(nullable id)sender {
    VideoRecorder *recorder = self.activeVideoRecorder;
    RecordingControlWindow *hud = self.recordingControlWindow;
    self.activeVideoRecorder = nil;
    self.recordingControlWindow = nil;
    [self updateStatusItemForRecording:NO];
    [hud dismissAllOverlays];
    [recorder cancelRecording];
}

- (void)openVideoPreviewWithURL:(NSURL *)videoURL screenRect:(NSRect)screenRect {
    VideoPreviewWindow *preview = [[VideoPreviewWindow alloc] initWithScreenRect:screenRect videoURL:videoURL];
    __weak typeof(self) weakSelf = self;
    preview.onClose = ^(VideoPreviewWindow *window) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.videoPreviewWindows removeObjectIdenticalTo:window];
            malloc_zone_pressure_relief(NULL, 0);
        });
    };
    preview.onNewRecording = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf takeVideoRecording:nil];
    };
    [self.videoPreviewWindows addObject:preview];
    [NSApp activateIgnoringOtherApps:YES];
    [preview orderFrontRegardless];
    [preview makeKeyAndOrderFront:nil];
    if ([self boolForKey:CSPlaySoundKey defaultValue:NO]) {
        NSSound *sound = [NSSound soundNamed:@"Tink"];
        [sound play];
    }
}

- (void)openVideoToEdit:(nullable id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.title = @"Open Video to Edit (Cut & Crop)";
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = @[@"mp4", @"mov", @"m4v"];
#pragma clang diagnostic pop

    [NSApp activateIgnoringOtherApps:YES];
    if ([panel runModal] == NSModalResponseOK && panel.URL != nil) {
        NSRect screenRect = [self activeScreenForMouse].visibleFrame;
        [self openVideoPreviewWithURL:panel.URL screenRect:screenRect];
    }
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    NSURL *url = [NSURL fileURLWithPath:filename];
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) {
        NSRect screenRect = [self activeScreenForMouse].visibleFrame;
        [self openVideoPreviewWithURL:url screenRect:screenRect];
        return YES;
    }
    return NO;
}

- (void)captureAndEditScreenRect:(NSRect)screenRect {
    [self captureAndEditScreenRect:screenRect belowWindowID:kCGNullWindowID];
}

- (void)captureAndEditScreenRect:(NSRect)screenRect belowWindowID:(CGWindowID)belowWindowID {
    BOOL testMode = getenv("CS_TEST_MODE") != NULL;
    self.lastProbeTime = 0;
    BOOL granted = [self screenRecordingGranted];
    NSImage *image = CaptureScreenRectBelowWindow(screenRect, belowWindowID);
    if (image == nil || (!testMode && !granted)) {
        self.isSelecting = NO;
        self.captureVerified = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CSCaptureVerified"];
        [self showLauncherForPermission];
        return;
    }
    self.captureVerified = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"CSCaptureVerified"];
    [self.launcher updateScreenRecordingGranted:YES];

    EditorWindow *editor = [[EditorWindow alloc] initWithScreenRect:screenRect image:image];
    __weak typeof(self) weakSelf = self;
    editor.onClose = ^(EditorWindow *window) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        // Removing the last reference from inside -close can deallocate the
        // window while AppKit is still finishing the close; defer one turn.
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.editingWindows removeObjectIdenticalTo:window];
            malloc_zone_pressure_relief(NULL, 0);
        });
    };
    [self.editingWindows addObject:editor];
    [editor orderFrontRegardless];
    [editor makeKeyAndOrderFront:nil];
    if ([self boolForKey:CSPlaySoundKey defaultValue:NO]) {
        NSSound *sound = [NSSound soundNamed:@"Tink"];
        [sound play];
    }
}

#pragma mark - Preferences

- (void)showPreferences:(id)sender {
    if (self.preferencesWindow == nil) {
        PreferencesWindow *prefs = [[PreferencesWindow alloc] initWithDelegate:self];
        __weak typeof(self) weakSelf = self;
        prefs.onClose = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            PreferencesWindow *closing = strongSelf.preferencesWindow;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (strongSelf.preferencesWindow == closing) {
                    strongSelf.preferencesWindow = nil;
                }
            });
        };
        self.preferencesWindow = prefs;
    }
    [self.preferencesWindow refreshFromSettings];
    if (self.preferencesWindow.isMiniaturized) {
        [self.preferencesWindow deminiaturize:nil];
    }
    if (self.preferencesWindow.isVisible && !self.preferencesWindow.isOnActiveSpace) {
        [self.preferencesWindow orderOut:nil];
    }
    NSScreen *activeScreen = [self activeScreenForMouse];
    if (activeScreen != nil && !self.preferencesWindow.isVisible) {
        NSRect vis = activeScreen.visibleFrame;
        NSRect wFrame = self.preferencesWindow.frame;
        NSPoint origin = NSMakePoint(floor(NSMidX(vis) - NSWidth(wFrame) / 2.0),
                                     floor(NSMidY(vis) - NSHeight(wFrame) / 2.0));
        [self.preferencesWindow setFrameOrigin:origin];
    } else if (!self.preferencesWindow.isVisible) {
        [self.preferencesWindow center];
    }
    self.preferencesWindow.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
    [self.preferencesWindow orderFrontRegardless];
    [self.preferencesWindow makeKeyAndOrderFront:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.preferencesWindow.collectionBehavior = NSWindowCollectionBehaviorDefault;
    });
}

- (void)showPreferencesForTesting {
    [self showPreferences:nil];
}

- (CSShortcut *)preferencesCurrentShortcut {
    return [CSShortcut savedShortcut];
}

- (BOOL)preferencesApplyShortcut:(CSShortcut *)shortcut errorMessage:(NSString **)errorMessage {
    CSShortcut *oldShortcut = [CSShortcut savedShortcut];
    if (![self registerHotkey:shortcut]) {
        [self registerHotkey:oldShortcut];
        if (errorMessage != NULL) {
            *errorMessage = @"That shortcut is already used by macOS or another app. Try another combination.";
        }
        return NO;
    }
    [shortcut save];
    return YES;
}

- (void)preferencesGeneralSettingsChanged {
    [self applyGeneralSettings];
}

- (BOOL)preferencesScreenRecordingGranted {
    return [self screenRecordingGranted];
}

- (void)preferencesGrantScreenRecording {
    [self grantScreenRecordingPermission];
}

- (void)preferencesCheckScreenRecording {
    [self checkScreenRecordingPermission];
}

- (void)preferencesRestartApplication {
    [self relaunchChoxieshoot:nil];
}

- (void)preferencesResetScreenRecording {
    [self resetScreenRecordingPermission:nil];
}

#pragma mark - About

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Choxieshoot";
    alert.informativeText = @"A lightweight, local-only screenshot tool for macOS.\\n\\n⌘⇧2 — capture an area\\n⌘N — new screenshot from the editor\\n⌘S — save PNG\\n⌘C — copy image\\n⇧⌘C — copy text (OCR)\\n⌘Z / ⇧⌘Z — undo / redo\\nEsc — close\\n\\nEyedropper: pick the dropper in the toolbar to read HEX / RGB / HSB / HSL and copy them.\\n\\n100% local: screenshots never leave your Mac.";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (gHotKeyRef != NULL) {
        UnregisterEventHotKey(gHotKeyRef);
        gHotKeyRef = NULL;
    }

    if (self.preferencesWindow != nil) {
        [self.preferencesWindow orderOut:nil];
        [self.preferencesWindow close];
        self.preferencesWindow = nil;
    }
    if (self.launcher != nil) {
        [self.launcher orderOut:nil];
        [self.launcher close];
        self.launcher = nil;
    }

    // Tear windows down explicitly before the process exits.
    if (self.selectionWindow != nil) {
        [self.selectionWindow orderOut:nil];
        [self.selectionWindow close];
        self.selectionWindow = nil;
    }
    if (self.activeVideoRecorder != nil) {
        [self.activeVideoRecorder cancelRecording];
        self.activeVideoRecorder = nil;
    }
    if (self.recordingControlWindow != nil) {
        [self.recordingControlWindow dismissAllOverlays];
        self.recordingControlWindow = nil;
    }
    for (VideoPreviewWindow *window in [self.videoPreviewWindows copy]) {
        [window close];
    }
    [self.videoPreviewWindows removeAllObjects];
    for (EditorWindow *window in [self.editingWindows copy]) {
        [window close];
    }
    [self.editingWindows removeAllObjects];
    [self.hiddenEditors removeAllObjects];

    if (self.statusItem != nil) {
        self.statusItem.menu = nil;
        [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
        self.statusItem = nil;
    }
}

@end
