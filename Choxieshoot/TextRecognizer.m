#import "TextRecognizer.h"
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <malloc/malloc.h>

@implementation CSTextObservation

- (instancetype)initWithText:(NSString *)text
                 boundingBox:(NSRect)boundingBox
                  confidence:(float)confidence
                   lineIndex:(NSInteger)lineIndex {
    if ((self = [super init])) {
        _text = [text copy];
        _boundingBox = boundingBox;
        _confidence = confidence;
        _lineIndex = lineIndex;
    }
    return self;
}

- (NSRect)rectInBounds:(NSRect)bounds {
    CGFloat x = NSMinX(bounds) + self.boundingBox.origin.x * NSWidth(bounds);
    CGFloat y = NSMinY(bounds) + self.boundingBox.origin.y * NSHeight(bounds);
    CGFloat w = self.boundingBox.size.width * NSWidth(bounds);
    CGFloat h = self.boundingBox.size.height * NSHeight(bounds);
    return NSInsetRect(NSMakeRect(x, y, w, h), -3.0, -2.0);
}

@end

@implementation CSBarcodeObservation

- (instancetype)initWithPayload:(NSString *)payload
                      symbology:(NSString *)symbology
                    boundingBox:(NSRect)boundingBox {
    if ((self = [super init])) {
        _payload = [payload copy];
        _symbology = [symbology copy];
        _boundingBox = boundingBox;
    }
    return self;
}

- (BOOL)isURL {
    NSString *trimmed = [self.payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }
    NSURL *url = [NSURL URLWithString:trimmed];
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"mailto"];
}

- (NSRect)rectInBounds:(NSRect)bounds {
    CGFloat x = NSMinX(bounds) + self.boundingBox.origin.x * NSWidth(bounds);
    CGFloat y = NSMinY(bounds) + self.boundingBox.origin.y * NSHeight(bounds);
    CGFloat w = self.boundingBox.size.width * NSWidth(bounds);
    CGFloat h = self.boundingBox.size.height * NSHeight(bounds);
    return NSInsetRect(NSMakeRect(x, y, w, h), -4.0, -4.0);
}

@end

@implementation CSTextRecognitionResult

- (instancetype)initWithObservations:(NSArray<CSTextObservation *> *)observations
                            fullText:(NSString *)fullText {
    return [self initWithObservations:observations fullText:fullText barcodes:@[]];
}

- (instancetype)initWithObservations:(NSArray<CSTextObservation *> *)observations
                            fullText:(NSString *)fullText
                            barcodes:(NSArray<CSBarcodeObservation *> *)barcodes {
    if ((self = [super init])) {
        _observations = [observations copy] ?: @[];
        _fullText = [fullText copy] ?: @"";
        _barcodes = [barcodes copy] ?: @[];
    }
    return self;
}

- (NSString *)textForObservationIndexes:(NSIndexSet *)indexes {
    if (indexes.count == 0 || self.observations.count == 0) {
        return @"";
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableArray<NSString *> *currentLineParts = [NSMutableArray array];
    __block NSInteger currentLineIndex = -1;

    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx >= self.observations.count) {
            return;
        }
        CSTextObservation *obs = self.observations[idx];
        if (obs.text.length == 0) {
            return;
        }
        if (currentLineIndex >= 0 && obs.lineIndex != currentLineIndex) {
            if (currentLineParts.count > 0) {
                [lines addObject:[currentLineParts componentsJoinedByString:@"  "]];
                [currentLineParts removeAllObjects];
            }
        }
        currentLineIndex = obs.lineIndex;
        [currentLineParts addObject:obs.text];
    }];

    if (currentLineParts.count > 0) {
        [lines addObject:[currentLineParts componentsJoinedByString:@"  "]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

@end

@implementation TextRecognizer

+ (void)recognizeObservationsInImage:(NSImage *)image
                          completion:(void (^)(CSTextRecognitionResult * _Nullable, NSError * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block CSTextRecognitionResult *result = nil;
        __block NSError *error = nil;
        @autoreleasepool {
            result = [self recognizeObservationsViaWorkerWithImage:image error:&error];
            if (result == nil && error == nil) {
                result = [self recognizeObservationsInImageSync:image error:&error];
            }
        }
        malloc_zone_pressure_relief(NULL, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result, error);
        });
    });
}

