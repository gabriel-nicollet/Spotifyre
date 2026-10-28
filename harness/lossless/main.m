// Native decoder capability probe. Generated fixtures only; no Spotify hooks or credentials.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>

static void report(NSDictionary *row) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:nil];
    printf("LOSSLESS %s\n", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    fflush(stdout);
}

typedef struct {
    BOOL ready, described; UInt64 packets, bytes; AudioStreamBasicDescription format;
    __unsafe_unretained NSMutableData *payload, *descriptions;
    NSUInteger cursor; AudioStreamPacketDescription current;
} ParseState;
static void property(void *context, AudioFileStreamID stream, AudioFileStreamPropertyID prop, UInt32 *flags) {
    ParseState *s = context;
    if (prop == kAudioFileStreamProperty_ReadyToProducePackets) s->ready = YES;
    if (prop == kAudioFileStreamProperty_DataFormat) {
        UInt32 size = sizeof(s->format);
        AudioFileStreamGetProperty(stream, prop, &size, &s->format);
    }
}
static void packets(void *context, UInt32 bytes, UInt32 count, const void *data,
                    AudioStreamPacketDescription *descriptions) {
    ParseState *s = context; s->packets += count; s->bytes += bytes;
    NSUInteger base = s->payload.length;
    [s->payload appendBytes:data length:bytes];
    for (UInt32 i=0; i<count; ++i) {
        AudioStreamPacketDescription description;
        if (descriptions) description = descriptions[i];
        else if (s->format.mBytesPerPacket)
            description = (AudioStreamPacketDescription){i*s->format.mBytesPerPacket, 0, s->format.mBytesPerPacket};
        else { s->described = NO; return; }
        description.mStartOffset += base;
        [s->descriptions appendBytes:&description length:sizeof(description)];
    }
}
static OSStatus converterInput(AudioConverterRef converter, UInt32 *count, AudioBufferList *data,
                               AudioStreamPacketDescription **descriptions, void *context) {
    ParseState *s = context;
    NSUInteger total = s->descriptions.length / sizeof(AudioStreamPacketDescription);
    if (s->cursor == total) { *count = 0; return noErr; }
    s->current = ((const AudioStreamPacketDescription *)s->descriptions.bytes)[s->cursor++];
    data->mNumberBuffers = 1;
    data->mBuffers[0] = (AudioBuffer){s->format.mChannelsPerFrame, s->current.mDataByteSize,
                                    (char *)s->payload.bytes + s->current.mStartOffset};
    s->current.mStartOffset = 0;
    *count = 1;
    if (descriptions) *descriptions = &s->current;
    return noErr;
}
static void convertPackets(ParseState *s, AudioFileStreamID stream, NSString *name) {
    AudioStreamBasicDescription target = {.mSampleRate=s->format.mSampleRate, .mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, .mBytesPerPacket=8,
        .mFramesPerPacket=1, .mBytesPerFrame=8, .mChannelsPerFrame=2, .mBitsPerChannel=32};
    AudioConverterRef converter = NULL;
    OSStatus status = AudioConverterNew(&s->format, &target, &converter);
    UInt32 size = 0; Boolean writable = false; OSStatus cookieStatus = 0;
    if (!status && !AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &size, &writable) && size) {
        NSMutableData *cookie = [NSMutableData dataWithLength:size];
        cookieStatus = AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &size, cookie.mutableBytes);
        if (!cookieStatus) cookieStatus = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie, size, cookie.bytes);
        status = cookieStatus;
    }
    UInt64 total = 0; double maxError = 0; float samples[4096*2];
    while (!status) {
        UInt32 count = 4096;
        AudioBufferList list = {.mNumberBuffers=1, .mBuffers={{2,sizeof(samples),samples}}};
        status = AudioConverterFillComplexBuffer(converter, converterInput, s, &count, &list, NULL);
        if (status || !count) break;
        for (UInt32 i=0; i<count; ++i) {
            double t = (total+i)/target.mSampleRate;
            maxError = fmax(maxError, fabs(samples[2*i]-0.08*sin(2*M_PI*440*t)));
            maxError = fmax(maxError, fabs(samples[2*i+1]-0.06*sin(2*M_PI*997*t)));
        }
        total += count;
    }
    if (converter) AudioConverterDispose(converter);
    report(@{@"test":@"parsed-packet-decode", @"file":name, @"status":@(status),
             @"cookieStatus":@(cookieStatus), @"frames":@(total), @"maxError":@(maxError)});
}
static void parse(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url];
    __attribute__((objc_precise_lifetime)) NSMutableData *payload = [NSMutableData data], *descriptions = [NSMutableData data];
    ParseState state = {.described=YES, .payload=payload, .descriptions=descriptions}; AudioFileStreamID stream = NULL;
    AudioFileTypeID hint = [url.pathExtension isEqualToString:@"flac"] ? kAudioFileFLACType : kAudioFileM4AType;
    OSStatus status = data ? AudioFileStreamOpen(&state, property, packets, hint, &stream) : -1;
    NSUInteger consumed = 0;
    while (!status && consumed < data.length) {
        UInt32 count = (UInt32)MIN(257, data.length - consumed);
        status = AudioFileStreamParseBytes(stream, count, (const char *)data.bytes + consumed, 0);
        consumed += count;
    }
    report(@{@"test": @"incremental-parser", @"file": url.lastPathComponent, @"status": @(status),
             @"ready": @(state.ready), @"packets": @(state.packets), @"inputBytes": @(consumed),
             @"packetBytes": @(state.bytes), @"rate": @(state.format.mSampleRate),
             @"formatID": @(state.format.mFormatID), @"framesPerPacket": @(state.format.mFramesPerPacket),
             @"bits": @(state.format.mBitsPerChannel), @"channels": @(state.format.mChannelsPerFrame)});
    if (!status && state.ready && state.described && state.packets) convertPackets(&state, stream, url.lastPathComponent);
    if (stream) AudioFileStreamClose(stream);
}

