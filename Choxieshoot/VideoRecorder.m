#import "VideoRecorder.h"
#import "ChoxieshootPreferences.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <malloc/malloc.h>

static CGRect CGRectForScreenRect(NSRect nsRect) {
    NSScreen *primary = [NSScreen screens].firstObject;
    if (primary == nil) {
        return NSRectToCGRect(nsRect);
    }
    CGFloat primaryHeight = primary.frame.size.height;
    CGFloat cgY = primaryHeight - NSMaxY(nsRect);
    return CGRectMake(NSMinX(nsRect), cgY, NSWidth(nsRect), NSHeight(nsRect));
}

static CGPathRef CreateMacCursorPath(CGFloat size) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat s = size / 22.0;
    CGPathMoveToPoint(path, NULL, 0, 0);
    CGPathAddLineToPoint(path, NULL, 0, -21.0 * s);
    CGPathAddLineToPoint(path, NULL, 5.5 * s, -16.5 * s);
    CGPathAddLineToPoint(path, NULL, 10.0 * s, -24.5 * s);
    CGPathAddLineToPoint(path, NULL, 13.5 * s, -22.5 * s);
    CGPathAddLineToPoint(path, NULL, 9.0 * s, -14.5 * s);
    CGPathAddLineToPoint(path, NULL, 15.5 * s, -14.5 * s);
    CGPathCloseSubpath(path);
    return path;
}

static void DrawCursorAtContextPoint(CGContextRef ctx, CGPoint pt, CGFloat size, CGFloat alpha) {
    CGPathRef path = CreateMacCursorPath(size);
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, pt.x, pt.y);

    if (alpha > 0.45) {
        CGContextSetShadowWithColor(ctx, CGSizeMake(1.5, -2.5), 3.5, [NSColor colorWithWhite:0.0 alpha:0.35 * alpha].CGColor);
    } else {
        CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    }

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, alpha);
    CGContextAddPath(ctx, path);
    CGContextFillPath(ctx);

    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    CGContextSetRGBStrokeColor(ctx, 0.06, 0.06, 0.08, alpha);
    CGContextSetLineWidth(ctx, MAX(1.2, size / 16.0));
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextAddPath(ctx, path);
    CGContextStrokePath(ctx);

    CGContextRestoreGState(ctx);
    CGPathRelease(path);
}

