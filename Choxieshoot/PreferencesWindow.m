#import "PreferencesWindow.h"
#import "ShortcutRecorderView.h"
#import "CSTheme.h"
#import "ChoxieshootPreferences.h"
#import <Carbon/Carbon.h>
#import <malloc/malloc.h>

NSString *const CSShowLauncherKey = @"CSShowLauncher";
NSString *const CSShowMenuBarIconKey = @"CSShowMenuBarIcon";
NSString *const CSPlaySoundKey = @"CSPlaySound";
NSString *const CSDelaySecondsKey = @"CSDelaySeconds";
NSString *const CSRecordMicrophoneKey = @"CSRecordMicrophone";
NSString *const CSVideoFPSKey = @"CSVideoFPS";
NSString *const CSVideoMotionBlurKey = @"CSVideoMotionBlur";
NSString *const CSVideoRecordCursorKey = @"CSVideoRecordCursor";
NSString *const CSVideoCursorMotionBlurKey = @"CSVideoCursorMotionBlur";

@interface PreferencesWindow () <NSWindowDelegate>

@property (nonatomic, weak) id<PreferencesWindowDelegate> preferencesDelegate;
@property (nonatomic, strong) NSTabView *tabView;

@property (nonatomic, strong) NSButton *showLauncherCheckbox;
@property (nonatomic, strong) NSButton *showMenuBarCheckbox;
@property (nonatomic, strong) NSButton *playSoundCheckbox;
@property (nonatomic, strong) NSPopUpButton *delayPopup;

@property (nonatomic, strong) NSPopUpButton *videoFPSPopup;
@property (nonatomic, strong) NSPopUpButton *videoMotionBlurPopup;
@property (nonatomic, strong) NSButton *videoRecordCursorCheckbox;
@property (nonatomic, strong) NSButton *videoCursorBlurCheckbox;
@property (nonatomic, strong) NSButton *videoMicDefaultCheckbox;

@property (nonatomic, strong) ShortcutRecorderView *recorder;
@property (nonatomic, strong) NSTextField *shortcutErrorLabel;

@property (nonatomic, strong) NSView *permissionDot;
@property (nonatomic, strong) NSTextField *permissionStatusLabel;
@property (nonatomic, strong) NSTextField *permissionDetailLabel;

@end

@implementation PreferencesWindow

- (instancetype)initWithDelegate:(id<PreferencesWindowDelegate>)delegate {
    NSRect contentRect = NSMakeRect(0, 0, 500, 410);
    self = [super initWithContentRect:contentRect
                            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil) {
        return nil;
    }
    self.title = @"Choxieshoot Preferences";
    self.floatingPanel = NO;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.level = NSNormalWindowLevel;
    self.releasedWhenClosed = NO;
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    self.preferencesDelegate = delegate;
    self.delegate = self;
    self.backgroundColor = [CSTheme surface];
    [self enableTrafficLightMinimizeButton];

    NSView *content = [[NSView alloc] initWithFrame:contentRect];
    content.wantsLayer = YES;
    content.layer.backgroundColor = [CSTheme surface].CGColor;
    self.contentView = content;

    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(12, 12, 476, 386)];
    self.tabView.tabViewType = NSTopTabsBezelBorder;
    [content addSubview:self.tabView];

    NSTabViewItem *general = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    general.label = @"General";
    general.view = [self buildGeneralView];
    [self.tabView addTabViewItem:general];

    NSTabViewItem *video = [[NSTabViewItem alloc] initWithIdentifier:@"video"];
    video.label = @"Video";
    video.view = [self buildVideoView];
    [self.tabView addTabViewItem:video];

    NSTabViewItem *shortcuts = [[NSTabViewItem alloc] initWithIdentifier:@"shortcuts"];
    shortcuts.label = @"Shortcuts";
    shortcuts.view = [self buildShortcutsView];
    [self.tabView addTabViewItem:shortcuts];

    NSTabViewItem *permissions = [[NSTabViewItem alloc] initWithIdentifier:@"permissions"];
    permissions.label = @"Permissions";
    permissions.view = [self buildPermissionsView];
    [self.tabView addTabViewItem:permissions];

    [self refreshFromSettings];
    return self;
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:key] == nil) {
        return defaultValue;
    }
    return [defaults boolForKey:key];
}

