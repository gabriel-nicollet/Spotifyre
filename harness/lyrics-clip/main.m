// Renders lines of lyrics through the tweak's own SGLyricsClip.m, both styles, and reads every file back
// with AVFoundation: its length, its size, its frames, and that the words came out where they should.
// Each clip's first frame is kept beside it as a PNG to look at. Exits 1 on any failure.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

// A stand-in cover: two colored halves and a light disc, so the blur and the darkening show.
static CGImageRef newCover(void) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, 640, 640, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(context, 0.9, 0.3, 0.2, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 640, 320));
    CGContextSetRGBFillColor(context, 0.2, 0.4, 0.9, 1);
    CGContextFillRect(context, CGRectMake(0, 320, 640, 320));
    CGContextSetRGBFillColor(context, 0.95, 0.9, 0.7, 1);
    CGContextFillEllipseInRect(context, CGRectMake(200, 200, 240, 240));
    CGImageRef cover = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return cover;
}

static CGImageRef newImageAt(NSString *path) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return NULL;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    return image;
}

static void savePNG(CGImageRef image, NSURL *url) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

// The share of pixels in a band of rows lighter than the backdrop's by 30 of 255 a channel or more:
// the words, white or dimmed, and not the cover. `backdrop` NULL counts near-white pixels instead.
static double wordsIn(CGImageRef image, CGImageRef backdrop, CGFloat fromY, CGFloat toY) {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    CGContextRef under = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    if (backdrop) CGContextDrawImage(under, CGRectMake(0, 0, width, height), backdrop);
    const uint8_t *base = CGBitmapContextGetData(under);
    size_t white = 0, all = 0;
    // Rows counted from the top.
    for (size_t y = (size_t)(fromY * height); y < (size_t)(toY * height); y++) {
        for (size_t x = 0; x < width; x++) {
            const uint8_t *p = pixels + y * width * 4 + x * 4;
            const uint8_t *b = base + y * width * 4 + x * 4;
            BOOL lit = backdrop ? p[0] + p[1] + p[2] > b[0] + b[1] + b[2] + 90 : p[0] > 230 && p[1] > 230 && p[2] > 230;
            if (lit) white++;
            all++;
        }
    }
    CGContextRelease(context);
    CGContextRelease(under);
    CGColorSpaceRelease(space);
    return all ? (double)white / all : 0;
}

static void verify(NSURL *url, CGImageRef backdrop, CGSize size, SGLyricsClipStyle style, BOOL hasWords) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    double seconds = CMTimeGetSeconds(asset.duration);
    double wanted = style == SGLyricsClipAnimated ? 4 : 2;
    check(track != nil, @"has a video track");
    if (!track) return;
    check(fabs(seconds - wanted) < 0.05, [NSString stringWithFormat:@"lasts %.3f s (want %.0f)", seconds, wanted]);
    check(CGSizeEqualToSize(track.naturalSize, size), [NSString stringWithFormat:@"is %.0fx%.0f (want %.0fx%.0f)",
        track.naturalSize.width, track.naturalSize.height, size.width, size.height]);
    FourCharCode codec = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject);
    check(codec == kCMVideoCodecType_H264, @"is H.264");

    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [reader addOutput:output];
    [reader startReading];
    int samples = 0;
    CMSampleBufferRef sample;
    while ((sample = [output copyNextSampleBuffer])) {
        if (CMSampleBufferGetNumSamples(sample)) samples++;
        CFRelease(sample);
    }
    int wantedSamples = style == SGLyricsClipAnimated ? 60 : 1;
    check(samples == wantedSamples, [NSString stringWithFormat:@"holds %d frames (want %d)", samples, wantedSamples]);

    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
    CGImageRef first = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    CGImageRef late = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(wanted - 0.1, 600) actualTime:NULL error:nil];
    check(first && late, @"frames read back at the start and the end");
    if (first) {
        savePNG(first, [url URLByAppendingPathExtension:@"png"]);
        double middle = wordsIn(first, backdrop, 0.3, 0.7), top = wordsIn(first, NULL, 0, 0.15), bottom = wordsIn(first, NULL, 0.85, 1);
        if (hasWords) check(middle > 0.005, [NSString stringWithFormat:@"words in the middle band (%.2f%% white)", middle * 100]);
        else check(middle < 0.001, [NSString stringWithFormat:@"no words when there are none (%.2f%% white)", middle * 100]);
        check(top < 0.001 && bottom < 0.001, @"nothing white under the clock or the controls");
    }
    if (first && late) {
        // A still holds its frame to the end; it is the frame the preview image shows too.
        double a = wordsIn(first, NULL, 0.3, 0.7), b = wordsIn(late, NULL, 0.3, 0.7);
        check(fabs(a - b) < 0.002, [NSString stringWithFormat:@"the words hold still to the end (%.3f%% / %.3f%%)", a * 100, b * 100]);
    }
    CGImageRelease(first);
    CGImageRelease(late);
}