+ (nullable CSTextRecognitionResult *)recognizeObservationsViaWorkerWithImage:(NSImage *)image
                                                                        error:(NSError **)error {
    if (image == nil) {
        return nil;
    }
    NSString *execPath = [[NSBundle mainBundle] executablePath];
    if (execPath.length == 0 || ![[NSFileManager defaultManager] isExecutableFileAtPath:execPath]) {
        return nil;
    }

    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    if (cgImage == NULL) {
        return nil;
    }

    NSString *tempName = [NSString stringWithFormat:@"choxieshoot-ocr-%@.png", [NSUUID UUID].UUIDString];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:tempName];
    @autoreleasepool {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG
                                            properties:@{NSImageCompressionFactor: @(0.1)}];
        if (pngData.length == 0 || ![pngData writeToFile:tempPath atomically: NO]) {
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
            return nil;
        }
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:execPath];
    task.arguments = @[@"--ocr-worker", tempPath];
    NSPipe *outPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = [NSPipe pipe];

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];
        return nil;
    }

    NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:NULL];

    if (task.terminationStatus != 0 || outData.length == 0) {
        return nil;
    }

    NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:outData
                                                                   options:NSPropertyListImmutable
                                                                    format:NULL
                                                                     error:NULL];
    if (![dict isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSArray<NSDictionary *> *rawObs = dict[@"observations"];
    NSMutableArray<CSTextObservation *> *observations = [NSMutableArray arrayWithCapacity:rawObs.count];
    for (NSDictionary *o in rawObs) {
        NSString *text = o[@"text"] ?: @"";
        NSRect box = NSMakeRect([o[@"x"] doubleValue],
                                [o[@"y"] doubleValue],
                                [o[@"w"] doubleValue],
                                [o[@"h"] doubleValue]);
        float conf = [o[@"c"] floatValue];
        NSInteger lineIdx = [o[@"l"] integerValue];
        [observations addObject:[[CSTextObservation alloc] initWithText:text
                                                            boundingBox:box
                                                             confidence:conf
                                                              lineIndex:lineIdx]];
    }

    NSArray<NSDictionary *> *rawBarcodes = dict[@"barcodes"];
    NSMutableArray<CSBarcodeObservation *> *barcodes = [NSMutableArray arrayWithCapacity:rawBarcodes.count];
    for (NSDictionary *b in rawBarcodes) {
        NSString *payload = b[@"payload"] ?: @"";
        NSString *sym = b[@"symbology"] ?: @"QR";
        NSRect box = NSMakeRect([b[@"x"] doubleValue],
                                [b[@"y"] doubleValue],
                                [b[@"w"] doubleValue],
                                [b[@"h"] doubleValue]);
        [barcodes addObject:[[CSBarcodeObservation alloc] initWithPayload:payload
                                                                symbology:sym
                                                              boundingBox:box]];
    }

    NSString *fullText = dict[@"fullText"] ?: @"";
    return [[CSTextRecognitionResult alloc] initWithObservations:observations
                                                        fullText:fullText
                                                        barcodes:barcodes];
}

+ (int)runOCRWorkerWithImagePath:(NSString *)imagePath {
    @autoreleasepool {
        if (imagePath.length == 0) {
            return 2;
        }
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
        if (image == nil) {
            return 3;
        }
        NSError *error = nil;
        CSTextRecognitionResult *result = [self recognizeObservationsInImageSync:image error:&error];
        if (result == nil) {
            return 4;
        }
        NSMutableArray<NSDictionary *> *rawObs = [NSMutableArray arrayWithCapacity:result.observations.count];
        for (CSTextObservation *o in result.observations) {
            [rawObs addObject:@{
                @"text": o.text ?: @"",
                @"x": @(o.boundingBox.origin.x),
                @"y": @(o.boundingBox.origin.y),
                @"w": @(o.boundingBox.size.width),
                @"h": @(o.boundingBox.size.height),
                @"c": @(o.confidence),
                @"l": @(o.lineIndex)
            }];
        }
        NSMutableArray<NSDictionary *> *rawBarcodes = [NSMutableArray arrayWithCapacity:result.barcodes.count];
        for (CSBarcodeObservation *b in result.barcodes) {
            [rawBarcodes addObject:@{
                @"payload": b.payload ?: @"",
                @"symbology": b.symbology ?: @"QR",
                @"x": @(b.boundingBox.origin.x),
                @"y": @(b.boundingBox.origin.y),
                @"w": @(b.boundingBox.size.width),
                @"h": @(b.boundingBox.size.height)
            }];
        }
        NSDictionary *payload = @{
            @"fullText": result.fullText ?: @"",
            @"observations": rawObs,
            @"barcodes": rawBarcodes
        };
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:payload
                                                                       format:NSPropertyListBinaryFormat_v1_0
                                                                      options:0
                                                                        error:NULL];
        if (plistData.length == 0) {
            return 5;
        }
        [[NSFileHandle fileHandleWithStandardOutput] writeData:plistData];
        return 0;
    }
}

