// `lyrics-clip motion [video ...]`: the words over moving artwork (SGLyricsClipWriteOverMotion). Makes two
// stand-in videos, a bright busy one (a waving pink and white flag with white stars, 720 x 1280, 30 fps, the
// shape of a Canvas) and a dark one (dim drifting blobs and specks, 904 x 1206, 24 fps, the shape of an Apple
// Music cover at SGMotionPixels), takes any videos given too, and for each writes lines over it and checks
// the file: length, 3:4 size, H.264, frame count, words in the middle and none under the clock or the
// controls, the picture moving, the preview matching the first frame. It times each clip against the video
// cut alone (SGMotionClipShape) and the Animated lyrics clip, and prints the contrast of the words with the
// brightest of the picture behind them. Exits 1 on any failure.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <mach/mach.h>
#import "Shared/AnimatedArtwork/SGMotionClip.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

static double footprintMB(BOOL peak) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
    return (peak ? info.ledger_phys_footprint_peak : info.phys_footprint) / 1048576.0;
}

static CGContextRef newContext(size_t width, size_t height, void *data, size_t bytesPerRow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    return context;
}

static void star(CGContextRef c, CGFloat x, CGFloat y, CGFloat r) {
    for (int i = 0; i < 10; i++) {
        CGFloat a = M_PI_2 + i * M_PI / 5, l = i % 2 ? r * 0.4 : r;
        if (i) CGContextAddLineToPoint(c, x + l * cos(a), y + l * sin(a));
        else CGContextMoveToPoint(c, x + l * cos(a), y + l * sin(a));
    }
    CGContextClosePath(c);
    CGContextFillPath(c);
}

// A frame of the bright stand-in at `t` seconds: pink and white stripes waving across, a navy field of
// white stars at the top left, a white figure in the middle, the way a flag cover is busy and light.
static void drawFlag(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGFloat stripe = h / 13.0;
    CGContextSetRGBFillColor(c, 0.88, 0.22, 0.58, 1);
    for (int i = 0; i < 14; i += 2) {
        CGContextMoveToPoint(c, 0, i * stripe);
        for (int x = 0; x <= (int)w; x += 8) {
            CGFloat y = i * stripe + stripe * 0.35 * sin(x / (CGFloat)w * 2 * M_PI + t * 2.2);
            CGContextAddLineToPoint(c, x, y);
        }
        for (int x = (int)w; x >= 0; x -= 8) {
            CGFloat y = (i + 1) * stripe + stripe * 0.35 * sin(x / (CGFloat)w * 2 * M_PI + t * 2.2);
            CGContextAddLineToPoint(c, x, y);
        }
        CGContextClosePath(c);
        CGContextFillPath(c);
    }
    CGFloat sway = 12 * sin(t * 2.2);
    CGRect field = CGRectMake(-20, h * 0.42 + sway, w * 0.62, h * 0.6);
    CGContextSetRGBFillColor(c, 0.06, 0.07, 0.16, 1);
    CGContextFillRect(c, field);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 5; col++) {
            star(c, 30 + col * w * 0.12 + (row % 2) * w * 0.06, h * 0.45 + sway + row * h * 0.062, w * 0.035);
        }
    }
    CGContextSetRGBFillColor(c, 0.97, 0.97, 0.97, 1);
    CGContextFillEllipseInRect(c, CGRectMake(w * 0.38, h * 0.18, w * 0.24, h * 0.22));
}

// A frame of the dark stand-in: a near-black field, slow dim colored blobs, and small bright specks.
static void drawDark(CGContextRef c, size_t w, size_t h, double t) {
    CGContextSetRGBFillColor(c, 0.03, 0.03, 0.06, 1);
    CGContextFillRect(c, CGRectMake(0, 0, w, h));
    CGFloat colors[][3] = {{0.35, 0.1, 0.45}, {0.1, 0.2, 0.45}, {0.45, 0.15, 0.1}};
    for (int i = 0; i < 3; i++) {
        CGFloat x = w * (0.3 + 0.25 * i + 0.1 * sin(t * 0.8 + i)), y = h * (0.3 + 0.2 * i + 0.08 * cos(t * 0.8 + i * 2));
        CGContextSetRGBFillColor(c, colors[i][0], colors[i][1], colors[i][2], 0.6);
        CGContextFillEllipseInRect(c, CGRectMake(x - w * 0.3, y - w * 0.3, w * 0.6, w * 0.6));
    }
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.9);
    for (int i = 0; i < 60; i++) {
        CGFloat x = fmod(i * 97.3 + t * 20, w), y = fmod(i * 211.7, h), r = 1.5 + (i % 3);
        CGContextFillEllipseInRect(c, CGRectMake(x, y, r * 2, r * 2));
    }
}

