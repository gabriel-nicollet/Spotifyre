// Sing in the simulator, end to end: the voice model downloaded by SGSingModel.m from Hugging Face and checked,
// loaded by Sing.x, and Spotify's audio chain rebuilt with real Core Audio units (a converter fed by a render
// callback, a mixer and RemoteIO, wired with MakeConnection, slices of 4096) with SpeedPitch.x and Sing.x
// compiled in. The harness is the main executable, so its AudioUnitSetProperty and AudioOutputUnitStart go
// through the rebound import slots as Spotify's do, and Sing's stage runs in Speed and pitch's chain.
//
// The converter's callback stands in for Spotify's decoder: a voice (macOS's speech, bundled by build-sim.sh)
// over synthetic chords. A mock SPTPlayerState computes -position the way Spotify's does (positionAsOfTimestamp
// messaged and run on from its timestamp, disassembly at 0x1057735ec), reported as Spotify's player reports: when
// playing starts and on a seek, not as it plays. A mock SPTEsperantoPlayer moves the decoder on seekTo:. A render
// notify on the RemoteIO unit records what plays. The script: Sing on at the vocals' 0, play, seek, rest at As sung,
// separate again, the thermal state Serious and back to Fair, a memory warning's stop, a pause and a resume, Sing
// off; each check prints a line, and what played is scored against the chords alone.
//
//     THEOS=$HOME/theos VOICE=speech.aiff ./build-sim.sh
//     xcrun simctl install <udid> build/sim/SingHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.singharness
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "Shared/Sing/Sing.h"
#import "Shared/Sing/SGSingLoader.h"

static const double kRate = 44100;
enum { kMixSeconds = 60, kRecordSeconds = 70 };

static int sg_failures;
// The vocals' checks need the model to keep up, which the simulator's Core ML (on the CPU) does not: there they
// are reported as skipped, with the time a window took.
static BOOL sg_modelKeepsUp = YES;
#define VOCALS_CHECK(ok, ...) do { if (sg_modelKeepsUp) CHECK(ok, __VA_ARGS__); else NSLog(@"[harness] skipped %@ (Sing is %@: the model is slower than the song here)", [NSString stringWithFormat:__VA_ARGS__], SGSingStatusText()); } while (0)
#define CHECK(ok, ...) do { bool _ok = (ok); if (!_ok) sg_failures++; NSLog(@"[harness] %@ %@", _ok ? @"  ok  " : @"FAILED", [NSString stringWithFormat:__VA_ARGS__]); } while (0)

#pragma mark - Spotify's player, as far as Sing reads it

// Shared/Player/PlayerState.x's: the harness's last report, told to Sing's track watcher when the script says.
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}

@protocol SGHarnessWatcher
- (void)playerStateDidChange:(id)state;
@end

static id sg_watcher, sg_reported, sg_player;

// Which clock the mock player keeps (launch argument -clock): Spotify's last report run on by the time, read as it is
// (report); that report stamped again at every read of the player's state, the same line of the clock (restamp); or
// reported again every half second with what the decoder has handed over (decoded).
typedef NS_ENUM(NSInteger, SGHarnessClock) { SGHarnessClockReport, SGHarnessClockRestamp, SGHarnessClockDecoded };
static SGHarnessClock sg_clock;

void SGAddPlayerStateObserver(id observer) {
    sg_watcher = observer;
}

id SGPlayerState(void) {
    return sg_reported;
}

// Shared/Lyrics/KaraokeSource.x's: the player the lyrics read and seek, the mock below, sent the line's time in seconds.
@class SPTPlayerState;
@interface SPTEsperantoPlayer : NSObject
- (id)seekTo:(double)position;
- (SPTPlayerState *)state;
@end

id SGKaraokePlayer(void) {
    return sg_player;
}

void SGKaraokeSeek(NSInteger ms) {
    [sg_player seekTo:ms / 1000.0];
}

// Shared/HeadGestures' head motion, for spatial voice: none in the simulator, so the voice stays ahead.
void SGHeadMotionListen(NSString *name, void (^handler)(id motion)) {}
void SGHeadMotionAskPermission(void) {}
BOOL SGHeadGesturesAvailable(void) {
    return NO;
}

