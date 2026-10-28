// Runs SGTimePitch.m on the Mac both ways the tweak runs it: in place over IO buffers of Spotify's sizes
// (pitch alone), and pulling a source at a rate (speed, with or without pitch). Checks a sine comes out
// at the pitch asked for and the source is consumed at the rate asked for, reports the unit's pulls,
// underruns, delay and cost, and writes a song shifted up and down to listen to.
//
//     ./build.sh && build/pitch [song]
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import "Shared/Player/SGTimePitch.h"

static const double kRate = 44100;

// Frequency by the zero crossings of the steady part.
static double frequency(const float *samples, size_t count) {
    size_t first = 0, last = 0, crossings = 0;
    for (size_t i = 1; i < count; i++) {
        if (samples[i - 1] < 0 && samples[i] >= 0) {
            if (!crossings) first = i;
            last = i;
            crossings++;
        }
    }
    return crossings > 1 ? (crossings - 1) * kRate / (last - first) : 0;
}

// The frame where the output first gets loud: the delay the shifter adds.
static size_t onset(const float *samples, size_t count) {
    for (size_t i = 0; i < count; i++) if (fabsf(samples[i]) > 0.1f) return i;
    return count;
}

static UInt32 bufferSize(size_t index, int pattern) {
    if (pattern == 0) return 1024;
    if (pattern == 1) return 4096;
    static const UInt32 odd[] = {470, 471, 512, 1024, 256, 941};
    return odd[index % 6];
}

static void runSine(float semitones, int pattern) {
    size_t total = (size_t)(kRate * 3);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t i = 0; i < total; i++) left[i] = right[i] = 0.5f * sinf(2 * M_PI * 440 * i / kRate);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    if (!shifter) {
        printf("no shifter\n");
        exit(1);
    }
    SGTimePitchSetSemitones(shifter, semitones);
    SGTimePitchReset(shifter);
    uint64_t start = mach_absolute_time();
    size_t done = 0, index = 0;
    while (done < total) {
        UInt32 frames = (UInt32)MIN((size_t)bufferSize(index++, pattern), total - done);
        float *channels[2] = {left + done, right + done};
        if (!SGTimePitchProcess(shifter, channels, frames)) printf("  process failed at %zu\n", done);
        done += frames;
    }
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    double seconds = (mach_absolute_time() - start) * (double)timebase.numer / timebase.denom / 1e9;
    double expected = 440 * pow(2, semitones / 12);
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    printf("sine %+5.1f st, buffers %-8s: %6.1f Hz (want %6.1f, %+.2f%%), delay %4zu frames (unit %.1f ms), largest pull %u, underruns %u, failures %u, cost %.2f%% of real time\n",
           semitones, pattern == 0 ? "1024" : pattern == 1 ? "4096" : "mixed", measured, expected, (measured / expected - 1) * 100,
           onset(left, total), SGTimePitchLatency(shifter) * 1000, SGTimePitchLargestPull(shifter),
           SGTimePitchUnderruns(shifter), SGTimePitchFailures(shifter), seconds / 3 * 100);
    free(left);
    free(right);
}

static void runSong(NSString *path, float semitones, NSString *outPath) {
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) {
        printf("cannot open %s\n", path.UTF8String);
        return;
    }
    AudioStreamBasicDescription format = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 32,
    };
    ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    ExtAudioFileRef output;
    AudioStreamBasicDescription wav = {
        .mSampleRate = kRate, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4, .mChannelsPerFrame = 2, .mBitsPerChannel = 16,
    };
    ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:outPath], kAudioFileWAVEType, &wav, NULL, kAudioFileFlags_EraseFile, &output);
    ExtAudioFileSetProperty(output, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
    SGTimePitch *shifter = SGTimePitchCreate(kRate, 2, NULL, NULL);
    SGTimePitchSetSemitones(shifter, semitones);
    float left[1024], right[1024];
    size_t seconds = 0;
    for (;;) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
        UInt32 frames = 1024;
        if (ExtAudioFileRead(file, &frames, &buffers.list) || !frames) break;
        float *channels[2] = {left, right};
        SGTimePitchProcess(shifter, channels, frames);
        buffers.list.mBuffers[0].mDataByteSize = buffers.second.mDataByteSize = frames * 4;
        ExtAudioFileWrite(output, frames, &buffers.list);
        seconds += frames;
        if (seconds > kRate * 40) break;
    }
    ExtAudioFileDispose(file);
    ExtAudioFileDispose(output);
    printf("wrote %s (%+.0f st), underruns %u\n", outPath.UTF8String, semitones, SGTimePitchUnderruns(shifter));
}

typedef struct { double phase; } Sine;

static OSStatus sineSource(void *context, UInt32 frames, AudioBufferList *data) {
    Sine *sine = context;
    for (UInt32 i = 0; i < frames; i++) {
        float value = 0.5f * sinf(2 * M_PI * 440 * (sine->phase + i) / kRate);
        for (UInt32 c = 0; c < data->mNumberBuffers; c++) ((float *)data->mBuffers[c].mData)[i] = value;
    }
    sine->phase += frames;
    return noErr;
}

