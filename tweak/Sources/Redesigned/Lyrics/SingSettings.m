// Mod Settings > Karaoke, in the redesign (App/ModSettings.x puts its row on the main page): Sing's switch and
// its voice model. The switch puts the microphone in the player's lyrics and takes it away again at once; off, Sing
// does no work at all. The model row reads out where the download is and moves along with it, over a bar
// while it runs, and the row under it is what can be done next: download it, stop the download, or remove
// the model. Below iOS 27, where the separator cannot run, the section is one row saying so.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Sing/SGSingModel.h"
#import "Shared/Sing/SGSingAlternateModels.h"
#import "Shared/Sing/SGSingDSP.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "Sing.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#include <math.h>

static void tell(NSString *title, NSString *message);

#define SGRKeySpatialReverb @"spotifyglass.redesign.spatialReverb"
#define SGRKeySpatialEcho @"spotifyglass.redesign.spatialEcho"
#define SGRKeySpatialWidth @"spotifyglass.redesign.spatialWidth"
#define SGRKeySpatialDistance @"spotifyglass.redesign.spatialDistance"
#define SGRKeySpatialGainDB @"spotifyglass.redesign.spatialGainDB"
#define SGRKeySpatialEQ @"spotifyglass.redesign.spatialEQ"
#define SGRKeySpatialEQLowDB @"spotifyglass.redesign.spatialEQLowDB"
#define SGRKeySpatialEQMidDB @"spotifyglass.redesign.spatialEQMidDB"
#define SGRKeySpatialEQHighDB @"spotifyglass.redesign.spatialEQHighDB"

static double spatialValue(NSString *key, double fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value doubleValue] : fallback;
}

static void applySpatialValues(void) {
    SGSingDSPSetSpatialParameters((float)spatialValue(SGRKeySpatialReverb, 0.26),
                                  (float)spatialValue(SGRKeySpatialEcho, 0.08),
                                  (float)spatialValue(SGRKeySpatialWidth, 0.35),
                                  (float)spatialValue(SGRKeySpatialDistance, 0.18));
    SGSingDSPSetVocalGainDB((float)spatialValue(SGRKeySpatialGainDB, 0.0));
    SGSingDSPSetVocalEQ(SGFlag(SGRKeySpatialEQ, NO),
                        (float)spatialValue(SGRKeySpatialEQLowDB, 0.0),
                        (float)spatialValue(SGRKeySpatialEQMidDB, 0.0),
                        (float)spatialValue(SGRKeySpatialEQHighDB, 0.0));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SGSpatialVoiceDemoSettingsDidChange" object:nil];
}

void SGRSpatialVoiceApplySettings(void) { applySpatialValues(); }

static void setSpatialValue(NSString *key, double value) {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    applySpatialValues();
}

@interface SGSpatialVoiceDemo : NSObject <SGPlayerStateObserver, CMHeadphoneMotionManagerDelegate>
+ (instancetype)shared;
- (BOOL)isPlaying;
- (void)play;
- (void)pauseSpotifyAndPlay;
- (void)startDemoAfterSpotifyPauses;
- (void)stop;
- (void)stopWithoutResumingSpotify;
- (void)updateEffects;
@end

