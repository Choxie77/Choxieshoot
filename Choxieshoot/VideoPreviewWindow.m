#import "VideoPreviewWindow.h"
#import "CSTheme.h"
#import "VideoCropOverlayView.h"
#import "VideoTimelineTrimmerView.h"
#import "VideoEditorEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <malloc/malloc.h>

@interface VideoPreviewWindow () <NSWindowDelegate, NSDraggingDestination>

@property (nonatomic, readwrite) NSURL *videoURL;
@property (nonatomic, strong, nullable) NSURL *lastSavedURL;
@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerView *playerView;
@property (nonatomic, strong, nullable) id timeObserver;
@property (nonatomic, strong, nullable) id endTimeObserver;
@property (nonatomic, strong, nullable) NSTextField *toastField;

@property (nonatomic, strong) NSView *headerBar;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *metaLabel;
@property (nonatomic, strong) NSTextField *statusBadge;

@property (nonatomic, strong) NSView *playerContainer;
@property (nonatomic, strong) VideoCropOverlayView *cropOverlay;
@property (nonatomic, strong) NSView *cropBar;
@property (nonatomic, strong) NSSegmentedControl *aspectSegment;
@property (nonatomic, strong) NSButton *cropSwapButton;
@property (nonatomic, strong) NSButton *cropCenterButton;
@property (nonatomic, strong) NSButton *cropFitButton;
@property (nonatomic, strong) NSButton *cropPreviewButton;
@property (nonatomic, strong) NSButton *cropResolutionButton;
@property (nonatomic, strong) NSButton *cropDoneButton;

@property (nonatomic, strong) VideoTimelineTrimmerView *timelineView;

@property (nonatomic, strong) NSView *bottomBar;
@property (nonatomic, strong) NSButton *recordNewButton;
@property (nonatomic, strong) NSButton *openVideoButton;
@property (nonatomic, strong) NSButton *cropButton;
@property (nonatomic, strong) NSButton *rotateButton;
@property (nonatomic, strong) NSButton *speedButton;
@property (nonatomic, strong) NSButton *audioButton;
@property (nonatomic, strong) NSButton *snapFrameButton;
@property (nonatomic, strong) NSButton *resetEditsButton;
@property (nonatomic, strong) NSButton *exportGifButton;
@property (nonatomic, strong) NSButton *revealInFinderButton;
@property (nonatomic, strong) NSButton *clipboardButton;
@property (nonatomic, strong) NSButton *saveMP4Button;
@property (nonatomic, strong) NSButton *minimizeButton;
@property (nonatomic, strong) NSButton *closeButton;

@property (nonatomic) BOOL loopPlayback;
@property (nonatomic, readwrite) NSSize videoNaturalSize;
@property (nonatomic, readwrite) NSTimeInterval duration;
@property (nonatomic, readwrite) NSTimeInterval trimStartTime;
@property (nonatomic, readwrite) NSTimeInterval trimEndTime;
@property (nonatomic, readwrite) CGRect cropPixelRect;
@property (nonatomic, readwrite) BOOL cropModeActive;
@property (nonatomic, readwrite) BOOL cropPreviewActive;
@property (nonatomic, readwrite) NSInteger rotationDegrees;
@property (nonatomic, readwrite) CGFloat playbackSpeed;
@property (nonatomic, readwrite) BOOL audioMuted;

@property (nonatomic) BOOL isExporting;
@property (nonatomic, strong, nullable) AVAssetExportSession *activeExportSession;
@property (nonatomic, copy, nullable) void (^activeExportCancelBlock)(void);
@property (nonatomic, strong, nullable) NSView *exportHUDView;
@property (nonatomic, strong, nullable) NSProgressIndicator *exportHUDProgress;
@property (nonatomic, strong, nullable) NSTextField *exportHUDLabel;

@end

@implementation VideoPreviewWindow

