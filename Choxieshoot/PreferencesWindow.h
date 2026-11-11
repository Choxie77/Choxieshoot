#import <Cocoa/Cocoa.h>
#import "CSShortcut.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PreferencesWindowDelegate <NSObject>
- (CSShortcut *)preferencesCurrentShortcut;
- (BOOL)preferencesApplyShortcut:(CSShortcut *)shortcut errorMessage:(NSString * _Nullable * _Nullable)errorMessage;
- (void)preferencesGeneralSettingsChanged;
- (BOOL)preferencesScreenRecordingGranted;
- (void)preferencesGrantScreenRecording;
- (void)preferencesCheckScreenRecording;
- (void)preferencesRestartApplication;
- (void)preferencesResetScreenRecording;
@end

@interface PreferencesWindow : NSPanel

@property (nonatomic, copy, nullable) void (^onClose)(void);

- (instancetype)initWithDelegate:(id<PreferencesWindowDelegate>)delegate;

- (void)refreshFromSettings;

@end

NS_ASSUME_NONNULL_END