- (NSTextField *)labelWithString:(NSString *)string
                            font:(NSFont *)font
                           color:(NSColor *)color
                           frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.textColor = color;
    label.frame = frame;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.maximumNumberOfLines = 3;
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *checkbox = [NSButton checkboxWithTitle:title target:self action:action];
    checkbox.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    checkbox.frame = frame;
    return checkbox;
}

- (NSView *)buildGeneralView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 456, 336)];
    NSTextField *title = [self labelWithString:@"General"
                                          font:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]
                                         color:[CSTheme text]
                                         frame:NSMakeRect(20, 292, 300, 22)];
    [view addSubview:title];

    self.showLauncherCheckbox = [self checkboxWithTitle:@"Show launcher window at launch"
                                                  frame:NSMakeRect(20, 248, 380, 22)
                                                 action:@selector(generalCheckboxChanged:)];
    [view addSubview:self.showLauncherCheckbox];

    self.showMenuBarCheckbox = [self checkboxWithTitle:@"Show menu bar icon"
                                                 frame:NSMakeRect(20, 216, 380, 22)
                                                action:@selector(generalCheckboxChanged:)];
    [view addSubview:self.showMenuBarCheckbox];

    self.playSoundCheckbox = [self checkboxWithTitle:@"Play a sound after a capture"
                                               frame:NSMakeRect(20, 184, 380, 22)
                                              action:@selector(generalCheckboxChanged:)];
    [view addSubview:self.playSoundCheckbox];

    NSTextField *delayLabel = [self labelWithString:@"Delayed capture"
                                               font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                              color:[CSTheme text]
                                              frame:NSMakeRect(20, 140, 140, 20)];
    [view addSubview:delayLabel];

    self.delayPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(170, 134, 130, 28) pullsDown:NO];
    [self.delayPopup addItemsWithTitles:@[@"3 seconds", @"5 seconds", @"10 seconds"]];
    self.delayPopup.target = self;
    self.delayPopup.action = @selector(delayChanged:);
    [view addSubview:self.delayPopup];

    NSTextField *hint = [self labelWithString:@"New captures open in the editor. The launcher and menu-bar icon can be hidden if you prefer the Dock only."
                                         font:[NSFont systemFontOfSize:10 weight:NSFontWeightRegular]
                                        color:[CSTheme mutedText]
                                        frame:NSMakeRect(20, 70, 416, 40)];
    [view addSubview:hint];
    return view;
}