int motionMain(NSURL *out, int argc, char **argv);

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *here = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        if (argc > 1 && !strcmp(argv[1], "motion")) {
            NSURL *motionOut = [NSURL fileURLWithPath:[here stringByAppendingPathComponent:@"motion"] isDirectory:YES];
            [NSFileManager.defaultManager createDirectoryAtURL:motionOut withIntermediateDirectories:YES attributes:nil error:nil];
            return motionMain(motionOut, argc - 2, argv + 2);
        }
        NSURL *out = [NSURL fileURLWithPath:[here stringByAppendingPathComponent:@"clips"] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:out withIntermediateDirectories:YES attributes:nil error:nil];
        CGImageRef cover = argc > 1 ? newImageAt([NSString stringWithUTF8String:argv[1]]) : newCover();
        // 1206 pixels wide, an iPhone 17 Pro, at SGMotionPixels' three quarters.
        CGSize size = SGLyricsClipSize(round(1206 * 0.75));
        CGImageRef backdrop = SGLyricsClipBackdrop(cover, size);
        CGImageRef plain = SGLyricsClipBackdrop(NULL, size);
        NSArray *cases = @[
            @[@"short", @"Hold on", @"we're almost there"],
            @[@"long", @"And every word I never said keeps ringing out across the quiet of the night", @"until the morning finds us"],
            @[@"cjk", @"夜空に光る星を数えながら", @"君の名前を呼んだ"],
            @[@"break", @"", @"The first line, coming up"],
            @[@"last", @"The very last line", @""],
            @[@"empty", @"", @""],
        ];
        for (NSArray *c in cases) {
            for (SGLyricsClipStyle style = SGLyricsClipStill; style <= SGLyricsClipAnimated; style++) {
                NSString *name = [NSString stringWithFormat:@"%@-%@.mp4", c[0], style == SGLyricsClipStill ? @"still" : @"animated"];
                NSURL *url = [out URLByAppendingPathComponent:name];
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                BOOL written = SGLyricsClipWrite(url, [c[0] isEqual:@"empty"] ? plain : backdrop, c[1], c[2], size, style);
                double ms = (CFAbsoluteTimeGetCurrent() - start) * 1000;
                printf("%s\n", name.UTF8String);
                check(written, [NSString stringWithFormat:@"written in %.0f ms", ms]);
                if (!written) continue;
                NSNumber *bytes = nil;
                [url getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
                printf("  %.0f KB\n", bytes.doubleValue / 1024);
                verify(url, [c[0] isEqual:@"empty"] ? plain : backdrop, size, style, [c[1] length] || [c[2] length]);
            }
        }
        CGImageRef preview = SGLyricsClipFrame(backdrop, @"Hold on", @"we're almost there", size);
        check(preview && CGImageGetWidth(preview) == size.width && CGImageGetHeight(preview) == size.height, @"the preview frame is the clip's size");
        savePNG(preview, [out URLByAppendingPathComponent:@"preview.png"]);
        CGImageRelease(preview);
        CGImageRelease(backdrop);
        CGImageRelease(plain);
        CGImageRelease(cover);
        printf("%s, clips in %s\n", failures ? "FAILED" : "all passed", out.path.UTF8String);
        return failures ? 1 : 0;
    }
}
