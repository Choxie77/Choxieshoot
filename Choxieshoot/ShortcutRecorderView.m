#import "ShortcutRecorderView.h"
#import "CSTheme.h"

@interface ShortcutRecorderView ()

@property (nonatomic, strong) NSTextField *label;
@property (nonatomic) BOOL recording;
@property (nonatomic, strong) NSString *savedMessage;

@end

@implementation ShortcutRecorderView

- (instancetype)initWithFrame:(NSRect)frameRect {
    if ((self = [super initWithFrame:frameRect])) {
        [self build];
    }
    return self;
}

- (void)build {
    self.wantsLayer = YES;
    self.layer.backgroundColor = [CSTheme controlSurface].CGColor;
    self.layer.cornerRadius = CSRadiusSmall;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.9].CGColor;
    self.focusRingType = NSFocusRingTypeExterior;

    self.label = [NSTextField labelWithString:@"⌘⇧2"];
    self.label.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightSemibold];
    self.label.textColor = [CSTheme text];
    self.label.alignment = NSTextAlignmentCenter;
    self.label.frame = NSMakeRect(8, (NSHeight(self.bounds) - 18) / 2.0, NSWidth(self.bounds) - 16, 18);
    self.label.autoresizingMask = NSViewWidthSizable;
    [self addSubview:self.label];
    [self setAccessibilityLabel:@"Global shortcut recorder"];
    self.shortcut = [CSShortcut savedShortcut];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)setShortcut:(CSShortcut *)shortcut {
    _shortcut = shortcut;
    [self updateDisplay];
}

- (void)updateDisplay {
    if (self.recording) {
        return;
    }
    self.label.stringValue = self.shortcut != nil ? [self.shortcut displayString] : @"Click to record";
    self.label.textColor = [CSTheme text];
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    [self beginRecording];
}

- (void)beginRecording {
    self.recording = YES;
    self.savedMessage = self.label.stringValue;
    self.label.stringValue = @"Press shortcut…";
    self.label.textColor = [CSTheme mutedText];
    self.layer.borderColor = [CSTheme accent].CGColor;
    self.layer.borderWidth = 2.0;
}

- (void)endRecording {
    self.recording = NO;
    self.layer.borderWidth = 1.0;
    self.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.9].CGColor;
    [self updateDisplay];
}

- (void)cancelRecording {
    self.recording = NO;
    [self endRecording];
}

- (BOOL)resignFirstResponder {
    if (self.recording) {
        [self endRecording];
    }
    return [super resignFirstResponder];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.recording && event.type == NSEventTypeKeyDown) {
        [self handleKeyEvent:event];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    if (!self.recording) {
        [super keyDown:event];
        return;
    }
    [self handleKeyEvent:event];
}

- (void)handleKeyEvent:(NSEvent *)event {
    unsigned short keyCode = event.keyCode;

    if (keyCode == 53) { // Esc
        [self cancelRecording];
        return;
    }
    // Ignore bare modifier presses.
    if (keyCode == 54 || keyCode == 55 || keyCode == 56 || keyCode == 57 ||
        keyCode == 58 || keyCode == 59 || keyCode == 60 || keyCode == 61 || keyCode == 62) {
        return;
    }

    UInt32 modifiers = [CSShortcut carbonModifiersFromEventFlags:event.modifierFlags];
    CSShortcut *shortcut = [CSShortcut shortcutWithKeyCode:keyCode modifiers:modifiers];
    if (![shortcut isValid]) {
        NSBeep();
        self.label.stringValue = @"Add ⌘, ⌥ or ⌃";
        self.label.textColor = [NSColor systemRedColor];
        return;
    }

    self.shortcut = shortcut;
    [self endRecording];
    if (self.onShortcutChange != nil) {
        self.onShortcutChange(shortcut);
    }
}

@end
