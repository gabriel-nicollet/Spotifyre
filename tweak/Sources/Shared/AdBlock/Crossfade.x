// Crossfade under Spoof Premium (EeveeSpotify's): the fade engine reads the stored crossfade switch,
// but the duration slider only writes the duration, so the fade stayed off at any length.
#import "Core/SGCore.h"
#import "Shared/SpotifyPrefs/SpotifyPrefs.h"
#import "AdBlock.h"

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (void)setAudioCrossfadeTime:(NSInteger)time {
    %orig;
    [self setAudioCrossfade:time > 0];
}
%end

%ctor {
    if (!SGHidden(SGKeyFakePremium)) return;
    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
