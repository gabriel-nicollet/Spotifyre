// The lyrics page harness: the redesign's Lyrics page as App/Pages.m opens it, its preview playing the sample
// song in the real lyrics view, the presets under it and the sliders' sheet, with one stand-in section under them.
//
// Launch arguments (NSUserDefaults' argument domain):
//   -preset N   stores preset N before the page opens (0 Apple Music, 1 Large, 2 Compact, 3 Calm, 4 Vivid)
//   -sheet S    opens the sliders' sheet S seconds in, as a tap on its button would
//   -check 1    asserts the page's behavior (see runChecks), prints PASS and FAIL lines and quits with the
//               number of failures
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"

static int sg_failures;

static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    fflush(stdout);
    if (!ok) sg_failures++;
}

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static void collect(UIView *root, Class cls, NSMutableArray *into) {
    if ([root isKindOfClass:cls]) [into addObject:root];
    for (UIView *view in root.subviews) collect(view, cls, into);
}

static NSArray *find(UIView *root, Class cls) {
    NSMutableArray *found = [NSMutableArray array];
    collect(root, cls, found);
    return found;
}

// The preset buttons, in order.
static NSArray<UIButton *> *chipsOf(UIViewController *page) {
    return [page valueForKey:@"chips"];
}

static BOOL lit(UIButton *chip) {
    return (chip.accessibilityTraits & UIAccessibilityTraitSelected) != 0;
}

static void runChecks(UIViewController *page) {
    SGRKaraokeView *preview = [page valueForKey:@"preview"];
    NSArray<UIButton *> *chips = chipsOf(page);
    expect(chips.count == SGRLyricsLookPresetNames().count && lit(chips[0]), @"with nothing stored Apple Music is lit");
    expect([preview valueForKey:@"tops"] != nil && !preview.hidden, @"the preview plays its lines");
    UIView *header = ((UITableViewController *)page).tableView.tableHeaderView;
    expect(CGRectGetMaxY([chips[0] convertRect:chips[0].bounds toView:header]) < header.bounds.size.height,
           [NSString stringWithFormat:@"the header holds the preview and the presets (%.0f pt tall)", header.bounds.size.height]);

    [chips[1] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    expect(lit(chips[1]) && !lit(chips[0]) && [[preview valueForKey:@"fontSize"] doubleValue] == 36,
           @"a tap on Large lights it and sets the preview's lines at 36 pt");

    UIButton *adjust = [page valueForKey:@"adjust"];
    // The fifth preset, past the edge of the strip on a phone, is scrolled into sight when it is picked.
    [chips.lastObject sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [page.view layoutIfNeeded];
    UIScrollView *strip = [page valueForKey:@"strip"];
    after(0.6, ^{
        CGRect shown = [strip convertRect:chips.lastObject.bounds fromView:chips.lastObject];
        expect(CGRectContainsRect(strip.bounds, shown), @"a preset picked past the edge of the strip is scrolled into sight");
    });
    [adjust sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    after(1.2, ^{
        UINavigationController *nav = (UINavigationController *)page.presentedViewController;
        UITableViewController *sheet = (UITableViewController *)nav.topViewController;
        expect([nav isKindOfClass:UINavigationController.class] && [NSStringFromClass(sheet.class) isEqualToString:@"SGRLyricsStyleSheet"],
               @"the sliders' button opens the sheet");
        NSArray<UISlider *> *sliders = find(sheet.tableView, UISlider.class);
        expect(sliders.count == 5, [NSString stringWithFormat:@"the sheet has five sliders (%lu)", (unsigned long)sliders.count]);
        UISlider *spacing = nil;
        for (UISlider *slider in sliders) {
            if (slider.maximumValue == 40 && slider.minimumValue == 12) spacing = slider;
        }
        spacing.value = 34;
        [spacing sendActionsForControlEvents:UIControlEventValueChanged];
        expect([[preview valueForKey:@"lineGap"] doubleValue] == 34 && lit(adjust) && [adjust.accessibilityValue isEqualToString:@"Custom"],
               [NSString stringWithFormat:@"a slider moves the preview's lines apart (%@ pt) and the look reads Custom",
                [preview valueForKey:@"lineGap"]]);
        // A preset picked over the sheet is read back into its sliders.
        [chips[0] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        [sheet.tableView layoutIfNeeded];
        UISlider *again = nil;
        for (UISlider *slider in find(sheet.tableView, UISlider.class)) {
            if (slider.maximumValue == 40 && slider.minimumValue == 12) again = slider;
        }
        expect(again.value == 24 && lit(chips[0]), [NSString stringWithFormat:@"Apple Music picked over the sheet puts its slider back to 24 (%.0f)", again.value]);
        after(0.8, ^{
            printf("%d failed\n", sg_failures);
            fflush(stdout);
            exit(sg_failures);
        });
    });
}

@interface SGHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *args = NSUserDefaults.standardUserDefaults;
    [args removeObjectForKey:SGRKeyLyricsLook];   // each launch starts from its own arguments
    if ([args objectForKey:@"preset"]) SGRSetLyricsLook(SGRLyricsLookPreset((NSUInteger)[args integerForKey:@"preset"]), nil);
    SGModSection *stand = SGSection(@"Sources", @[SGSwitchRow(@"Lyrics for every track", @"Even where Spotify has none", @"harness.everyTrack")]);
    UIViewController *page = SGRLyricsSettingsPage(@"Lyrics", SGRestartNote, @[stand]);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.navigationBar.prefersLargeTitles = NO;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    if ([args objectForKey:@"sheet"]) {
        after([args doubleForKey:@"sheet"], ^{
            [(UIButton *)[page valueForKey:@"adjust"] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        });
    }
    if ([args boolForKey:@"check"]) after(2.5, ^{ runChecks(page); });   // the preview measures its lines off the main thread
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessDelegate.class));
    }
}