- (instancetype)initWithScreenRect:(NSRect)screenRect videoURL:(NSURL *)videoURL {
    _videoURL = videoURL;
    _loopPlayback = YES;
    _cropModeActive = NO;
    _cropPreviewActive = NO;
    _rotationDegrees = 0;
    _playbackSpeed = 1.0;
    _audioMuted = NO;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
    NSSize videoSize = screenRect.size;
    Float64 totalDuration = CMTimeGetSeconds(asset.duration);
    if (isnan(totalDuration) || isinf(totalDuration) || totalDuration <= 0) {
        totalDuration = 1.0;
    }
    _duration = totalDuration;
    _trimStartTime = 0.0;
    _trimEndTime = totalDuration;

    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        AVAssetTrack *track = videoTracks.firstObject;
        CGSize nat = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
        if (fabs(nat.width) >= 16.0 && fabs(nat.height) >= 16.0) {
            videoSize = NSMakeSize(fabs(nat.width), fabs(nat.height));
        }
    }
    _videoNaturalSize = videoSize;
    _cropPixelRect = CGRectMake(0, 0, videoSize.width, videoSize.height);

    NSScreen *targetScreen = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens]) {
        if (NSIntersectsRect(s.frame, screenRect)) {
            targetScreen = s;
            break;
        }
    }
    NSRect visible = targetScreen != nil ? targetScreen.visibleFrame : NSMakeRect(0, 0, 1440, 900);

    CGFloat maxVideoW = MAX(visible.size.width - 80.0, 520.0);
    CGFloat maxVideoH = MAX(visible.size.height - 240.0, 260.0);
    CGFloat scale = 1.0;
    if (screenRect.size.width > 0 && screenRect.size.height > 0) {
        videoSize = screenRect.size;
    }
    if (videoSize.width > 0) {
        scale = MIN(scale, maxVideoW / videoSize.width);
    }
    if (videoSize.height > 0) {
        scale = MIN(scale, maxVideoH / videoSize.height);
    }
    scale = MAX(scale, 0.1);

    NSSize displaySize = NSMakeSize(MAX(480.0, floor(videoSize.width * scale)),
                                    MAX(260.0, floor(videoSize.height * scale)));

    CGFloat contentWidth = MAX(displaySize.width + 32.0, 880.0);
    CGFloat headerHeight = 36.0;
    CGFloat timelineHeight = 56.0;
    CGFloat toolbarHeight = 50.0;
    CGFloat contentHeight = displaySize.height + headerHeight + timelineHeight + toolbarHeight + 20.0;

    CGFloat originX = floor(NSMidX(screenRect) - contentWidth / 2.0);
    CGFloat originY = floor(NSMidY(screenRect) - contentHeight / 2.0);
    originX = MIN(MAX(originX, NSMinX(visible) + 8.0), NSMaxX(visible) - contentWidth - 8.0);
    originY = MIN(MAX(originY, NSMinY(visible) + 8.0), NSMaxY(visible) - contentHeight - 8.0);

    self = [super initWithContentRect:NSMakeRect(originX, originY, contentWidth, contentHeight)
                            styleMask:(NSWindowStyleMaskTitled |
                                       NSWindowStyleMaskClosable |
                                       NSWindowStyleMaskMiniaturizable |
                                       NSWindowStyleMaskResizable |
                                       NSWindowStyleMaskFullSizeContentView |
                                       NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil) {
        return nil;
    }

    self.title = @"Video Studio & Editor";
    self.miniwindowTitle = @"Video Editor";
    self.minSize = NSMakeSize(760.0, 440.0);
    self.titlebarAppearsTransparent = YES;
    self.titleVisibility = NSWindowTitleHidden;
    self.floatingPanel = NO;
    self.becomesKeyOnlyIfNeeded = NO;
    self.worksWhenModal = YES;
    self.hidesOnDeactivate = NO;
    self.releasedWhenClosed = NO;
    self.opaque = NO;
    self.backgroundColor = [CSTheme surface];
    self.hasShadow = YES;
    self.level = NSNormalWindowLevel;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary);
    self.delegate = self;
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, (id)kUTTypeMovie]];
    [self enableTrafficLightMinimizeButton];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, contentHeight)];
    container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    container.wantsLayer = YES;
    container.layer.backgroundColor = [CSTheme surface].CGColor;
    container.layer.cornerRadius = CSRadiusLarge;
    container.layer.masksToBounds = YES;
    container.layer.borderWidth = 1.0;
    container.layer.borderColor = [[CSTheme border] colorWithAlphaComponent:0.75].CGColor;
    self.contentView = container;

    // Header bar (at top)
    self.headerBar = [[NSView alloc] initWithFrame:NSMakeRect(0, contentHeight - headerHeight, contentWidth, headerHeight)];
    self.headerBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [container addSubview:self.headerBar];

    NSImageView *videoIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(78, 9, 18, 18)];
    NSImage *vImg = [NSImage imageWithSystemSymbolName:@"film.stack" accessibilityDescription:@"Video Editor"];
    if (vImg == nil) {
        vImg = [NSImage imageWithSystemSymbolName:@"video.fill" accessibilityDescription:@"Video Editor"];
    }
    videoIcon.image = vImg;
    videoIcon.contentTintColor = [CSTheme accent];
    [self.headerBar addSubview:videoIcon];

    self.titleLabel = [NSTextField labelWithString:@"Video Studio & Editor"];
    self.titleLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.titleLabel.textColor = [CSTheme text];
    self.titleLabel.frame = NSMakeRect(102, 8, 150, 19);
    [self.headerBar addSubview:self.titleLabel];

    self.statusBadge = [NSTextField labelWithString:@""];
    self.statusBadge.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
    self.statusBadge.textColor = [CSTheme accent];
    self.statusBadge.frame = NSMakeRect(256, 8, 220, 18);
    [self.headerBar addSubview:self.statusBadge];

    self.metaLabel = [NSTextField labelWithString:[self metadataSummaryForAsset:asset url:videoURL]];
    self.metaLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    self.metaLabel.textColor = [CSTheme mutedText];
    self.metaLabel.alignment = NSTextAlignmentRight;
    self.metaLabel.autoresizingMask = NSViewMinXMargin;
    self.metaLabel.frame = NSMakeRect(480, 8, contentWidth - 496.0, 18);
    [self.headerBar addSubview:self.metaLabel];

    // Bottom action bar (at Y = 0)
    self.bottomBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, toolbarHeight)];
    self.bottomBar.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.bottomBar.wantsLayer = YES;
    self.bottomBar.layer.backgroundColor = [CSTheme controlSurface].CGColor;
    [container addSubview:self.bottomBar];

    [self setupBottomBarButtons];

    // Timeline Trimmer View (at Y = toolbarHeight = 50.0)
    CGFloat timelineY = toolbarHeight + 2.0;
    self.timelineView = [[VideoTimelineTrimmerView alloc] initWithFrame:NSMakeRect(16.0, timelineY, contentWidth - 32.0, timelineHeight)
                                                               duration:self.duration];
    self.timelineView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [container addSubview:self.timelineView];

    // Player Container
    CGFloat playerY = timelineY + timelineHeight + 8.0;
    CGFloat playerH = contentHeight - headerHeight - playerY - 6.0;
    self.playerContainer = [[NSView alloc] initWithFrame:NSMakeRect(16.0, playerY, contentWidth - 32.0, playerH)];
    self.playerContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.playerContainer.wantsLayer = YES;
    self.playerContainer.layer.cornerRadius = CSRadiusMedium;
    self.playerContainer.layer.masksToBounds = YES;
    self.playerContainer.layer.backgroundColor = [NSColor blackColor].CGColor;
    [container addSubview:self.playerContainer];

    // Video player
    self.player = [AVPlayer playerWithURL:videoURL];
    self.playerView = [[AVPlayerView alloc] initWithFrame:self.playerContainer.bounds];
    self.playerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.playerView.controlsStyle = AVPlayerViewControlsStyleNone;
    self.playerView.player = self.player;
    [self.playerContainer addSubview:self.playerView];

    // Crop Overlay positioned inside playerContainer
    self.cropOverlay = [[VideoCropOverlayView alloc] initWithFrame:self.playerContainer.bounds
                                                 videoNaturalSize:_videoNaturalSize];
    self.cropOverlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.cropOverlay.hidden = YES;
    [self.playerContainer addSubview:self.cropOverlay];

    __weak typeof(self) weakSelf = self;
    self.cropOverlay.onCropChanged = ^(CGRect pixelRect) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_cropPixelRect = pixelRect;
            [strongSelf updateCropUI];
            [strongSelf updateEditStatus];
        }
    };

    // Crop Control Bar (floating glassmorphic strip inside playerContainer)
    [self setupCropBar];

    // Wire up timeline trimmer callbacks
    self.timelineView.onSeek = ^(NSTimeInterval time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.player != nil) {
            CMTime seekTime = CMTimeMakeWithSeconds(time, 600);
            [strongSelf.player seekToTime:seekTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
    };

    self.timelineView.onTrimChanged = ^(NSTimeInterval startTime, NSTimeInterval endTime) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf.trimStartTime = startTime;
            strongSelf.trimEndTime = endTime;
            [strongSelf updateEditStatus];
        }
    };

    self.timelineView.onScrubbingStateChanged = ^(BOOL isScrubbing) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.player != nil) {
            if (isScrubbing) {
                [strongSelf.player pause];
            } else {
                if (strongSelf.loopPlayback) {
                    [strongSelf.player play];
                    strongSelf.player.rate = (float)strongSelf.playbackSpeed;
                    strongSelf.timelineView.isPlaying = YES;
                }
            }
        }
    };

    self.timelineView.onPlayPauseToggle = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.player == nil) { return; }
        if (strongSelf.player.rate > 0.0) {
            [strongSelf.player pause];
            strongSelf.timelineView.isPlaying = NO;
        } else {
            Float64 currentSec = CMTimeGetSeconds(strongSelf.player.currentTime);
            if (currentSec >= strongSelf.trimEndTime || currentSec < strongSelf.trimStartTime) {
                [strongSelf.player seekToTime:CMTimeMakeWithSeconds(strongSelf.trimStartTime, 600)];
            }
            [strongSelf.player play];
            strongSelf.player.rate = (float)strongSelf.playbackSpeed;
            strongSelf.timelineView.isPlaying = YES;
        }
    };

    // Periodic time observer on player
    CMTime interval = CMTimeMakeWithSeconds(0.04, 600);
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:interval
                                                                  queue:dispatch_get_main_queue()
                                                             usingBlock:^(CMTime time) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf.player == nil) { return; }

        Float64 currentSec = CMTimeGetSeconds(time);
        strongSelf.timelineView.currentTime = currentSec;

        if (strongSelf.loopPlayback) {
            if (currentSec >= strongSelf.trimEndTime) {
                CMTime loopStart = CMTimeMakeWithSeconds(strongSelf.trimStartTime, 600);
                [strongSelf.player seekToTime:loopStart toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                [strongSelf.player play];
                strongSelf.player.rate = (float)strongSelf.playbackSpeed;
            }
        }
    }];

    self.endTimeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:self.player.currentItem
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf != nil && strongSelf.loopPlayback && strongSelf.player != nil) {
                        CMTime loopStart = CMTimeMakeWithSeconds(strongSelf.trimStartTime, 600);
                        [strongSelf.player seekToTime:loopStart toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                        [strongSelf.player play];
                        strongSelf.player.rate = (float)strongSelf.playbackSpeed;
                    }
                }];

    [self updateAudioButtonAvailability];
    [self layoutToolbar];
    [self updateEditStatus];

    // Start playing
    [self.player play];
    self.player.rate = (float)self.playbackSpeed;
    self.timelineView.isPlaying = YES;

    return self;
}

- (void)updateAudioButtonAvailability {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.videoURL options:nil];
    BOOL hasAudio = ([asset tracksWithMediaType:AVMediaTypeAudio].count > 0);
    self.audioButton.enabled = hasAudio;
    if (!hasAudio) {
        self.audioButton.title = @"No Audio";
        self.audioButton.toolTip = @"Source video has no audio track";
    }
}