@interface SPTPlayerState : NSObject
@property (nonatomic) double positionAsOfTimestamp;
@property (nonatomic) double spotifyAsOf;   // the same, out of the hook's reach, for the mock to stamp again
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic) BOOL isPaused, isPlaying;
@property (nonatomic) double duration;
@property (nonatomic, strong) id track;
@end

@implementation SPTPlayerState
- (double)playbackSpeed {
    return 1;
}
// As Spotify's: -1 kept, otherwise run on by the time since, never below 0.
- (double)position {
    double asOf = [self positionAsOfTimestamp];
    if (asOf == -1) return asOf;
    return MAX(0, asOf - self.timestamp.timeIntervalSinceNow * [self playbackSpeed]);
}
@end

// The thermal state Sing reads, set by the script.
static NSProcessInfoThermalState sg_thermal = NSProcessInfoThermalStateNominal;

static NSProcessInfoThermalState thermalState(id self, SEL _cmd) {
    return sg_thermal;
}

static void setThermal(NSProcessInfoThermalState state) {
    sg_thermal = state;
    [NSNotificationCenter.defaultCenter postNotificationName:NSProcessInfoThermalStateDidChangeNotification object:NSProcessInfo.processInfo];
}

#pragma mark - the decoder

static float *sg_left, *sg_right, *sg_chordsLeft, *sg_chordsRight;
static size_t sg_mixFrames;
static atomic_uint_fast64_t sg_decoded;   // frames handed over
static atomic_uint_fast64_t sg_readAt;    // where in the mix the next one comes from

static OSStatus decoder(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                        UInt32 frames, AudioBufferList *data) {
    uint64_t at = atomic_fetch_add(&sg_readAt, frames);
    atomic_fetch_add(&sg_decoded, frames);
    float *left = data->mBuffers[0].mData, *right = data->mNumberBuffers > 1 ? data->mBuffers[1].mData : left;
    for (UInt32 i = 0; i < frames; i++) {
        size_t index = (size_t)((at + i) % sg_mixFrames);
        left[i] = sg_left[index];
        right[i] = sg_right[index];
    }
    return noErr;
}

static id sg_seekResult;

// Each command returns an object of Spotify's, which the hook must hand back.
@implementation SPTEsperantoPlayer
// As Spotify's, into the last seek, which moves the decoder.
- (id)seekTo:(double)position {
    return [self seekTo:position relative:0 options:nil creatorTimestampPositionMs:-1];
}
- (SPTPlayerState *)state {
    SPTPlayerState *reported = sg_reported;
    if (sg_clock != SGHarnessClockRestamp || !reported || reported.isPaused) return reported;
    SPTPlayerState *again = [SPTPlayerState new];
    again.timestamp = [NSDate date];
    again.positionAsOfTimestamp = again.spotifyAsOf = reported.spotifyAsOf - reported.timestamp.timeIntervalSinceNow;
    again.isPlaying = YES;
    return again;
}
- (id)seekTo:(double)position relative:(long long)relative { return sg_seekResult; }
- (id)seekTo:(double)position options:(id)options { return [self seekTo:position]; }
- (id)seekTo:(double)position relative:(long long)relative options:(id)options { return sg_seekResult; }
- (id)seekTo:(double)position relative:(long long)relative options:(id)options creatorTimestampPositionMs:(double)creator {
    atomic_store(&sg_readAt, (uint64_t)(position * kRate));
    return sg_seekResult;
}
- (id)skipToNextTrackWithOptions:(id)options { return sg_seekResult; }
- (id)skipToPreviousTrackWithOptions:(id)options { return sg_seekResult; }
- (id)skipToNextTrackWithOptions:(id)options track:(id)track { return sg_seekResult; }
- (id)skipToPreviousTrackWithOptions:(id)options track:(id)track { return sg_seekResult; }
- (id)stop { return sg_seekResult; }
@end

#pragma mark - what plays

static float *sg_heardLeft, *sg_heardRight;
static size_t sg_heardCapacity;
static atomic_uint_fast64_t sg_heard;
static double sg_hardwareRate;

static OSStatus record(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                       UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || data->mNumberBuffers < 2) return noErr;
    uint64_t at = atomic_load(&sg_heard);
    for (UInt32 i = 0; i < frames && at + i < sg_heardCapacity; i++) {
        sg_heardLeft[at + i] = ((float *)data->mBuffers[0].mData)[i];
        sg_heardRight[at + i] = ((float *)data->mBuffers[1].mData)[i];
    }
    atomic_store(&sg_heard, at + frames);
    return noErr;
}

