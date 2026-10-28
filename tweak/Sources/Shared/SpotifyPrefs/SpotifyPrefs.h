// Spotify's preferences object, the one Settings > Playback reads and writes, captured as Spotify makes it at launch
// (SpotifyPrefs.x). Lossless lowers the streaming quality through it, AutoMix sets Automix and Crossfade, and
// AdBlock/Crossfade.x hooks it.
#import <Foundation/Foundation.h>

@interface _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation : NSObject
- (NSInteger)audioPlayBitrate;
- (NSInteger)audioPlayBitrateNonMetered;
- (void)setAudioPlayBitrate:(NSInteger)level;
- (void)setAudioPlayBitrateNonMetered:(NSInteger)level;
- (BOOL)audioAutomix;
- (void)setAudioAutomix:(BOOL)on;
- (BOOL)audioCrossfade;
- (void)setAudioCrossfade:(BOOL)on;
- (NSInteger)audioCrossfadeTime;   // milliseconds
- (void)setAudioCrossfadeTime:(NSInteger)milliseconds;
- (NSInteger)playbackSpeed;        // percent, 100 at normal speed
@end
@compatibility_alias SPTPreferences _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation;

// Main thread. Nil until Spotify has made the object and read its user's settings into it, about 3 s into a launch:
// before that every user setting reads 0, which is not the user's.
SPTPreferences *SGSpotifyPreferences(void);