static BOOL makeVideo(NSURL *url, size_t w, size_t h, int fps, int seconds, void (*draw)(CGContextRef, size_t, size_t, double)) {
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264, AVVideoWidthKey: @(w), AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(w * h * 3), AVVideoMaxKeyFrameIntervalKey: @(fps * 2)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                                      (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h)}];
    [writer addInput:input];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    for (int i = 0; i < fps * seconds; i++) {
        while (!input.readyForMoreMediaData) [NSThread sleepForTimeInterval:0.002];
        CVPixelBufferRef buffer = NULL;
        CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = newContext(w, h, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        draw(context, w, h, (double)i / fps);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, fps)];
        CVPixelBufferRelease(buffer);
    }
    [input markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return writer.status == AVAssetWriterStatusCompleted;
}

static void savePNG(CGImageRef image, NSURL *url) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

static CGImageRef frameAt(NSURL *url, double seconds) CF_RETURNS_RETAINED {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset URLAssetWithURL:url options:nil]];
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    return [generator copyCGImageAtTime:CMTimeMakeWithSeconds(seconds, 600) actualTime:NULL error:nil];
}

// RGBA bytes of `image`, freed by the caller.
static uint8_t *pixelsOf(CGImageRef image, size_t *width, size_t *height) {
    *width = CGImageGetWidth(image);
    *height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    uint8_t *data = calloc(*width * *height, 4);
    CGContextRef context = CGBitmapContextCreate(data, *width, *height, 8, *width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, *width, *height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

// Share of pixels lighter than `above` in every channel in rows `from` to `to` of the height, counted from the
// top. The picture is dimmed to 0.75 of white (kMotionDim), and to 0.4 under the words (kBandDim), so past 225
// only the words reach, and past 120 in the band only the words, dimmed ones too.
static double whiteIn(CGImageRef image, double from, double to, int above) {
    size_t w, h, lit = 0, all = 0;
    uint8_t *p = pixelsOf(image, &w, &h);
    for (size_t y = from * h; y < to * h; y++) {
        for (size_t x = 0; x < w; x++, all++) {
            uint8_t *q = p + (y * w + x) * 4;
            if (q[0] > above && q[1] > above && q[2] > above) lit++;
        }
    }
    free(p);
    return all ? (double)lit / all : 0;
}

static double linear(double c) {
    c /= 255;
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

// The relative luminance the brightest 5% of the picture reaches in rows `from` to `to`, and their mean.
static double brightIn(CGImageRef image, double from, double to, double *mean) {
    size_t w, h;
    uint8_t *p = pixelsOf(image, &w, &h);
    NSMutableArray<NSNumber *> *all = [NSMutableArray array];
    double sum = 0;
    for (size_t y = from * h; y < to * h; y += 2) {
        for (size_t x = 0; x < w; x += 2) {
            uint8_t *q = p + (y * w + x) * 4;
            double l = 0.2126 * linear(q[0]) + 0.7152 * linear(q[1]) + 0.0722 * linear(q[2]);
            [all addObject:@(l)];
            sum += l;
        }
    }
    free(p);
    [all sortUsingSelector:@selector(compare:)];
    *mean = sum / all.count;
    return all[(NSUInteger)(all.count * 0.95)].doubleValue;
}

// Mean absolute difference of two images of the same size, per channel, 0 to 255.
static double differ(CGImageRef a, CGImageRef b) {
    size_t w, h, w2, h2;
    uint8_t *p = pixelsOf(a, &w, &h), *q = pixelsOf(b, &w2, &h2);
    double sum = 0;
    if (w == w2 && h == h2) {
        for (size_t i = 0; i < w * h * 4; i++) if (i % 4 != 3) sum += abs(p[i] - q[i]);
    }
    free(p);
    free(q);
    return w == w2 && h == h2 ? sum / (w * h * 3) : 255;
}

typedef struct { double seconds; int frames; CGSize size; BOOL h264; } Read;

static Read readBack(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    Read read = {CMTimeGetSeconds(asset.duration), 0, track.naturalSize, NO};
    if (!track) return read;
    read.h264 = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject) == kCMVideoCodecType_H264;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [reader addOutput:output];
    [reader startReading];
    CMSampleBufferRef sample;
    while ((sample = [output copyNextSampleBuffer])) {
        if (CMSampleBufferGetNumSamples(sample)) read.frames++;
        CFRelease(sample);
    }
    return read;
}

static double contrast(double lighter, double darker) {
    return (lighter + 0.05) / (darker + 0.05);
}

int motionMain(NSURL *out, int argc, char **argv) {
    printf("footprint at start %.1f MB\n", footprintMB(NO));
    // `motion one video` and `motion cut video`: a single line's clip, or the video cut alone as LockScreenMotion.x
    // cuts it, in a fresh process, for the memory one takes.
    if (argc == 2 && (!strcmp(argv[0], "one") || !strcmp(argv[0], "cut"))) {
        NSURL *video = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL ok = !strcmp(argv[0], "one")
            ? SGLyricsClipWriteOverMotion([out URLByAppendingPathComponent:@"one.mp4"], video, @"(And I turn into a stalker)",
                                          @"I stare at the moon", @"When nighttime comes", 1, 4.5)
            : SGMotionClipShape(video, 0.75, [out URLByAppendingPathComponent:@"one-cut.mp4"]);
        printf("%s %s in %.0f ms; footprint now %.1f MB, peak %.1f MB\n", argv[0], ok ? "written" : "FAILED",
               (CFAbsoluteTimeGetCurrent() - start) * 1000, footprintMB(NO), footprintMB(YES));
        return ok ? 0 : 1;
    }
    NSMutableArray<NSURL *> *videos = [NSMutableArray array];
    NSURL *flag = [out URLByAppendingPathComponent:@"source-flag.mp4"], *dark = [out URLByAppendingPathComponent:@"source-dark.mp4"];
    check(makeVideo(flag, 720, 1280, 30, 6, drawFlag), @"made the bright stand-in, 720x1280, 30 fps, 6 s");

    // The end of the artwork ID (LyricsArtwork.x): a style change or another video gives another ID, so no clip is
    // kept past either; two store names that share their first four characters still differ.
    printf("artwork IDs\n");
    NSURL *a = [NSURL fileURLWithPath:@"/c/Motion/3f9a0c11d2e4b5a6978877665544332211009988.mp4"];
    NSURL *b = [NSURL fileURLWithPath:@"/c/Motion/3f9a77aa00bb11cc22dd33ee44ff556677889900.mp4"];
    check(![SGLyricsClipLook(a, SGLyricsClipStill) isEqual:SGLyricsClipLook(a, SGLyricsClipAnimated)],
          [NSString stringWithFormat:@"the style is in it over moving artwork (%@, %@)", SGLyricsClipLook(a, SGLyricsClipStill),
           SGLyricsClipLook(a, SGLyricsClipAnimated)]);
    check(![SGLyricsClipLook(a, SGLyricsClipStill) isEqual:SGLyricsClipLook(b, SGLyricsClipStill)], @"another video gives another one");
    check([SGLyricsClipLook(a, SGLyricsClipStill) isEqual:SGLyricsClipLook([a copy], SGLyricsClipStill)], @"the same video and style give the same one");
    check(![SGLyricsClipLook(nil, SGLyricsClipStill) isEqual:SGLyricsClipLook(a, SGLyricsClipStill)]
          && ![SGLyricsClipLook(nil, SGLyricsClipStill) isEqual:SGLyricsClipLook(nil, SGLyricsClipAnimated)], @"over the cover, the style alone");

    // A video gone from the store or cut short fails at once, with no preview, for LyricsArtwork.x to remember.
    printf("videos that will not read\n");
    NSURL *gone = [out URLByAppendingPathComponent:@"gone.mp4"], *cutShort = [out URLByAppendingPathComponent:@"cut-short.mp4"];
    [NSFileManager.defaultManager removeItemAtURL:gone error:nil];
    NSData *whole = [NSData dataWithContentsOfURL:flag];
    [[whole subdataWithRange:NSMakeRange(0, whole.length / 3)] writeToURL:cutShort atomically:YES];
    for (NSURL *bad in @[gone, cutShort]) {
        NSURL *clip = [out URLByAppendingPathComponent:[@"from-" stringByAppendingString:bad.lastPathComponent]];
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        BOOL written = SGLyricsClipWriteOverMotion(clip, bad, nil, @"A line", @"the next", 1, 3);
        double ms = (CFAbsoluteTimeGetCurrent() - started) * 1000;
        CGImageRef preview = SGLyricsClipMotionFrame(bad, nil, @"A line", @"the next", 1);
        check(!written && !preview && ![NSFileManager.defaultManager fileExistsAtPath:clip.path],
              [NSString stringWithFormat:@"%@: not written (in %.0f ms) and no preview", bad.lastPathComponent, ms]);
        CGImageRelease(preview);
    }
    check(makeVideo(dark, 904, 1206, 24, 8, drawDark), @"made the dark stand-in, 904x1206, 24 fps, 8 s");
    [videos addObjectsFromArray:@[flag, dark]];
    for (int i = 0; i < argc; i++) [videos addObject:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[i]]]];

    // The lyrics clip as it is, Animated, for the Mac-to-phone ratio: the phone wrote 96 such frames in about 4 s.
    CGImageRef plain = SGLyricsClipBackdrop(NULL, SGLyricsClipSize(904));
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    SGLyricsClipWrite([out URLByAppendingPathComponent:@"animated.mp4"], plain, @"Hold on", @"we're almost there", SGLyricsClipSize(904), SGLyricsClipAnimated);
    double animatedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000;
    CGImageRelease(plain);
    printf("the Animated lyrics clip, 60 frames at 896x1200: %.0f ms, %.1f ms a frame\n", animatedMs, animatedMs / 60);

    NSArray *cases = @[
        // name, previous, line, next, from, seconds
        @[@"line", @"(And I turn into a stalker)", @"I stare at the moon", @"When nighttime comes", @1.0, @3.5],
        @[@"long", @"Hold on", @"And every word I never said keeps ringing out across the quiet of the night", @"until the morning finds us", @2.0, @5.0],
        @[@"wrap", @"", @"Round the end of the video", @"and on from its start", @-1.5, @3.0],
        @[@"whole", @"Before", @"A line longer than the video", @"", @3.0, @20.0],
        @[@"rest", @"", @"", @"The first line, coming up", @0.0, @4.0],
        @[@"bare", @"", @"", @"", @2.0, @2.0],
    ];
    for (NSURL *video in videos) {
        NSString *name = video.lastPathComponent.stringByDeletingPathExtension;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:video options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        double length = CMTimeGetSeconds(asset.duration), fps = MIN(round(track.nominalFrameRate), 30);   // kept to 30 fps
        CGSize cut = SGMotionClipCut(track.naturalSize, 0.75);
        printf("\n%s: %.0fx%.0f, %.2f s at %.0f fps, cut to %.0fx%.0f\n", name.UTF8String, track.naturalSize.width, track.naturalSize.height,
               length, fps, cut.width, cut.height);
        // drawOver refuses a decoded frame of another size than the track states, and the clip is then not written,
        // so LyricsArtwork.x draws the line over the cover. A video with non-square pixels does that: its natural size
        // is the shown one (960x1280 for 720x1280 at 4:3), its frames the stored one.
        BOOL matches;
        {
            AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
                outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
            [reader addOutput:output];
            [reader startReading];
            CMSampleBufferRef sample = [output copyNextSampleBuffer];
            CVPixelBufferRef buffer = sample ? CMSampleBufferGetImageBuffer(sample) : NULL;
            size_t w = buffer ? CVPixelBufferGetWidth(buffer) : 0, h = buffer ? CVPixelBufferGetHeight(buffer) : 0;
            matches = w == (size_t)round(track.naturalSize.width) && h == (size_t)round(track.naturalSize.height);
            printf("  %s\n", [NSString stringWithFormat:@"%@ at its natural size (%.3fx%.3f, frames %zux%zu, %zu bytes a row)",
                   matches ? @"decodes" : @"does NOT decode", track.naturalSize.width, track.naturalSize.height, w, h,
                   buffer ? CVPixelBufferGetBytesPerRow(buffer) : 0].UTF8String);
            if (sample) CFRelease(sample);
            [reader cancelReading];
        }
        // The video cut alone, the decode and encode with nothing drawn, to tell the drawing's share.
        start = CFAbsoluteTimeGetCurrent();
        SGMotionClipShape(video, 0.75, [out URLByAppendingPathComponent:[name stringByAppendingString:@"-cut.mp4"]]);
        double cutMs = (CFAbsoluteTimeGetCurrent() - start) * 1000;
        printf("  the cut alone: %.0f ms for %.2f s, %.1f ms a frame\n", cutMs, length, cutMs / (length * fps));
        for (NSArray *c in cases) @autoreleasepool {
            double from = [c[4] doubleValue] < 0 ? length + [c[4] doubleValue] : [c[4] doubleValue], seconds = [c[5] doubleValue];
            double wanted = MIN(seconds, length);
            NSURL *url = [out URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.mp4", name, c[0]]];
            start = CFAbsoluteTimeGetCurrent();
            BOOL written = SGLyricsClipWriteOverMotion(url, video, c[1], c[2], c[3], from, seconds);
            if (!matches) {
                CGImageRef preview = SGLyricsClipMotionFrame(video, c[1], c[2], c[3], from);
                check(!written && !preview && ![NSFileManager.defaultManager fileExistsAtPath:url.path],
                      @"not written and no preview, so the line falls back to the cover rather than showing without its words");
                CGImageRelease(preview);
                continue;
            }
            double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
            printf("  footprint after writing %.1f MB\n", footprintMB(NO));
            printf(" %s\n", url.lastPathComponent.UTF8String);
            check(written, [NSString stringWithFormat:@"written in %.0f ms, %.1f ms a frame, %.1f s of clip a second",
                            ms, ms / (wanted * fps), wanted / (ms / 1000)]);
            if (!written) continue;
            Read read = readBack(url);
            check(fabs(read.seconds - wanted) < 0.05, [NSString stringWithFormat:@"lasts %.3f s (want %.3f)", read.seconds, wanted]);
            check(CGSizeEqualToSize(read.size, cut), [NSString stringWithFormat:@"is %.0fx%.0f", read.size.width, read.size.height]);
            check(read.h264, @"is H.264");
            check(abs(read.frames - (int)round(wanted * fps)) <= 1, [NSString stringWithFormat:@"holds %d frames (want %.0f)", read.frames, wanted * fps]);
            CGImageRef first = frameAt(url, 0), middle = frameAt(url, wanted / 2);
            if (!first || !middle) {
                check(NO, @"frames read back");
                continue;
            }
            savePNG(first, [url URLByAppendingPathExtension:@"png"]);
            BOOL words = [c[1] length] || [c[2] length] || [c[3] length];
            double band = [c[2] length] || ![c[3] length] ? whiteIn(first, 0.3, 0.7, 225) : whiteIn(first, 0.42, 0.58, 120);
            if (words) check(band > 0.003, [NSString stringWithFormat:@"words in the middle band (%.2f%% white)", band * 100]);
            else check(band < 0.0005, [NSString stringWithFormat:@"no words when there are none (%.3f%% white)", band * 100]);
            check(whiteIn(first, 0, 0.15, 225) < 0.0005 && whiteIn(first, 0.85, 1, 225) < 0.0005, @"nothing white under the clock or the controls");
            double moved = differ(first, middle);
            check(moved > 2, [NSString stringWithFormat:@"the picture moves (%.1f of 255 between the start and the middle)", moved]);
            CGImageRef preview = SGLyricsClipMotionFrame(video, c[1], c[2], c[3], from);
            double off = preview ? differ(preview, first) : 255;
            check(off < 10, [NSString stringWithFormat:@"the preview is the first frame (%.1f of 255 apart, the encode's loss)", off]);
            if (preview && [c[0] isEqual:@"line"]) savePNG(preview, [out URLByAppendingPathComponent:[name stringByAppendingString:@"-preview.png"]]);
            CGImageRelease(preview);
            if ([c[0] isEqual:@"bare"]) {
                // The picture under the words, as dimmed: white on its brightest 5%, and the dimmed lines' 40% white over it.
                double mean, top = brightIn(first, 0.42, 0.58, &mean);
                double dimTop = linear(255 * (0.4 + 0.6 * pow(top, 1 / 2.2)));
                printf("  under the words: brightest 5%% at luminance %.3f, mean %.3f; white on it %.1f:1, white on the mean %.1f:1, "
                       "a dimmed line on the brightest %.1f:1\n", top, mean, contrast(1, top), contrast(1, mean), contrast(dimTop, top));
                CGImageRef source = frameAt(video, from);
                double sourceMean, sourceTop = brightIn(source, 0.42, 0.58, &sourceMean);
                printf("  the same rows undimmed: brightest 5%% at %.3f, white on it %.1f:1\n", sourceTop, contrast(1, sourceTop));
                CGImageRelease(source);
            }
            CGImageRelease(first);
            CGImageRelease(middle);
        }
    }
    printf("\nfootprint now %.1f MB, peak %.1f MB\n", footprintMB(NO), footprintMB(YES));
    printf("%s, clips in %s\n", failures ? "FAILED" : "all passed", out.path.UTF8String);
    return failures ? 1 : 0;
}