static void ApplyMotionBlurToPixelBuffer(
    uint8_t * __restrict baseAddress,
    size_t width,
    size_t height,
    size_t bytesPerRow,
    uint8_t * __restrict prevRaw,
    uint8_t * __restrict history,
    BOOL *hasHistory,
    CSVideoMotionBlurMode mode
) {
    if (mode == CSVideoMotionBlurModeOff || baseAddress == NULL || prevRaw == NULL || history == NULL) {
        return;
    }

    float blendFactor = 0.32f;
    if (mode == CSVideoMotionBlurModeCinematic) {
        blendFactor = 0.45f;
    } else if (mode == CSVideoMotionBlurModeHeavy) {
        blendFactor = 0.58f;
    }

    uint32_t wHist = (uint32_t)(blendFactor * 256.0f + 0.5f);
    uint32_t wCurr = 256 - wHist;

    if (!(*hasHistory)) {
        for (size_t y = 0; y < height; y++) {
            uint8_t *rowSrc = baseAddress + y * bytesPerRow;
            uint8_t *rowHist = history + y * width * 4;
            uint8_t *rowRaw = prevRaw + y * width * 4;
            memcpy(rowHist, rowSrc, width * 4);
            memcpy(rowRaw, rowSrc, width * 4);
        }
        *hasHistory = YES;
        return;
    }

    const int threshold = 12;
    size_t chunks = 4;
    size_t rowsPerChunk = (height + chunks - 1) / chunks;

    dispatch_apply(chunks, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^(size_t c) {
        size_t yStart = c * rowsPerChunk;
        size_t yEnd = MIN(height, yStart + rowsPerChunk);
        for (size_t y = yStart; y < yEnd; y++) {
            uint8_t *rowSrc = baseAddress + y * bytesPerRow;
            uint8_t *rowHist = history + y * width * 4;
            uint8_t *rowRaw = prevRaw + y * width * 4;

            for (size_t x = 0; x < width; x++) {
                size_t i = x * 4;
                uint8_t cb = rowSrc[i];
                uint8_t cg = rowSrc[i+1];
                uint8_t cr = rowSrc[i+2];

                uint8_t rb = rowRaw[i];
                uint8_t rg = rowRaw[i+1];
                uint8_t rr = rowRaw[i+2];

                int d = abs((int)cb - (int)rb) + abs((int)cg - (int)rg) + abs((int)cr - (int)rr);

                rowRaw[i]   = cb;
                rowRaw[i+1] = cg;
                rowRaw[i+2] = cr;

                if (d <= threshold) {
                    rowHist[i]   = cb;
                    rowHist[i+1] = cg;
                    rowHist[i+2] = cr;
                } else {
                    uint8_t hb = rowHist[i];
                    uint8_t hg = rowHist[i+1];
                    uint8_t hr = rowHist[i+2];

                    uint8_t nb = (uint8_t)(((uint32_t)cb * wCurr + (uint32_t)hb * wHist + 128) >> 8);
                    uint8_t ng = (uint8_t)(((uint32_t)cg * wCurr + (uint32_t)hg * wHist + 128) >> 8);
                    uint8_t nr = (uint8_t)(((uint32_t)cr * wCurr + (uint32_t)hr * wHist + 128) >> 8);

                    rowSrc[i]   = nb;
                    rowSrc[i+1] = ng;
                    rowSrc[i+2] = nr;

                    rowHist[i]   = nb;
                    rowHist[i+1] = ng;
                    rowHist[i+2] = nr;
                }
            }
        }
    });
}

@interface VideoRecorder () <AVCaptureAudioDataOutputSampleBufferDelegate>

@property (nonatomic, readwrite) NSRect screenRect;
@property (nonatomic, readwrite) BOOL recordMicrophone;
@property (nonatomic, readwrite) BOOL isRecording;
@property (nonatomic, readwrite) BOOL isPaused;
@property (nonatomic, readwrite, nullable) NSURL *outputURL;

@property (nonatomic, readwrite) NSInteger fps;
@property (nonatomic, readwrite) CSVideoMotionBlurMode motionBlurMode;
@property (nonatomic, readwrite) BOOL recordCursor;
@property (nonatomic, readwrite) BOOL cursorMotionBlur;

@property (nonatomic, strong, nullable) AVAssetWriter *assetWriter;
@property (nonatomic, strong, nullable) AVAssetWriterInput *videoInput;
@property (nonatomic, strong, nullable) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;
@property (nonatomic, strong, nullable) AVAssetWriterInput *audioInput;
@property (nonatomic, strong, nullable) AVCaptureSession *audioSession;
@property (nonatomic, strong, nullable) AVCaptureAudioDataOutput *audioOutput;

@property (nonatomic, strong) dispatch_queue_t writerQueue;
@property (nonatomic, strong, nullable) dispatch_source_t frameTimer;

@property (nonatomic) CGRect captureCGRect;
@property (nonatomic) NSInteger outputWidth;
@property (nonatomic) NSInteger outputHeight;
@property (nonatomic) CFTimeInterval startTime;
@property (nonatomic) CFTimeInterval pauseStartTime;
@property (nonatomic) CFTimeInterval totalPausedDuration;
@property (nonatomic) int64_t lastFrameTick;
@property (nonatomic) NSInteger framesWritten;
@property (nonatomic) CMTime firstAudioSourcePTS;
@property (nonatomic) BOOL hasFirstAudioPTS;