- (NSView *)buildVideoView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 456, 336)];
    NSTextField *title = [self labelWithString:@"Video Recording"
                                          font:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]
                                         color:[CSTheme text]
                                         frame:NSMakeRect(20, 292, 300, 22)];
    [view addSubview:title];

    NSTextField *fpsLabel = [self labelWithString:@"Frame rate"
                                             font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                            color:[CSTheme text]
                                            frame:NSMakeRect(20, 252, 130, 20)];
    [view addSubview:fpsLabel];

    self.videoFPSPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(160, 246, 230, 28) pullsDown:NO];
    [self.videoFPSPopup addItemsWithTitles:@[@"60 FPS (Silky Smooth)", @"30 FPS (Standard)"]];
    self.videoFPSPopup.target = self;
    self.videoFPSPopup.action = @selector(videoSettingsChanged:);
    [view addSubview:self.videoFPSPopup];

    NSTextField *blurLabel = [self labelWithString:@"Motion blur"
                                              font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular]
                                             color:[CSTheme text]
                                             frame:NSMakeRect(20, 212, 130, 20)];
    [view addSubview:blurLabel];

    self.videoMotionBlurPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(160, 206, 230, 28) pullsDown:NO];
    [self.videoMotionBlurPopup addItemsWithTitles:@[
        @"Off (Raw sharp snapshots)",
        @"Subtle (180° Shutter - Smooth)",
        @"Cinematic (270° Shutter)",
        @"Heavy (360° Shutter)"
    ]];
    self.videoMotionBlurPopup.target = self;
    self.videoMotionBlurPopup.action = @selector(videoSettingsChanged:);
    [view addSubview:self.videoMotionBlurPopup];

    self.videoRecordCursorCheckbox = [self checkboxWithTitle:@"Record mouse cursor in videos"
                                                       frame:NSMakeRect(20, 168, 380, 22)
                                                      action:@selector(videoSettingsChanged:)];
    [view addSubview:self.videoRecordCursorCheckbox];

    self.videoCursorBlurCheckbox = [self checkboxWithTitle:@"Apply smooth motion blur to cursor"
                                                     frame:NSMakeRect(40, 138, 360, 22)
                                                    action:@selector(videoSettingsChanged:)];
    [view addSubview:self.videoCursorBlurCheckbox];

    self.videoMicDefaultCheckbox = [self checkboxWithTitle:@"Enable microphone audio by default"
                                                     frame:NSMakeRect(20, 104, 380, 22)
                                                    action:@selector(videoSettingsChanged:)];
    [view addSubview:self.videoMicDefaultCheckbox];

    NSTextField *hint = [self labelWithString:@"Motion blur simulates physical camera exposure during movement (window dragging, web scrolling, cursor motion) while preserving 100% razor-sharp clarity for static text."
                                         font:[NSFont systemFontOfSize:10 weight:NSFontWeightRegular]
                                        color:[CSTheme mutedText]
                                        frame:NSMakeRect(20, 36, 416, 52)];
    [view addSubview:hint];
    return view;
}

- (NSView *)buildShortcutsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 456, 336)];
    NSTextField *title = [self labelWithString:@"Global shortcut"
                                          font:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]
                                         color:[CSTheme text]
                                         frame:NSMakeRect(20, 292, 300, 22)];
    [view addSubview:title];

    NSTextField *subtitle = [self labelWithString:@"Click the field, then press the key combination you want."
                                             font:[NSFont systemFontOfSize:11 weight:NSFontWeightRegular]
                                            color:[CSTheme mutedText]
                                            frame:NSMakeRect(20, 270, 416, 18)];
    [view addSubview:subtitle];

    self.recorder = [[ShortcutRecorderView alloc] initWithFrame:NSMakeRect(20, 222, 220, 36)];
    __weak typeof(self) weakSelf = self;
    self.recorder.onShortcutChange = ^(CSShortcut *shortcut) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applyShortcut:shortcut];
    };
    [view addSubview:self.recorder];

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset to Default" target:self action:@selector(resetShortcut:)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    resetButton.frame = NSMakeRect(254, 226, 160, 28);
    [view addSubview:resetButton];

    NSTextField *recommended = [self labelWithString:@"Recommended"
                                                font:[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]
                                               color:[CSTheme mutedText]
                                               frame:NSMakeRect(20, 188, 200, 18)];
    [view addSubview:recommended];

    NSArray<NSArray *> *presets = @[
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_2 modifiers:(cmdKey | shiftKey)], @"Default"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_S modifiers:(controlKey | optionKey)], @"Quiet"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_X modifiers:(optionKey | cmdKey)], @"Option-Cmd-X"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_2 modifiers:(controlKey | cmdKey)], @"Control-Cmd-2"]
    ];
    CGFloat x = 20;
    for (NSArray *preset in presets) {
        CSShortcut *shortcut = preset[0];
        NSButton *button = [NSButton buttonWithTitle:[shortcut displayString] target:self action:@selector(presetClicked:)];
        button.bezelStyle = NSBezelStyleRounded;
        button.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightMedium];
        button.frame = NSMakeRect(x, 154, 100, 28);
        button.tag = [presets indexOfObject:preset];
        [view addSubview:button];
        x += 108;
    }

    self.shortcutErrorLabel = [self labelWithString:@""
                                               font:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]
                                              color:[NSColor systemRedColor]
                                              frame:NSMakeRect(20, 118, 416, 18)];
    [view addSubview:self.shortcutErrorLabel];

    NSTextField *note = [self labelWithString:@"Avoid ⌘⇧3 / ⌘⇧4 / ⌘⇧5 (macOS screenshots) and combinations already used by other apps. At least one of ⌘, ⌥ or ⌃ is required — or a function key."
                                          font:[NSFont systemFontOfSize:10 weight:NSFontWeightRegular]
                                         color:[CSTheme mutedText]
                                         frame:NSMakeRect(20, 60, 416, 48)];
    [view addSubview:note];
    return view;
}

