// Add a Tab harness: Shared/Navigation/AddTabSheet.m and TabIcons.m run for real in the simulator, over a
// stand-in for Spotify's Encore classes (a few glyphs drawn as SF Symbols), with Links.x compiled as it
// is (no dispatcher, so every link is "unknown" and let through, as before Spotify has set it up).
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "Shared/Navigation/AddTabSheet.h"
#import "Shared/Navigation/TabIcons.h"
#import "Redesigned/Navbar/Navbar.h"

#pragma mark - Spotify's classes, by the names TabIcons.m looks for

@interface SGHarnessGlyph : NSObject
@property (nonatomic, copy) NSString *name;
@end
@implementation SGHarnessGlyph
@end

@interface SPTEncoreIcon : NSObject
@end
@implementation SPTEncoreIcon
static id glyph(NSString *name) { SGHarnessGlyph *g = [SGHarnessGlyph new]; g.name = name; return g; }
+ (id)home { return glyph(@"home"); }
+ (id)search { return glyph(@"search"); }
+ (id)heart { return glyph(@"heart"); }
+ (id)podcasts { return glyph(@"podcasts"); }
+ (id)star { return glyph(@"star"); }
+ (id)playlist { return glyph(@"playlist"); }
+ (id)plus { return glyph(@"plus"); }
+ (id)queue { return glyph(@"queue"); }
// Not glyphs: one takes an argument, one returns no object, one has no name.
+ (id)iconNamed:(NSString *)name { return glyph(name); }
+ (NSInteger)count { return 8; }
+ (id)helper { return [NSObject new]; }
@end

@interface SPTEncoreIconView : UIImageView
- (instancetype)initWithIcon:(id)icon;
- (void)setForegroundColor:(UIColor *)color;
@end
@implementation SPTEncoreIconView
- (instancetype)initWithIcon:(id)icon {
    NSDictionary *symbols = @{@"home": @"house", @"search": @"magnifyingglass", @"heart": @"heart", @"podcasts": @"mic",
                              @"star": @"star", @"playlist": @"music.note.list", @"plus": @"plus", @"queue": @"list.bullet"};
    if (!(self = [super initWithImage:[UIImage systemImageNamed:symbols[[icon name]] ?: @"questionmark"]])) return nil;
    self.contentMode = UIViewContentModeScaleAspectFit;
    return self;
}
- (void)setForegroundColor:(UIColor *)color { self.tintColor = color; }
@end

#pragma mark - the app

@interface SGHarnessRoot : UIViewController
@end
@implementation SGHarnessRoot
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
}
@end

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static UITableViewController *topPage(UIViewController *root) {
    UINavigationController *nav = (UINavigationController *)root.presentedViewController;
    return (UITableViewController *)nav.topViewController;
}