@property (nonatomic) uint8_t *motionPrevRawBuffer;
@property (nonatomic) uint8_t *motionHistoryBuffer;
@property (nonatomic) BOOL hasMotionHistory;

@property (nonatomic) CGPoint lastCursorPoint;
@property (nonatomic) BOOL hasLastCursorPoint;

@end

@implementation VideoRecorder

+ (void)requestMicrophoneAccessIfNeeded:(void (^)(BOOL granted))completion {
    if (getenv("CS_TEST_MODE") != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO);
            }
        });
        return;
    }
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (status == AVAuthorizationStatusAuthorized) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(YES);
            }
        });
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(granted);
                }
            });
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO);
            }
        });
    }
}

- (instancetype)initWithScreenRect:(NSRect)screenRect
                  recordMicrophone:(BOOL)recordMicrophone
              excludeAboveWindowID:(CGWindowID)excludeAboveWindowID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger fps = [defaults integerForKey:CSVideoFPSKey];
    if (fps <= 0) {
        fps = 60;
    }
    NSInteger blurMode = [defaults objectForKey:CSVideoMotionBlurKey]
        ? [defaults integerForKey:CSVideoMotionBlurKey]
        : CSVideoMotionBlurModeSubtle;
    if (blurMode < 0 || blurMode > 3) {
        blurMode = CSVideoMotionBlurModeSubtle;
    }
    BOOL recordCursor = [defaults objectForKey:CSVideoRecordCursorKey]
        ? [defaults boolForKey:CSVideoRecordCursorKey]
        : YES;
    BOOL cursorBlur = [defaults objectForKey:CSVideoCursorMotionBlurKey]
        ? [defaults boolForKey:CSVideoCursorMotionBlurKey]
        : YES;

    return [self initWithScreenRect:screenRect
                   recordMicrophone:recordMicrophone
               excludeAboveWindowID:excludeAboveWindowID
                                fps:fps
                     motionBlurMode:(CSVideoMotionBlurMode)blurMode
                       recordCursor:recordCursor
                   cursorMotionBlur:cursorBlur];
}

- (instancetype)initWithScreenRect:(NSRect)screenRect
                  recordMicrophone:(BOOL)recordMicrophone
              excludeAboveWindowID:(CGWindowID)excludeAboveWindowID
                               fps:(NSInteger)fps
                    motionBlurMode:(CSVideoMotionBlurMode)motionBlurMode
                      recordCursor:(BOOL)recordCursor
                  cursorMotionBlur:(BOOL)cursorMotionBlur {
    self = [super init];
    if (self) {
        _screenRect = screenRect;
        _recordMicrophone = recordMicrophone;
        _excludeAboveWindowID = excludeAboveWindowID;
        _fps = (fps >= 60) ? 60 : 30;
        _motionBlurMode = motionBlurMode;
        _recordCursor = recordCursor;
        _cursorMotionBlur = cursorMotionBlur;
        _captureCGRect = CGRectForScreenRect(screenRect);
        _writerQueue = dispatch_queue_create("com.choxieshoot.videorecorder.queue", DISPATCH_QUEUE_SERIAL);
        _lastFrameTick = -1;
    }
    return self;
}

- (NSTimeInterval)elapsedSeconds {
    if (!self.isRecording || self.startTime <= 0) {
        return 0.0;
    }
    CFTimeInterval now = self.isPaused ? self.pauseStartTime : CACurrentMediaTime();
    CFTimeInterval elapsed = (now - self.startTime) - self.totalPausedDuration;
    return MAX(0.0, elapsed);
}

