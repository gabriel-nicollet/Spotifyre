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
#import "Shared/Sing/SGSingDSP.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "Sing.h"
#import <AVFoundation/AVFoundation.h>
#include <math.h>

static void tell(NSString *title, NSString *message);

#define SGRKeySpatialReverb @"spotifyglass.redesign.spatialReverb"
#define SGRKeySpatialEcho @"spotifyglass.redesign.spatialEcho"
#define SGRKeySpatialWidth @"spotifyglass.redesign.spatialWidth"
#define SGRKeySpatialDistance @"spotifyglass.redesign.spatialDistance"
#define SGRKeySpatialPreset @"spotifyglass.redesign.spatialPreset"

static double spatialValue(NSString *key, double fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return value ? [value doubleValue] : fallback;
}

static void applySpatialValues(void) {
    SGSingDSPSetSpatialParameters((float)spatialValue(SGRKeySpatialReverb, 0.26),
                                  (float)spatialValue(SGRKeySpatialEcho, 0.08),
                                  (float)spatialValue(SGRKeySpatialWidth, 0.35),
                                  (float)spatialValue(SGRKeySpatialDistance, 0.18));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SGSpatialVoiceDemoSettingsDidChange" object:nil];
}

void SGRSpatialVoiceApplySettings(void) { applySpatialValues(); }

static void setSpatialValue(NSString *key, double value) {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    applySpatialValues();
}

static NSArray<NSString *> *spatialPresets(void) {
    return @[@"Room", @"Hall", @"Garage", @"Studio", @"Cathedral"];
}

static void selectSpatialPreset(NSInteger index) {
    static const double values[][4] = {
        {0.26, 0.08, 0.35, 0.18}, {0.72, 0.22, 0.22, 0.38}, {0.12, 0.46, 0.72, 0.08},
        {0.18, 0.03, 0.20, 0.05}, {0.90, 0.34, 0.18, 0.45}
    };
    if (index < 0 || index >= (NSInteger)(sizeof(values) / sizeof(values[0]))) return;
    [NSUserDefaults.standardUserDefaults setInteger:index forKey:SGRKeySpatialPreset];
    [NSUserDefaults.standardUserDefaults setDouble:values[index][0] forKey:SGRKeySpatialReverb];
    [NSUserDefaults.standardUserDefaults setDouble:values[index][1] forKey:SGRKeySpatialEcho];
    [NSUserDefaults.standardUserDefaults setDouble:values[index][2] forKey:SGRKeySpatialWidth];
    [NSUserDefaults.standardUserDefaults setDouble:values[index][3] forKey:SGRKeySpatialDistance];
    applySpatialValues();
}

@interface SGSpatialVoiceDemo : NSObject
+ (instancetype)shared;
- (BOOL)isPlaying;
- (void)play;
- (void)playResumingSpotify;
- (void)stop;
- (void)updateEffects;
@end

@implementation SGSpatialVoiceDemo {
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_vocals, *_soundtrack;
    AVAudioUnitReverb *_reverb;
    AVAudioUnitDelay *_delay;
    AVAudioEnvironmentNode *_environment;
    BOOL _resumeSpotify;
}
+ (instancetype)shared {
    static SGSpatialVoiceDemo *demo; static dispatch_once_t once;
    dispatch_once(&once, ^{ demo = [SGSpatialVoiceDemo new]; }); return demo;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateEffects)
                                                name:@"SGSpatialVoiceDemoSettingsDidChange" object:nil];
    return self;
}
- (BOOL)isPlaying { return _engine.isRunning; }
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
    _engine = [AVAudioEngine new]; _vocals = [AVAudioPlayerNode new]; _soundtrack = [AVAudioPlayerNode new];
    _reverb = [AVAudioUnitReverb new]; _delay = [AVAudioUnitDelay new];
    [_engine attachNode:_vocals]; [_engine attachNode:_soundtrack]; [_engine attachNode:_reverb]; [_engine attachNode:_delay];
    _environment = _engine.mainMixerNode ? [AVAudioEnvironmentNode new] : nil;
    if (_environment) {
        [_engine attachNode:_environment];
        _environment.outputType = AVAudioEnvironmentOutputTypeHeadphones;
        _environment.listenerPosition = AVAudio3DPointMake(0, 0, 0);
        _vocals.position = AVAudio3DPointMake(0, 0, -1);
        _vocals.renderingAlgorithm = AVAudio3DMixingRenderingAlgorithmHRTF;
        [_engine connect:_vocals to:_reverb format:voiceFile.processingFormat];
        [_engine connect:_reverb to:_delay format:voiceFile.processingFormat];
        [_engine connect:_delay to:_environment format:voiceFile.processingFormat];
        [_engine connect:_environment to:_engine.mainMixerNode format:nil];
    }
    [_engine connect:_soundtrack to:_engine.mainMixerNode format:musicFile.processingFormat];
    [self updateEffects];
    if (![_engine startAndReturnError:&error]) { tell(@"Could not start demo", error.localizedDescription ?: @"Audio could not be started."); [self stop]; return; }
    [_vocals scheduleFile:voiceFile atTime:nil completionHandler:^{ dispatch_async(dispatch_get_main_queue(), ^{ [self demoFinished]; }); }];
    [_soundtrack scheduleFile:musicFile atTime:nil completionHandler:nil];
    [_vocals play]; [_soundtrack play];
}
- (void)playResumingSpotify {
    [self play];
    if (_engine.isRunning) _resumeSpotify = YES;
    else [(id<SPTPlayer>)SGKaraokePlayer() resume:nil];
}
- (void)demoFinished {
    [self stop];
}
- (void)stop {
    BOOL resume = _resumeSpotify;
    [_vocals stop]; [_soundtrack stop]; [_engine stop];
    _vocals = nil; _soundtrack = nil; _reverb = nil; _delay = nil; _environment = nil; _engine = nil;
    _resumeSpotify = NO;
    if (resume) [(id<SPTPlayer>)SGKaraokePlayer() resume:nil];
}
- (void)updateEffects {
    if (!_reverb || !_delay) return;
    _reverb.wetDryMix = (float)(spatialValue(SGRKeySpatialReverb, 0.26) * 75.0);
    _delay.delayTime = 0.12 + spatialValue(SGRKeySpatialEcho, 0.08) * 0.28;
    _delay.feedback = (float)(spatialValue(SGRKeySpatialEcho, 0.08) * 65.0);
    _delay.wetDryMix = (float)(spatialValue(SGRKeySpatialEcho, 0.08) * 70.0);
    double distance = spatialValue(SGRKeySpatialDistance, 0.18);
    _vocals.position = AVAudio3DPointMake(0, 0, (float)(-1.0 - distance * 4.0));
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
        id<SPTPlayer> player = (id<SPTPlayer>)SGKaraokePlayer();
        [player pause:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [demo playResumingSpotify]; });
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
            "It works on iOS 27 only. Its voice model, %@, is downloaded once and runs only on this iPhone. "
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
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove the voice model?"
        message:installed ? [NSString stringWithFormat:@"Sing is unavailable until it is downloaded again (%@).", aboutSize()]
                          : [NSString stringWithFormat:@"The %@ downloaded so far are deleted, and the next download starts over.",
                             SGSingModelBytesText(SGSingModelReceived())]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSingModelRemove();
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Below iOS 27 the switch is a row saying what is missing.
static SGModRow *unavailableRow(void) {
    return SGStatActionRow(@"Sing", nil, ^NSString *{ return @"Needs iOS 27"; }, ^{
        tell(@"Sing", [NSString stringWithFormat:@"Sing separates a song's vocals on this iPhone with a voice model that needs iOS 27. "
                       "This iPhone runs iOS %@.", UIDevice.currentDevice.systemVersion]);
    });
}

