// Mod Settings > Vibrations (Shared/Haptics/HapticsSettings.m), its preview (SGVibrationsPreview.m) and
// its cards, with the real Settings/ framework and SGFeedback.m behind them and stubs.m for Music Haptics' engine. The launch line sets the switches up and then plays actions, one every 0.7 s from 1 s
// in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/HapticsPageHarness.app
//     xcrun simctl launch <udid> com.vojta.hapticspageharness [setup...] [action...]
//
// Setup: keep (the stored settings stay; otherwise every haptics key is cleared first),
// controls-off (Controls switched off), music (Music Haptics switched on), background (In the Background switched on),
// mode=<n> (the one choice of before stored, None 0, Generated 1, Native iOS 2, for the page to move to the switches),
// ios-off (Music Haptics off in Settings > Accessibility, as SystemMusicHaptics.x would report it), follows=<n>,
// slow (animations at a twentieth of their speed).
// More actions: ios=on|off (iOS's switch changing while the page shows), expect=<music>,<background> (on or off
// each: what the switches read, logged as ok or FAILED).
// Actions: toggle=<section>.<row> (that row's switch flipped the way a tap does), slide=<section>.<row>:<value>
// (that slider dragged there and let go), tap (the preview tapped, as VoiceOver's double tap does it),
// pulse=<intensity> (a tap of Music Haptics' handed to the preview, as the engine does while the page shows), swipe=<section>.<row>:<n> (VoiceOver's swipe up on it, n times, down
// for a negative n), info=<section>.<row> (a tap on its ⓘ), select=<section>.<row> (a tap on a row of the page
// on top), pop, bottom (scrolled to the end), dump (the stored haptics keys, what the hooks would read, and the
// rows each section shows, to the log).
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Haptics/Haptics.h"