@implementation SGSpatialVoiceDemo {
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_vocals, *_soundtrack;
    AVAudioUnitReverb *_reverb;
    AVAudioUnitDelay *_delay;
    AVAudioUnitEQ *_eq;
    AVAudioEnvironmentNode *_environment;
    AVAudioPCMBuffer *_voiceBuffer;
    CMHeadphoneMotionManager *_motionManager;
    NSOperationQueue *_motionQueue;
    BOOL _resumeSpotify;
    BOOL _stopOnPlayback;
    BOOL _waitingForSpotifyPause;
    BOOL _hasHeadReference;
    double _referenceYaw;
    NSUInteger _generation;
    NSUInteger _pauseAttempt;
}
+ (instancetype)shared {
    static SGSpatialVoiceDemo *demo; static dispatch_once_t once;
    dispatch_once(&once, ^{ demo = [SGSpatialVoiceDemo new]; }); return demo;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateEffects)
                                                name:@"SGSpatialVoiceDemoSettingsDidChange" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopWithoutResumingSpotify)
                                                name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(stopWithoutResumingSpotify)
                                                name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioInterrupted:)
                                                name:AVAudioSessionInterruptionNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioRouteChanged:)
                                                name:AVAudioSessionRouteChangeNotification object:nil];
    SGAddPlayerStateObserver(self);
    return self;
}
- (BOOL)isPlaying { return _engine.isRunning; }
- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (_waitingForSpotifyPause) {
        [self startDemoAfterSpotifyPauses];
        return;
    }
    if (!_engine.isRunning) return;
    if (!state.isPlaying || state.isPaused) {
        _stopOnPlayback = YES;
        return;
    }
    if (_stopOnPlayback) {
        // The user resumed Spotify while the demo was holding it. Do not resume it again
        // from stop; Spotify is already playing.
        _resumeSpotify = NO;
        [self stop];
    }
}
- (void)audioInterrupted:(NSNotification *)note {
    if ([note.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan)
        [self stopWithoutResumingSpotify];
}
- (void)audioRouteChanged:(NSNotification *)note {
    [self stopWithoutResumingSpotify];
}
- (AVAudioPCMBuffer *)monoBufferForFile:(AVAudioFile *)file error:(NSError **)error {
    AVAudioFormat *sourceFormat = file.processingFormat;
    AVAudioFormat *monoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sourceFormat.sampleRate channels:1];
    if (!monoFormat || file.length <= 0 || file.length > UINT32_MAX) return nil;
    AVAudioPCMBuffer *source = [[AVAudioPCMBuffer alloc] initWithPCMFormat:sourceFormat
                                                              frameCapacity:(AVAudioFrameCount)file.length];
    if (![file readIntoBuffer:source frameCount:(AVAudioFrameCount)file.length error:error]) return nil;
    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:monoFormat];
    if (!converter) return nil;
    AVAudioPCMBuffer *mono = [[AVAudioPCMBuffer alloc] initWithPCMFormat:monoFormat frameCapacity:source.frameLength];
    __block BOOL supplied = NO;
    AVAudioConverterOutputStatus status = [converter convertToBuffer:mono error:error withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount packets, AVAudioConverterInputStatus *inputStatus) {
        if (supplied) { *inputStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
        supplied = YES;
        *inputStatus = AVAudioConverterInputStatus_HaveData;
        return source;
    }];
    return status == AVAudioConverterOutputStatus_Error || mono.frameLength == 0 ? nil : mono;
}
- (void)startHeadTracking {
    id usage = NSBundle.mainBundle.infoDictionary[@"NSMotionUsageDescription"];
    CMAuthorizationStatus authorization = CMHeadphoneMotionManager.authorizationStatus;
    if (![usage isKindOfClass:NSString.class] || ![(NSString *)usage length] ||
        authorization == CMAuthorizationStatusDenied || authorization == CMAuthorizationStatusRestricted) return;
    if (!_motionManager) {
        _motionManager = [CMHeadphoneMotionManager new];
        _motionManager.delegate = self;
        _motionQueue = [NSOperationQueue new];
        _motionQueue.name = @"spotifyglass.spatialvoice.preview-motion";
        _motionQueue.maxConcurrentOperationCount = 1;
        _motionQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    }
    if (!_motionManager.isDeviceMotionAvailable) return;
    _hasHeadReference = NO;
    __weak typeof(self) weakSelf = self;
    [_motionManager startDeviceMotionUpdatesToQueue:_motionQueue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (error || !motion) return;
        double yaw = motion.attitude.yaw;
        if (!isfinite(yaw)) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) self = weakSelf;
            if (!self || !self->_engine.isRunning || !self->_vocals) return;
            if (!self->_hasHeadReference) {
                self->_referenceYaw = yaw;
                self->_hasHeadReference = YES;
            }
            double relative = yaw - self->_referenceYaw;
            while (relative > M_PI) relative -= 2.0 * M_PI;
            while (relative < -M_PI) relative += 2.0 * M_PI;
            double radius = 1.0 + spatialValue(SGRKeySpatialDistance, 0.18) * 4.0;
            self->_vocals.position = AVAudioMake3DPoint((float)-sin(relative) * (float)radius, 0,
                                                        (float)-cos(relative) * (float)radius);
        });
    }];
}
- (void)stopHeadTracking {
    [_motionManager stopDeviceMotionUpdates];
    _hasHeadReference = NO;
}
- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_hasHeadReference = NO;
        [self updateEffects];
    });
}
- (void)headphoneMotionManagerDidConnect:(CMHeadphoneMotionManager *)manager {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self->_engine.isRunning) [self startHeadTracking]; });
}
- (void)play {
    [self stop];
    NSString *directory = @"SpotifyreDemo.bundle";
    NSString *voicePath = [NSBundle.mainBundle pathForResource:@"Vocals" ofType:@"m4a" inDirectory:directory];
    NSString *musicPath = [NSBundle.mainBundle pathForResource:@"Soundtrack" ofType:@"m4a" inDirectory:directory];
    if (!voicePath || !musicPath) { tell(@"Demo audio unavailable", @"The demo tracks were not included in this build."); return; }
    NSError *error = nil;
    AVAudioFile *voiceFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:voicePath] error:&error];
    AVAudioFile *musicFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:musicPath] error:&error];
    if (!voiceFile || !musicFile) { tell(@"Could not open demo audio", error.localizedDescription ?: @"The demo tracks could not be read."); return; }
    AVAudioPCMBuffer *voiceBuffer = [self monoBufferForFile:voiceFile error:&error];
    if (!voiceBuffer) { tell(@"Could not prepare demo audio", error.localizedDescription ?: @"The vocal stem could not be converted for spatial playback."); return; }
    _voiceBuffer = voiceBuffer;
    _engine = [AVAudioEngine new]; _vocals = [AVAudioPlayerNode new]; _soundtrack = [AVAudioPlayerNode new];
    _reverb = [AVAudioUnitReverb new]; _delay = [AVAudioUnitDelay new]; _eq = [[AVAudioUnitEQ alloc] initWithNumberOfBands:3];
    [_engine attachNode:_vocals]; [_engine attachNode:_soundtrack]; [_engine attachNode:_eq]; [_engine attachNode:_reverb]; [_engine attachNode:_delay];
    _environment = _engine.mainMixerNode ? [AVAudioEnvironmentNode new] : nil;
    if (_environment) {
        [_engine attachNode:_environment];
        _environment.outputType = AVAudioEnvironmentOutputTypeHeadphones;
        _environment.listenerPosition = AVAudioMake3DPoint(0, 0, 0);
        _environment.listenerVectorOrientation = AVAudioMake3DVectorOrientation(AVAudioMake3DVector(0, 0, -1),
                                                                                   AVAudioMake3DVector(0, 1, 0));
        // AVAudioEnvironmentNode faces along -Z; a source at -Z is in front of the listener.
        _vocals.position = AVAudioMake3DPoint(0, 0, -1);
        _vocals.sourceMode = AVAudio3DMixingSourceModeSpatializeIfMono;
        _vocals.renderingAlgorithm = AVAudio3DMixingRenderingAlgorithmHRTF;
        // AVAudioEnvironmentNode only spatializes mono inputs. The supplied vocal file is
        // stereo, so feed the downmixed mono buffer through the HRTF source chain.
        [_engine connect:_vocals to:_eq format:voiceBuffer.format];
        [_engine connect:_eq to:_reverb format:voiceBuffer.format];
        [_engine connect:_reverb to:_delay format:voiceBuffer.format];
        [_engine connect:_delay to:_environment format:voiceBuffer.format];
        [_engine connect:_environment to:_engine.mainMixerNode format:nil];
    }
    [_engine connect:_soundtrack to:_engine.mainMixerNode format:musicFile.processingFormat];
    [self updateEffects];
    if (![_engine startAndReturnError:&error]) { tell(@"Could not start demo", error.localizedDescription ?: @"Audio could not be started."); [self stop]; return; }
    NSUInteger generation = ++_generation;
    [_vocals scheduleBuffer:voiceBuffer atTime:nil options:0 completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{ if (generation == self->_generation) [self demoFinished]; });
    }];
    [_soundtrack scheduleFile:musicFile atTime:nil completionHandler:nil];
    [_vocals play]; [_soundtrack play];
    [self startHeadTracking];
}
- (void)pauseSpotifyAndPlay {
    [self stop];
    _waitingForSpotifyPause = YES;
    NSUInteger attempt = ++_pauseAttempt;
    [(id<SPTPlayer>)SGKaraokePlayer() pause:nil];
    [self startDemoAfterSpotifyPauses];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_waitingForSpotifyPause || self->_pauseAttempt != attempt) return;
        self->_waitingForSpotifyPause = NO;
        tell(@"Spotify is still playing", @"The demo stayed stopped because Spotify did not confirm that playback paused.");
    });
}
- (void)startDemoAfterSpotifyPauses {
    if (!_waitingForSpotifyPause) return;
    SPTPlayerState *state = SGPlayerState();
    if (state.isPlaying && !state.isPaused) return;
    _waitingForSpotifyPause = NO;
    [self play];
    if (_engine.isRunning) { _resumeSpotify = YES; _stopOnPlayback = YES; }
    else [(id<SPTPlayer>)SGKaraokePlayer() resume:nil];
}
- (void)demoFinished {
    [self stop];
}
- (void)stop {
    BOOL resume = _resumeSpotify;
    ++_generation;
    ++_pauseAttempt;
    _waitingForSpotifyPause = NO;
    [self stopHeadTracking];
    [_vocals stop]; [_soundtrack stop]; [_engine stop];
    _vocals = nil; _soundtrack = nil; _reverb = nil; _delay = nil; _eq = nil; _environment = nil; _engine = nil; _voiceBuffer = nil;
    _resumeSpotify = NO; _stopOnPlayback = NO;
    if (resume) [(id<SPTPlayer>)SGKaraokePlayer() resume:nil];
}
- (void)stopWithoutResumingSpotify {
    _resumeSpotify = NO;
    [self stop];
}
- (void)updateEffects {
    if (!_reverb || !_delay) return;
    _reverb.wetDryMix = (float)(spatialValue(SGRKeySpatialReverb, 0.26) * 75.0);
    _delay.delayTime = 0.12 + spatialValue(SGRKeySpatialEcho, 0.08) * 0.28;
    _delay.feedback = (float)(spatialValue(SGRKeySpatialEcho, 0.08) * 65.0);
    _delay.wetDryMix = (float)(spatialValue(SGRKeySpatialEcho, 0.08) * 70.0);
    double gains[] = {spatialValue(SGRKeySpatialEQLowDB, 0.0), spatialValue(SGRKeySpatialEQMidDB, 0.0), spatialValue(SGRKeySpatialEQHighDB, 0.0)};
    for (NSUInteger i = 0; i < 3; i++) {
        AVAudioUnitEQFilterParameters *band = _eq.bands[i];
        band.filterType = i == 0 ? AVAudioUnitEQFilterTypeLowShelf : (i == 2 ? AVAudioUnitEQFilterTypeHighShelf : AVAudioUnitEQFilterTypeParametric);
        band.frequency = i == 0 ? 180 : (i == 1 ? 1200 : 5000);
        band.bandwidth = 1.0; band.gain = (float)gains[i]; band.bypass = !SGFlag(SGRKeySpatialEQ, NO);
    }
    _vocals.volume = powf(10.0f, (float)spatialValue(SGRKeySpatialGainDB, 0.0) / 20.0f);
    double distance = spatialValue(SGRKeySpatialDistance, 0.18);
    if (!_hasHeadReference)
        _vocals.position = AVAudioMake3DPoint(0, 0, (float)(-1.0 - distance * 4.0));
    if (_environment.distanceAttenuationParameters)
        _environment.distanceAttenuationParameters.rolloffFactor = (float)(0.25 + distance * 2.5);
}
@end