- (BOOL)startRecordingWithError:(NSError * _Nullable * _Nullable)error {
    if (self.isRecording) {
        return YES;
    }

    // Determine backing scale for the target screen
    CGFloat scale = 2.0;
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSIntersectsRect(screen.frame, self.screenRect)) {
            scale = MAX(1.0, screen.backingScaleFactor);
            break;
        }
    }

    NSInteger rawW = (NSInteger)llround(NSWidth(self.screenRect) * scale);
    NSInteger rawH = (NSInteger)llround(NSHeight(self.screenRect) * scale);
    // Cap maximum dimension to 3840 for smooth real-time H.264 encoding
    if (rawW > 3840 || rawH > 3840) {
        CGFloat downscale = 3840.0 / (CGFloat)MAX(rawW, rawH);
        rawW = (NSInteger)llround(rawW * downscale);
        rawH = (NSInteger)llround(rawH * downscale);
    }
    // H.264 requires even dimensions >= 64
    rawW = MAX(64, (rawW / 2) * 2);
    rawH = MAX(64, (rawH / 2) * 2);
    self.outputWidth = rawW;
    self.outputHeight = rawH;

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *filename = [NSString stringWithFormat:@"Choxieshoot-Recording-%@.mp4", [uuid substringToIndex:8]];
    NSURL *tempURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:filename];
    [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
    self.outputURL = tempURL;

    NSError *writerError = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:tempURL fileType:AVFileTypeMPEG4 error:&writerError];
    if (writer == nil) {
        if (error) {
            *error = writerError;
        }
        return NO;
    }

    NSInteger fps = (self.fps >= 60) ? 60 : 30;
    self.fps = fps;

    NSInteger bitRate = MAX(2000000, rawW * rawH * (fps >= 60 ? 6 : 4));
    NSDictionary *compressionProps = @{
        AVVideoAverageBitRateKey: @(bitRate),
        AVVideoMaxKeyFrameIntervalKey: @(fps),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: @(fps)
    };
    NSDictionary *videoSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(rawW),
        AVVideoHeightKey: @(rawH),
        AVVideoCompressionPropertiesKey: compressionProps
    };

    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                        outputSettings:videoSettings];
    videoInput.expectsMediaDataInRealTime = YES;
    if (![writer canAddInput:videoInput]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.choxieshoot.videorecorder"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot add H.264 video input to asset writer."}];
        }
        return NO;
    }
    [writer addInput:videoInput];

    NSDictionary *pixelBufferAttrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(rawW),
        (id)kCVPixelBufferHeightKey: @(rawH),
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoInput
                                                                         sourcePixelBufferAttributes:pixelBufferAttrs];

    // Optional microphone setup
    if (self.recordMicrophone && getenv("CS_TEST_MODE") == NULL) {
        [self setupMicrophoneInputForWriter:writer];
    }

    if (![writer startWriting]) {
        if (error) {
            *error = writer.error ?: [NSError errorWithDomain:@"com.choxieshoot.videorecorder"
                                                         code:102
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to start writing MP4 file."}];
        }
        return NO;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    self.assetWriter = writer;
    self.videoInput = videoInput;
    self.pixelBufferAdaptor = adaptor;
    self.startTime = CACurrentMediaTime();
    self.totalPausedDuration = 0.0;
    self.pauseStartTime = 0.0;
    self.lastFrameTick = -1;
    self.framesWritten = 0;
    self.hasFirstAudioPTS = NO;
    self.isPaused = NO;
    self.isRecording = YES;

    // Allocate motion blur buffers if enabled
    if (self.motionBlurMode != CSVideoMotionBlurModeOff) {
        size_t bufSize = (size_t)rawW * (size_t)rawH * 4;
        self.motionPrevRawBuffer = malloc(bufSize);
        self.motionHistoryBuffer = malloc(bufSize);
        self.hasMotionHistory = NO;
    }
    self.hasLastCursorPoint = NO;

    if (self.audioSession != nil) {
        [self.audioSession startRunning];
    }

    // Start frame capture timer on writerQueue at target FPS
    __weak typeof(self) weakSelf = self;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.writerQueue);
    uint64_t interval = NSEC_PER_SEC / (uint64_t)fps;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf captureNextFrameOnQueue];
    });
    self.frameTimer = timer;
    dispatch_resume(timer);

    return YES;
}

