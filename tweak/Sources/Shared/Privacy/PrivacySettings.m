#import "Settings/SGModPage.h"
#import "Privacy.h"

SGModSection *SGPrivacySection(void) {
    return SGSection(@"Privacy", @[
        SGSwitchRow(@"Block telemetry", @"Spotify's own events still go out, since Recents is built from them", SGKeyBlockTelemetry),
        SGSwitchRow(@"Hide videos in search", @"Removes the video carousel from search results", SGKeyHideSearchVideos),
        SGSwitchRow(@"Hide social proof in search", @"Hides playlist and play-count sections in search results", SGKeyHideSocialProof),
        SGSwitchRow(@"Clean shared links", @"Takes the tracking (si, utm) off the links you copy or share", SGKeyCleanLinks),
    ]);
}

SGModSection *SGPrivacyCountersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGBlockedLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGBlockedCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(@"Total", ^NSString *{
        return @(SGBlockedCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(@"Reset the telemetry counters", nil, ^{ SGResetBlocked(); })];
    return SGSection(@"Telemetry blocked so far", counts);
}