static void promptDemo(void) {
    SGSpatialVoiceDemo *demo = [SGSpatialVoiceDemo shared];
    if (demo.isPlaying) { [demo stop]; return; }
    SPTPlayerState *state = SGPlayerState();
    BOOL playing = state.isPlaying && !state.isPaused;
    if (!playing) { [demo play]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Spotify is playing"
        message:@"Keep Spotify playing without interruption while you adjust its vocal effects, or pause it and use the demo song?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep Spotify Playing" style:UIAlertActionStyleDefault handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Pause & Play Demo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [demo pauseSpotifyAndPlay];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// The model's size as the footer and the prompts say it, to the nearest ten megabytes.
static NSString *aboutSize(void) {
    return [NSString stringWithFormat:@"about %lld MB", ((SGSingModelSize() >> 20) + 5) / 10 * 10];
}

static NSString *footer(void) {
    return [NSString stringWithFormat:@"Sing controls the song from the microphone in its lyrics. At 100 percent it leaves the mix unchanged; below 100 percent it reduces the vocals and overall level, and above 100 percent it takes the instrumental out until 110 percent is vocals only. "
            "It works on iOS 27 only. The full voice model is %@; two smaller alternatives are available below. Models are downloaded once and run only on this iPhone. "
            "Vocals only plays the singing alone, with the instrumental taken out, and the microphone's slider has no say "
            "while it is on. The switches and the download apply straight away.", aboutSize()];
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSString *modelStatus(void) {
    int64_t received = SGSingModelReceived(), size = SGSingModelSize();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled: return [@"Downloaded · " stringByAppendingString:SGSingModelBytesText(size)];
        case SGSingModelChecking: return @"Checking…";
        case SGSingModelDownloading:
            return [NSString stringWithFormat:@"Downloading %lld %% · %lld of %@", received * 100 / size,
                    (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
        case SGSingModelMissing:
            if (SGSingModelFailure()) return @"Download failed";
            if (received > 0) return [NSString stringWithFormat:@"Paused · %lld of %@", (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
            return @"Not downloaded";
    }
    return nil;
}

// A tap on the model row says what its value is short for.
static void explainModel(void) {
    NSString *failure = SGSingModelFailure();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled:
            tell(@"Voice model", [NSString stringWithFormat:@"It takes %@ on this iPhone. Remove it to free the space; Sing is unavailable without it.",
                                  SGSingModelBytesText(SGSingModelSize())]);
            break;
        case SGSingModelMissing:
            tell(failure ? @"Download failed" : @"Voice model",
                 failure ? [failure stringByAppendingString:@" Download goes on from where it stopped."]
                         : [NSString stringWithFormat:@"Sing needs its voice model, %@, before its microphone shows in the lyrics.", aboutSize()]);
            break;
        default:
            tell(@"Voice model", @"The download goes on while Spotify is in the background. Sing's microphone shows in the lyrics once it is in.");
    }
}

// Enough room first, then the network: nothing leaves on cellular without a yes.
static void startDownload(void) {
    NSString *space = SGSingModelSpaceProblem();
    if (space) { tell(@"Not enough space", space); return; }
    SGSingModelCheckNetwork(^(SGSingModelNetwork network) {
        if (network == SGSingModelOffline) {
            tell(@"No internet connection", @"Connect to Wi-Fi to download Sing's voice model.");
        } else if (network == SGSingModelMetered) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download over cellular?"
                message:[NSString stringWithFormat:@"This iPhone isn't on Wi-Fi, and Sing's voice model is %@.", aboutSize()]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                SGSingModelDownload(YES);
            }]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        } else {
            SGSingModelDownload(NO);
        }
    });
}

static void confirmRemove(void) {
    BOOL installed = SGSingModelCurrentState() == SGSingModelInstalled;
    BOOL hasAlternative = SGSingAlternateModelInstalled(SGSingAlternateModelANE) || SGSingAlternateModelInstalled(SGSingAlternateModelLight);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove the voice model?"
        message:installed ? (hasAlternative ? [NSString stringWithFormat:@"The full model will be removed (%@). Sing will switch to another downloaded model if one is available.", aboutSize()]
                                             : [NSString stringWithFormat:@"Sing is unavailable until it is downloaded again (%@).", aboutSize()])
                          : [NSString stringWithFormat:@"The %@ downloaded so far are deleted, and the next download starts over.",
                             SGSingModelBytesText(SGSingModelReceived())]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSingModelRemove();
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSString *alternateModelStatus(SGSingAlternateModel model) {
    if (SGSingAlternateModelInstalled(model)) return @"Downloaded";
    if (SGSingAlternateModelDownloading(model)) {
        double progress = SGSingAlternateModelProgress(model);
        return progress >= 0 ? [NSString stringWithFormat:@"Downloading %d%%", (int)lrint(progress * 100)] : @"Downloading…";
    }
    return @"Not downloaded";
}

static void alternateModelAction(SGSingAlternateModel model) {
    if (SGSingAlternateModelDownloading(model)) { SGSingAlternateModelCancel(model); return; }
    if (SGSingAlternateModelInstalled(model)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove this model?"
            message:@"The downloaded files will be deleted. Sing will use another installed model if one is available."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { SGSingAlternateModelRemove(model); }]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *space=SGSingAlternateModelSpaceProblem(model);
    if(space) { tell(@"Not enough space",space); return; }
    SGSingModelCheckNetwork(^(SGSingModelNetwork network) {
        if (network == SGSingModelOffline) { tell(@"No internet connection", @"Connect to Wi-Fi to download this Sing model."); return; }
        BOOL metered = network == SGSingModelMetered;
        void (^download)(BOOL) = ^(BOOL allowsMetered) {
            if (!allowsMetered && metered) return;
            SGSingAlternateModelDownload(model, allowsMetered);
        };
        if (!metered) { download(NO); return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download over cellular?"
            message:[NSString stringWithFormat:@"This model is %@. Continue over cellular?", SGSingModelBytesText(SGSingAlternateModelSize(model))]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { download(YES); }]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}

// Below iOS 27 the switch is a row saying what is missing.
static SGModRow *unavailableRow(void) {
    return SGStatActionRow(@"Sing", nil, ^NSString *{ return @"Needs iOS 27"; }, ^{
        tell(@"Sing", [NSString stringWithFormat:@"Sing separates a song's vocals on this iPhone with a voice model that needs iOS 27. "
                       "This iPhone runs iOS %@.", UIDevice.currentDevice.systemVersion]);
    });
}

static SGModSection *karaokeSection(void) {
    if (!SGSingSupported()) return SGNotedSection(@"Karaoke", @[unavailableRow()], footer());
    applySpatialValues();
    SGModRow *sing = SGOptionRow(@"Sing", @"The microphone in the lyrics", SGRKeySing);
    sing.changed = ^(BOOL on) { SGRSingApplySwitch(); };
    SGModRow *model = SGStatActionRow(@"Full quality model", nil, ^NSString *{ return modelStatus(); }, ^{ explainModel(); });
    model.progress = ^double {
        return SGSingModelCurrentState() == SGSingModelDownloading ? (double)SGSingModelReceived() / SGSingModelSize() : -1;
    };
    model.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *modelChoice = SGChoiceRow(@"Separator model", @"Choose the model used by Sing and Spatial Voice", SGKeySingModelVariant,
        @[@"Full · best quality", @"Neural Engine · faster", @"Light · smaller"], SGSingAlternateModelFull);
    modelChoice.choiceNotes = @[[NSString stringWithFormat:@"About %@. Preferred automatically when multiple models are installed.", SGSingModelBytesText(SGSingAlternateModelSize(SGSingAlternateModelFull))],
        [NSString stringWithFormat:@"About %@. Same separator with a faster Neural Engine export.", SGSingModelBytesText(SGSingAlternateModelSize(SGSingAlternateModelANE))],
        [NSString stringWithFormat:@"About %@. Smallest download, with more vocals left in the instrumental.", SGSingModelBytesText(SGSingAlternateModelSize(SGSingAlternateModelLight))]];
    modelChoice.choiceFooter = @"The selected model is used after it has downloaded. If it is missing, Sing uses the best available installed model.";
    modelChoice.chosen = ^(NSInteger index) { SGSingAlternateModelSelect((SGSingAlternateModel)index); };

    SGModRow *ane = SGStatActionRow(@"Neural Engine model", @"Tap to download, cancel, or remove", ^NSString *{ return alternateModelStatus(SGSingAlternateModelANE); }, ^{ alternateModelAction(SGSingAlternateModelANE); });
    ane.progress = ^double { return SGSingAlternateModelDownloading(SGSingAlternateModelANE) ? SGSingAlternateModelProgress(SGSingAlternateModelANE) : -1; };
    ane.refreshOn = SGSingModelDidChangeNotification;
    SGModRow *light = SGStatActionRow(@"Light model", @"Tap to download, cancel, or remove", ^NSString *{ return alternateModelStatus(SGSingAlternateModelLight); }, ^{ alternateModelAction(SGSingAlternateModelLight); });
    light.progress = ^double { return SGSingAlternateModelDownloading(SGSingAlternateModelLight) ? SGSingAlternateModelProgress(SGSingAlternateModelLight) : -1; };
    light.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *download = SGActionRow(@"Download full quality model", nil, ^{ startDownload(); });
    download.visible = ^BOOL { return SGSingModelCurrentState() == SGSingModelMissing; };
    SGModRow *cancel = SGActionRow(@"Cancel full model download", nil, ^{ SGSingModelCancel(); });
    cancel.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelDownloading || state == SGSingModelChecking;
    };
    // Removing also takes what a stopped download kept, which can be most of the model.
    SGModRow *remove = SGActionRow(@"Remove full quality model", nil, ^{ confirmRemove(); });
    remove.color = SGRed();
    remove.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelInstalled || (state == SGSingModelMissing && SGSingModelReceived() > 0);
    };
    return SGNotedSection(@"Karaoke", @[sing, model, modelChoice, ane, light, download, cancel, remove], footer());
}

static SGModSection *spatialVoiceSection(void) {
    if (!SGSingSupported()) return SGSection(@"Spatial Voice", @[]);
    BOOL installed = SGSingModelPath() != nil;
    NSString *gatingInfo = @"Download the Sing voice model above to enable Spatial Voice. Tuning works with any headphones; AirPods are required only for head tracking.";
    SGModRow *spatial = SGOptionRow(@"Spatial Voice", @"Keep vocals focused in front", SGRKeySingSpatialVoice);
    spatial.info = installed ? @"Adjust the vocal stem's position and character. AirPods are needed for head tracking; effect tuning works with other headphones." : gatingInfo;
    spatial.enabled = ^BOOL { return SGSingModelPath() != nil; };
    spatial.changed = ^(BOOL on) { SGRSingApplySpatialVoice(); applySpatialValues(); };
    SGModRow *gain = SGSliderRow(@"Vocal level", @"Relative vocal gain", -12, 6, 0.5,
        ^double { return spatialValue(SGRKeySpatialGainDB, 0.0); },
        ^(double value) { setSpatialValue(SGRKeySpatialGainDB, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%+.1f dB", value]; });
    SGModRow *reverb = SGSliderRow(@"Reverb", @"Room reflections", 0, 1, 0.01,
        ^double { return spatialValue(SGRKeySpatialReverb, 0.26); },
        ^(double value) { setSpatialValue(SGRKeySpatialReverb, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)lrint(value * 100)]; });
    SGModRow *echo = SGSliderRow(@"Echo", @"Delay and repeats", 0, 1, 0.01,
        ^double { return spatialValue(SGRKeySpatialEcho, 0.08); },
        ^(double value) { setSpatialValue(SGRKeySpatialEcho, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)lrint(value * 100)]; });
    SGModRow *width = SGSliderRow(@"Soundstage", @"Vocal stereo width", 0, 1, 0.01,
        ^double { return spatialValue(SGRKeySpatialWidth, 0.35); },
        ^(double value) { setSpatialValue(SGRKeySpatialWidth, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)lrint(value * 100)]; });
    SGModRow *distance = SGSliderRow(@"Distance", @"How far away the singer sounds", 0, 1, 0.01,
        ^double { return spatialValue(SGRKeySpatialDistance, 0.18); },
        ^(double value) { setSpatialValue(SGRKeySpatialDistance, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)lrint(value * 100)]; });
    SGModRow *eq = SGOptionRow(@"Voice EQ", @"Shape the vocal tone", SGRKeySpatialEQ);
    eq.changed = ^(BOOL on) { applySpatialValues(); };
    SGModRow *low = SGSliderRow(@"Low", @"Warmth and body", -6, 6, 0.5,
        ^double { return spatialValue(SGRKeySpatialEQLowDB, 0.0); },
        ^(double value) { setSpatialValue(SGRKeySpatialEQLowDB, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%+.1f dB", value]; });
    SGModRow *mid = SGSliderRow(@"Mid", @"Vocal presence", -6, 6, 0.5,
        ^double { return spatialValue(SGRKeySpatialEQMidDB, 0.0); },
        ^(double value) { setSpatialValue(SGRKeySpatialEQMidDB, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%+.1f dB", value]; });
    SGModRow *high = SGSliderRow(@"High", @"Clarity and air", -6, 6, 0.5,
        ^double { return spatialValue(SGRKeySpatialEQHighDB, 0.0); },
        ^(double value) { setSpatialValue(SGRKeySpatialEQHighDB, value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%+.1f dB", value]; });
    SGModRow *demo = SGActionRow(@"Play Spatial Voice demo", @"Hear the supplied vocal and soundtrack stems", ^{ promptDemo(); });
    demo.value = ^NSString *{ return [[SGSpatialVoiceDemo shared] isPlaying] ? @"Playing · Tap to stop" : @"Preview"; };
    NSArray<SGModRow *> *tunedRows = @[gain, reverb, echo, width, distance, eq];
    for (SGModRow *row in tunedRows) row.visible = ^BOOL { return SGSingModelPath() != nil && SGFlag(SGRKeySingSpatialVoice, NO); };
    low.visible = mid.visible = high.visible = ^BOOL { return SGSingModelPath() != nil && SGFlag(SGRKeySingSpatialVoice, NO) && SGFlag(SGRKeySpatialEQ, NO); };
    demo.visible = ^BOOL { return SGSingModelPath() != nil && SGFlag(SGRKeySingSpatialVoice, NO); };
    spatial.visible = ^BOOL { return YES; };
    return SGNotedSection(@"Spatial Voice", @[spatial, gain, reverb, echo, width, distance, eq, low, mid, high, demo],
        @"AirPods are required for head tracking. Effect tuning works with other headphones.");
}

@interface SGRKaraokeSettingsPageController : SGModPage
@end

@implementation SGRKaraokeSettingsPageController
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController || self.isBeingDismissed)
        [[SGSpatialVoiceDemo shared] stop];
}
@end

UIViewController *SGRKaraokeSettingsPage(void) {
    NSArray<SGModSection *> *sections = SGSingSupported() ? @[karaokeSection(), spatialVoiceSection()] : @[karaokeSection()];
    return [[SGRKaraokeSettingsPageController alloc] initWithTitle:@"Karaoke & Spatial Voice" intro:nil sections:sections footer:nil];
}

// Beside the main page's row: what Sing would do now, or how far its model has come.
NSString *SGRKaraokeSummary(void) {
    if (!SGSingSupported()) return @"Needs iOS 27";
    if (SGSingModelPath()) return SGFlag(SGRKeySing, NO) ? @"On" : @"Off";
    SGSingModelState state = SGSingModelCurrentState();
    if (state == SGSingModelDownloading) return [NSString stringWithFormat:@"%lld %%", SGSingModelReceived() * 100 / SGSingModelSize()];
    if (state == SGSingModelChecking) return @"Checking…";
    if (SGSingAlternateModelDownloading(SGSingAlternateModelANE))
        return [NSString stringWithFormat:@"Neural Engine %d%%", (int)lrint(SGSingAlternateModelProgress(SGSingAlternateModelANE) * 100)];
    if (SGSingAlternateModelDownloading(SGSingAlternateModelLight))
        return [NSString stringWithFormat:@"Light model %d%%", (int)lrint(SGSingAlternateModelProgress(SGSingAlternateModelLight) * 100)];
    if (!SGFlag(SGRKeySing, NO)) return @"Off";
    return @"No model";
}