static SGModSection *karaokeSection(void) {
    if (!SGSingSupported()) return SGNotedSection(@"Karaoke & Spatial Voice", @[unavailableRow()], footer());
    applySpatialValues();
    SGModRow *sing = SGOptionRow(@"Sing", @"The microphone in the lyrics", SGRKeySing);
    sing.changed = ^(BOOL on) { SGRSingApplySwitch(); };
    SGModRow *spatial = SGOptionRow(@"Spatial Voice", @"Keep the vocals focused in front", SGRKeySingSpatialVoice);
    spatial.info = @"Keeps the voice anchored in front as you turn your head, when compatible headphone motion is available. "
                   @"Reverb, echo, width and distance change the vocal stem; the Sing slider still controls the mix from 0 to 110 percent.";
    spatial.changed = ^(BOOL on) { SGRSingApplySpatialVoice(); };
    SGModRow *model = SGStatActionRow(@"Voice model", nil, ^NSString *{ return modelStatus(); }, ^{ explainModel(); });
    model.progress = ^double {
        return SGSingModelCurrentState() == SGSingModelDownloading ? (double)SGSingModelReceived() / SGSingModelSize() : -1;
    };
    model.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *download = SGActionRow(@"Download voice model", nil, ^{ startDownload(); });
    download.visible = ^BOOL { return SGSingModelCurrentState() == SGSingModelMissing; };
    SGModRow *cancel = SGActionRow(@"Cancel download", nil, ^{ SGSingModelCancel(); });
    cancel.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelDownloading || state == SGSingModelChecking;
    };
    // Removing also takes what a stopped download kept, which can be most of the model.
    SGModRow *remove = SGActionRow(@"Remove voice model", nil, ^{ confirmRemove(); });
    remove.color = SGRed();
    remove.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelInstalled || (state == SGSingModelMissing && SGSingModelReceived() > 0);
    };
    SGModRow *preset = SGChoiceRow(@"Room preset", nil, SGRKeySpatialPreset, spatialPresets(), 0);
    preset.choiceFooter = @"Sets a starting point for the room controls. You can then fine-tune each effect.";
    preset.chosen = ^(NSInteger index) { selectSpatialPreset(index); };
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
    SGModRow *demo = SGActionRow(@"Play Spatial Voice demo", @"Hear the supplied vocal and soundtrack stems", ^{ promptDemo(); });
    demo.value = ^NSString *{ return [[SGSpatialVoiceDemo shared] isPlaying] ? @"Playing · Tap to stop" : @"Preview"; };
    return SGNotedSection(@"Karaoke & Spatial Voice", @[sing, spatial, preset, reverb, echo, width, distance, demo, model, download, cancel, remove], footer());
}

UIViewController *SGRKaraokeSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Karaoke & Spatial Voice" intro:nil sections:@[karaokeSection()] footer:nil];
}

// Beside the main page's row: what Sing would do now, or how far its model has come.
NSString *SGRKaraokeSummary(void) {
    if (!SGSingSupported()) return @"Needs iOS 27";
    SGSingModelState state = SGSingModelCurrentState();
    if (state == SGSingModelDownloading) return [NSString stringWithFormat:@"%lld %%", SGSingModelReceived() * 100 / SGSingModelSize()];
    if (state == SGSingModelChecking) return @"Checking…";
    if (!SGFlag(SGRKeySing, NO)) return @"Off";
    return state == SGSingModelInstalled ? @"On" : @"No model";
}