- (NSView *)buildPermissionsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 456, 336)];
    NSTextField *title = [self labelWithString:@"Screen Recording"
                                          font:[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold]
                                         color:[CSTheme text]
                                         frame:NSMakeRect(20, 292, 300, 22)];
    [view addSubview:title];

    self.permissionDot = [[NSView alloc] initWithFrame:NSMakeRect(20, 258, 10, 10)];
    self.permissionDot.wantsLayer = YES;
    self.permissionDot.layer.cornerRadius = 5.0;
    [view addSubview:self.permissionDot];

    self.permissionStatusLabel = [self labelWithString:@"Checking…"
                                                  font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                                 color:[CSTheme text]
                                                 frame:NSMakeRect(40, 253, 380, 20)];
    [view addSubview:self.permissionStatusLabel];

    self.permissionDetailLabel = [self labelWithString:@""
                                                  font:[NSFont systemFontOfSize:11 weight:NSFontWeightRegular]
                                                 color:[CSTheme mutedText]
                                                 frame:NSMakeRect(20, 196, 416, 50)];
    [view addSubview:self.permissionDetailLabel];

    NSArray *titles = @[@"Open Settings", @"Check Again", @"Restart App", @"Reset Access"];
    NSArray *selectors = @[NSStringFromSelector(@selector(grantClicked:)),
                           NSStringFromSelector(@selector(checkClicked:)),
                           NSStringFromSelector(@selector(restartClicked:)),
                           NSStringFromSelector(@selector(resetClicked:))];
    CGFloat y = 140;
    for (NSInteger i = 0; i < titles.count; i++) {
        NSButton *button = [NSButton buttonWithTitle:titles[i] target:self action:NSSelectorFromString(selectors[i])];
        button.bezelStyle = NSBezelStyleRounded;
        button.frame = NSMakeRect(20 + (i % 2) * 200, y - (i / 2) * 38, 180, 28);
        [view addSubview:button];
    }

    NSTextField *note = [self labelWithString:@"macOS only applies Screen Recording to a newly launched process. If the toggle is already on but captures show only the desktop, use Reset Access, grant again, then Restart."
                                          font:[NSFont systemFontOfSize:10 weight:NSFontWeightRegular]
                                         color:[CSTheme mutedText]
                                         frame:NSMakeRect(20, 40, 416, 50)];
    [view addSubview:note];
    return view;
}

