// Mod Settings > Appearance as App/Pages.m builds it, with the real rows of either look's accent
// (Native/Appearance/AppearanceSettings.m, Redesigned/Kit/SGRAppearanceSettings.m), the font rows and their import
// (Shared/Fonts/FontImport.m) and the Settings/ framework, stubs.m for the hooks. The launch line sets the keys up
// and then plays actions, one every 0.9 s from 1 s in; screenshot after.
//
//     ./build.sh && xcrun simctl install <udid> build/AppearancePageHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.appearancepageharness [setup...] [action...]
//
// Setup: keep (the stored settings stay; otherwise every spotifyglass.accent / .redesign.accent / .font key is
// cleared first), redesign (the redesign's rows), accent=<hex|-1>, raccent=<hex|-1>, font=<n>.
// Actions: open=<section>.<row> (the row's menu opened as a tap does), menu=<section>.<row>:<n> (its nth item
// picked), select=<section>.<row> (a tap on the row), color=<hex> (the open picker moved there), confirm (its
// checkmark), close (the sheet dismissed without it), import=<path,path> (those files handed to the font import as
// Files would), dismiss (whatever is presented goes), dump (the stored keys and every row with what it reads).
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Shared/Fonts/Fonts.h"

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

static NSInteger hex(NSString *text) {
    return [text isEqualToString:@"-1"] ? -1 : (NSInteger)strtol(text.UTF8String, NULL, 16);
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

// SGAppearancePage's sections, the Redesigned UI switch standing in for either first row.
- (UIViewController *)appearancePage {
    SGModRow *look = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
    look.glows = YES;
    return [[SGModPage alloc] initWithTitle:@"Appearance" intro:SGRestartNote sections:@[
        SGSection(nil, @[SGWithSymbol(look, @"sparkles")]),
        SGSection(nil, SGFlag(SGKeyRedesign, NO) ? SGRAppearanceRows() : SGNativeAppearanceRows()),
        SGSection(nil, SGAppFontRows()),
    ] footer:nil];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    // The family grouping the font import goes by: one shared name passes, a mix, a missing name or no face does not.
    NSCAssert([SGFontSingleFamily(@[@"Inter", @"Inter", @"Inter"]) isEqualToString:@"Inter"], @"one family");
    NSCAssert([SGFontSingleFamily(@[@"Inter"]) isEqualToString:@"Inter"], @"one face");
    NSCAssert(!SGFontSingleFamily(@[@"Inter", @"Lato"]), @"two families");
    NSCAssert(!SGFontSingleFamily(@[@"Inter", @""]), @"a face without a family");
    NSCAssert(!SGFontSingleFamily(@[]), @"no faces");
    NSLog(@"[harness] family grouping ok");
    if (![args containsObject:@"keep"]) {
        for (NSString *key in store.dictionaryRepresentation.allKeys) {
            if ([key hasPrefix:@"spotifyglass.accent"] || [key hasPrefix:@"spotifyglass.redesign.accent"] || [key hasPrefix:@"spotifyglass.font"] ||
                [key isEqualToString:SGKeyRedesign]) [store removeObjectForKey:key];
        }
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"redesign"]) SGSetEnabled(SGKeyRedesign, YES);
        else if ([arg hasPrefix:@"accent="]) SGSetInt(SGKeyAccent, hex([arg substringFromIndex:7]));
        else if ([arg hasPrefix:@"raccent="]) SGSetInt(SGRKeyAccent, hex([arg substringFromIndex:8]));
        else if ([arg hasPrefix:@"font="]) SGSetInt(SGKeyAppFont, [arg substringFromIndex:5].integerValue);
        else if (![arg isEqualToString:@"keep"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:[self appearancePage]];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.9 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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

- (UIButton *)buttonAt:(NSString *)text {
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    findViews([self.table cellForRowAtIndexPath:[self pathFrom:text]], UIButton.class, buttons);
    return buttons.firstObject;
}

- (UIColorPickerViewController *)picker {
    UINavigationController *sheet = (UINavigationController *)self.nav.presentedViewController;
    return [sheet isKindOfClass:UINavigationController.class] ? (UIColorPickerViewController *)sheet.viewControllers.firstObject : nil;
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"open"]) {
        UIButton *button = [self buttonAt:value];
        if (@available(iOS 17.4, *)) [button performPrimaryAction];
    } else if ([verb isEqualToString:@"menu"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@":"];
        UIButton *button = [self buttonAt:at[0]];
        UIAction *item = (UIAction *)button.menu.children[(NSUInteger)at[1].integerValue];
        NSLog(@"[harness] menu offers %@, picking %@", [[button.menu.children valueForKey:@"title"] componentsJoinedByString:@" / "], item.title);
        [item performWithSender:button target:nil];
    } else if ([verb isEqualToString:@"select"]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[self pathFrom:value]];
    } else if ([verb isEqualToString:@"color"]) {
        self.picker.selectedColor = SGColorRGB(hex(value));
    } else if ([verb isEqualToString:@"confirm"]) {
        UIBarButtonItem *done = self.picker.navigationItem.rightBarButtonItem;
        NSLog(@"[harness] the sheet's bar: left %@, right %@", self.picker.navigationItem.leftBarButtonItems, done);
        [UIApplication.sharedApplication sendAction:done.action to:done.target from:done forEvent:nil];
    } else if ([verb isEqualToString:@"close"]) {
        UIBarButtonItem *close = self.picker.navigationItem.leftBarButtonItem;
        [UIApplication.sharedApplication sendAction:close.action to:close.target from:close forEvent:nil];
    } else if ([verb isEqualToString:@"dismiss"]) {
        [self.nav dismissViewControllerAnimated:YES completion:nil];
    } else if ([verb isEqualToString:@"import"]) {
        id picker = [NSClassFromString(@"SGFontPicker") new];
        NSMutableArray<NSURL *> *urls = [NSMutableArray array];
        for (NSString *path in [value componentsSeparatedByString:@","]) [urls addObject:[NSURL fileURLWithPath:path]];
        [picker documentPicker:[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFont] asCopy:YES] didPickDocumentsAtURLs:urls];
    } else if ([verb isEqualToString:@"delete"]) {
        UIContextualAction *action = [table.delegate tableView:table trailingSwipeActionsConfigurationForRowAtIndexPath:[self pathFrom:value]].actions.firstObject;
        NSLog(@"[harness] swipe on %@ offers %@", value, action.title ?: @"nothing");
        if (action) action.handler(action, [UIView new], ^(BOOL done) {});
    } else if ([verb isEqualToString:@"dump"]) {
        NSDictionary *all = NSUserDefaults.standardUserDefaults.dictionaryRepresentation;
        for (NSString *key in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if ([key hasPrefix:@"spotifyglass.accent"] || [key hasPrefix:@"spotifyglass.redesign.accent"] || [key hasPrefix:@"spotifyglass.font"])
                NSLog(@"[harness] stored %@ = %@", key, [all[key] isKindOfClass:NSNumber.class] && [all[key] integerValue] >= 0 ? [NSString stringWithFormat:@"%06lX", (long)[all[key] integerValue]] : all[key]);
        }
        NSLog(@"[harness] in effect: native #%06lX, redesign #%06lX", (long)SGAccentRGB(), (long)SGRAccentRGB());
        // What Fonts.x's launch would get: the file registered again, and a font made from its name.
        NSString *name = SGRegisterCustomFont();
        NSLog(@"[harness] the launch registers %@, which makes %@", name, name ? [UIFont fontWithName:name size:13] : nil);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.accessoryView, UILabel.class, labels);
                UIButton *button = [self buttonAt:[NSString stringWithFormat:@"%ld.%ld", (long)section, (long)row]];
                NSString *reads = button ? [NSString stringWithFormat:@"menu \"%@\" (VoiceOver: %@, %@)", button.configuration.attributedTitle.string, button.accessibilityLabel, button.accessibilityValue]
                                         : labels.firstObject.text;
                [rows addObject:[NSString stringWithFormat:@"%@ [%@]", [(UIListContentConfiguration *)cell.contentConfiguration text], reads ?: @""]];
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