- (void)setupMicrophoneInputForWriter:(AVAssetWriter *)writer {
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (authStatus != AVAuthorizationStatusAuthorized) {
        return;
    }
    AVCaptureDevice *micDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (micDevice == nil) {
        return;
    }
    NSError *inputErr = nil;
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:micDevice error:&inputErr];
    if (deviceInput == nil || inputErr != nil) {
        return;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    if (![session canAddInput:deviceInput]) {
        return;
    }
    [session addInput:deviceInput];

    AVCaptureAudioDataOutput *audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [audioOutput setSampleBufferDelegate:self queue:self.writerQueue];
    if (![session canAddOutput:audioOutput]) {
        return;
    }
    [session addOutput:audioOutput];

    NSDictionary *audioSettings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @(44100.0),
        AVNumberOfChannelsKey: @(1),
        AVEncoderBitRateKey: @(128000)
    };
    AVAssetWriterInput *audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                              outputSettings:audioSettings];
    audioWriterInput.expectsMediaDataInRealTime = YES;
    if ([writer canAddInput:audioWriterInput]) {
        [writer addInput:audioWriterInput];
        self.audioInput = audioWriterInput;
        self.audioSession = session;
        self.audioOutput = audioOutput;
    }
}

- (void)captureNextFrameOnQueue {
    @autoreleasepool {
        if (!self.isRecording || self.isPaused) {
            return;
        }
        if (self.assetWriter.status != AVAssetWriterStatusWriting) {
            return;
        }

        CFTimeInterval now = CACurrentMediaTime();
        CFTimeInterval elapsed = MAX(0.0, (now - self.startTime) - self.totalPausedDuration);
        int64_t tick = (int64_t)llround(elapsed * (double)self.fps);
        if (tick <= self.lastFrameTick) {
            tick = self.lastFrameTick + 1;
        }

        if (self.videoInput.isReadyForMoreMediaData) {
            CMTime presentationTime = CMTimeMake(tick, (int32_t)self.fps);
            if ([self appendFrameAtTime:presentationTime frameIndex:self.framesWritten]) {
                self.lastFrameTick = tick;
                self.framesWritten++;
            }
        }

        NSInteger updateInterval = MAX(3, self.fps / 5);
        if (self.onDurationUpdate != nil && (self.framesWritten % updateInterval == 0)) {
            void (^cb)(NSTimeInterval) = self.onDurationUpdate;
            dispatch_async(dispatch_get_main_queue(), ^{
                cb(elapsed);
            });
        }
    }
}

