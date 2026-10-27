// Spotify's streaming quality, read and set through its own preferences object (Shared/SpotifyPrefs).
#import "Core/SGCore.h"
#import "Shared/SpotifyPrefs/SpotifyPrefs.h"
#import "LosslessQuality.h"
#import "SGLossless.h"

#define SGKeyLosslessSavedQuality @"spotifyglass.lossless.savedQuality"   // [cellular, Wi-Fi] while lowered
static const NSInteger kLowest = 1;

BOOL SGStreamQuality(NSInteger *metered, NSInteger *nonMetered) {
    SPTPreferences *preferences = SGSpotifyPreferences();
    if (!preferences) return NO;
    *metered = preferences.audioPlayBitrate;
    *nonMetered = preferences.audioPlayBitrateNonMetered;
    return YES;
}

BOOL SGSetStreamQuality(NSInteger metered, NSInteger nonMetered) {
    SPTPreferences *preferences = SGSpotifyPreferences();
    if (!preferences) return NO;
    preferences.audioPlayBitrate = metered;
    preferences.audioPlayBitrateNonMetered = nonMetered;
    return YES;
}

void SGLosslessLowerQuality(BOOL lower) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray<NSNumber *> *saved = [defaults arrayForKey:SGKeyLosslessSavedQuality];
    NSInteger metered, nonMetered;
    if (!SGStreamQuality(&metered, &nonMetered)) return;
    if (lower && !saved) {
        if (metered == kLowest && nonMetered == kLowest) return;
        [defaults setObject:@[@(metered), @(nonMetered)] forKey:SGKeyLosslessSavedQuality];
        SGSetStreamQuality(kLowest, kLowest);
        SGLog(@"lossless: Spotify's quality lowered for the next track (was %ld, %ld)", (long)metered, (long)nonMetered);
    } else if (!lower && saved.count == 2) {
        if (metered == kLowest && nonMetered == kLowest) SGSetStreamQuality(saved[0].integerValue, saved[1].integerValue);
        [defaults removeObjectForKey:SGKeyLosslessSavedQuality];
        SGLog(@"lossless: Spotify's quality back to %ld, %ld", (long)saved[0].integerValue, (long)saved[1].integerValue);
    }
}
