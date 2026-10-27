// Renders the lock screen's Fluid artwork through the tweak's own SGFluidClip.m and reads the file back
// with AVFoundation: its length, its size, its codec and frames, that the field moves, that the loop has
// no seam, and that the cover sits sharp in the middle. The first frame is kept beside it as a PNG to look
// at. Exits 1 on any failure.
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared/AnimatedArtwork/SGFluidClip.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

// A stand-in cover: two colored halves and a light disc in the middle.
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

// RGBA bytes of an image, rows from the top.
static NSData *pixelsOf(CGImageRef image, size_t *width, size_t *height) {
    *width = CGImageGetWidth(image);
    *height = CGImageGetHeight(image);
    NSMutableData *data = [NSMutableData dataWithLength:*width * *height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, *width, *height, 8, *width * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, *width, *height), image);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return data;
}

// The mean difference of two images' channels, out of 255, over a band of rows (shares from the top) and
// columns, so the cover in the middle can be left out of what the field is judged by.
static double difference(CGImageRef a, CGImageRef b, CGFloat fromY, CGFloat toY, CGFloat fromX, CGFloat toX) {
    size_t w, h, w2, h2;
    NSData *pa = pixelsOf(a, &w, &h), *pb = pixelsOf(b, &w2, &h2);
    if (w != w2 || h != h2) return 255;
    const uint8_t *x = pa.bytes, *y = pb.bytes;
    double sum = 0;
    size_t count = 0;
    for (size_t row = (size_t)(fromY * h); row < (size_t)(toY * h); row++) {
        for (size_t column = (size_t)(fromX * w); column < (size_t)(toX * w); column++) {
            size_t i = (row * w + column) * 4;
            sum += abs(x[i] - y[i]) + abs(x[i + 1] - y[i + 1]) + abs(x[i + 2] - y[i + 2]);
            count += 3;
        }
    }
    return count ? sum / count : 255;
}

// The color at a point, given as shares from the top left.
static void colourAt(CGImageRef image, CGFloat sx, CGFloat sy, int rgb[3]) {
    size_t w, h;
    NSData *data = pixelsOf(image, &w, &h);
    const uint8_t *p = (const uint8_t *)data.bytes + ((size_t)(sy * h) * w + (size_t)(sx * w)) * 4;
    for (int i = 0; i < 3; i++) rgb[i] = p[i];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *here = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        NSURL *out = [NSURL fileURLWithPath:[here stringByAppendingPathComponent:@"clips"] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:out withIntermediateDirectories:YES attributes:nil error:nil];
        CGImageRef cover = argc > 1 ? newImageAt([NSString stringWithUTF8String:argv[1]]) : newCover();
        // 1206 pixels wide, an iPhone 17 Pro, at SGMotionPixels' three quarters, as LockScreenMotion.x asks.
        CGSize size = SGLyricsClipSize(round(1206 * 0.75));
        NSURL *url = [out URLByAppendingPathComponent:@"fluid.mp4"];
        printf("fluid.mp4\n");
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        BOOL written = SGFluidClipWrite(url, cover, size);
        check(written, [NSString stringWithFormat:@"written in %.0f ms", (CFAbsoluteTimeGetCurrent() - start) * 1000]);
        check(!SGFluidClipWrite([out URLByAppendingPathComponent:@"none.mp4"], NULL, size), @"no cover, no clip");
        if (!written) return 1;
        NSNumber *bytes = nil;
        [url getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
        printf("  %.0f KB\n", bytes.doubleValue / 1024);

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
        check(track != nil, @"has a video track");
        if (!track) return 1;
        double seconds = CMTimeGetSeconds(asset.duration);
        check(fabs(seconds - 8) < 0.05, [NSString stringWithFormat:@"lasts %.3f s (want 8)", seconds]);
        check(CGSizeEqualToSize(track.naturalSize, size) && fabs(size.height / size.width - 4.0 / 3) < 0.02,
              [NSString stringWithFormat:@"is %.0fx%.0f, 3:4", track.naturalSize.width, track.naturalSize.height]);
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
        check(samples == 192, [NSString stringWithFormat:@"holds %d frames (want 192, 8 s at 24)", samples]);

        AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
        generator.requestedTimeToleranceBefore = generator.requestedTimeToleranceAfter = kCMTimeZero;
        CGImageRef first = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
        CGImageRef second = [generator copyCGImageAtTime:CMTimeMake(1, 24) actualTime:NULL error:nil];
        CGImageRef middle = [generator copyCGImageAtTime:CMTimeMake(96, 24) actualTime:NULL error:nil];
        CGImageRef last = [generator copyCGImageAtTime:CMTimeMake(191, 24) actualTime:NULL error:nil];
        check(first && second && middle && last, @"frames read back");
        if (first && second && middle && last) {
            savePNG(first, [url URLByAppendingPathExtension:@"png"]);
            savePNG(middle, [[out URLByAppendingPathComponent:@"fluid-middle"] URLByAppendingPathExtension:@"png"]);
            // Measured against the preview, which is the loop's start drawn exactly, over the field in the top
            // quarter, clear of the cover: H.264 alone puts a decoded frame a little over 2 of 255 off it.
            CGImageRef preview = SGFluidClipFrame(cover, size);
            double toFirst = difference(preview, first, 0, 0.25, 0, 1), toSecond = difference(preview, second, 0, 0.25, 0, 1);
            double toLast = difference(preview, last, 0, 0.25, 0, 1), toMiddle = difference(preview, middle, 0, 0.25, 0, 1);
            check(toMiddle > 4, [NSString stringWithFormat:@"the field moves over the loop (%.2f of 255 from the start to the middle)", toMiddle]);
            check(toFirst < 4 && toFirst < toMiddle / 2, [NSString stringWithFormat:@"the preview is the clip's first frame (%.2f of 255 apart)", toFirst]);
            // The last frame is one step before the start as the second is one step after it: no seam.
            check(toLast < toSecond + 0.5, [NSString stringWithFormat:@"no seam where it loops (the last frame %.2f from the start, the second %.2f)", toLast, toSecond]);
            // The cover stays where it is, sharp: its middle is the stand-in's light disc, and it does not move.
            double still = difference(first, middle, 0.38, 0.52, 0.35, 0.65);
            check(still < 2, [NSString stringWithFormat:@"the cover holds still (%.2f of 255)", still]);
            if (argc <= 1) {
                int rgb[3];
                colourAt(first, 0.5, 0.45, rgb);
                check(rgb[0] > 200 && rgb[1] > 190 && rgb[2] > 140, [NSString stringWithFormat:@"the cover's middle is drawn sharp (%d, %d, %d)", rgb[0], rgb[1], rgb[2]]);
            }
            CGImageRelease(preview);
        }
        CGImageRelease(first);
        CGImageRelease(second);
        CGImageRelease(middle);
        CGImageRelease(last);
        CGImageRelease(cover);
        printf("%s, clips in %s\n", failures ? "FAILED" : "all passed", out.path.UTF8String);
        return failures ? 1 : 0;
    }
}