- (void)setupBottomBarButtons {
    self.recordNewButton = [self buttonWithTitle:@"New"
                                          symbol:@"video.badge.plus"
                                         tooltip:@"Record a new video (⌘N)"
                                          action:@selector(newRecordingClicked:)];
    [self.bottomBar addSubview:self.recordNewButton];

    self.openVideoButton = [self buttonWithTitle:@"Open…"
                                          symbol:@"folder"
                                         tooltip:@"Open an existing video to edit (⌘O)"
                                          action:@selector(openVideoClicked:)];
    [self.bottomBar addSubview:self.openVideoButton];

    self.cropButton = [self buttonWithTitle:@"Crop"
                                     symbol:@"crop"
                                    tooltip:@"Toggle visual video crop mode (C)"
                                     action:@selector(toggleCropMode:)];
    [self.bottomBar addSubview:self.cropButton];

    self.rotateButton = [self buttonWithTitle:@"Rotate"
                                       symbol:@"rotate.right"
                                      tooltip:@"Rotate video 90° clockwise (R)"
                                       action:@selector(rotateClicked:)];
    [self.bottomBar addSubview:self.rotateButton];

    self.speedButton = [self buttonWithTitle:@"1.0×"
                                      symbol:@"bolt.fill"
                                     tooltip:@"Playback speed (0.5× – 2.0×)"
                                      action:@selector(cycleSpeedClicked:)];
    [self.bottomBar addSubview:self.speedButton];

    self.audioButton = [self buttonWithTitle:@"Audio"
                                      symbol:@"speaker.wave.2.fill"
                                     tooltip:@"Toggle audio mute for playback and export (M)"
                                      action:@selector(toggleMuteClicked:)];
    [self.bottomBar addSubview:self.audioButton];

    self.snapFrameButton = [self buttonWithTitle:@"Snap"
                                          symbol:@"camera"
                                         tooltip:@"Capture current still frame to clipboard (⌘⇧C)"
                                          action:@selector(captureFrameClicked:)];
    [self.bottomBar addSubview:self.snapFrameButton];

    self.resetEditsButton = [self buttonWithTitle:@"Reset"
                                           symbol:@"arrow.uturn.backward"
                                          tooltip:@"Reset trim, crop, rotation, speed, and audio"
                                           action:@selector(resetEdits:)];
    [self.bottomBar addSubview:self.resetEditsButton];

    self.exportGifButton = [self buttonWithTitle:@"GIF…"
                                          symbol:@"film"
                                         tooltip:@"Export trimmed & cropped clip as animated GIF (⌘G)"
                                          action:@selector(exportGifClicked:)];
    [self.bottomBar addSubview:self.exportGifButton];

    self.revealInFinderButton = [self buttonWithTitle:@"Finder"
                                              symbol:@"magnifyingglass"
                                             tooltip:@"Reveal video file in Finder"
                                              action:@selector(revealInFinderClicked:)];
    [self.bottomBar addSubview:self.revealInFinderButton];

    self.clipboardButton = [self buttonWithTitle:@"Copy Video"
                                         symbol:@"doc.on.doc"
                                        tooltip:@"Copy cut & cropped video to clipboard (⌘C)"
                                         action:@selector(copyClicked:)];
    [self.bottomBar addSubview:self.clipboardButton];

    self.saveMP4Button = [self buttonWithTitle:@"Save MP4…"
                                        symbol:@"square.and.arrow.down"
                                       tooltip:@"Export cut & cropped video (⌘S)"
                                        action:@selector(saveClicked:)];
    self.saveMP4Button.bezelColor = [CSTheme accent];
    [self.bottomBar addSubview:self.saveMP4Button];

    self.minimizeButton = [self buttonWithTitle:@"Minimize"
                                         symbol:@"minus"
                                        tooltip:@"Minimize window (⌘M)"
                                         action:@selector(minimizeClicked:)];
    [self.bottomBar addSubview:self.minimizeButton];

    self.closeButton = [self buttonWithTitle:@"Cancel"
                                      symbol:@"xmark"
                                     tooltip:@"Close window (Esc / ⌘W)"
                                      action:@selector(closeClicked:)];
    [self.bottomBar addSubview:self.closeButton];
}

- (void)setupCropBar {
    CGFloat cropW = 660.0;
    CGFloat cropH = 36.0;
    CGFloat playerW = NSWidth(self.playerContainer.bounds);
    CGFloat playerH = NSHeight(self.playerContainer.bounds);

    self.cropBar = [[NSView alloc] initWithFrame:NSMakeRect(floor((playerW - cropW) / 2.0), playerH - cropH - 10.0, cropW, cropH)];
    self.cropBar.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin;
    self.cropBar.wantsLayer = YES;
    self.cropBar.layer.backgroundColor = [[CSTheme elevatedSurface] colorWithAlphaComponent:0.94].CGColor;
    self.cropBar.layer.cornerRadius = CSRadiusSmall;
    self.cropBar.layer.borderWidth = 1.0;
    self.cropBar.layer.borderColor = [[CSTheme accent] colorWithAlphaComponent:0.75].CGColor;
    self.cropBar.hidden = YES;
    [self.playerContainer addSubview:self.cropBar];

    NSArray *segments = @[@"Free", @"16:9", @"9:16", @"1:1", @"4:5", @"4:3", @"21:9", @"Orig"];
    self.aspectSegment = [NSSegmentedControl segmentedControlWithLabels:segments
                                                           trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                 target:self
                                                                 action:@selector(aspectSegmentChanged:)];
    self.aspectSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    self.aspectSegment.selectedSegment = 0;
    self.aspectSegment.frame = NSMakeRect(8.0, 6.0, 310.0, 24.0);
    [self.cropBar addSubview:self.aspectSegment];

    // Flip orientation button
    self.cropSwapButton = [NSButton buttonWithTitle:@"⇄" target:self action:@selector(swapOrientationClicked:)];
    self.cropSwapButton.bezelStyle = NSBezelStyleInline;
    self.cropSwapButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightBold];
    self.cropSwapButton.toolTip = @"Swap width and height orientation (⇄)";
    self.cropSwapButton.frame = NSMakeRect(324.0, 6.0, 30.0, 24.0);
    [self.cropBar addSubview:self.cropSwapButton];

    // Center crop button
    self.cropCenterButton = [NSButton buttonWithTitle:@"⊙" target:self action:@selector(centerCropClicked:)];
    self.cropCenterButton.bezelStyle = NSBezelStyleInline;
    self.cropCenterButton.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightBold];
    self.cropCenterButton.toolTip = @"Center crop box in video";
    self.cropCenterButton.frame = NSMakeRect(358.0, 6.0, 30.0, 24.0);
    [self.cropBar addSubview:self.cropCenterButton];

    // Fit button
    self.cropFitButton = [NSButton buttonWithTitle:@"Fit" target:self action:@selector(cropFitClicked:)];
    self.cropFitButton.bezelStyle = NSBezelStyleInline;
    self.cropFitButton.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    self.cropFitButton.toolTip = @"Reset crop to full video frame";
    self.cropFitButton.frame = NSMakeRect(392.0, 6.0, 40.0, 24.0);
    [self.cropBar addSubview:self.cropFitButton];

    // Live preview toggle button
    self.cropPreviewButton = [NSButton buttonWithTitle:@"Preview" target:self action:@selector(toggleCropPreview:)];
    self.cropPreviewButton.bezelStyle = NSBezelStyleInline;
    self.cropPreviewButton.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
    self.cropPreviewButton.toolTip = @"Preview cropped video framed in player";
    self.cropPreviewButton.frame = NSMakeRect(436.0, 6.0, 60.0, 24.0);
    [self.cropBar addSubview:self.cropPreviewButton];

    // Resolution button / preset cycler
    self.cropResolutionButton = [NSButton buttonWithTitle:@"1920×1080" target:self action:@selector(resolutionPresetClicked:)];
    self.cropResolutionButton.bezelStyle = NSBezelStyleInline;
    self.cropResolutionButton.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
    self.cropResolutionButton.toolTip = @"Click to cycle standard resolution presets (1080p, 720p, 540p, Square)";
    self.cropResolutionButton.frame = NSMakeRect(500.0, 6.0, 92.0, 24.0);
    [self.cropBar addSubview:self.cropResolutionButton];

    // Done button
    self.cropDoneButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(cropDoneClicked:)];
    self.cropDoneButton.bezelStyle = NSBezelStyleInline;
    self.cropDoneButton.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
    self.cropDoneButton.frame = NSMakeRect(596.0, 6.0, 52.0, 24.0);
    [self.cropBar addSubview:self.cropDoneButton];
}