#pragma mark - the mix

static void makeMix(void) {
    sg_mixFrames = (size_t)(kMixSeconds * kRate);
    sg_left = calloc(sg_mixFrames, sizeof(float));
    sg_right = calloc(sg_mixFrames, sizeof(float));
    sg_chordsLeft = calloc(sg_mixFrames, sizeof(float));
    sg_chordsRight = calloc(sg_mixFrames, sizeof(float));
    float *voice = calloc(sg_mixFrames, sizeof(float));
    size_t voiceFrames = 0;
    NSURL *url = [NSBundle.mainBundle URLForResource:@"voice" withExtension:@"aiff"];
    ExtAudioFileRef file;
    if (url && !ExtAudioFileOpenURL((__bridge CFURLRef)url, &file)) {
        AudioStreamBasicDescription format = {kRate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked, 4, 1, 4, 1, 32, 0};
        ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof format, &format);
        while (voiceFrames < sg_mixFrames) {
            UInt32 frames = (UInt32)MIN((size_t)8192, sg_mixFrames - voiceFrames);
            AudioBufferList list = {1, {{1, frames * 4, voice + voiceFrames}}};
            if (ExtAudioFileRead(file, &frames, &list) || !frames) break;
            voiceFrames += frames;
        }
        ExtAudioFileDispose(file);
    }
    NSLog(@"[harness] the voice is %.1f s long", voiceFrames / kRate);
    static const double roots[] = {130.81, 174.61, 196.00, 110.00}, ratios[] = {1, 1.26, 1.5, 2};
    size_t beat = (size_t)kRate / 2;
    for (size_t i = 0; i < sg_mixFrames; i++) {
        size_t bar = i / (beat * 4), within = i % beat;
        double root = roots[bar % 4], env = exp(-3.0 * within / beat), t = i / kRate, l = 0, r = 0;
        for (int n = 0; n < 4; n++) {
            double f = root * ratios[n], tone = sin(2 * M_PI * f * t) + 0.4 * sin(4 * M_PI * f * t) + 0.2 * sin(6 * M_PI * f * t);
            l += tone * (n % 2 ? 0.6 : 1.0);
            r += tone * (n % 2 ? 1.0 : 0.6);
        }
        sg_chordsLeft[i] = (float)(0.06 * env * l);
        sg_chordsRight[i] = (float)(0.06 * env * r);
        // The voice over and over, a second apart, from a second in.
        size_t from = i >= (size_t)kRate && voiceFrames ? (i - (size_t)kRate) % (voiceFrames + (size_t)kRate) : SIZE_MAX;
        float v = from < voiceFrames ? 0.5f * voice[from] : 0;
        sg_left[i] = sg_chordsLeft[i] + v;
        sg_right[i] = sg_chordsRight[i] + v;
    }
    free(voice);
}

// What played, at the hardware's rate, brought to 44.1 kHz.
static NSArray<NSData *> *heardAt44k(size_t *frames) {
    size_t count = MIN((size_t)atomic_load(&sg_heard), sg_heardCapacity);
    AVAudioFormat *from = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sg_hardwareRate channels:2 interleaved:NO];
    AVAudioFormat *to = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:kRate channels:2 interleaved:NO];
    AVAudioPCMBuffer *input = [[AVAudioPCMBuffer alloc] initWithPCMFormat:from frameCapacity:(AVAudioFrameCount)count];
    memcpy(input.floatChannelData[0], sg_heardLeft, count * sizeof(float));
    memcpy(input.floatChannelData[1], sg_heardRight, count * sizeof(float));
    input.frameLength = (AVAudioFrameCount)count;
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:from toFormat:to];
    converter.sampleRateConverterQuality = AVAudioQualityMax;
    AVAudioPCMBuffer *output = [[AVAudioPCMBuffer alloc] initWithPCMFormat:to frameCapacity:(AVAudioFrameCount)(count * kRate / sg_hardwareRate + 4096)];
    __block BOOL given = NO;
    [converter convertToBuffer:output error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount packets, AVAudioConverterInputStatus *status) {
        if (given) {
            *status = AVAudioConverterInputStatus_EndOfStream;
            return nil;
        }
        given = YES;
        *status = AVAudioConverterInputStatus_HaveData;
        return input;
    }];
    *frames = output.frameLength;
    return @[[NSData dataWithBytes:output.floatChannelData[0] length:output.frameLength * sizeof(float)],
             [NSData dataWithBytes:output.floatChannelData[1] length:output.frameLength * sizeof(float)]];
}