void SGHarnessPulse(float intensity);   // stubs.m

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![args containsObject:@"keep"]) {
        for (NSString *key in store.dictionaryRepresentation.allKeys) {
            if ([key hasPrefix:@"spotifyglass."] && [key containsString:@"haptics"]) [store removeObjectForKey:key];
        }
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"controls-off"]) SGSetEnabled(SGKeyControlHaptics, NO);
        else if ([arg isEqualToString:@"music"]) SGSetEnabled(SGKeyMusicHaptics, YES);
        else if ([arg isEqualToString:@"background"]) SGSetEnabled(SGKeyMusicHapticsBackground, YES);
        else if ([arg hasPrefix:@"mode="]) SGSetInt(SGKeyMusicHapticsMode, [arg substringFromIndex:5].integerValue);
        else if ([arg isEqualToString:@"ios-off"]) SGSetSystemMusicHapticsOn(NO);
        else if ([arg hasPrefix:@"follows="]) SGSetInt(SGKeyMusicFollows, [arg substringFromIndex:8].integerValue);
        else if (![@[@"keep", @"slow"] containsObject:arg]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGVibrationsSettingsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    if ([args containsObject:@"slow"]) self.window.layer.speed = 0.05;

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (NSIndexPath *)pathFrom:(NSString *)text {
    NSArray<NSString *> *at = [text componentsSeparatedByString:@"."];
    return [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"toggle"]) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:value]];
        NSMutableArray<UISwitch *> *switches = [NSMutableArray array];
        findViews(cell, UISwitch.class, switches);
        UISwitch *toggle = switches.firstObject;
        [toggle setOn:!toggle.on animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"slide"] || [verb isEqualToString:@"swipe"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:at[0]]];
        NSMutableArray<UISlider *> *sliders = [NSMutableArray array];
        findViews(cell, UISlider.class, sliders);
        UISlider *slider = sliders.firstObject;
        if ([verb isEqualToString:@"swipe"]) {
            NSInteger n = at[1].integerValue;
            for (NSInteger i = 0; i < labs(n); i++) {
                if (n > 0) [slider accessibilityIncrement];
                else [slider accessibilityDecrement];
            }
        } else {
            // A drag: a few values on the way, off the steps, then let go.
            float from = slider.value, to = at[1].floatValue;
            for (int step = 1; step <= 4; step++) {
                slider.value = from + (to - from) * step / 4 + (step < 4 ? 1.3f : 0);
                [slider sendActionsForControlEvents:UIControlEventValueChanged];
            }
            [slider sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        NSLog(@"[harness] slider %@ reads %@ (thumb at %.1f)", slider.accessibilityLabel, slider.accessibilityValue, slider.value);
    } else if ([verb isEqualToString:@"info"]) {
        UITableViewCell *cell = [table cellForRowAtIndexPath:[self pathFrom:value]];
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        findViews(cell, UIButton.class, buttons);
        [buttons.firstObject sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIAlertController *alert = (UIAlertController *)self.nav.topViewController.presentedViewController;
        NSLog(@"[harness] the ⓘ shows \"%@\": %@", alert.title, [alert.message substringToIndex:MIN(60, alert.message.length)]);
    } else if ([verb isEqualToString:@"select"]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[self pathFrom:value]];
    } else if ([verb isEqualToString:@"tap"]) {
        [table.tableHeaderView accessibilityActivate];
    } else if ([verb isEqualToString:@"pulse"]) {
        SGHarnessPulse(value.floatValue);
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"bottom"]) {
        CGFloat max = MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
        [table setContentOffset:CGPointMake(0, max) animated:NO];
    } else if ([verb isEqualToString:@"ios"]) {
        SGSetSystemMusicHapticsOn([value isEqualToString:@"on"]);
    } else if ([verb isEqualToString:@"expect"]) {
        NSString *got = [NSString stringWithFormat:@"%@,%@", SGMusicHapticsOn() ? @"on" : @"off", SGMusicHapticsInBackground() ? @"on" : @"off"];
        NSLog(@"[harness] %@ Music Haptics, In the Background read %@ (want %@), the old choice %@", [got isEqualToString:value] ? @"  ok  " : @"FAILED",
              got, value, [NSUserDefaults.standardUserDefaults objectForKey:SGKeyMusicHapticsMode] ? @"still stored" : @"gone");
    } else if ([verb isEqualToString:@"alert"]) {
        UIAlertController *alert = (UIAlertController *)self.nav.topViewController.presentedViewController;
        NSLog(@"[harness] on top: %@", [alert isKindOfClass:UIAlertController.class]
              ? [NSString stringWithFormat:@"\"%@\": %@", alert.title, [alert.message substringToIndex:MIN(70, alert.message.length)]] : @"no alert");
    } else if ([verb isEqualToString:@"dump"]) {
        NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key hasPrefix:@"spotifyglass."] && [key containsString:@"haptics"]) NSLog(@"[harness] stored %@ = %@", key, all[key]);
        }
        NSLog(@"[harness] the hooks read: Controls %@ at %.0f%%, Music Haptics %@ at %.0f%% following %ld, In the Background %@, iOS's Music Haptics %@; "
              @"the preview says \"%@\"", SGEnabled(SGKeyControlHaptics) ? @"on" : @"off",
              SGHapticsStrength(SGKeyControlStrength) * 100, SGMusicHapticsOn() ? @"on" : @"off", SGHapticsStrength(SGKeyMusicStrength) * 100,
              (long)SGMusicHapticsFollows(), SGMusicHapticsInBackground() ? @"on" : @"off", SGSystemMusicHapticsOn() ? @"on" : @"off",
              table.tableHeaderView.accessibilityHint);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSString *title = [(UIListContentConfiguration *)cell.contentConfiguration text];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                if (!title) findViews(cell.contentView, UILabel.class, labels);
                [rows addObject:[NSString stringWithFormat:@"%@ (%.0fpt%@)", title ?: labels.firstObject.text ?: @"?", [table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]].size.height,
                                 cell.contentView.alpha < 1 ? @", grayed" : @""]];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // The redesign's look: black, the redesign's own accent.
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeyRedesign];
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