- (void)drawCursorInContext:(CGContextRef)ctx {
    if (!self.recordCursor) {
        return;
    }

    NSPoint mouseLoc = [NSEvent mouseLocation];
    NSRect expandedArea = NSInsetRect(self.screenRect, -40, -40);
    if (!NSPointInRect(mouseLoc, expandedArea)) {
        self.hasLastCursorPoint = NO;
        return;
    }

    CGFloat scaleX = (CGFloat)self.outputWidth / NSWidth(self.screenRect);
    CGFloat scaleY = (CGFloat)self.outputHeight / NSHeight(self.screenRect);
    CGPoint currPt = CGPointMake((mouseLoc.x - NSMinX(self.screenRect)) * scaleX,
                                 (mouseLoc.y - NSMinY(self.screenRect)) * scaleY);

    CGFloat cursorScale = (scaleX + scaleY) / 2.0;
    CGFloat cursorSize = 22.0 * cursorScale;

    // Subtle click halo when primary mouse button is pressed
    NSUInteger buttons = [NSEvent pressedMouseButtons];
    BOOL isPressed = (buttons & 1) != 0;
    if (isPressed) {
        CGContextSaveGState(ctx);
        CGContextSetRGBFillColor(ctx, 0.18, 0.65, 0.98, 0.32);
        CGContextSetRGBStrokeColor(ctx, 0.18, 0.65, 0.98, 0.85);
        CGContextSetLineWidth(ctx, 1.5 * cursorScale);
        CGFloat ringR = 14.0 * cursorScale;
        CGRect clickRing = CGRectMake(currPt.x - ringR, currPt.y - ringR, ringR * 2.0, ringR * 2.0);
        CGContextFillEllipseInRect(ctx, clickRing);
        CGContextStrokeEllipseInRect(ctx, clickRing);
        CGContextRestoreGState(ctx);
    }

    if (self.cursorMotionBlur && self.hasLastCursorPoint) {
        CGFloat dx = currPt.x - self.lastCursorPoint.x;
        CGFloat dy = currPt.y - self.lastCursorPoint.y;
        CGFloat dist = hypot(dx, dy);

        if (dist > 3.5) {
            int steps = (int)MIN(7, MAX(2, dist / 22.0));
            for (int i = 0; i < steps; i++) {
                CGFloat t = (CGFloat)i / (CGFloat)steps;
                CGPoint pt = CGPointMake(self.lastCursorPoint.x + dx * t, self.lastCursorPoint.y + dy * t);
                CGFloat alpha = 0.12 + 0.48 * t;
                DrawCursorAtContextPoint(ctx, pt, cursorSize, alpha);
            }
        }
    }

    DrawCursorAtContextPoint(ctx, currPt, cursorSize, 1.0);

    self.lastCursorPoint = currPt;
    self.hasLastCursorPoint = YES;
}

- (void)cleanupMotionBuffers {
    if (self.motionPrevRawBuffer != NULL) {
        free(self.motionPrevRawBuffer);
        self.motionPrevRawBuffer = NULL;
    }
    if (self.motionHistoryBuffer != NULL) {
        free(self.motionHistoryBuffer);
        self.motionHistoryBuffer = NULL;
    }
    self.hasMotionHistory = NO;
    self.hasLastCursorPoint = NO;
}

- (BOOL)appendFrameAtTime:(CMTime)presentationTime frameIndex:(NSInteger)frameIndex {
    CVPixelBufferPoolRef pool = self.pixelBufferAdaptor.pixelBufferPool;
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = kCVReturnError;
    if (pool != NULL) {
        status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer);
    } else {
        NSDictionary *attrs = @{
            (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
        };
        status = CVPixelBufferCreate(kCFAllocatorDefault,
                                     self.outputWidth,
                                     self.outputHeight,
                                     kCVPixelFormatType_32BGRA,
                                     (__bridge CFDictionaryRef)attrs,
                                     &pixelBuffer);
    }
    if (status != kCVReturnSuccess || pixelBuffer == NULL) {
        return NO;
    }

    CGWindowID belowID = self.excludeAboveWindowID;
    CGWindowListOption listOption = (belowID != kCGNullWindowID)
        ? kCGWindowListOptionOnScreenBelowWindow
        : kCGWindowListOptionOnScreenOnly;
    CGImageRef cgImage = CGWindowListCreateImage(
        self.captureCGRect,
        listOption,
        belowID,
        kCGWindowImageBestResolution | kCGWindowImageBoundsIgnoreFraming
    );
    if (cgImage == NULL && belowID != kCGNullWindowID) {
        cgImage = CGWindowListCreateImage(
            self.captureCGRect,
            kCGWindowListOptionOnScreenOnly,
            kCGNullWindowID,
            kCGWindowImageBestResolution | kCGWindowImageBoundsIgnoreFraming
        );
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddress,
        self.outputWidth,
        self.outputHeight,
        8,
        bytesPerRow,
        colorSpace,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst
    );

    if (ctx != NULL) {
        if (cgImage != NULL) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            CGContextDrawImage(ctx, CGRectMake(0, 0, self.outputWidth, self.outputHeight), cgImage);
        } else {
            // Synthetic animated fallback (used when headless or in automated --videotest without TCC)
            CGFloat t = (CGFloat)(frameIndex % 60) / 60.0;
            CGContextSetRGBFillColor(ctx, 0.08, 0.11, 0.16, 1.0);
            CGContextFillRect(ctx, CGRectMake(0, 0, self.outputWidth, self.outputHeight));
            CGContextSetRGBFillColor(ctx, 0.14, 0.72, 0.82, 1.0);
            CGFloat barW = MAX(24.0, (CGFloat)self.outputWidth * 0.25);
            CGFloat barX = t * ((CGFloat)self.outputWidth - barW);
            CGContextFillRect(ctx, CGRectMake(barX, self.outputHeight * 0.35, barW, self.outputHeight * 0.3));
        }

        // Apply motion-adaptive shutter blur across baseAddress
        if (self.motionBlurMode != CSVideoMotionBlurModeOff &&
            self.motionPrevRawBuffer != NULL &&
            self.motionHistoryBuffer != NULL) {
            BOOL hasHist = self.hasMotionHistory;
            ApplyMotionBlurToPixelBuffer((uint8_t *)baseAddress,
                                         self.outputWidth,
                                         self.outputHeight,
                                         bytesPerRow,
                                         self.motionPrevRawBuffer,
                                         self.motionHistoryBuffer,
                                         &hasHist,
                                         self.motionBlurMode);
            self.hasMotionHistory = hasHist;
        }

        // Draw mouse cursor with optional cursor motion blur
        [self drawCursorInContext:ctx];

        CGContextRelease(ctx);
    }
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    if (cgImage != NULL) {
        CGImageRelease(cgImage);
    }

    BOOL appended = [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentationTime];
    CVPixelBufferRelease(pixelBuffer);
    return appended;
}

