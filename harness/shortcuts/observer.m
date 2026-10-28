// A stand-in for LiveActivity.x's SGShortcut observer, registered the same way (no queue, the reply read out
// of userInfo and checked as it is there), answering from a script instead of Spotify's player.
#import <Foundation/Foundation.h>
#import "observer.h"

NSInteger SGHarnessPosts;
NSString *SGHarnessLastAction;

void SGHarnessObserve(NSInteger waitPosts) {
    [NSNotificationCenter.defaultCenter addObserverForName:@"SGShortcut" object:nil queue:nil usingBlock:^(NSNotification *note) {
        NSMutableDictionary *reply = note.userInfo[@"reply"];
        if (!NSThread.isMainThread || ![note.object isKindOfClass:NSString.class] || ![reply isKindOfClass:NSMutableDictionary.class]) {
            NSLog(@"FAIL: posted off the main thread or without a mutable reply");
            exit(1);
        }
        NSString *action = note.object;
        SGHarnessPosts++;
        SGHarnessLastAction = action;
        static NSInteger total;
        // The player not up for the first posts: no answer, as runShortcut gives none without a track.
        if (++total <= waitPosts ||[action isEqualToString:@"previous"]) return;
        if ([action isEqualToString:@"sing:on"]) reply[@"failed"] = @"Karaoke needs its voice model.";
        else reply[@"said"] = [action isEqualToString:@"like"] ? @"Added Song to Liked Songs." : @"";
    }];
}
