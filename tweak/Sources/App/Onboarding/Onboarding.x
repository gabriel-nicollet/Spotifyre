// The tour goes up the first time Home appears, not at launch: a fresh sideload lands on the login
// screen first, and a tour over that is wrong. A moment after, so Home has drawn under the glass. A
// build that has had its tour and runs a version for the first time shows What's new there instead;
// a fresh install's tour counts as this version's What's new.
#import "Core/SGCore.h"
#import "Onboarding.h"

static BOOL newVersion(void) {
    return ![[NSUserDefaults.standardUserDefaults stringForKey:SGKeyWhatsNewSeen] isEqualToString:@(SG_VERSION)];
}

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL fresh = newVersion();
            [NSUserDefaults.standardUserDefaults setObject:@(SG_VERSION) forKey:SGKeyWhatsNewSeen];
            if (!SGFlag(SGKeyOnboardingSeen, NO)) SGShowOnboarding();
            else if (fresh) SGShowWhatsNew();
        });
    });
}
%end

%ctor {
    SGCheckEnvironmentOnce();
    if (SGFlag(SGKeyOnboardingSeen, NO) && !newVersion()) return;
    %init;
    SGRequireClasses(@[@"_TtC19Home_FunkisPageImpl20FunkisViewController"]);
}
