#import <UIKit/UIKit.h>
#import "SGUIMode.h"
#import "SGLog.h"
#import "SGPrefs.h"

BOOL SGRedesignAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static NSString *const kStarting = @"spotifyglass.redesign.untested.starting";
static const NSTimeInterval kStarted = 15;
static BOOL sg_fellBack;

BOOL SGRedesignFellBack(void) {
    return sg_fellBack;
}

// Below iOS 26 a launch with the redesign leaves a mark that the main queue takes off once it has run
// for a while, or as Spotify first leaves the front, which only a main thread that answers is told of. A
// launch that hung (the watchdog of #37) gets to neither, so the next one finds the mark and starts
// native. ponytail: a force quit from the switcher in the first 15 s, with Spotify still in front until
// then, counts as a hang; a hang later on is not caught.
static BOOL startsUntested(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if ([store boolForKey:kStarting]) {
        [store removeObjectForKey:kStarting];
        SGSetEnabled(SGKeyRedesign, NO);
        SGSetEnabled(SGKeyRedesignUntested, NO);
        sg_fellBack = YES;
        SGLog(@"ui: the last launch with the redesign on iOS %@ did not get going, so this one is native",
              NSProcessInfo.processInfo.operatingSystemVersionString);
        return NO;
    }
    [store setBool:YES forKey:kStarting];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kStarted * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [store removeObjectForKey:kStarting];
    });
    __block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                                                                  usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        [store removeObjectForKey:kStarting];
    }];
    return YES;
}

BOOL SGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGRedesignedUIStored() && (SGRedesignAvailable() || startsUntested());
        SGLog(@"ui: %@%@", on ? @"redesigned" : @"native", SGRedesignAvailable() ? @"" : on ? @" (untested below iOS 26)" : @" (the redesign needs iOS 26)");
    });
    return on;
}

BOOL SGNativeUI(void) {
    return !SGRedesignedUI();
}

BOOL SGRedesignedUIStored(void) {
    // The stored switch is left alone rather than turned off: a phone updated to iOS 26 gets the
    // redesign it was last asked for back. Below 26 it counts only with the warning accepted.
    return SGFlag(SGKeyRedesign, NO) && (SGRedesignAvailable() || SGFlag(SGKeyRedesignUntested, NO));
}