- (void)aspectSegmentChanged:(NSSegmentedControl *)sender {
    NSInteger sel = sender.selectedSegment;
    CSVideoCropAspect aspect = CSVideoCropAspectFreeform;
    switch (sel) {
        case 1: aspect = CSVideoCropAspect16_9; break;
        case 2: aspect = CSVideoCropAspect9_16; break;
        case 3: aspect = CSVideoCropAspect1_1; break;
        case 4: aspect = CSVideoCropAspect4_5; break;
        case 5: aspect = CSVideoCropAspect4_3; break;
        case 6: aspect = CSVideoCropAspect21_9; break;
        case 7: aspect = CSVideoCropAspectOriginal; break;
        case 0:
        default:
            aspect = CSVideoCropAspectFreeform;
            break;
    }
    self.cropOverlay.aspectPreset = aspect;
    [self updateCropUI];
}

- (void)swapOrientationClicked:(id)sender {
    [self.cropOverlay swapOrientation];
    [self updateCropUI];
    [self updateEditStatus];
    [self showToast:[NSString stringWithFormat:@"Aspect: %@", [self.cropOverlay aspectRatioTitle]]];
}

- (void)centerCropClicked:(id)sender {
    [self.cropOverlay centerCropInVideo];
    [self updateCropUI];
    [self updateEditStatus];
    [self showToast:@"Centered crop box"];
}

- (void)cropFitClicked:(id)sender {
    [self.cropOverlay resetToFullVideo];
    self.aspectSegment.selectedSegment = 0;
    [self updateCropUI];
    [self updateEditStatus];
    [self showToast:@"Fit crop to full video"];
}

- (void)resolutionPresetClicked:(id)sender {
    CGRect px = [self.cropOverlay pixelCropRect];
    // Cycle standard presets based on current width
    if (px.size.width >= 1920) {
        [self.cropOverlay setPixelCropSize:NSMakeSize(1280, 720)];
    } else if (px.size.width >= 1280) {
        [self.cropOverlay setPixelCropSize:NSMakeSize(960, 540)];
    } else if (px.size.width >= 960) {
        [self.cropOverlay setPixelCropSize:NSMakeSize(1080, 1080)];
    } else {
        [self.cropOverlay resetToFullVideo];
    }
    [self updateCropUI];
    [self updateEditStatus];
}

- (void)cropDoneClicked:(id)sender {
    [self toggleCropMode:nil];
}

- (void)updateCropUI {
    CGRect px = [self.cropOverlay pixelCropRect];
    _cropPixelRect = px;
    self.cropResolutionButton.title = [NSString stringWithFormat:@"%ld×%ld",
                                       (long)px.size.width, (long)px.size.height];
}

- (void)updateEditStatus {
    BOOL isTrimmed = [self.timelineView isTrimmed];
    BOOL isCropped = [self.cropOverlay isCropped];
    BOOL isRotated = (self.rotationDegrees != 0);
    BOOL isSped = (fabs(self.playbackSpeed - 1.0) > 0.05);
    BOOL isMuted = self.audioMuted;

    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if (isTrimmed) {
        NSTimeInterval cut = self.duration - [self.timelineView trimmedDuration];
        [tags addObject:[NSString stringWithFormat:@"✂ Cut %.1fs", cut]];
    }
    if (isCropped) {
        CGRect px = [self.cropOverlay pixelCropRect];
        [tags addObject:[NSString stringWithFormat:@"⛶ Crop %ld×%ld", (long)px.size.width, (long)px.size.height]];
    }
    if (isRotated) {
        [tags addObject:[NSString stringWithFormat:@"↷ %ld°", (long)self.rotationDegrees]];
    }
    if (isSped) {
        [tags addObject:[NSString stringWithFormat:@"⚡ %.2g×", self.playbackSpeed]];
    }
    if (isMuted) {
        [tags addObject:@"🔇 Muted"];
    }

    if (tags.count > 0) {
        self.statusBadge.stringValue = [NSString stringWithFormat:@"[%@]", [tags componentsJoinedByString:@" · "]];
        self.resetEditsButton.enabled = YES;
    } else {
        self.statusBadge.stringValue = @"";
        self.resetEditsButton.enabled = NO;
    }
}

- (NSButton *)buttonWithTitle:(NSString *)title
                       symbol:(nullable NSString *)symbol
                      tooltip:(nullable NSString *)tooltip
                       action:(SEL)action {
    NSButton *btn = [NSButton buttonWithTitle:title target:self action:action];
    btn.bezelStyle = NSBezelStyleRounded;
    btn.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold];
    if (symbol != nil) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        if (img != nil) {
            btn.image = img;
            btn.imagePosition = NSImageLeading;
        }
    }
    if (tooltip != nil) {
        btn.toolTip = tooltip;
        [btn setAccessibilityLabel:tooltip];
    }
    return btn;
}

- (void)layoutToolbar {
    if (self.bottomBar == nil) {
        return;
    }
    CGFloat totalW = NSWidth(self.bottomBar.bounds);
    if (totalW <= 0) {
        return;
    }

    CGFloat btnH = 28.0;
    CGFloat btnY = 11.0;
    CGFloat gap = 4.0;

    // Compact button widths
    CGFloat newW = 54.0;
    CGFloat openW = 58.0;
    CGFloat cropW = 52.0;
    CGFloat rotW = 58.0;
    CGFloat spdW = 48.0;
    CGFloat audW = 56.0;
    CGFloat snapW = 52.0;
    CGFloat resetW = 54.0;

    // Left buttons
    CGFloat x = 12.0;
    self.recordNewButton.frame = NSMakeRect(x, btnY, newW, btnH);
    x += newW + gap;

    self.openVideoButton.frame = NSMakeRect(x, btnY, openW, btnH);
    x += openW + gap + 3.0; // slight group gap

    self.cropButton.frame = NSMakeRect(x, btnY, cropW, btnH);
    x += cropW + gap;

    self.rotateButton.frame = NSMakeRect(x, btnY, rotW, btnH);
    x += rotW + gap;

    self.speedButton.frame = NSMakeRect(x, btnY, spdW, btnH);
    x += spdW + gap;

    self.audioButton.frame = NSMakeRect(x, btnY, audW, btnH);
    x += audW + gap;

    // Right-to-left layout for essential right buttons first
    CGFloat rightX = totalW - 12.0;

    CGFloat cancelW = 54.0;
    self.closeButton.frame = NSMakeRect(rightX - cancelW, btnY, cancelW, btnH);
    rightX -= (cancelW + gap);

    CGFloat saveW = 86.0;
    self.saveMP4Button.frame = NSMakeRect(rightX - saveW, btnY, saveW, btnH);
    rightX -= (saveW + gap);

    CGFloat copyW = 78.0;
    self.clipboardButton.frame = NSMakeRect(rightX - copyW, btnY, copyW, btnH);
    rightX -= (copyW + gap);

    // Optional GIF export button
    CGFloat gifW = 54.0;
    if (rightX - gifW > x + snapW + resetW + 12.0) {
        self.exportGifButton.hidden = NO;
        self.exportGifButton.frame = NSMakeRect(rightX - gifW, btnY, gifW, btnH);
        rightX -= (gifW + gap);
    } else {
        self.exportGifButton.hidden = YES;
    }

    // Optional Reveal in Finder
    CGFloat revealW = 62.0;
    if (rightX - revealW > x + snapW + resetW + 12.0 && totalW >= 880.0) {
        self.revealInFinderButton.hidden = NO;
        self.revealInFinderButton.frame = NSMakeRect(rightX - revealW, btnY, revealW, btnH);
        rightX -= (revealW + gap);
    } else {
        self.revealInFinderButton.hidden = YES;
    }

    // Optional Minimize button
    CGFloat minW = 68.0;
    if (rightX - minW > x + snapW + resetW + 12.0 && totalW >= 940.0) {
        self.minimizeButton.hidden = NO;
        self.minimizeButton.frame = NSMakeRect(rightX - minW, btnY, minW, btnH);
        rightX -= (minW + gap);
    } else {
        self.minimizeButton.hidden = YES;
    }

    // Left auxiliary buttons: snapFrame and resetEdits
    if (x + snapW + resetW + 6.0 <= rightX) {
        self.snapFrameButton.hidden = NO;
        self.snapFrameButton.frame = NSMakeRect(x, btnY, snapW, btnH);
        x += snapW + gap;

        self.resetEditsButton.hidden = NO;
        self.resetEditsButton.frame = NSMakeRect(x, btnY, resetW, btnH);
    } else if (x + resetW + 6.0 <= rightX) {
        self.snapFrameButton.hidden = YES;
        self.resetEditsButton.hidden = NO;
        self.resetEditsButton.frame = NSMakeRect(x, btnY, resetW, btnH);
    } else {
        self.snapFrameButton.hidden = YES;
        self.resetEditsButton.hidden = YES;
    }
}