- (void)refreshFromSettings {
    self.showLauncherCheckbox.state = [self boolForKey:CSShowLauncherKey defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    self.showMenuBarCheckbox.state = [self boolForKey:CSShowMenuBarIconKey defaultValue:YES] ? NSControlStateValueOn : NSControlStateValueOff;
    self.playSoundCheckbox.state = [self boolForKey:CSPlaySoundKey defaultValue:NO] ? NSControlStateValueOn : NSControlStateValueOff;

    NSInteger delay = [[NSUserDefaults standardUserDefaults] integerForKey:CSDelaySecondsKey];
    if (delay <= 0) {
        delay = 3;
    }
    NSInteger index = delay == 5 ? 1 : (delay == 10 ? 2 : 0);
    [self.delayPopup selectItemAtIndex:index];

    // Video settings
    NSInteger fps = [[NSUserDefaults standardUserDefaults] integerForKey:CSVideoFPSKey];
    [self.videoFPSPopup selectItemAtIndex:(fps == 30 ? 1 : 0)];

    NSInteger blur = [[NSUserDefaults standardUserDefaults] objectForKey:CSVideoMotionBlurKey]
        ? [[NSUserDefaults standardUserDefaults] integerForKey:CSVideoMotionBlurKey]
        : 1; // Default to Subtle (1)
    if (blur < 0 || blur > 3) {
        blur = 1;
    }
    [self.videoMotionBlurPopup selectItemAtIndex:blur];

    BOOL recCursor = [self boolForKey:CSVideoRecordCursorKey defaultValue:YES];
    self.videoRecordCursorCheckbox.state = recCursor ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL cursorBlur = [self boolForKey:CSVideoCursorMotionBlurKey defaultValue:YES];
    self.videoCursorBlurCheckbox.state = cursorBlur ? NSControlStateValueOn : NSControlStateValueOff;
    self.videoCursorBlurCheckbox.enabled = recCursor;

    BOOL micDef = [self boolForKey:CSRecordMicrophoneKey defaultValue:NO];
    self.videoMicDefaultCheckbox.state = micDef ? NSControlStateValueOn : NSControlStateValueOff;

    self.recorder.shortcut = [self.preferencesDelegate preferencesCurrentShortcut];
    [self refreshPermissions];
}

- (void)refreshPermissions {
    BOOL granted = [self.preferencesDelegate preferencesScreenRecordingGranted];
    self.permissionDot.layer.backgroundColor = (granted ? [NSColor systemGreenColor] : [NSColor systemRedColor]).CGColor;
    self.permissionStatusLabel.stringValue = granted ? @"Screen Recording: granted" : @"Screen Recording: not granted";
    self.permissionDetailLabel.stringValue = granted
        ? @"Captures include other apps. You can revoke this at any time in System Settings."
        : @"Enable Choxieshoot in System Settings → Privacy & Security → Screen Recording. If it is already on for an older build, use Reset Access.";
}

- (void)enableTrafficLightMinimizeButton {
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    if (miniBtn != nil) {
        miniBtn.enabled = YES;
        miniBtn.target = self;
        miniBtn.action = @selector(minimizePreferencesClicked:);
    }
}

- (void)makeKeyAndOrderFront:(id)sender {
    [super makeKeyAndOrderFront:sender];
    [self enableTrafficLightMinimizeButton];
}

- (void)orderFrontRegardless {
    [super orderFrontRegardless];
    [self enableTrafficLightMinimizeButton];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (void)minimizePreferencesClicked:(id)sender {
    self.collectionBehavior = NSWindowCollectionBehaviorDefault;
    [super miniaturize:sender];
}

- (void)performMiniaturize:(id)sender {
    [self minimizePreferencesClicked:sender];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self enableTrafficLightMinimizeButton];
    [self refreshFromSettings];
}

#pragma mark - General

- (void)generalCheckboxChanged:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.showLauncherCheckbox.state == NSControlStateValueOn forKey:CSShowLauncherKey];
    [defaults setBool:self.showMenuBarCheckbox.state == NSControlStateValueOn forKey:CSShowMenuBarIconKey];
    [defaults setBool:self.playSoundCheckbox.state == NSControlStateValueOn forKey:CSPlaySoundKey];
    [self.preferencesDelegate preferencesGeneralSettingsChanged];
}

- (void)delayChanged:(NSPopUpButton *)sender {
    NSArray *values = @[@3, @5, @10];
    NSInteger seconds = [values[sender.indexOfSelectedItem] integerValue];
    [[NSUserDefaults standardUserDefaults] setInteger:seconds forKey:CSDelaySecondsKey];
    [self.preferencesDelegate preferencesGeneralSettingsChanged];
}