#pragma mark - Audio sample buffer delegate

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (!self.isRecording || self.isPaused) {
        return;
    }
    if (self.assetWriter.status != AVAssetWriterStatusWriting) {
        return;
    }
    if (self.audioInput == nil || !self.audioInput.isReadyForMoreMediaData) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        return;
    }

    CMTime sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (!self.hasFirstAudioPTS) {
        self.firstAudioSourcePTS = sourcePTS;
        self.hasFirstAudioPTS = YES;
    }

    CMTime relativePTS = CMTimeSubtract(sourcePTS, self.firstAudioSourcePTS);
    CMTime pausedCM = CMTimeMakeWithSeconds(self.totalPausedDuration, sourcePTS.timescale > 0 ? sourcePTS.timescale : 44100);
    CMTime adjustedPTS = CMTimeSubtract(relativePTS, pausedCM);
    if (CMTimeCompare(adjustedPTS, kCMTimeZero) < 0) {
        adjustedPTS = kCMTimeZero;
    }

    CMSampleTimingInfo timingInfo;
    timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer);
    timingInfo.presentationTimeStamp = adjustedPTS;
    timingInfo.decodeTimeStamp = kCMTimeInvalid;

    CMSampleBufferRef adjustedBuffer = NULL;
    OSStatus status = CMSampleBufferCreateCopyWithNewTiming(
        kCFAllocatorDefault,
        sampleBuffer,
        1,
        &timingInfo,
        &adjustedBuffer
    );
    if (status == noErr && adjustedBuffer != NULL) {
        [self.audioInput appendSampleBuffer:adjustedBuffer];
        CFRelease(adjustedBuffer);
    }
}

#pragma mark - Pause / Resume / Stop / Cancel

- (void)pauseRecording {
    dispatch_sync(self.writerQueue, ^{
        if (!self.isRecording || self.isPaused) {
            return;
        }
        self.isPaused = YES;
        self.pauseStartTime = CACurrentMediaTime();
    });
}