static double snr(const float *truthL, const float *truthR, const float *left, const float *right, size_t from, size_t to) {
    double signal = 0, noise = 0;
    for (size_t i = from; i < to; i++) {
        signal += truthL[i] * truthL[i] + truthR[i] * truthR[i];
        double l = left[i] - truthL[i], r = right[i] - truthR[i];
        noise += l * l + r * r;
    }
    return 10 * log10(signal / fmax(noise, 1e-20));
}

#pragma mark - the app

static AudioUnit make(OSType type, OSType subType) {
    AudioComponentDescription description = {type, subType, kAudioUnitManufacturer_Apple, 0, 0};
    AudioUnit unit = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &description), &unit);
    return unit;
}

static void check(OSStatus status, const char *what) {
    if (status) NSLog(@"[harness] %s failed: %d", what, (int)status);
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate {
    AudioUnit _output;
    CFTimeInterval _startedAt;
    uint64_t _lastDecoded;
    CFTimeInterval _lastAt;
    SPTPlayerState *_state;
    BOOL _paused;
    CFTimeInterval _tappedAt;
    double _seekLead;
}

- (void)startChain {
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    AudioUnit converter = make(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    AudioUnit mixer = make(kAudioUnitType_Mixer, kAudioUnitSubType_MultiChannelMixer);
    _output = make(kAudioUnitType_Output, kAudioUnitSubType_RemoteIO);
    AURenderCallbackStruct callback = {decoder, NULL};
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback), "callback");
    AudioUnitConnection toMixer = {converter, 0, 0}, toOutput = {mixer, 0, 0};
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toMixer, sizeof toMixer), "connect mixer");
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &toOutput, sizeof toOutput), "connect output");
    AudioStreamBasicDescription format = {kRate, kAudioFormatLinearPCM, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "converter in");
    check(AudioUnitSetProperty(converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "converter out");
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "mixer in");
    check(AudioUnitSetProperty(mixer, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof format), "mixer out");
    check(AudioUnitSetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format), "output in");
    UInt32 slice = 4096;
    AudioUnit units[] = {converter, mixer, _output};
    for (int i = 0; i < 3; i++) check(AudioUnitSetProperty(units[i], kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &slice, sizeof slice), "slice");
    for (int i = 0; i < 3; i++) check(AudioUnitInitialize(units[i]), "initialize");
    AudioStreamBasicDescription hardware = {0};
    UInt32 size = sizeof hardware;
    AudioUnitGetProperty(_output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &hardware, &size);
    sg_hardwareRate = hardware.mSampleRate;
    sg_heardCapacity = (size_t)(kRecordSeconds * sg_hardwareRate);
    sg_heardLeft = calloc(sg_heardCapacity, sizeof(float));
    sg_heardRight = calloc(sg_heardCapacity, sizeof(float));
    check(AudioOutputUnitStart(_output), "start");
    check(AudioUnitAddRenderNotify(_output, record, NULL), "record");
    _startedAt = CACurrentMediaTime();
    _lastAt = _startedAt;
    NSLog(@"[harness] the chain runs, the hardware at %.0f Hz", sg_hardwareRate);
}

- (void)after:(double)seconds do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// The player reporting what the decoder has handed over, as Spotify's does on a change (playing, a seek), not as it plays.
- (void)playerReports {
    _state = [SPTPlayerState new];
    _state.positionAsOfTimestamp = _state.spotifyAsOf = atomic_load(&sg_readAt) / kRate;
    _state.timestamp = [NSDate date];
    _state.isPaused = _paused;
    _state.isPlaying = YES;
    sg_reported = _state;
}

// What is heard now, in seconds of the mix: what the output played, less what a seek skipped.
- (double)heardContent {
    return atomic_load(&sg_heard) / sg_hardwareRate;
}

