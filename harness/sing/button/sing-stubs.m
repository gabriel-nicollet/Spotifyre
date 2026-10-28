// Shared/Sing's calls as the mic button makes them, answering from the launch line instead of the model and the
// audio: -state is an SGSingState (Sing.h), -progress the download's fraction, -waiting 1 a download held for the
// network. The lyrics harness links it too,
// since SGRKaraokeView puts the mic on the lyrics.
#import <UIKit/UIKit.h>
#import "Shared/Sing/Sing.h"

NSString *const SGSingChangedNotification = @"SGSingChangedNotification";

static NSUserDefaults *defaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

SGSingState SGSingCurrentState(void) {
    return [defaults() objectForKey:@"state"] ? [defaults() integerForKey:@"state"] : SGSingStateOff;
}

static NSArray<NSString *> *names(void) {
    return @[@"Unavailable", @"Needs its voice model", @"Downloading", @"Off", @"Preparing", @"Waiting for Spotify", @"Listening ahead",
             @"On", @"Too slow", @"Held, too hot", @"Failed"];
}

NSString *SGSingStatusText(void) {
    NSInteger state = SGSingCurrentState();
    return state >= 0 && state < (NSInteger)names().count ? names()[state] : @"";
}

NSString *SGSingStatusDetail(void) { return SGSingStatusText(); }
NSString *SGSingMissing(void) { return @"Karaoke needs iOS 18, the first its voice model runs on."; }
BOOL SGSingOn(void) { return SGSingCurrentState() >= SGSingStatePreparing; }

void SGSetSingOn(BOOL on) {
    [defaults() setInteger:on ? SGSingStateSinging : SGSingStateOff forKey:@"state"];
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingChangedNotification object:nil];
}

float SGSingLevel(void) { return [defaults() objectForKey:@"level"] ? [defaults() floatForKey:@"level"] : 0.15f; }
void SGSetSingLevel(float level) { [defaults() setFloat:level forKey:@"level"]; }

NSString *SGSingLevelText(double level) {
    if (level <= 0.001) return @"Gone";
    if (level < 0.999) return [NSString stringWithFormat:@"%.0f%%", level * 100];
    if (level <= 1.001) return @"As sung";
    if (level >= 1.999) return @"Vocals only";
    return [NSString stringWithFormat:@"Backing %.0f%%", (2 - level) * 100];
}

double SGSingModelProgress(void) { return [defaults() doubleForKey:@"progress"]; }
BOOL SGSingModelWaitingForNetwork(void) { return [defaults() boolForKey:@"waiting"]; }
NSString *SGSingModelSizeText(void) { return @"210.4 MB"; }
NSString *SGSingModelError(void) { return nil; }
void SGSingDownloadModel(void) {}
void SGSingCancelModelDownload(void) {}