- (void)layoutHeader {
    if (self.headerBar == nil || self.metaLabel == nil) {
        return;
    }
    CGFloat totalW = NSWidth(self.headerBar.bounds);
    self.metaLabel.frame = NSMakeRect(480, 8, MAX(120.0, totalW - 496.0), 18);
}

- (void)windowDidResize:(NSNotification *)notification {
    [self layoutToolbar];
    [self layoutHeader];
}

- (NSString *)metadataSummaryForAsset:(AVURLAsset *)asset url:(NSURL *)url {
    NSInteger w = 0;
    NSInteger h = 0;
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count > 0) {
        AVAssetTrack *track = videoTracks.firstObject;
        CGSize nat = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
        w = (NSInteger)llround(fabs(nat.width));
        h = (NSInteger)llround(fabs(nat.height));
    }
    Float64 seconds = CMTimeGetSeconds(asset.duration);
    if (isnan(seconds) || isinf(seconds) || seconds < 0) {
        seconds = 0;
    }
    NSNumber *fileSizeNum = nil;
    [url getResourceValue:&fileSizeNum forKey:NSURLFileSizeKey error:nil];
    double kb = fileSizeNum.doubleValue / 1024.0;
    NSString *sizeStr = (kb >= 1024.0)
        ? [NSString stringWithFormat:@"%.1f MB", kb / 1024.0]
        : [NSString stringWithFormat:@"%.0f KB", MAX(1.0, kb)];

    BOOL hasAudio = ([asset tracksWithMediaType:AVMediaTypeAudio].count > 0);
    return [NSString stringWithFormat:@"%ld×%ld  ·  %.1fs  ·  %@  ·  MP4%@",
            (long)w, (long)h, seconds, sizeStr, hasAudio ? @" + Audio" : @""];
}

#pragma mark - Video Loading & Drag Drop

- (BOOL)loadVideoURL:(NSURL *)newURL {
    if (newURL == nil || ![[NSFileManager defaultManager] fileExistsAtPath:newURL.path]) {
        return NO;
    }
    self.videoURL = newURL;
    self.lastSavedURL = nil;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:newURL options:nil];
    Float64 totalDuration = CMTimeGetSeconds(asset.duration);
    if (isnan(totalDuration) || isinf(totalDuration) || totalDuration <= 0) {
        totalDuration = 1.0;
    }
    self.duration = totalDuration;
    self.trimStartTime = 0.0;
    self.trimEndTime = totalDuration;

    NSSize videoSize = NSMakeSize(1280, 720);
    NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count > 0) {
        AVAssetTrack *tr = tracks.firstObject;
        CGSize nat = CGSizeApplyAffineTransform(tr.naturalSize, tr.preferredTransform);
        if (fabs(nat.width) >= 16.0 && fabs(nat.height) >= 16.0) {
            videoSize = NSMakeSize(fabs(nat.width), fabs(nat.height));
        }
    }
    self.videoNaturalSize = videoSize;
    _cropPixelRect = CGRectMake(0, 0, videoSize.width, videoSize.height);

    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    [self.player replaceCurrentItemWithPlayerItem:item];

    if (self.endTimeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.endTimeObserver];
        self.endTimeObserver = nil;
    }
    __weak typeof(self) weakSelf = self;
    self.endTimeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:self.player.currentItem
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (strongSelf != nil && strongSelf.loopPlayback && strongSelf.player != nil) {
                        CMTime loopStart = CMTimeMakeWithSeconds(strongSelf.trimStartTime, 600);
                        [strongSelf.player seekToTime:loopStart toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
                        [strongSelf.player play];
                        strongSelf.player.rate = (float)strongSelf.playbackSpeed;
                    }
                }];

    self.cropOverlay.videoNaturalSize = videoSize;
    [self.cropOverlay resetToFullVideo];

    self.timelineView.duration = totalDuration;
    [self.timelineView resetTrim];

    self.metaLabel.stringValue = [self metadataSummaryForAsset:asset url:newURL];
    self.title = [NSString stringWithFormat:@"Video Editor — %@", newURL.lastPathComponent];
    [self updateCropUI];
    [self updateAudioButtonAvailability];
    [self updateEditStatus];

    [self.player seekToTime:kCMTimeZero];
    [self.player play];
    self.player.rate = (float)self.playbackSpeed;
    self.timelineView.isPlaying = YES;
    return YES;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    if ([pboard.types containsObject:NSPasteboardTypeFileURL]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pboard = [sender draggingPasteboard];
    NSArray *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:nil];
    if (urls.count > 0) {
        NSURL *fileURL = urls.firstObject;
        NSString *ext = fileURL.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) {
            return [self loadVideoURL:fileURL];
        }
    }
    return NO;
}

#pragma mark - Editing & Tools

- (void)toggleCropMode:(nullable id)sender {
    self.cropModeActive = !self.cropModeActive;
    self.cropOverlay.cropActive = self.cropModeActive;
    self.cropOverlay.hidden = !self.cropModeActive;
    self.cropBar.hidden = !self.cropModeActive;

    if (self.cropModeActive) {
        self.cropButton.state = NSControlStateValueOn;
        self.cropButton.bezelColor = [CSTheme accent];
        [self showToast:@"Crop Mode: Drag box · 8 Presets · ⇄ Flip · ⊙ Center"];
    } else {
        self.cropButton.state = NSControlStateValueOff;
        self.cropButton.bezelColor = nil;
        if (self.cropPreviewActive) {
            [self toggleCropPreview:nil];
        }
    }
    [self updateEditStatus];
}

- (void)toggleCropPreview:(nullable id)sender {
    self.cropPreviewActive = !self.cropPreviewActive;
    if (self.cropPreviewActive) {
        self.cropOverlay.hidden = YES;
        self.cropPreviewButton.state = NSControlStateValueOn;
        self.cropPreviewButton.bezelColor = [CSTheme accent];
        [self applyCropPreviewZoom];
        [self showToast:@"Crop Preview (Playing Framed Output)"];
    } else {
        self.cropOverlay.hidden = !self.cropModeActive;
        self.cropPreviewButton.state = NSControlStateValueOff;
        self.cropPreviewButton.bezelColor = nil;
        self.playerView.frame = self.playerContainer.bounds;
        [self showToast:@"Crop Edit Mode"];
    }
}

- (void)applyCropPreviewZoom {
    NSRect cBounds = self.playerContainer.bounds;
    NSRect crop = [self.cropOverlay displayCropRect];
    if (crop.size.width <= 0 || crop.size.height <= 0 || cBounds.size.width <= 0 || cBounds.size.height <= 0) {
        return;
    }

    CGFloat scale = MIN(cBounds.size.width / crop.size.width, cBounds.size.height / crop.size.height);
    CGFloat scaledW = cBounds.size.width * scale;
    CGFloat scaledH = cBounds.size.height * scale;

    CGFloat cropMidX = NSMidX(crop);
    CGFloat cropMidY = NSMidY(crop);

    CGFloat newX = (cBounds.size.width / 2.0) - (cropMidX * scale);
    CGFloat newY = (cBounds.size.height / 2.0) - (cropMidY * scale);

    self.playerView.frame = NSMakeRect(floor(newX), floor(newY), floor(scaledW), floor(scaledH));
}

- (void)rotateClicked:(nullable id)sender {
    self.rotationDegrees = (self.rotationDegrees + 90) % 360;
    [self applyRotationPreview];
    [self updateEditStatus];
    [self showToast:[NSString stringWithFormat:@"Rotated %ld° CW", (long)self.rotationDegrees]];
}

- (void)setRotationDegrees:(NSInteger)degrees {
    _rotationDegrees = ((degrees % 360) + 360) % 360;
    [self applyRotationPreview];
    [self updateEditStatus];
}

- (void)applyRotationPreview {
    if (self.rotationDegrees != 0) {
        self.rotateButton.title = [NSString stringWithFormat:@"%ld°", (long)self.rotationDegrees];
        self.rotateButton.bezelColor = [CSTheme accent];
    } else {
        self.rotateButton.title = @"Rotate";
        self.rotateButton.bezelColor = nil;
    }
}

