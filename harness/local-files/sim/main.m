// Edit info in the simulator: EditInfoMenu.x and LocalFiles.m as the tweak compiles them, on a mock of
// Spotify's context menu sheet presented over a player that plays a local file. The script taps the row,
// which closes the menu and brings up the editor, then types, picks a cover, saves, opens it again,
// restores the file's info, and tries to swipe away unsaved changes. It logs PASS or FAIL for each step
// and `[harness] SHOT <name>` when the screen is worth a screenshot (build-sim.sh takes them).
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"

static NSString *const kURI = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
static int sg_failures;

#define CHECK(what, cond) do { BOOL ok = (cond); if (!ok) sg_failures++; NSLog(@"[harness] %@ %@", ok ? @"PASS" : @"FAIL", what); } while (0)

// What EditInfoMenu.x reads of the player: the track playing, and that the menu is the player's.
@interface SGHarnessTrack : NSObject
@property (nonatomic, strong) id URI;
@end
@implementation SGHarnessTrack
@end
@interface SGHarnessState : NSObject
@property (nonatomic, strong) SGHarnessTrack *track;
@end
@implementation SGHarnessState
@end

id SGPlayerState(void) {
    SGHarnessState *state = [SGHarnessState new];
    state.track = [SGHarnessTrack new];
    state.track.URI = [NSURL URLWithString:kURI];
    return state;
}
NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSURL.class] ? [(NSURL *)uri absoluteString] : uri;
}
BOOL SGPlayerMenuIsPlayers(UIViewController *menu) {
    return YES;
}

// Spotify's context menu sheet, as far as the hook goes: a table whose layout runs the hook.
@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@end
@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = @[@"Add to playlist", @"Go to queue", @"Share"][(NSUInteger)indexPath.row];
    return cell;
}
@end

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static void shot(NSString *name) {
    NSLog(@"[harness] SHOT %@", name);
}

static UIImage *redSquare(void) {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(300, 300)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemRedColor setFill];
        UIRectFill(CGRectMake(0, 0, 300, 300));
    }];
}

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SGHarnessApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyLocalFileEdits];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *player = [UIViewController new];
    player.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];
    [self runOn:player];
    return YES;
}

- (UIViewController *)editorOver:(UIViewController *)player {
    UINavigationController *navigation = (UINavigationController *)player.presentedViewController;
    if (![navigation isKindOfClass:UINavigationController.class]) return nil;
    UIViewController *editor = navigation.viewControllers.firstObject;
    return [NSStringFromClass(editor.class) isEqualToString:@"SGLocalFileEditor"] ? editor : nil;
}

- (void)runOn:(UIViewController *)player {
    BOOL large = [NSProcessInfo.processInfo.arguments containsObject:@"large"];
    __block UIViewController *menu;
    after(1, ^{
        menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:menu];
        navigation.navigationBarHidden = YES;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        [player presentViewController:navigation animated:YES completion:nil];
    });
    after(2.5, ^{
        UIView *footer = ((_TtC24ContextMenu_InternalImpl25ContextMenuViewController *)menu).table.tableFooterView;
        CHECK(@"the menu has the Edit info row", [NSStringFromClass(footer.class) isEqualToString:@"SGEditInfoRow"]);
        shot(@"menu");
        [(UIControl *)footer sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    after(4.5, ^{
        UIViewController *editor = [self editorOver:player];
        CHECK(@"the menu closed and the editor came up over the player", editor != nil);
        CHECK(@"the editor is dark", editor.navigationController.overrideUserInterfaceStyle == UIUserInterfaceStyleDark);
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        CHECK(@"the fields show the file's names", [fields[0].text isEqualToString:@"One More Time"] && [fields[1].text isEqualToString:@"Daft Punk"]);
        CHECK(@"Save is off with nothing changed", !editor.navigationItem.rightBarButtonItem.enabled && !editor.modalInPresentation);
        shot(large ? @"editor-large" : @"editor");
        if (large) after(2, ^{ exit(sg_failures ? 1 : 0); });
    });
    if (large) return;
    after(6, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        fields[0].text = @"One More Time (Edit)";
        [fields[0] sendActionsForControlEvents:UIControlEventEditingChanged];
        CHECK(@"a typed name turns Save on and holds a swipe", editor.navigationItem.rightBarButtonItem.enabled && editor.modalInPresentation);
        [editor performSelector:@selector(useCover:) withObject:redSquare()];
        CHECK(@"a picked cover is not stored before Save", !SGLocalFileEditFor(kURI));
    });
    after(7, ^{ shot(@"edited"); });
    after(8, ^{
        UIViewController *editor = [self editorOver:player];
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        NSDictionary *edit = SGLocalFileEditFor(kURI);
        CHECK(@"Save stores the name and the cover", [edit[@"title"] isEqualToString:@"One More Time (Edit)"] && SGLocalFileCoverPath(edit));
        CHECK(@"the rename gives a new lyrics key", [SGLocalFileLyricsKey(kURI) containsString:@"#"]);
    });
    after(9.5, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(11, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"opened again, it shows the edit and offers the restore", [fields[0].text isEqualToString:@"One More Time (Edit)"] && restore.userInteractionEnabled);
        shot(@"reopened");
    });
    after(12.5, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        [(UITableViewController *)editor tableView:[(UITableViewController *)editor tableView] didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
        CHECK(@"Restore puts the file's names back, unsaved", [fields[0].text isEqualToString:@"One More Time"] && SGLocalFileEditFor(kURI)
              && editor.navigationItem.rightBarButtonItem.enabled && !restore.userInteractionEnabled);
        UIBarButtonItem *save = editor.navigationItem.rightBarButtonItem;
        [[UIApplication sharedApplication] sendAction:save.action to:save.target from:save forEvent:nil];
        CHECK(@"saved, the edit and its cover are gone", !SGLocalFileEditFor(kURI) && [SGLocalFileLyricsKey(kURI) isEqualToString:kURI]);
    });
    after(14, ^{ SGLocalFilePresentEditor(player, kURI); });
    after(15.5, ^{
        UIViewController *editor = [self editorOver:player];
        NSArray<UITextField *> *fields = [editor valueForKey:@"fields"];
        UITableViewCell *restore = [editor valueForKey:@"restoreCell"];
        CHECK(@"with no edit, Restore is off", !restore.userInteractionEnabled);
        fields[2].text = @"Homework";
        [fields[2] sendActionsForControlEvents:UIControlEventEditingChanged];
        [(id<UIAdaptivePresentationControllerDelegate>)editor presentationControllerDidAttemptToDismiss:editor.navigationController.presentationController];
    });
    after(17, ^{
        UIViewController *editor = [self editorOver:player];
        UIAlertController *confirm = (UIAlertController *)editor.presentedViewController;
        CHECK(@"a swipe away with changes asks first", [confirm isKindOfClass:UIAlertController.class] && confirm.preferredStyle == UIAlertControllerStyleActionSheet
              && [confirm.actions.firstObject.title isEqualToString:@"Discard changes"]);
        shot(@"discard");
    });
    after(19, ^{
        NSLog(@"[harness] %@: %d failed", sg_failures ? @"FAIL" : @"PASS", sg_failures);
        exit(sg_failures ? 1 : 0);
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