static void decode(NSURL *url, double requestedRate) {
    ExtAudioFileRef file = NULL;
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)url, &file);
    AudioStreamBasicDescription source = {0}; UInt32 size = sizeof(source);
    if (!status) status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source);
    double rate = requestedRate ?: source.mSampleRate;
    AudioStreamBasicDescription target = {.mSampleRate=rate, .mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, .mBytesPerPacket=8,
        .mFramesPerPacket=1, .mBytesPerFrame=8, .mChannelsPerFrame=2, .mBitsPerChannel=32};
    if (!status) status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(target), &target);
    float samples[4096 * 2]; UInt64 total = 0; double energy = 0;
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    while (!status) {
        AudioBufferList list = {.mNumberBuffers=1, .mBuffers={{2, sizeof(samples), samples}}};
        UInt32 frames = 4096; status = ExtAudioFileRead(file, &frames, &list);
        if (status || !frames) break;
        total += frames;
        for (UInt32 i=0; i<frames*2; ++i) energy += samples[i] * samples[i];
    }
    double elapsed = CFAbsoluteTimeGetCurrent() - started;
    // Seek in FILE frames, even when the client rate differs. Check the native-rate decoded waveform.
    SInt64 seekFrame = (SInt64)(3.125 * source.mSampleRate);
    OSStatus seekStatus = status ?: ExtAudioFileSeek(file, seekFrame);
    UInt32 seekFrames = 1024; double maxError = 0;
    if (!seekStatus) {
        AudioBufferList list = {.mNumberBuffers=1, .mBuffers={{2, sizeof(samples), samples}}};
        seekStatus = ExtAudioFileRead(file, &seekFrames, &list);
        if (rate == source.mSampleRate) for (UInt32 i=0; i<seekFrames; ++i) {
            double t = (seekFrame + i) / source.mSampleRate;
            maxError = fmax(maxError, fabs(samples[2*i] - 0.08*sin(2*M_PI*440*t)));
            maxError = fmax(maxError, fabs(samples[2*i+1] - 0.06*sin(2*M_PI*997*t)));
        }
    }
    if (file) ExtAudioFileDispose(file);
    report(@{@"test": @"local-decode-seek", @"file": url.lastPathComponent, @"status": @(status),
             @"sourceRate": @(source.mSampleRate), @"sourceBits": @(source.mBitsPerChannel),
             @"clientRate": @(rate), @"frames": @(total), @"energy": @(energy), @"decodeSeconds": @(elapsed),
             @"seekStatus": @(seekStatus), @"seekFrames": @(seekFrames),
             @"seekMaxError": rate == source.mSampleRate ? @(maxError) : NSNull.null});
}

