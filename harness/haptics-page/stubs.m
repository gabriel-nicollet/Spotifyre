// Music Haptics' side of Haptics.h (MusicHaptics.x in the tweak), which the page calls as its switches and its
// settings change and its preview is tapped: each is logged with what the hooks would read at that moment.
// The preview's watcher is kept, for the harness's pulse to hand a tap to.
#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"

__attribute__((constructor)) static void sg_logSwitches(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:SGMusicHapticsSwitchesChangedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSLog(@"[harness] the engines read Music Haptics %@, In the Background %@", SGMusicHapticsOn() ? @"on" : @"off", SGMusicHapticsInBackground() ? @"on" : @"off");
    }];
}

void SGMusicHapticsSettingsChanged(void) {
    NSLog(@"[harness] Music Haptics reads strength %.0f%%, follows %ld", SGHapticsStrength(SGKeyMusicStrength) * 100, (long)SGMusicHapticsFollows());
}

void SGMusicHapticsPreview(void) {
    NSLog(@"[harness] Music Haptics plays the preview's kick at %.0f%%%@", SGHapticsStrength(SGKeyMusicStrength) * 100,
          SGMusicHapticsFollows() == SGMusicFollowsBeat ? @"" : @" with the rumble");
}

static void (^sg_watcher)(float intensity);

void SGMusicHapticsWatchTaps(void (^watcher)(float intensity)) {
    NSLog(@"[harness] the preview %@ Music Haptics' taps", watcher ? @"watches" : @"stops watching");
    sg_watcher = [watcher copy];
}

void SGHarnessPulse(float intensity) {
    if (sg_watcher) sg_watcher(intensity);
    else NSLog(@"[harness] nothing watches Music Haptics' taps");
}