- (void)cycleSpeedClicked:(nullable id)sender {
    NSArray<NSNumber *> *speeds = @[@(0.5), @(0.75), @(1.0), @(1.25), @(1.5), @(2.0)];
    NSUInteger idx = 2; // 1.0
    for (NSUInteger i = 0; i < speeds.count; i++) {
        if (fabs(speeds[i].doubleValue - self.playbackSpeed) < 0.05) {
            idx = i;
            break;
        }
    }
    idx = (idx + 1) % speeds.count;
    [self setPlaybackSpeed:speeds[idx].doubleValue];
}

- (void)setPlaybackSpeed:(CGFloat)speed {
    _playbackSpeed = (speed >= 0.25 && speed <= 4.0) ? speed : 1.0;
    self.speedButton.title = [NSString stringWithFormat:@"%.2g×", _playbackSpeed];
    if (fabs(_playbackSpeed - 1.0) > 0.05) {
        self.speedButton.bezelColor = [CSTheme accent];
    } else {
        self.speedButton.bezelColor = nil;
    }
    if (self.player.rate > 0.0) {
        self.player.rate = (float)_playbackSpeed;
    }
    [self updateEditStatus];
    [self showToast:[NSString stringWithFormat:@"Playback Speed: %.2g×", _playbackSpeed]];
}

- (void)toggleMuteClicked:(nullable id)sender {
    [self setAudioMuted:!self.audioMuted];
}

- (void)setAudioMuted:(BOOL)muted {
    _audioMuted = muted;
    self.player.muted = muted;
    if (_audioMuted) {
        self.audioButton.title = @"Muted";
        self.audioButton.image = [NSImage imageWithSystemSymbolName:@"speaker.slash.fill" accessibilityDescription:@"Audio Muted"];
        self.audioButton.bezelColor = [NSColor systemRedColor];
        [self showToast:@"Audio Muted (Silent Video)"];
    } else {
        self.audioButton.title = @"Audio";
        self.audioButton.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:@"Audio On"];
        self.audioButton.bezelColor = nil;
        [self showToast:@"Audio Enabled"];
    }
    [self updateEditStatus];
}

- (void)captureFrameClicked:(nullable id)sender {
    NSImage *img = [self currentFrameImage];
    if (img == nil) {
        [self showToast:@"Could not capture frame"];
        return;
    }

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[img]];

    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[img TIFFRepresentation]];
    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *filename = [NSString stringWithFormat:@"Video Frame %@.png", [df stringFromDate:[NSDate date]]];
    NSURL *destURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:filename];
    [pngData writeToURL:destURL atomically:YES];
    [pb setPropertyList:@[destURL.path] forType:NSFilenamesPboardType];

    [self showToast:[NSString stringWithFormat:@"Captured frame %.0f×%.0f to clipboard", img.size.width, img.size.height]];
}

- (nullable NSImage *)currentFrameImage {
    Float64 sec = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(sec) || sec < 0) sec = 0.0;
    return [VideoEditorEngine captureFrameAtURL:self.videoURL
                                         atTime:sec
                                       cropRect:self.cropPixelRect
                                       rotation:self.rotationDegrees
                                          error:nil];
}

- (void)resetEdits:(nullable id)sender {
    [self.timelineView resetTrim];
    self.trimStartTime = 0.0;
    self.trimEndTime = self.duration;

    [self.cropOverlay resetToFullVideo];
    self.aspectSegment.selectedSegment = 0;
    [self updateCropUI];

    self.rotationDegrees = 0;
    [self applyRotationPreview];

    self.playbackSpeed = 1.0;
    self.speedButton.title = @"1.0×";
    self.speedButton.bezelColor = nil;
    if (self.player.rate > 0.0) {
        self.player.rate = 1.0;
    }

    self.audioMuted = NO;
    self.player.muted = NO;
    self.audioButton.title = @"Audio";
    self.audioButton.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2.fill" accessibilityDescription:@"Audio On"];
    self.audioButton.bezelColor = nil;

    if (self.cropPreviewActive) {
        [self toggleCropPreview:nil];
    }

    [self updateEditStatus];
    [self showToast:@"Reset all edits"];
}

- (void)setTrimStart:(NSTimeInterval)start end:(NSTimeInterval)end {
    self.trimStartTime = MAX(0.0, start);
    self.trimEndTime = MIN(self.duration, end);
    self.timelineView.trimStartTime = self.trimStartTime;
    self.timelineView.trimEndTime = self.trimEndTime;
    [self updateEditStatus];
}

- (void)setCropPixelRect:(CGRect)pixelRect {
    [self.cropOverlay setPixelCropRect:pixelRect];
    _cropPixelRect = [self.cropOverlay pixelCropRect];
    [self updateCropUI];
    [self updateEditStatus];
}

- (nullable AVAssetExportSession *)exportEditedVideoToURL:(NSURL *)destinationURL
                                          progressHandler:(nullable void (^)(float progress))progressHandler
                                               completion:(void (^)(BOOL success, NSError * _Nullable error))completion {
    return [VideoEditorEngine exportVideoAtURL:self.videoURL
                                 trimStartTime:self.trimStartTime
                                   trimEndTime:self.trimEndTime
                                      cropRect:self.cropPixelRect
                                      rotation:self.rotationDegrees
                                 playbackSpeed:self.playbackSpeed
                                     muteAudio:self.audioMuted
                                destinationURL:destinationURL
                               progressHandler:progressHandler
                               completionQueue:dispatch_get_main_queue()
                                    completion:completion];
}

- (BOOL)saveVideoToURL:(NSURL *)destinationURL error:(NSError * _Nullable * _Nullable)error {
    if (destinationURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"com.choxieshoot"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"Destination URL cannot be nil."}];
        }
        return NO;
    }

    if (destinationURL.pathExtension.length == 0) {
        destinationURL = [destinationURL URLByAppendingPathExtension:@"mp4"];
    }

    BOOL ok = [VideoEditorEngine exportVideoSynchronousAtURL:self.videoURL
                                               trimStartTime:self.trimStartTime
                                                 trimEndTime:self.trimEndTime
                                                    cropRect:self.cropPixelRect
                                                    rotation:self.rotationDegrees
                                               playbackSpeed:self.playbackSpeed
                                                   muteAudio:self.audioMuted
                                              destinationURL:destinationURL
                                                       error:error];
    if (ok) {
        self.lastSavedURL = destinationURL;
    }
    return ok;
}

- (BOOL)saveGifToURL:(NSURL *)destinationURL error:(NSError * _Nullable * _Nullable)error {
    if (destinationURL == nil) return NO;
    if (![destinationURL.pathExtension.lowercaseString isEqualToString:@"gif"]) {
        destinationURL = [destinationURL URLByAppendingPathExtension:@"gif"];
    }
    return [VideoEditorEngine exportGifSynchronousAtURL:self.videoURL
                                          trimStartTime:self.trimStartTime
                                            trimEndTime:self.trimEndTime
                                               cropRect:self.cropPixelRect
                                               rotation:self.rotationDegrees
                                          playbackSpeed:self.playbackSpeed
                                                    fps:15.0
                                         destinationURL:destinationURL
                                                  error:error];
}

#pragma mark - Actions

- (void)openVideoClicked:(nullable id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.title = @"Open Video to Edit";
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypeMPEG4Movie, UTTypeQuickTimeMovie];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"mp4", @"mov", @"m4v"];
#pragma clang diagnostic pop
    }

    [self.player pause];
    [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL != nil) {
            [self loadVideoURL:panel.URL];
            [self showToast:[NSString stringWithFormat:@"Opened %@", panel.URL.lastPathComponent]];
        }
    }];
}