static void runPull(float rate, float semitones, bool follows) {
    Sine sine = {0};
    SGTimePitch *unit = SGTimePitchCreate(kRate, 2, sineSource, &sine);
    SGTimePitchSetFollows(unit, follows);
    SGTimePitchSetRate(unit, rate);
    SGTimePitchSetSemitones(unit, semitones);
    SGTimePitchReset(unit);
    size_t total = (size_t)(kRate * 4);
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    for (size_t done = 0; done < total; done += 1024) {
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, 4096, left + done}}}, {1, 4096, right + done}};
        if (SGTimePitchRender(unit, 1024, &buffers.list) != noErr) printf("  render failed\n");
    }
    double measured = frequency(left + (size_t)kRate, total - (size_t)kRate);
    // Following speed, the pitch rises with the rate, the way a record played faster does.
    double expected = follows && (rate != 1 || semitones == 0) ? 440 * rate : 440 * pow(2, semitones / 12);
    double consumedRate = (double)SGTimePitchConsumed(unit) / total;
    printf("pull %-10s rate %.2f %+3.0f st: %6.1f Hz (want %6.1f, %+.2f%%), consumed %.3fx, largest pull %u, failures %u\n", follows ? "varispeed" : "stretch", rate, semitones,
           measured, expected, (measured / expected - 1) * 100, consumedRate, SGTimePitchLargestPull(unit), SGTimePitchFailures(unit));
    free(left);
    free(right);
}

// The longest run of near silence, in frames, after the unit's first sound.
static size_t longestGap(const float *samples, size_t count) {
    size_t longest = 0, run = 0;
    for (size_t i = onset(samples, count); i < count; i++) {
        run = fabsf(samples[i]) < 0.01f ? run + 1 : 0;
        if (run > longest) longest = run;
    }
    return longest;
}

// One unit through a change of speed or pitch, the way the menu makes one: `before` for a second, then
// `after`, resetting only when SGTimePitchSwitchPending says (SpeedPitch.x's switchIfAsked). A sine has no
// silence longer than its zero crossings, about 2 frames, so a longer gap is the change heard.
typedef struct { float rate, semitones; bool follows; } Setting;
static bool runChange(const char *name, Setting before, Setting after, bool wantSwitch, size_t allowedGap) {
    Sine sine = {0};
    SGTimePitch *unit = SGTimePitchCreate(kRate, 2, sineSource, &sine);
    SGTimePitchSetFollows(unit, before.follows);
    SGTimePitchSetRate(unit, before.rate);
    SGTimePitchSetSemitones(unit, before.semitones);
    SGTimePitchReset(unit);
    size_t half = (size_t)kRate, total = 2 * half;
    float *left = calloc(total, sizeof(float)), *right = calloc(total, sizeof(float));
    bool switched = false, changed = false;
    for (size_t done = 0; done < total; done += 1024) {
        if (done >= half && !changed) {
            changed = true;
            SGTimePitchSetFollows(unit, after.follows);
            SGTimePitchSetRate(unit, after.rate);
            SGTimePitchSetSemitones(unit, after.semitones);
            switched = SGTimePitchSwitchPending(unit);
            if (switched) SGTimePitchReset(unit);
        }
        struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, 4096, left + done}}}, {1, 4096, right + done}};
        SGTimePitchRender(unit, 1024, &buffers.list);
    }
    size_t gap = longestGap(left, total);
    bool resamples = after.follows && (after.rate != 1 || after.semitones == 0);
    double expected = resamples ? 440 * after.rate : 440 * pow(2, after.semitones / 12);
    double measured = frequency(left + half + half / 2, half / 2);
    bool ok = switched == wantSwitch && gap <= allowedGap && fabs(measured / expected - 1) < 0.005;
    printf("%s change %-44s: %s units, longest gap %4zu frames (%.1f ms), then %6.1f Hz (want %6.1f)\n", ok ? "ok  " : "FAIL", name,
           switched ? "switched" : "kept    ", gap, gap * 1000 / kRate, measured, expected);
    free(left);
    free(right);
    return ok;
}

// The changes SpeedPitch.x makes while the unit is in, Pitch follows speed being on unless said.
static bool runChanges(void) {
    bool ok = true;
    // A hold let go, Speed reset, a drag across 1: Varispeed all along, nothing lost.
    ok &= runChange("follows, 2x to 1x", (Setting){2, 0, true}, (Setting){1, 0, true}, false, 8);
    ok &= runChange("follows, 1x to 1.5x", (Setting){1, 0, true}, (Setting){1.5f, 0, true}, false, 8);
    // Pitch alone at 1x is the stretch's, reset on the way in: its delay once, never sound from before.
    ok &= runChange("follows, 1x, pitch 0 to +3", (Setting){1, 0, true}, (Setting){1, 3, true}, true, 4200);
    ok &= runChange("follows, 1.5x +3 to 1x +3", (Setting){1.5f, 3, true}, (Setting){1, 3, true}, true, 4200);
    ok &= runChange("follows switched off at 1.5x", (Setting){1.5f, 0, true}, (Setting){1.5f, 0, false}, true, 4200);
    ok &= runChange("follows switched on at 1.5x", (Setting){1.5f, 0, false}, (Setting){1.5f, 0, true}, true, 64);
    // Without following it stays the stretch.
    ok &= runChange("stretch, 1.5x to 1x", (Setting){1.5f, 0, false}, (Setting){1, 0, false}, false, 8);
    return ok;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        for (int pattern = 0; pattern < 3; pattern++) {
            for (NSNumber *semitones in @[@-12, @-5, @-1, @0.5, @3, @7, @12]) runSine(semitones.floatValue, pattern);
        }
        for (NSNumber *rate in @[@0.5, @0.75, @1, @1.25, @1.5, @2]) {
            runPull(rate.floatValue, 0, false);
            runPull(rate.floatValue, 3, false);
            runPull(rate.floatValue, 0, true);
        }
        if (!runChanges()) {
            printf("a change failed\n");
            return 1;
        }
        if (argc > 1) {
            NSString *song = @(argv[1]);
            runSong(song, 3, @"build/song+3.wav");
            runSong(song, -4, @"build/song-4.wav");
        }
    }
    return 0;
}