// Where in the mix what is heard now is, by the decoder less what Sing holds (the Mac harness checks the lead to the frame).
- (double)heardInMix {
    return atomic_load(&sg_readAt) / kRate - SGSingHeldLead();
}

- (void)report {
    CFTimeInterval now = CACurrentMediaTime();
    uint64_t decoded = atomic_load(&sg_decoded);
    NSLog(@"[harness] %5.1f s  %-22@ decoder %.2fx  position %.2f s, heard %.2f s, decoded %.2f s, lead %.2f s",
          now - _startedAt, SGSingStatusText(), (decoded - _lastDecoded) / kRate / (now - _lastAt), _state.position,
          [self heardInMix], atomic_load(&sg_readAt) / kRate, SGSingHeldLead());
    _lastDecoded = decoded;
    _lastAt = now;
}

- (void)waitFor:(BOOL (^)(void))condition every:(double)seconds then:(void (^)(void))then {
    if (condition()) {
        then();
        return;
    }
    [self after:seconds do:^{ [self waitFor:condition every:seconds then:then]; }];
}

// The position Spotify shows against where in the mix what is heard is.
// The state the lyrics read: the player's.
- (SPTPlayerState *)lyricsState {
    return [(SPTEsperantoPlayer *)sg_player state];
}

- (void)checkPosition:(NSString *)when {
    double position = [self lyricsState].position, heard = [self heardInMix];
    CHECK(fabs(position - heard) < 0.15, @"%@ the position Spotify shows, %.2f s, is what is heard, %.2f s (decoded %.2f s, %.2f s held)", when, position, heard,
          atomic_load(&sg_readAt) / kRate, SGSingHeldLead());
}

