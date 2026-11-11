#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A global shortcut (virtual key code + Carbon modifier mask).
@interface CSShortcut : NSObject

@property (nonatomic) unsigned short keyCode;
@property (nonatomic) UInt32 carbonModifiers;

+ (instancetype)defaultShortcut;
+ (nullable instancetype)savedShortcut;
+ (instancetype)shortcutWithKeyCode:(unsigned short)keyCode modifiers:(UInt32)modifiers;

- (void)save;
- (NSString *)displayString;
- (BOOL)isValid;

+ (NSString *)keyNameForKeyCode:(unsigned short)keyCode;
+ (UInt32)carbonModifiersFromEventFlags:(NSEventModifierFlags)flags;
+ (BOOL)isFunctionKeyCode:(unsigned short)keyCode;

@end

NS_ASSUME_NONNULL_END
