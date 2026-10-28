// Spotify's preferences object: made on Spotify's core thread at launch, and read only when Settings > Playback
// opens, so its getters are too late to capture it. Captured in every launch, since AutoMix's switch takes effect
// without a restart.
#import "Core/SGCore.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Lossless/LosslessQuality.h"
#import "Shared/Lossless/SGLossless.h"
#import "SpotifyPrefs.h"

static __weak SPTPreferences *sg_preferences, *sg_loaded;

SPTPreferences *SGSpotifyPreferences(void) {
    SPTPreferences *preferences = sg_preferences;
    // The playback speed is the user's one setting that is never 0, so it tells the settings loaded from not yet.
    if (preferences && preferences != sg_loaded && preferences.playbackSpeed > 0) sg_loaded = preferences;
    return preferences == sg_loaded ? preferences : nil;
}

// Every half second until the user's settings are in, then what a switch left to do when they were not.
static void reconcileWhenLoaded(void) {
    if (!sg_preferences) return;
    if (!SGSpotifyPreferences()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ reconcileWhenLoaded(); });
        return;
    }
    SGLog(@"spotify prefs: the user's settings are in");
    // Lowered when Spotify last quit, and lossless is off now: nothing else would put it back.
    if (!SGHidden(SGKeyLossless)) SGLosslessLowerQuality(NO);
    SGAutoMixReconcile();
}

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (id)initWithScheduler:(id)scheduler {
    id made = %orig;
    sg_preferences = made;
    dispatch_async(dispatch_get_main_queue(), ^{ reconcileWhenLoaded(); });
    return made;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