static void reader(NSURL *url) {
    // This runs on a worker, including asynchronous asset loading; no render thread is involved.
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{ dispatch_semaphore_signal(loaded); }];
    if (dispatch_semaphore_wait(loaded, dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC))) {
        [asset cancelLoading]; report(@{@"test":@"asset-reader", @"file":url.lastPathComponent,
                                       @"remote":@(!url.isFileURL), @"error":@"load-timeout"}); return;
    }
    NSError *error = nil;
    AVKeyValueStatus loadStatus = [asset statusOfValueForKey:@"tracks" error:&error];
    AVAssetTrack *track = loadStatus == AVKeyValueStatusLoaded ? [asset tracksWithMediaType:AVMediaTypeAudio].firstObject : nil;
    AVAssetReader *reader = track ? [[AVAssetReader alloc] initWithAsset:asset error:&error] : nil;
    AVAssetReaderTrackOutput *output = nil;
    if (reader) {
        output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{
            AVFormatIDKey:@(kAudioFormatLinearPCM), AVLinearPCMIsFloatKey:@YES, AVLinearPCMBitDepthKey:@32,
            AVLinearPCMIsNonInterleaved:@NO}];
        if ([reader canAddOutput:output]) [reader addOutput:output];
        else { [reader cancelReading]; reader = nil; }
    }
    BOOL started = NO; UInt64 frames = 0; double firstPTS = -1, sampleRate = 0;
    if (reader) {
        reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(3.125, 1000000), CMTimeMakeWithSeconds(1, 1000000));
        started = [reader startReading];
        if (started) {
            CMSampleBufferRef sample;
            while ((sample = [output copyNextSampleBuffer])) {
                if (firstPTS < 0) firstPTS = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
                frames += CMSampleBufferGetNumSamples(sample);
                const AudioStreamBasicDescription *format = CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
                if (format) sampleRate = format->mSampleRate;
                CFRelease(sample);
            }
        }
        error = reader.error ?: error;
    }
    report(@{@"test":@"asset-reader", @"file":url.lastPathComponent, @"remote":@(!url.isFileURL),
             @"loadStatus":@(loadStatus), @"started":@(started), @"readerStatus":@(reader.status),
             @"frames":@(frames), @"rate":@(sampleRate), @"firstPTS":@(firstPTS),
             @"errorDomain": error.domain ?: @"", @"errorCode":@(error.code),
             @"error":error.localizedDescription ?: @""});
}

@interface LosslessProbe : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation LosslessProbe
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            report(@{@"test":@"environment", @"os":UIDevice.currentDevice.systemVersion,
                     @"scope":@"simulator native decoding only; no Spotify playback"});
            NSString *base = NSProcessInfo.processInfo.environment[@"LOSSLESS_HTTP_BASE"];
            for (NSString *name in @[@"cd.flac", @"hires.flac", @"alac.m4a", @"alac-fast.m4a"]) {
                NSURL *url = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:name];
                parse(url); decode(url, 0); decode(url, 44100); reader(url);
                if (base.length) reader([[NSURL URLWithString:base] URLByAppendingPathComponent:name]);
            }
            report(@{@"test":@"complete"});
            exit(0);
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60*NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        report(@{@"test":@"watchdog-timeout"}); exit(124);
    });
    return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"LosslessProbe"); } }