- (void)play {
    // Spotify reports that it plays, once, and its clock runs on by itself from there; or, as the decoded clock,
    // again every half second while it plays.
    [self playerReports];
    if (sg_clock == SGHarnessClockDecoded) {
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            if (!self->_paused) [self playerReports];
        }];
    }
    for (int s = 1; s <= 100; s++) [self after:s do:^{ [self report]; }];
    [self after:14 do:^{
        double heard = [self heardContent], position = [self lyricsState].position, decoded = atomic_load(&sg_decoded) / kRate;
        sg_modelKeepsUp = SGSingCurrentState() != SGSingStateBehind && SGSingCurrentState() != SGSingStateBuffering;
        VOCALS_CHECK(SGSingCurrentState() == SGSingStateSinging, @"Sing is on with the vocals down at 14 s (%@)", SGSingStatusText());
        CHECK(SGSingHeldLead() > 2 && fabs(decoded - heard - SGSingHeldLead()) < 0.1,
              @"the lead Sing reports, %.2f s, is what the decoder handed over less what was heard (%.2f s less %.2f s)", SGSingHeldLead(), decoded, heard);
        CHECK(fabs(position - heard) < 0.15, @"as the lead filled, the position the lyrics read, %.2f s, is what is heard, %.2f s, "
              @"not what was decoded, %.2f s, nor that less the lead now, %.2f s", position, heard, decoded, position - SGSingHeldLead());
    }];
    // A tap on the lyrics line at 5 s, with the lead held: the lyrics' seek, as the karaoke view sends it.
    [self after:20 do:^{
        self->_seekLead = SGSingHeldLead();
        CHECK(self->_seekLead > 2, @"before the tap a lead is held (%.2f s)", self->_seekLead);
        SGKaraokeSeek(5000);
        [self playerReports];
        self->_tappedAt = CACurrentMediaTime();
        CHECK(fabs(atomic_load(&sg_readAt) / kRate - 5) < 0.05, @"the tap sends Spotify to the line's 5.00 s (%.2f s)", atomic_load(&sg_readAt) / kRate);
    }];
    [self after:20.5 do:^{
        double ahead = atomic_load(&sg_readAt) / kRate - [self lyricsState].position;
        CHECK(ahead < 1.2, @"the seek dropped the %.1f s held ahead: %.2f s ahead half a second later", self->_seekLead, ahead);
    }];
    [self after:21 do:^{
        double since = CACurrentMediaTime() - self->_tappedAt, heard = [self heardInMix];
        CHECK(fabs(heard - (5 + since)) < 0.2, @"a second after the tap what is heard is the line's 5 s run on by %.2f s: %.2f s", since, heard);
        [self checkPosition:@"a second after the tap,"];
    }];
    [self after:27 do:^{
        CHECK(SGSingHeldLead() > 2, @"after the seek the lead is built again (%.2f s)", SGSingHeldLead());
        [self checkPosition:@"seven seconds after the seek, with no report since,"];
        // At As sung with Spatial voice off and no page reading the lines, Sing rests.
        SGSetSingLevel(1);
    }];
    [self after:29 do:^{
        CHECK(SGSingCurrentState() == SGSingStateWaiting && [SGSingStatusText() isEqualToString:@"As sung"] && SGSingHeldLead() > 2,
              @"resting at As sung, Sing reads %@ and plays on the %.2f s it holds as they are", SGSingStatusText(), SGSingHeldLead());
        [self checkPosition:@"resting,"];
        SGSetSingLevel(0);
    }];
    [self after:31 do:^{
        CHECK(SGSingHeldLead() > 2, @"separating again, the lead was kept (%.2f s)", SGSingHeldLead());
        [self checkPosition:@"separating again,"];
        setThermal(NSProcessInfoThermalStateSerious);
    }];
    [self after:32 do:^{
        CHECK(SGSingCurrentState() == SGSingStateHot && SGSingHeldLead() > 2 && !SGSingLoaderSeparator(),
              @"at the thermal state Serious Sing is held (%@), the model let go and the %.2f s held played on", SGSingStatusText(), SGSingHeldLead());
        [self checkPosition:@"held at Serious,"];
        setThermal(NSProcessInfoThermalStateFair);
        CFTimeInterval fair = CACurrentMediaTime();
        [self waitFor:^BOOL { return SGSingLoaderSeparator() || CACurrentMediaTime() - fair > 40; } every:0.25 then:^{
            CHECK(SGSingCurrentState() != SGSingStateHot && SGSingLoaderSeparator() && SGSingHeldLead() > 2,
                  @"at Fair it loads the model again in %.1f s (%@), the lead kept (%.2f s)", CACurrentMediaTime() - fair, SGSingStatusText(), SGSingHeldLead());
            [self checkPosition:@"running again,"];
            // A memory warning stops Sing with the mic still on.
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:UIApplication.sharedApplication];
            [self after:1 do:^{
                CHECK(SGSingOn() && [SGSingStatusText() isEqualToString:@"Stopped"] && SGSingHeldLead() > 2,
                      @"stopped by a memory warning, Sing reads %@ and plays on the %.2f s it holds", SGSingStatusText(), SGSingHeldLead());
                [self checkPosition:@"stopped,"];
                [self pauseThenResume];
            }];
        }];
    }];
}

// Spotify pauses (its output stops and it reports), Sing seeks it back to what was heard, which drops the lead, and
// Spotify resumes from there: nothing heard is lost.
- (void)pauseThenResume {
    double heard = [self heardInMix], lead = SGSingHeldLead();
    AudioOutputUnitStop(_output);
    _paused = YES;
    [self playerReports];
    [sg_watcher playerStateDidChange:_state];
    [self playerReports];   // Spotify's report of the seek
    double seekedTo = atomic_load(&sg_readAt) / kRate;
    CHECK(fabs(seekedTo - heard) < 0.15 && SGSingHeldLead() == 0, @"paused, Spotify is seeked back from %.2f s to %.2f s, what was heard (%.2f s), and the %.2f s held "
          @"are let go (%.2f s held)", heard + lead, seekedTo, heard, lead, SGSingHeldLead());
    [self checkPosition:@"paused,"];
    _paused = NO;
    AudioOutputUnitStart(_output);
    [self playerReports];
    CFTimeInterval resumed = CACurrentMediaTime();
    [self after:2 do:^{
        double since = CACurrentMediaTime() - resumed;
        CHECK(SGSingHeldLead() < 0.001 && fabs([self heardInMix] - (heard + since)) < 0.2,
              @"resumed, the song plays on from %.2f s, where it was heard, nothing skipped: %.2f s heard %.2f s on (%.2f s held)", heard, [self heardInMix], since,
              SGSingHeldLead());
        [self checkPosition:@"resumed,"];
        SGSetSingOn(NO);
        [self after:1 do:^{
            CHECK(SGSingHeldLead() < 0.001 && SGSingCurrentState() == SGSingStateOff, @"switched off, nothing is held (%.3f s) and Sing is %@",
                  SGSingHeldLead(), SGSingStatusText());
            [self score];
            NSLog(@"[harness] %@", sg_failures ? @"FAILED" : @"all passed");
            exit(sg_failures ? 1 : 0);
        }];
    }];
}