+ (CSTextRecognitionResult *)recognizeObservationsInImageSync:(NSImage *)image error:(NSError **)error {
    if (image == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"ChoxieshootTextRecognizer"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"No image to recognise."}];
        }
        return nil;
    }

    __block CSTextRecognitionResult *finalResult = nil;
    __block NSError *capturedError = nil;
    @autoreleasepool {
        CGImageRef cgImage = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
        if (cgImage == NULL) {
            capturedError = [NSError errorWithDomain:@"ChoxieshootTextRecognizer"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey: @"The screenshot could not be converted for recognition."}];
        } else {
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
            VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc] init];
            textRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            textRequest.usesLanguageCorrection = YES;
            if (@available(macOS 13.0, *)) {
                textRequest.automaticallyDetectsLanguage = YES;
            }

            VNDetectBarcodesRequest *barcodeRequest = [[VNDetectBarcodesRequest alloc] init];
            barcodeRequest.symbologies = @[
                VNBarcodeSymbologyQR,
                VNBarcodeSymbologyAztec,
                VNBarcodeSymbologyDataMatrix,
                VNBarcodeSymbologyCode128,
                VNBarcodeSymbologyEAN13
            ];

            NSError *performError = nil;
            BOOL bothOK = [handler performRequests:@[textRequest, barcodeRequest] error:&performError];
            if (!bothOK) {
                // Retry text recognition alone if combined request failed on barcode request
                performError = nil;
                if (![handler performRequests:@[textRequest] error:&performError]) {
                    capturedError = performError;
                }
            }

            if (capturedError == nil) {
                NSArray<CSBarcodeObservation *> *barcodes = [self barcodesFromRequest:barcodeRequest
                                                                          requestSucceeded:bothOK
                                                                                   cgImage:cgImage];
                NSArray<VNRecognizedTextObservation *> *results = textRequest.results ?: @[];
                finalResult = [self resultFromObservations:results barcodes:barcodes];
            }
        }
    }
    if (finalResult == nil && error != NULL) {
        *error = capturedError;
    }
    return finalResult;
}

+ (NSArray<CSBarcodeObservation *> *)barcodesFromRequest:(VNDetectBarcodesRequest *)barcodeRequest
                                        requestSucceeded:(BOOL)requestSucceeded
                                                 cgImage:(CGImageRef)cgImage {
    if (cgImage == NULL) {
        return @[];
    }
    NSMutableArray<CSBarcodeObservation *> *barcodes = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPayloads = [NSMutableSet set];

    if (requestSucceeded) {
        for (VNBarcodeObservation *obs in barcodeRequest.results) {
            NSString *payload = [obs.payloadStringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (payload.length > 0 && ![seenPayloads containsObject:payload]) {
                [seenPayloads addObject:payload];
                NSString *sym = obs.symbology ?: @"QR";
                if ([sym containsString:@"QR"]) {
                    sym = @"QR";
                } else if ([sym hasPrefix:@"VNBarcodeSymbology"]) {
                    sym = [sym substringFromIndex:@"VNBarcodeSymbology".length];
                }
                CSBarcodeObservation *item = [[CSBarcodeObservation alloc] initWithPayload:payload
                                                                                 symbology:sym
                                                                               boundingBox:NSRectFromCGRect(obs.boundingBox)];
                [barcodes addObject:item];
            }
        }
    }

    if (barcodes.count == 0) {
        @autoreleasepool {
            CIImage *ciImage = [CIImage imageWithCGImage:cgImage];
            CIContext *cpuContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @YES}];
            CIDetector *qrDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                        context:cpuContext
                                                        options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
            NSArray<CIFeature *> *features = [qrDetector featuresInImage:ciImage];
            CGFloat imgW = MAX((CGFloat)CGImageGetWidth(cgImage), 1.0);
            CGFloat imgH = MAX((CGFloat)CGImageGetHeight(cgImage), 1.0);
            for (CIFeature *feature in features) {
                if ([feature isKindOfClass:[CIQRCodeFeature class]]) {
                    CIQRCodeFeature *qr = (CIQRCodeFeature *)feature;
                    NSString *payload = [qr.messageString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (payload.length > 0 && ![seenPayloads containsObject:payload]) {
                        [seenPayloads addObject:payload];
                        CGRect b = qr.bounds;
                        NSRect norm = NSMakeRect(b.origin.x / imgW,
                                                 b.origin.y / imgH,
                                                 b.size.width / imgW,
                                                 b.size.height / imgH);
                        CSBarcodeObservation *item = [[CSBarcodeObservation alloc] initWithPayload:payload
                                                                                         symbology:@"QR"
                                                                                       boundingBox:norm];
                        [barcodes addObject:item];
                    }
                }
            }
        }
    }

    return barcodes;
}