- (void)showExportHUDWithTitle:(NSString *)title {
    if (self.exportHUDView != nil) {
        [self.exportHUDView removeFromSuperview];
        self.exportHUDView = nil;
    }

    NSView *container = self.contentView;
    if (container == nil) return;

    NSView *hud = [[NSView alloc] initWithFrame:container.bounds];
    hud.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    hud.wantsLayer = YES;
    hud.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.65].CGColor;
    hud.layer.zPosition = 200;

    CGFloat boxW = 280.0;
    CGFloat boxH = 140.0;
    CGFloat boxX = floor((NSWidth(hud.bounds) - boxW) / 2.0);
    CGFloat boxY = floor((NSHeight(hud.bounds) - boxH) / 2.0);

    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(boxX, boxY, boxW, boxH)];
    box.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    box.wantsLayer = YES;
    box.layer.cornerRadius = 12.0;
    box.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:0.95].CGColor;
    box.layer.borderColor = [[NSColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    box.layer.borderWidth = 1.0;
    [hud addSubview:box];

    NSTextField *titleLabel = [NSTextField labelWithString:title ?: @"Exporting…"];
    titleLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    titleLabel.textColor = [NSColor whiteColor];
    titleLabel.alignment = NSTextAlignmentCenter;
    titleLabel.frame = NSMakeRect(16.0, boxH - 36.0, boxW - 32.0, 20.0);
    [box addSubview:titleLabel];
    self.exportHUDLabel = titleLabel;

    NSProgressIndicator *prog = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24.0, boxH - 68.0, boxW - 48.0, 12.0)];
    prog.indeterminate = NO;
    prog.minValue = 0.0;
    prog.maxValue = 1.0;
    prog.doubleValue = 0.0;
    prog.style = NSProgressIndicatorStyleBar;
    [box addSubview:prog];
    self.exportHUDProgress = prog;

    NSButton *cancelBtn = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelActiveExport)];
    cancelBtn.bezelStyle = NSBezelStyleRounded;
    cancelBtn.frame = NSMakeRect(floor((boxW - 90.0) / 2.0), 16.0, 90.0, 28.0);
    [box addSubview:cancelBtn];

    [container addSubview:hud];
    self.exportHUDView = hud;
}

- (void)updateExportHUDProgress:(float)progress {
    if (self.exportHUDProgress != nil) {
        self.exportHUDProgress.doubleValue = (double)progress;
    }
}

- (void)hideExportHUD {
    if (self.exportHUDView != nil) {
        [self.exportHUDView removeFromSuperview];
        self.exportHUDView = nil;
        self.exportHUDProgress = nil;
        self.exportHUDLabel = nil;
    }
}

- (void)cancelActiveExport {
    if (!self.isExporting) {
        return;
    }
    fprintf(stderr, "[VideoPreviewWindow] User cancelled active export\n");
    if (self.activeExportSession != nil) {
        [self.activeExportSession cancelExport];
        self.activeExportSession = nil;
    }
    if (self.activeExportCancelBlock != nil) {
        self.activeExportCancelBlock();
        self.activeExportCancelBlock = nil;
    }
    self.isExporting = NO;
    [self hideExportHUD];
    [self showToast:@"Export cancelled"];
}

- (void)saveClicked:(nullable id)sender {
    if (self.videoURL == nil) {
        [self showToast:@"No video to save"];
        return;
    }
    if (self.isExporting) {
        [self showToast:@"Export already in progress"];
        return;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [self makeKeyAndOrderFront:nil];
    [self.player pause];
    self.timelineView.isPlaying = NO;

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.showsTagField = YES;
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypeMPEG4Movie, UTTypeQuickTimeMovie];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"mp4", @"mov"];
#pragma clang diagnostic pop
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    NSString *dateStr = [df stringFromDate:[NSDate date]];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"Video %@[Edited].mp4", dateStr];

    NSButton *copyCheckbox = [NSButton checkboxWithTitle:@"Also copy to clipboard" target:nil action:nil];
    copyCheckbox.state = NSControlStateValueOff;
    panel.accessoryView = copyCheckbox;

    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSURL *destURL = panel.URL;
        if (destURL.pathExtension.length == 0) {
            destURL = [destURL URLByAppendingPathExtension:@"mp4"];
        }

        strongSelf.isExporting = YES;
        [strongSelf showExportHUDWithTitle:@"Exporting MP4…"];

        strongSelf.activeExportSession = [strongSelf exportEditedVideoToURL:destURL
                           progressHandler:^(float progress) {
            [strongSelf updateExportHUDProgress:progress];
        }
                                completion:^(BOOL success, NSError * _Nullable error) {
            [strongSelf hideExportHUD];
            strongSelf.isExporting = NO;
            strongSelf.activeExportSession = nil;

            if (error != nil && error.code == NSUserCancelledError) {
                [strongSelf showToast:@"Export cancelled"];
                return;
            }

            if (!success) {
                if (strongSelf.isVisible && strongSelf.contentView != nil) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Could not save video";
                    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred while exporting.";
                    [alert beginSheetModalForWindow:strongSelf completionHandler:nil];
                }
                return;
            }

            strongSelf.lastSavedURL = destURL;
            BOOL alsoCopy = (copyCheckbox.state == NSControlStateValueOn);
            if (alsoCopy) {
                [strongSelf copyTargetURLToPasteboard:destURL];
                [strongSelf showToast:[NSString stringWithFormat:@"Saved & copied %@", destURL.lastPathComponent]];
            } else {
                [strongSelf showToast:[NSString stringWithFormat:@"Saved %@", destURL.lastPathComponent]];
            }

            strongSelf.title = [NSString stringWithFormat:@"Video Editor — %@", destURL.lastPathComponent];
            strongSelf.miniwindowTitle = destURL.lastPathComponent;
        }];
    }];
}

- (void)exportGifClicked:(nullable id)sender {
    if (self.videoURL == nil) {
        [self showToast:@"No video to export"];
        return;
    }
    if (self.isExporting) {
        [self showToast:@"Export already in progress"];
        return;
    }

    [NSApp activateIgnoringOtherApps:YES];
    [self makeKeyAndOrderFront:nil];
    [self.player pause];
    self.timelineView.isPlaying = NO;

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.title = @"Export Animated GIF";
    if (@available(macOS 11.0, *)) {
        panel.allowedContentTypes = @[UTTypeGIF];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"gif"];
#pragma clang diagnostic pop
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd 'at' HH.mm.ss";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"Video %@.gif", [df stringFromDate:[NSDate date]]];

    NSButton *copyCheckbox = [NSButton checkboxWithTitle:@"Also copy GIF to clipboard" target:nil action:nil];
    copyCheckbox.state = NSControlStateValueOn;
    panel.accessoryView = copyCheckbox;

    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self completionHandler:^(NSModalResponse result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || result != NSModalResponseOK || panel.URL == nil) {
            return;
        }

        NSURL *destURL = panel.URL;
        if (![destURL.pathExtension.lowercaseString isEqualToString:@"gif"]) {
            destURL = [destURL URLByAppendingPathExtension:@"gif"];
        }

        strongSelf.isExporting = YES;
        [strongSelf showExportHUDWithTitle:@"Creating GIF…"];

        strongSelf.activeExportCancelBlock = [VideoEditorEngine exportGifAtURL:strongSelf.videoURL
                            trimStartTime:strongSelf.trimStartTime
                              trimEndTime:strongSelf.trimEndTime
                                 cropRect:strongSelf.cropPixelRect
                                 rotation:strongSelf.rotationDegrees
                            playbackSpeed:strongSelf.playbackSpeed
                                      fps:15.0
                           destinationURL:destURL
                          progressHandler:^(float progress) {
            [strongSelf updateExportHUDProgress:progress];
        }
                          completionQueue:dispatch_get_main_queue()
                               completion:^(BOOL success, NSError * _Nullable error) {
            [strongSelf hideExportHUD];
            strongSelf.isExporting = NO;
            strongSelf.activeExportCancelBlock = nil;

            if (error != nil && error.code == NSUserCancelledError) {
                [strongSelf showToast:@"GIF export cancelled"];
                return;
            }

            if (!success) {
                if (strongSelf.isVisible && strongSelf.contentView != nil) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Could not export GIF";
                    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
                    [alert beginSheetModalForWindow:strongSelf completionHandler:nil];
                }
                return;
            }

            if (copyCheckbox.state == NSControlStateValueOn) {
                [strongSelf copyTargetURLToPasteboard:destURL];
                [strongSelf showToast:[NSString stringWithFormat:@"Exported & copied %@", destURL.lastPathComponent]];
            } else {
                [strongSelf showToast:[NSString stringWithFormat:@"Exported %@", destURL.lastPathComponent]];
            }
        }];
    }];
}

- (void)copyVideoForTesting {
    [self copyClicked:nil];
}

- (void)copyTargetURLToPasteboard:(NSURL *)targetURL {
    if (targetURL == nil) {
        return;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[targetURL]];
    [pb setPropertyList:@[targetURL.path] forType:NSFilenamesPboardType];
}