#pragma mark - Video

- (void)videoSettingsChanged:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger fps = (self.videoFPSPopup.indexOfSelectedItem == 1) ? 30 : 60;
    [defaults setInteger:fps forKey:CSVideoFPSKey];

    NSInteger blurMode = self.videoMotionBlurPopup.indexOfSelectedItem;
    [defaults setInteger:blurMode forKey:CSVideoMotionBlurKey];

    BOOL recCursor = (self.videoRecordCursorCheckbox.state == NSControlStateValueOn);
    [defaults setBool:recCursor forKey:CSVideoRecordCursorKey];
    self.videoCursorBlurCheckbox.enabled = recCursor;

    BOOL cursorBlur = (self.videoCursorBlurCheckbox.state == NSControlStateValueOn);
    [defaults setBool:cursorBlur forKey:CSVideoCursorMotionBlurKey];

    BOOL micDef = (self.videoMicDefaultCheckbox.state == NSControlStateValueOn);
    [defaults setBool:micDef forKey:CSRecordMicrophoneKey];
}

#pragma mark - Shortcuts

- (void)applyShortcut:(CSShortcut *)shortcut {
    NSString *error = nil;
    BOOL applied = [self.preferencesDelegate preferencesApplyShortcut:shortcut errorMessage:&error];
    if (applied) {
        self.shortcutErrorLabel.stringValue = @"";
    } else {
        self.shortcutErrorLabel.stringValue = error ?: @"That shortcut could not be registered.";
        self.recorder.shortcut = [self.preferencesDelegate preferencesCurrentShortcut];
    }
}

- (void)resetShortcut:(id)sender {
    CSShortcut *defaultShortcut = [CSShortcut defaultShortcut];
    self.recorder.shortcut = defaultShortcut;
    [self applyShortcut:defaultShortcut];
}

- (void)presetClicked:(NSButton *)sender {
    NSArray<NSArray *> *presets = @[
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_2 modifiers:(cmdKey | shiftKey)], @"Default"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_S modifiers:(controlKey | optionKey)], @"Quiet"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_X modifiers:(optionKey | cmdKey)], @"Option-Cmd-X"],
        @[[CSShortcut shortcutWithKeyCode:kVK_ANSI_2 modifiers:(controlKey | cmdKey)], @"Control-Cmd-2"]
    ];
    if (sender.tag < 0 || sender.tag >= (NSInteger)presets.count) {
        return;
    }
    CSShortcut *shortcut = presets[sender.tag][0];
    self.recorder.shortcut = shortcut;
    [self applyShortcut:shortcut];
}

#pragma mark - Permissions

- (void)grantClicked:(id)sender {
    [self.preferencesDelegate preferencesGrantScreenRecording];
    [self refreshPermissions];
}

- (void)checkClicked:(id)sender {
    [self.preferencesDelegate preferencesCheckScreenRecording];
    [self refreshPermissions];
}

- (void)restartClicked:(id)sender {
    [self.preferencesDelegate preferencesRestartApplication];
}

- (void)resetClicked:(id)sender {
    [self.preferencesDelegate preferencesResetScreenRecording];
}

- (void)cancelOperation:(id)sender {
    [self close];
}

- (void)close {
    [self orderOut:nil];
    self.recorder.onShortcutChange = nil;
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    miniBtn.target = nil;
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    void (^closeBlock)(void) = self.onClose;
    self.onClose = nil;
    [super close];
    if (closeBlock != nil) {
        closeBlock();
    }
    malloc_zone_pressure_relief(NULL, 0);
}

- (void)windowWillClose:(NSNotification *)notification {
    void (^closeBlock)(void) = self.onClose;
    self.onClose = nil;
    if (closeBlock != nil) {
        closeBlock();
    }
}

@end
