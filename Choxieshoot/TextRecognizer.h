#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A single recognized text region on the screenshot.
/// `boundingBox` is normalized in [0, 1] with a bottom-left origin (matching AppKit view coordinates).
@interface CSTextObservation : NSObject

@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, readonly) NSRect boundingBox;
@property (nonatomic, readonly) float confidence;
@property (nonatomic, readonly) NSInteger lineIndex;

- (instancetype)initWithText:(NSString *)text
                 boundingBox:(NSRect)boundingBox
                  confidence:(float)confidence
                   lineIndex:(NSInteger)lineIndex;

/// Converts the normalized bounding box into the given view bounds (bottom-left origin).
- (NSRect)rectInBounds:(NSRect)bounds;

@end

/// A single recognized QR code or barcode on the screenshot.
/// `boundingBox` is normalized in [0, 1] with a bottom-left origin.
@interface CSBarcodeObservation : NSObject

@property (nonatomic, copy, readonly) NSString *payload;
@property (nonatomic, copy, readonly) NSString *symbology;
@property (nonatomic, readonly) NSRect boundingBox;
@property (nonatomic, readonly) BOOL isURL;

- (instancetype)initWithPayload:(NSString *)payload
                      symbology:(NSString *)symbology
                    boundingBox:(NSRect)boundingBox;

/// Converts the normalized bounding box into the given view bounds (bottom-left origin).
- (NSRect)rectInBounds:(NSRect)bounds;

@end

/// Structured result of an OCR + barcode pass over a screenshot.
@interface CSTextRecognitionResult : NSObject

@property (nonatomic, copy, readonly) NSArray<CSTextObservation *> *observations;
@property (nonatomic, copy, readonly) NSString *fullText;
@property (nonatomic, copy, readonly) NSArray<CSBarcodeObservation *> *barcodes;

- (instancetype)initWithObservations:(NSArray<CSTextObservation *> *)observations
                            fullText:(NSString *)fullText;

- (instancetype)initWithObservations:(NSArray<CSTextObservation *> *)observations
                            fullText:(NSString *)fullText
                            barcodes:(NSArray<CSBarcodeObservation *> *)barcodes;

/// Joins the observations at `indexes` in reading order, preserving line breaks between visual lines.
- (NSString *)textForObservationIndexes:(NSIndexSet *)indexes;

@end

/// On-device OCR (Vision framework) for inspecting and copying text out of a screenshot.
@interface TextRecognizer : NSObject

+ (void)recognizeObservationsInImage:(NSImage *)image
                          completion:(void (^)(CSTextRecognitionResult * _Nullable result, NSError * _Nullable error))completion;

+ (nullable CSTextRecognitionResult *)recognizeObservationsInImageSync:(NSImage *)image
                                                                 error:(NSError * _Nullable * _Nullable)error;

+ (void)recognizeTextInImage:(NSImage *)image
                  completion:(void (^)(NSString * _Nullable text, NSError * _Nullable error))completion;

+ (nullable NSString *)recognizeTextInImageSync:(NSImage *)image
                                         error:(NSError * _Nullable * _Nullable)error;

/// Entry point for the short-lived `--ocr-worker <imagePath>` subprocess so Vision/Espresso/ANE caches are reclaimed by macOS immediately after OCR completes.
+ (int)runOCRWorkerWithImagePath:(NSString *)imagePath;

@end

NS_ASSUME_NONNULL_END