- (void)copyClicked:(nullable id)sender {
    if (self.videoURL == nil) {
        [self showToast:@"No video to copy"];
        return;
    }
    if (self.isExporting) {
        [self showToast:@"Export already in progress"];
        return;
    }

    BOOL isTrimmed = [self.timelineView isTrimmed];
    BOOL isCropped = [self.cropOverlay isCropped];
    BOOL isRotated = (self.rotationDegrees != 0);
    BOOL isSped = (fabs(self.playbackSpeed - 1.0) > 0.05);
    BOOL isMuted = self.audioMuted;

    if (!isTrimmed && !isCropped && !isRotated && !isSped && !isMuted) {
        NSURL *targetURL = self.lastSavedURL ?: self.videoURL;
        [self copyTargetURLToPasteboard:targetURL];
        [self showToast:@"Copied video to clipboard"];
        return;
    }

    NSString *tempName = [NSString stringWithFormat:@"choxieshoot-edit-%@.mp4", [[NSUUID UUID] UUIDString]];
    NSURL *tempDest = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:tempName];

    self.isExporting = YES;
    [self showExportHUDWithTitle:@"Preparing video…"];
    __weak typeof(self) weakSelf = self;
    self.activeExportSession = [self exportEditedVideoToURL:tempDest
                 progressHandler:^(float progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf updateExportHUDProgress:progress];
        }
    }
                      completion:^(BOOL success, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [strongSelf hideExportHUD];
        strongSelf.isExporting = NO;
        strongSelf.activeExportSession = nil;

        if (error != nil && error.code == NSUserCancelledError) {
            [strongSelf showToast:@"Copy cancelled"];
            return;
        }

        if (!success) {
            [strongSelf showToast:@"Could not copy video"];
            return;
        }
        [strongSelf copyTargetURLToPasteboard:tempDest];
        [strongSelf showToast:@"Copied edited video to clipboard"];
    }];
}

- (void)revealInFinderClicked:(nullable id)sender {
    NSURL *targetURL = self.lastSavedURL ?: self.videoURL;
    if (targetURL != nil && [[NSFileManager defaultManager] fileExistsAtPath:targetURL.path]) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[targetURL]];
    } else {
        [self showToast:@"Video file not found"];
    }
}

- (void)newRecordingClicked:(nullable id)sender {
    void (^block)(void) = self.onNewRecording;
    [self close];
    if (block != nil) {
        block();
    }
}

- (void)enableTrafficLightMinimizeButton {
    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    if (miniBtn != nil) {
        miniBtn.enabled = YES;
        miniBtn.target = self;
        miniBtn.action = @selector(minimizeClicked:);
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

- (void)windowDidBecomeKey:(NSNotification *)notification {
    [self enableTrafficLightMinimizeButton];
}

- (void)minimizeClicked:(id)sender {
    [self.player pause];
    self.timelineView.isPlaying = NO;
    self.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary);
    [super miniaturize:sender];
}

- (void)performMiniaturize:(id)sender {
    [self minimizeClicked:sender];
}

- (void)closeClicked:(id)sender {
    [self close];
}

- (void)showToast:(NSString *)message {
    if (self.toastField != nil) {
        [self.toastField removeFromSuperview];
        self.toastField = nil;
    }
    NSTextField *toast = [NSTextField labelWithString:message];
    toast.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    toast.textColor = [CSTheme toastText];
    toast.alignment = NSTextAlignmentCenter;
    toast.wantsLayer = YES;
    toast.layer.zPosition = 100;
    toast.layer.backgroundColor = [CSTheme toastBackground].CGColor;
    toast.layer.cornerRadius = 14.0;
    toast.layer.borderWidth = 1.0;
    toast.layer.borderColor = [[CSTheme accent] colorWithAlphaComponent:0.6].CGColor;

    NSSize textSize = [toast.stringValue sizeWithAttributes:@{NSFontAttributeName: toast.font}];
    CGFloat w = textSize.width + 28.0;
    CGFloat h = 28.0;
    NSView *container = self.contentView;
    toast.frame = NSMakeRect(floor((NSWidth(container.bounds) - w) / 2.0), 66.0, w, h);
    [container addSubview:toast];
    self.toastField = toast;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (self.toastField == toast) {
            [toast removeFromSuperview];
            self.toastField = nil;
        }
    });
}

#pragma mark - Keyboard & Window lifecycle

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    NSUInteger flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;

    if (event.keyCode == 53) { // Escape
        if (self.isExporting) {
            [self cancelActiveExport];
            return;
        }
        if (self.cropPreviewActive) {
            [self toggleCropPreview:nil];
            return;
        }
        if (self.cropModeActive) {
            [self toggleCropMode:nil];
            return;
        }
        [self close];
        return;
    }

    if (event.keyCode == 49 && flags == 0) { // Spacebar toggles playback
        if (self.player.rate > 0.0) {
            [self.player pause];
            self.timelineView.isPlaying = NO;
        } else {
            Float64 currentSec = CMTimeGetSeconds(self.player.currentTime);
            if (currentSec >= self.trimEndTime || currentSec < self.trimStartTime) {
                [self.player seekToTime:CMTimeMakeWithSeconds(self.trimStartTime, 600)];
            }
            [self.player play];
            self.player.rate = (float)self.playbackSpeed;
            self.timelineView.isPlaying = YES;
        }
        return;
    }

    if (event.keyCode == 123) { // Left arrow
        [self.timelineView stepFrames:-1 fps:30.0];
        return;
    }
    if (event.keyCode == 124) { // Right arrow
        [self.timelineView stepFrames:1 fps:30.0];
        return;
    }

    if (flags == 0) {
        if ([chars isEqualToString:@"["] || [chars isEqualToString:@"i"]) {
            [self.timelineView setInPointToCurrentTime];
            [self showToast:@"Set In-Point (Cut Start)"];
            return;
        }
        if ([chars isEqualToString:@"]"] || [chars isEqualToString:@"o"]) {
            [self.timelineView setOutPointToCurrentTime];
            [self showToast:@"Set Out-Point (Cut End)"];
            return;
        }
        if ([chars isEqualToString:@"c"]) {
            [self toggleCropMode:nil];
            return;
        }
        if ([chars isEqualToString:@"r"]) {
            [self rotateClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"m"]) {
            [self toggleMuteClicked:nil];
            return;
        }
    }

    if ((flags & NSEventModifierFlagCommand) != 0) {
        if ((flags & NSEventModifierFlagShift) != 0 && [chars isEqualToString:@"c"]) {
            [self captureFrameClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"s"]) {
            [self saveClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"g"]) {
            [self exportGifClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"c"]) {
            [self copyClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"o"]) {
            [self openVideoClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"w"]) {
            [self close];
            return;
        }
        if ([chars isEqualToString:@"m"]) {
            [self minimizeClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"n"]) {
            [self newRecordingClicked:nil];
            return;
        }
        if ([chars isEqualToString:@"z"]) {
            [self resetEdits:nil];
            return;
        }
    }

    [super keyDown:event];
}

- (void)close {
    if (self.isExporting) {
        [self cancelActiveExport];
    }
    [self orderOut:nil];

    if (self.timeObserver != nil && self.player != nil) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    if (self.endTimeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.endTimeObserver];
        self.endTimeObserver = nil;
    }

    if (self.player != nil) {
        [self.player pause];
        [self.player replaceCurrentItemWithPlayerItem:nil];
    }
    if (self.playerView != nil) {
        self.playerView.player = nil;
        self.playerView = nil;
    }
    self.player = nil;

    NSButton *miniBtn = [self standardWindowButton:NSWindowMiniaturizeButton];
    miniBtn.target = nil;
    self.onNewRecording = nil;
    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    VideoPreviewCloseBlock closeBlock = self.onClose;
    self.onClose = nil;
    [super close];
    if (closeBlock != nil) {
        closeBlock(self);
    }
    malloc_zone_pressure_relief(NULL, 0);
}

- (void)windowWillClose:(NSNotification *)notification {
    VideoPreviewCloseBlock closeBlock = self.onClose;
    self.onClose = nil;
    if (closeBlock != nil) {
        closeBlock(self);
    }
}

- (void)dealloc {
    if (self.timeObserver != nil && self.player != nil) {
        [self.player removeTimeObserver:self.timeObserver];
        self.timeObserver = nil;
    }
    if (self.endTimeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.endTimeObserver];
        self.endTimeObserver = nil;
    }
}

@end