// What played from 6 s to 19 s against the chords alone, beside the mix's own score. Before the seek what plays
// is the mix in order, so the two line up but for the resampler's delay, found on the first second (dry).
- (void)score {
    size_t frames;
    NSArray<NSData *> *heard = heardAt44k(&frames);
    const float *left = heard[0].bytes, *right = heard[1].bytes;
    size_t from = (size_t)(6 * kRate), to = (size_t)(19 * kRate);
    if (frames < to + 1000) {
        CHECK(NO, @"enough was heard to score (%.1f s)", frames / kRate);
        return;
    }
    int best = 0;
    double bestScore = -INFINITY;
    for (int lag = -64; lag <= 64; lag++) {
        double dot = 0;
        for (size_t i = (size_t)kRate / 4; i < (size_t)kRate; i++) dot += left[i + lag] * sg_left[i];
        if (dot > bestScore) bestScore = dot, best = lag;
    }
    double dry = snr(sg_left, sg_right, left + best, right + best, (size_t)(kRate / 4), (size_t)kRate);
    NSLog(@"[harness] what plays lags the mix by %d frames after resampling; the first second matches the mix to %.1f dB", best, dry);
    double karaoke = snr(sg_chordsLeft, sg_chordsRight, left + best, right + best, from, to);
    double mix = snr(sg_chordsLeft, sg_chordsRight, sg_left, sg_right, from, to);
    VOCALS_CHECK(karaoke > mix + 15, @"from 6 s to 19 s what plays scores %.1f dB against the chords alone, the mix %.1f dB", karaoke, mix);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    sg_seekResult = [NSObject new];
    sg_player = [SPTEsperantoPlayer new];
    NSString *clock = [NSUserDefaults.standardUserDefaults stringForKey:@"clock"];
    sg_clock = [clock isEqualToString:@"restamp"] ? SGHarnessClockRestamp : [clock isEqualToString:@"decoded"] ? SGHarnessClockDecoded : SGHarnessClockReport;
    NSLog(@"[harness] Spotify's clock: %@", @[@"its last report run on", @"its last report stamped again at every read", @"reported again every 0.5 s with what was decoded"][sg_clock]);
    // On the class processInfo really is, which may override NSProcessInfo's.
    class_replaceMethod(object_getClass(NSProcessInfo.processInfo), @selector(thermalState), (IMP)thermalState, "q16@0:8");
    makeMix();
    NSLog(@"[harness] Sing: %@ (%@)", SGSingStatusText(), SGSingMissing() ?: @"nothing missing");
    CFTimeInterval began = CACurrentMediaTime();
    if (SGSingModelCurrentState() != SGSingModelReady) SGSingDownloadModel();
    __block CFTimeInterval logged = 0;
    [self waitFor:^BOOL {
        if (CACurrentMediaTime() - logged > 5) {
            logged = CACurrentMediaTime();
            NSLog(@"[harness] %@", SGSingStatusText());
        }
        return SGSingModelCurrentState() != SGSingModelDownloading;
    } every:0.5 then:^{
        CHECK(SGSingModelCurrentState() == SGSingModelReady, @"the voice model is on the phone, checked (%@, %.0f s)", SGSingModelError() ?: @"no error",
              CACurrentMediaTime() - began);
        if (SGSingModelCurrentState() != SGSingModelReady) exit(1);
        SGSetSingLevel(0);
        CFTimeInterval loading = CACurrentMediaTime();
        SGSetSingOn(YES);
        [self waitFor:^BOOL { return SGSingCurrentState() != SGSingStatePreparing; } every:0.25 then:^{
            CHECK(SGSingCurrentState() == SGSingStateWaiting, @"the model loads in %.1f s, and Sing waits for Spotify (%@)", CACurrentMediaTime() - loading,
                  SGSingStatusText());
            [self startChain];
            [self play];
        }];
    }];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
