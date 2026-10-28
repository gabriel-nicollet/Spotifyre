// The Updates page and the launch notice on the simulator, with the real check running against the
// repo's GitHub Releases. The build it claims to be is SG_VERSION, set by build.sh, so `0.18.0`
// shows a version behind the newest and `99.0.0` shows one that is current. `wipe` clears what an
// earlier run stored, so it starts as a phone that has never checked does; `notice` puts a plain
// screen up and runs SGWatchForUpdates() over it, the way the settings %ctor does inside Spotify;
// `recheck` taps Check now five seconds in.
#import <UIKit/UIKit.h>
#import "App/About/About.h"

// Spotify's welcome tour is not built here, and nothing holds the screen against the notice.
BOOL SGOnboardingShowing(void) {
    return NO;
}

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation Delegate

// What the notice comes up over: a stand-in for whatever Spotify has on screen when it opens.
static UIViewController *plainScreen(void) {
    UIViewController *screen = [UIViewController new];
    screen.view.backgroundColor = UIColor.blackColor;
    UILabel *label = [UILabel new];
    label.text = @"Spotify";
    label.textColor = [UIColor colorWithWhite:1 alpha:0.35];
    label.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [screen.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:screen.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:screen.view.centerYAnchor],
    ]];
    return screen;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    // `versions`: the comparison the check sorts and decides by, then quits.
    if ([arguments containsObject:@"versions"]) {
        NSArray<NSArray<NSString *> *> *newer = @[
            @[@"0.21.2", @"0.21.1"], @[@"1.0.0", @"0.50.0"], @[@"1.0.0-beta.2", @"1.0.0-beta.1"],
            @[@"1.0.0-beta.10", @"1.0.0-beta.9"], @[@"1.0.0", @"1.0.0-beta.9"], @[@"1.0.0-rc.1", @"1.0.0-beta.9"],
            @[@"1.0.1-beta.1", @"1.0.0"], @[@"1.0.0-beta.1.1", @"1.0.0-beta.1"], @[@"1.1", @"1.0.9"],
            // Beta to beta to release, and on past it: each step is newer than the one before, so the
            // reverse, a downgrade, never is.
            @[@"1.0.0-beta.2", @"1.0.0-beta.1"], @[@"1.0.0", @"1.0.0-beta.2"], @[@"1.0.1-beta.1", @"1.0.0"],
            @[@"1.0.1", @"1.0.1-beta.1"], @[@"1.1.0-beta.1", @"1.0.1"], @[@"1.0.0-beta.1", @"0.50.0"],
        ];
        NSUInteger wrong = 0;
        for (NSArray<NSString *> *pair in newer) {
            if (!SGVersionIsNewer(pair[0], pair[1]) || SGVersionIsNewer(pair[1], pair[0])) {
                wrong++;
                NSLog(@"[harness] versions: WRONG %@ should be newer than %@", pair[0], pair[1]);
            }
        }
        for (NSString *same in @[@"1.0.0", @"1.0.0-beta.1", @"0.21.1"]) {
            if (SGVersionIsNewer(same, same)) { wrong++; NSLog(@"[harness] versions: WRONG %@ newer than itself", same); }
        }
        if (SGVersionIsNewer(@"1.0", @"1.0.0") || SGVersionIsNewer(@"1.0.0", @"1.0")) { wrong++; NSLog(@"[harness] versions: WRONG 1.0 and 1.0.0 differ"); }
        NSLog(@"[harness] versions: %lu wrong -- %@", (unsigned long)wrong, wrong ? @"FAIL" : @"PASS");
        exit(wrong ? 1 : 0);
    }
    // `releases`: what a reply and a stored list leave for the build it is, then quits. Build it as
    // 1.0.0 and as 1.0.0-beta.1; the checks name which they expect of each.
    if ([arguments containsObject:@"releases"]) {
        BOOL beta = strchr(SG_VERSION, '-') != NULL;
        NSUInteger wrong = 0;
        // As a phone that has never checked nor touched Include betas, whatever a crashed run left.
        for (NSString *key in @[@"spotifyglass.update.checked", @"spotifyglass.update.releases", SGKeyUpdateBetas, @"spotifyglass.stock"])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        // Twenty-five betas, newest first, with a stable 1.1.0 in 22nd place.
        NSMutableArray *reply = [NSMutableArray array];
        for (int i = 25; i >= 1; i--) {
            [reply addObject:@{@"tag_name": [NSString stringWithFormat:@"v2.0.0-beta.%d", i], @"prerelease": @YES, @"draft": @NO}];
            if (i == 5) [reply addObject:@{@"tag_name": @"v1.1.0", @"prerelease": @NO, @"draft": @NO}];
        }
        NSArray<NSDictionary *> *kept = SGUpdateReleasesFrom([NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL]);
        NSString *expected = beta ? @"2.0.0-beta.25" : @"1.1.0";
        if (kept.count != (beta ? 20 : 1) || ![kept.firstObject[@"version"] isEqualToString:expected]) {
            wrong++; NSLog(@"[harness] releases: WRONG kept %lu, newest %@, expected %@", (unsigned long)kept.count, kept.firstObject[@"version"], expected);
        }
        // Only betas: a release build has nothing newer, which is an empty list and not a failure.
        NSArray *onlyBetas = [reply filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"prerelease == YES"]];
        kept = SGUpdateReleasesFrom([NSJSONSerialization dataWithJSONObject:onlyBetas options:0 error:NULL]);
        if (!kept || kept.count != (beta ? 20 : 0)) { wrong++; NSLog(@"[harness] releases: WRONG only betas left %@", kept); }
        if (SGUpdateReleasesFrom([@"{\"message\":\"Not Found\"}" dataUsingEncoding:NSUTF8StringEncoding])) {
            wrong++; NSLog(@"[harness] releases: WRONG an error object read as releases");
        }
        // A list a beta stored, one entry before the prerelease mark existed: a release build sees neither.
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        [store setObject:@[@{@"version": @"1.1.0-beta.2", @"prerelease": @YES}, @{@"version": @"1.1.0-beta.1"}, @{@"version": @"1.0.0", @"prerelease": @NO}]
                  forKey:@"spotifyglass.update.releases"];
        [store setDouble:NSDate.date.timeIntervalSince1970 forKey:@"spotifyglass.update.checked"];
        NSString *newer = SGUpdateVersion(), *status = SGUpdateStatus();
        if (beta ? ![newer isEqualToString:@"1.1.0-beta.2"] : (newer != nil || ![status isEqualToString:@"up to date"])) {
            wrong++; NSLog(@"[harness] releases: WRONG the stored list reads %@ (%@)", newer, status);
        }
        [store setObject:@[] forKey:@"spotifyglass.update.releases"];
        if (![SGUpdateStatus() isEqualToString:@"up to date"]) { wrong++; NSLog(@"[harness] releases: WRONG an empty check reads %@", SGUpdateStatus()); }
        if (SGUpdateIncludesBetas() != beta) { wrong++; NSLog(@"[harness] releases: WRONG Include betas starts %d", SGUpdateIncludesBetas()); }

        // Include betas switched the other way from the build's default: the reply keeps what the other
        // kind of build would.
        [store setBool:!beta forKey:SGKeyUpdateBetas];
        kept = SGUpdateReleasesFrom([NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL]);
        expected = beta ? @"1.1.0" : @"2.0.0-beta.25";
        if (kept.count != (beta ? 1 : 20) || ![kept.firstObject[@"version"] isEqualToString:expected]) {
            wrong++; NSLog(@"[harness] releases: WRONG switched, kept %lu, newest %@, expected %@", (unsigned long)kept.count, kept.firstObject[@"version"], expected);
        }
        // A beta tag GitHub has not marked is still a beta.
        kept = SGUpdateReleasesFrom([@"[{\"tag_name\":\"v3.0.0-beta.1\",\"prerelease\":false}]" dataUsingEncoding:NSUTF8StringEncoding]);
        if (kept.count != (beta ? 0 : 1)) { wrong++; NSLog(@"[harness] releases: WRONG an unmarked beta tag, switched, left %@", kept); }

        // What is offered out of a stored list, with the switch on and off. The columns after the list
        // are a beta build (1.0.0-beta.1) on, off, then a release build (1.0.0) on, off; "-" is nothing.
        NSDictionary *pre = @{@"prerelease": @YES}, *final = @{@"prerelease": @NO};
        NSArray *offers = @[
            @[@[@[@"1.0.0-beta.2", pre]], @"1.0.0-beta.2", @"-", @"-", @"-"],
            @[@[@[@"1.0.0", final], @[@"1.0.0-beta.2", pre]], @"1.0.0", @"1.0.0", @"-", @"-"],
            @[@[@[@"1.0.1-beta.1", pre], @[@"1.0.0", final]], @"1.0.1-beta.1", @"1.0.0", @"1.0.1-beta.1", @"-"],
            @[@[@[@"1.0.0-beta.9", @{}]], @"1.0.0-beta.9", @"-", @"-", @"-"],   // stored before the mark
            @[@[@[@"1.1.0", final], @[@"1.0.1-beta.1", pre]], @"1.1.0", @"1.1.0", @"1.1.0", @"1.1.0"],
            @[@[@[@"0.9.0", final]], @"-", @"-", @"-", @"-"],
            @[@[], @"-", @"-", @"-", @"-"],
        ];
        for (NSArray *offer in offers) {
            NSMutableArray *stored = [NSMutableArray array], *versions = [NSMutableArray array];
            for (NSArray *entry in offer[0]) {
                NSMutableDictionary *release = [entry[1] mutableCopy];
                release[@"version"] = entry[0];
                [stored addObject:release];
                [versions addObject:entry[0]];
            }
            [store setObject:stored forKey:@"spotifyglass.update.releases"];
            NSString *list = [versions componentsJoinedByString:@", "];
            for (int on = 1; on >= 0; on--) {
                [store setBool:on forKey:SGKeyUpdateBetas];
                NSString *want = offer[(beta ? 1 : 3) + (on ? 0 : 1)];
                NSString *got = SGUpdateVersion() ?: @"-";
                BOOL saysBeta = SGUpdateNewestRelease().prerelease;
                BOOL right = [got isEqualToString:want] && (!SGUpdateVersion() || saysBeta == [got containsString:@"-"]);
                if (!right) wrong++;
                NSLog(@"[harness] releases: %@betas %s, stored [%@]: offered %@%@, expected %@", right ? @"" : @"WRONG ",
                      on ? "on" : "off", list, got, saysBeta && SGUpdateVersion() ? @" as a beta" : @"", want);
            }
        }
        for (NSString *key in @[@"spotifyglass.update.checked", @"spotifyglass.update.releases", SGKeyUpdateBetas]) [store removeObjectForKey:key];
        NSLog(@"[harness] releases as %s: %lu wrong -- %@", SG_VERSION, (unsigned long)wrong, wrong ? @"FAIL" : @"PASS");
        exit(wrong ? 1 : 0);
    }
    if ([arguments containsObject:@"wipe"]) {
        for (NSString *key in @[@"spotifyglass.update.checked", @"spotifyglass.update.releases", @"spotifyglass.update.told"])
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    }
    BOOL notice = [arguments containsObject:@"notice"];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UINavigationController *stack = [[UINavigationController alloc] initWithRootViewController:notice ? plainScreen() : SGUpdatePage()];
    stack.navigationBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = stack;
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    if (notice) SGWatchForUpdates();
    if ([arguments containsObject:@"recheck"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGCheckForUpdate(YES);
        });
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