- (void)resumeRecording {
    dispatch_sync(self.writerQueue, ^{
        if (!self.isRecording || !self.isPaused) {
            return;
        }
        CFTimeInterval pausedDelta = MAX(0.0, CACurrentMediaTime() - self.pauseStartTime);
        self.totalPausedDuration += pausedDelta;
        self.pauseStartTime = 0.0;
        self.isPaused = NO;
    });
}

- (void)stopRecordingWithCompletion:(VideoRecorderCompletionBlock)completion {
    dispatch_async(self.writerQueue, ^{
        if (!self.isRecording) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, [NSError errorWithDomain:@"com.choxieshoot.videorecorder"
                                                        code:103
                                                    userInfo:@{NSLocalizedDescriptionKey: @"Recorder is not active."}]);
                }
            });
            return;
        }

        if (self.isPaused) {
            CFTimeInterval pausedDelta = MAX(0.0, CACurrentMediaTime() - self.pauseStartTime);
            self.totalPausedDuration += pausedDelta;
            self.isPaused = NO;
        }
        self.isRecording = NO;

        if (self.frameTimer != nil) {
            dispatch_source_cancel(self.frameTimer);
            self.frameTimer = nil;
        }

        if (self.audioSession != nil && self.audioSession.isRunning) {
            [self.audioSession stopRunning];
        }
        self.audioSession = nil;
        self.audioOutput = nil;

        // Ensure at least 2 frames are present so even very short clips play cleanly
        while (self.framesWritten < 2 && self.assetWriter.status == AVAssetWriterStatusWriting && self.videoInput.isReadyForMoreMediaData) {
            int64_t tick = self.lastFrameTick + 1;
            if ([self appendFrameAtTime:CMTimeMake(tick, (int32_t)self.fps) frameIndex:self.framesWritten]) {
                self.lastFrameTick = tick;
                self.framesWritten++;
            } else {
                break;
            }
        }

        if (self.videoInput != nil) {
            [self.videoInput markAsFinished];
        }
        if (self.audioInput != nil) {
            [self.audioInput markAsFinished];
        }

        AVAssetWriter *writer = self.assetWriter;
        NSURL *outURL = self.outputURL;
        if (writer == nil || writer.status != AVAssetWriterStatusWriting) {
            NSError *err = writer.error ?: [NSError errorWithDomain:@"com.choxieshoot.videorecorder"
                                                               code:104
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Writer was not in writing state."}];
            [self cleanupMotionBuffers];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, err);
                }
            });
            return;
        }

        [writer finishWritingWithCompletionHandler:^{
            NSError *finishErr = writer.error;
            BOOL ok = (writer.status == AVAssetWriterStatusCompleted && finishErr == nil);
            self.pixelBufferAdaptor = nil;
            self.videoInput = nil;
            self.audioInput = nil;
            self.assetWriter = nil;
            self.onDurationUpdate = nil;
            [self cleanupMotionBuffers];
            malloc_zone_pressure_relief(NULL, 0);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(ok ? outURL : nil, finishErr);
                }
            });
        }];
    });
}

- (void)cancelRecording {
    dispatch_async(self.writerQueue, ^{
        self.isRecording = NO;
        self.isPaused = NO;
        if (self.frameTimer != nil) {
            dispatch_source_cancel(self.frameTimer);
            self.frameTimer = nil;
        }
        if (self.audioSession != nil && self.audioSession.isRunning) {
            [self.audioSession stopRunning];
        }
        self.audioSession = nil;
        self.audioOutput = nil;
        if (self.assetWriter != nil && self.assetWriter.status == AVAssetWriterStatusWriting) {
            [self.assetWriter cancelWriting];
        }
        self.pixelBufferAdaptor = nil;
        self.videoInput = nil;
        self.audioInput = nil;
        self.assetWriter = nil;
        self.onDurationUpdate = nil;
        [self cleanupMotionBuffers];
        if (self.outputURL != nil) {
            [[NSFileManager defaultManager] removeItemAtURL:self.outputURL error:nil];
        }
        malloc_zone_pressure_relief(NULL, 0);
    });
}

@end
