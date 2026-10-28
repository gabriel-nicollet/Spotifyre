// Mod Settings > Live Activity (Shared/LiveActivity/LiveActivitySettings.m) and its preview (SGLiveActivityPreview.m),
// with the real Settings/ framework behind them and stubs.m for the activity and the sleep timer. The launch line
// sets the page's options up, then plays actions, one every 0.7 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/LiveActivityPageHarness.app
//     xcrun simctl launch <udid> com.vojta.liveactivitypageharness [setup...] [action...]
//
// Setup (every Live Activity key is cleared first): view=<n> (Lyrics 0, Queue 1, Control menu 2), size=<n>,
// without=<n> (Note 0, Track 1), align=<n> (Left 0, Center 1), colors=<n> (Spotify 0, Artwork 1, Plain 2),
// translation, artwork-off, bar-off.
// Actions: tap (the preview's next step, as VoiceOver's double tap), stop (the page's off screen: the preview stops
// stepping), wait (nothing, for a step to pass), dump (the preview's value and the rows each section shows, to the log).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/LiveActivity/LiveActivity.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass.liveActivity"]) [store removeObjectForKey:key];
    }
    NSDictionary<NSString *, NSString *> *ints = @{@"view": SGKeyLiveActivityView, @"size": SGKeyLiveActivityTextSize,
        @"without": SGKeyLiveActivityWithoutLyrics, @"align": SGKeyLiveActivityAlignment, @"colors": SGKeyLiveActivityColors};
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        NSArray<NSString *> *parts = [arg componentsSeparatedByString:@"="];
        if (parts.count == 2 && ints[parts[0]]) SGSetInt(ints[parts[0]], parts[1].integerValue);
        else if ([arg isEqualToString:@"translation"]) SGSetEnabled(SGKeyLiveActivityTranslation, YES);
        else if ([arg isEqualToString:@"artwork-off"]) SGSetEnabled(SGKeyLiveActivityArtwork, NO);
        else if ([arg isEqualToString:@"bar-off"]) SGSetEnabled(SGKeyLiveActivityProgressBar, NO);
        else if (![arg hasPrefix:@"-"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGLiveActivitySettingsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (void)run:(NSString *)action {
    UITableView *table = ((UITableViewController *)self.nav.topViewController).tableView;
    UIView *preview = table.tableHeaderView;
    if ([action isEqualToString:@"tap"]) {
        [preview accessibilityActivate];
    } else if ([action isEqualToString:@"stop"]) {
        [preview setValue:@NO forKey:@"running"];
    } else if ([action isEqualToString:@"dump"]) {
        NSLog(@"[harness] preview \"%@\", \"%@\", %.0f pt high", preview.accessibilityLabel, preview.accessibilityValue, preview.bounds.size.height);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                if ([table rectForRowAtIndexPath:path].size.height < 1) continue;
                UITableViewCell *cell = [table cellForRowAtIndexPath:path];
                NSString *title = [(UIListContentConfiguration *)cell.contentConfiguration text] ?: cell.textLabel.text ?: @"?";
                [rows addObject:title];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