static void tap(UITableViewController *page, NSInteger section, NSInteger row) {
    NSLog(@"[harness] tap %ld.%ld on %@", (long)section, (long)row, page.title);
    [page.tableView.delegate tableView:page.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}

// The redesign's Tab bar page (Redesigned/Navbar/NavbarSettings.m) over a sample bar: Spotify's four tabs,
// Liked Songs added after Search, Create hidden and Search split apart. `navbar` the page; `icons` Icons only
// picked on its card; `links` scrolled to its end; `off` Custom tab bar switched off; `hide` Home's circle tapped; `edit` Liked Songs
// tapped, which opens its sheet; `remove` Remove Tab on that sheet. Each step logs the preview and the list.
static void runNavbar(UIViewController *root, NSString *mode) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store setBool:NO forKey:SGRKeyNavbarHideLabels];
    [store removeObjectForKey:SGRKeyNavbar];
    SGRSetNavbarStock(@[@"Home", @"Search", @"Your Library", @"Create"]);
    SGRSetNavbarLayout(@[
        @{SGRNavbarID: @"Home", SGRNavbarTitle: @"Home"},
        @{SGRNavbarID: @"Search", SGRNavbarTitle: @"Search"},
        @{SGRNavbarID: @"liked", SGRNavbarTitle: @"Liked Songs", SGRNavbarURI: @"spotify:collection:tracks", SGRNavbarIcon: @"heart"},
        @{SGRNavbarID: @"Your Library", SGRNavbarTitle: @"Your Library"},
        @{SGRNavbarID: @"Create", SGRNavbarTitle: @"Create", SGRNavbarHidden: @YES},
    ]);
    SGRSetNavbarSplit(@[@"Search"]);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGRNavbarSettingsPage()];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [root presentViewController:nav animated:NO completion:nil];
    UITableViewController *page = (UITableViewController *)nav.topViewController;
    void (^log)(NSString *) = ^(NSString *step) {
        UIView *preview = page.tableView.tableHeaderView.subviews.firstObject;
        NSMutableArray<NSString *> *rows = [NSMutableArray array];
        for (NSInteger row = 0; row < [page.tableView numberOfRowsInSection:2]; row++) {
            UITableViewCell *cell = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:2]];
            [rows addObject:[NSString stringWithFormat:@"%@ (%@)", [(UIListContentConfiguration *)cell.contentConfiguration text], cell.accessibilityValue]];
        }
        NSLog(@"[harness] %@: preview \"%@\", tabs %@, labels hidden %d, custom %d", step, preview.accessibilityValue,
              [rows componentsJoinedByString:@", "], [store boolForKey:SGRKeyNavbarHideLabels], [store objectForKey:SGRKeyNavbar] ? [store boolForKey:SGRKeyNavbar] : 1);
    };
    after(1.0, ^{ log(@"opened"); });
    if ([mode isEqualToString:@"icons"]) {
        after(1.5, ^{
            UIView *labels = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]].contentView.subviews.firstObject;
            UIControl *iconsOnly = ((UIStackView *)labels).arrangedSubviews.lastObject;
            [iconsOnly sendActionsForControlEvents:UIControlEventTouchUpInside];
            log(@"icons only");
        });
    } else if ([mode isEqualToString:@"links"]) {
        after(1.5, ^{
            UITableView *table = page.tableView;
            [table setContentOffset:CGPointMake(0, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom) animated:NO];
        });
    } else if ([mode isEqualToString:@"off"]) {
        after(1.5, ^{
            UISwitch *toggle = (UISwitch *)[page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].accessoryView;
            toggle.on = NO;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
            log(@"custom off");
        });
    } else if ([mode isEqualToString:@"hide"]) {
        after(1.5, ^{
            UITableViewCell *home = [page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
            for (UIView *v in home.contentView.subviews) if ([v isKindOfClass:UIButton.class]) [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
            log(@"Home hidden");
        });
    } else if ([mode isEqualToString:@"edit"] || [mode isEqualToString:@"remove"]) {
        after(1.5, ^{ tap(page, 2, 2); });
        if ([mode isEqualToString:@"remove"]) {
            after(3.0, ^{ tap(topPage(page), 2, 0); });
            after(4.0, ^{
                UIAlertController *alert = (UIAlertController *)topPage(page).presentedViewController;
                UIAlertAction *remove = alert.actions.firstObject;
                NSLog(@"[harness] asked: %@ -> %@", alert.message, remove.title);
                // UIAlertAction keeps its handler under a private key; a finger on the button runs the same block.
                void (^handler)(UIAlertAction *) = [remove valueForKey:@"handler"];
                NSLog(@"[harness] the action's handler %@", handler ? @"found" : @"missing");
                [alert dismissViewControllerAnimated:NO completion:^{ if (handler) handler(remove); }];
            });
            after(5.5, ^{ log(@"Liked Songs removed"); });
        }
    }
}

@implementation SGHarnessScene

// Launch words: `sheet` the sheet as it opens; `preset` Liked Songs picked from Choose a Link; `glyphs`
// Choose an Icon on Encore; `symbols` Choose an Icon searching SF Symbols for "heart"; `pick` one of its results
// tapped mid-search; `added` Liked Songs with
// the SF Symbol music.mic added, the tab logged. The glyph enumeration and the symbol list's size and time are logged.
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    SGHarnessRoot *root = [SGHarnessRoot new];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    NSString *mode = args.count > 1 ? args[1] : @"sheet";
    if ([@[@"navbar", @"icons", @"off", @"hide", @"edit", @"remove", @"links"] containsObject:mode]) {
        runNavbar(root, mode);
        return;
    }

    NSLog(@"[harness] glyphs %@", SGEncoreGlyphNames());
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    SGLoadSymbolNames(^(NSArray<NSString *> *names) {
        NSLog(@"[harness] %lu symbols in %.2f s, first %@, has heart.circle %d, has a .ar %d", (unsigned long)names.count,
              CFAbsoluteTimeGetCurrent() - start, names.firstObject, [names containsObject:@"heart.circle"],
              [names containsObject:@"0.circle.ar"]);
    });

    NSArray *presets = @[
        @{SGTabTitle: @"Liked Songs", SGTabURI: @"spotify:collection:tracks", SGTabIcon: @"heart"},
        @{SGTabTitle: @"Podcasts", SGTabURI: @"spotify:collection:podcasts", SGTabIcon: @"podcasts"},
        @{SGTabTitle: @"Queue", SGTabURI: @"spotify:now-playing:queue", SGTabIcon: @"queue"},
    ];
    after(0.5, ^{
        SGPresentAddTabSheet(root, presets, ^(NSDictionary *tab) { NSLog(@"[harness] added %@", tab); });
    });
    if ([mode isEqualToString:@"sheet"]) return;
    after(2.5, ^{ tap(topPage(root), 1, 0); });
    after(3.5, ^{
        if ([mode isEqualToString:@"preset"] || [mode isEqualToString:@"added"]) tap(topPage(root), 0, 0);
        else [topPage(root).navigationController popViewControllerAnimated:NO];
    });
    if ([mode isEqualToString:@"preset"]) return;
    after(4.5, ^{ tap(topPage(root), 1, 1); });
    if ([mode isEqualToString:@"glyphs"]) return;
    after(5.5, ^{
        UITableViewController *page = topPage(root);
        UISegmentedControl *sets = (UISegmentedControl *)page.navigationItem.titleView;
        sets.selectedSegmentIndex = 1;
        [sets sendActionsForControlEvents:UIControlEventValueChanged];
        if (![mode isEqualToString:@"symbols"] && ![mode isEqualToString:@"pick"]) return;
        page.navigationItem.searchController.active = YES;
        page.navigationItem.searchController.searchBar.text = @"heart";
        [page.navigationItem.searchController.searchResultsUpdater updateSearchResultsForSearchController:page.navigationItem.searchController];
    });
    if ([mode isEqualToString:@"symbols"]) return;
    // `pick`: a result tapped while the search is still up, as a finger would.
    if ([mode isEqualToString:@"pick"]) {
        after(7.0, ^{
            UITableViewController *page = topPage(root);
            NSLog(@"[harness] before pick: active %d, page presents %@, nav presents %@, search bar in window %d, rows %ld", page.navigationItem.searchController.active,
                  page.presentedViewController, page.navigationController.presentedViewController,
                  page.navigationItem.searchController.searchBar.window != nil, (long)[page.tableView numberOfRowsInSection:0]);
            tap(page, 0, 0);
        });
        after(9.5, ^{ NSLog(@"[harness] after pick: %@", topPage(root).title); });
        return;
    }
    after(7.0, ^{
        tap(topPage(root), 0, 6);
    });
    after(8.5, ^{
        UIBarButtonItem *add = topPage(root).navigationItem.rightBarButtonItem;
        NSLog(@"[harness] add enabled %d", add.enabled);
        ((void (*)(id, SEL))objc_msgSend)(add.target, add.action);
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