+ (void)recognizeTextInImage:(NSImage *)image
                  completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [self recognizeObservationsInImage:image completion:^(CSTextRecognitionResult * _Nullable result, NSError * _Nullable error) {
        completion(result.fullText, error);
    }];
}

+ (NSString *)recognizeTextInImageSync:(NSImage *)image error:(NSError **)error {
    CSTextRecognitionResult *result = [self recognizeObservationsInImageSync:image error:error];
    return result.fullText;
}

+ (CSTextRecognitionResult *)resultFromObservations:(NSArray<VNRecognizedTextObservation *> *)observations
                                           barcodes:(NSArray<CSBarcodeObservation *> *)barcodes {
    // Vision returns observations in no guaranteed reading order. Group them
    // into visual lines (bands with strong vertical overlap), order the bands
    // top-to-bottom, then each line left-to-right. Bounding boxes are
    // normalised with a bottom-left origin.
    NSMutableArray<NSMutableArray<VNRecognizedTextObservation *> *> *bands = [NSMutableArray array];

    for (VNRecognizedTextObservation *observation in observations) {
        CGRect box = observation.boundingBox;
        NSInteger matchingBand = -1;
        for (NSInteger i = 0; i < (NSInteger)bands.count; i++) {
            NSMutableArray<VNRecognizedTextObservation *> *band = bands[i];
            for (VNRecognizedTextObservation *member in band) {
                CGRect memberBox = member.boundingBox;
                CGFloat overlap = MIN(NSMaxY(box), NSMaxY(memberBox)) - MAX(NSMinY(box), NSMinY(memberBox));
                CGFloat minHeight = MIN(box.size.height, memberBox.size.height);
                if (minHeight > 0 && overlap / minHeight > 0.5) {
                    matchingBand = i;
                    break;
                }
            }
            if (matchingBand >= 0) {
                break;
            }
        }
        if (matchingBand >= 0) {
            [bands[matchingBand] addObject:observation];
        } else {
            [bands addObject:[NSMutableArray arrayWithObject:observation]];
        }
    }

    [bands sortUsingComparator:^NSComparisonResult(NSArray<VNRecognizedTextObservation *> *a,
                                                   NSArray<VNRecognizedTextObservation *> *b) {
        CGFloat topA = 0, topB = 0;
        for (VNRecognizedTextObservation *o in a) { topA = MAX(topA, NSMaxY(o.boundingBox)); }
        for (VNRecognizedTextObservation *o in b) { topB = MAX(topB, NSMaxY(o.boundingBox)); }
        return topA > topB ? NSOrderedAscending : (topA < topB ? NSOrderedDescending : NSOrderedSame);
    }];

    NSMutableArray<CSTextObservation *> *orderedObservations = [NSMutableArray array];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger lineIndex = 0;

    for (NSMutableArray<VNRecognizedTextObservation *> *band in bands) {
        [band sortUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a,
                                                      VNRecognizedTextObservation *b) {
            return NSMinX(a.boundingBox) < NSMinX(b.boundingBox) ? NSOrderedAscending : NSOrderedDescending;
        }];
        NSMutableArray<NSString *> *parts = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in band) {
            VNRecognizedText *candidate = [observation topCandidates:1].firstObject;
            NSString *trimmed = [candidate.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0) {
                [parts addObject:trimmed];
                CSTextObservation *item = [[CSTextObservation alloc] initWithText:trimmed
                                                                      boundingBox:NSRectFromCGRect(observation.boundingBox)
                                                                       confidence:candidate.confidence
                                                                        lineIndex:lineIndex];
                [orderedObservations addObject:item];
            }
        }
        if (parts.count > 0) {
            [lines addObject:[parts componentsJoinedByString:@"  "]];
            lineIndex++;
        }
    }

    NSString *fullText = [lines componentsJoinedByString:@"\n"];
    return [[CSTextRecognitionResult alloc] initWithObservations:orderedObservations
                                                        fullText:fullText
                                                        barcodes:barcodes];
}

@end
