// AirPods gestures in the simulator: the real HeadGestures.x (through Logos), its settings page, its teaching
// sheet and the detector, with Spotify's player and collection platform stood in for, and
// CMHeadphoneMotionManager's start and stop taken over so the harness hands the handler made-up motion on the
// manager's own queue. The simulator has no headphones, so this proves the wiring (the switch, playing or not,
// each action's player call, Try it, the sheet's five recordings, Redo last, Cancel, Forget), not the motion.
// Steps run in order; each is asked again every quarter second until it says it is done, and fails after
// 20 s. Each check logs "ok" or "FAIL" and the last line says how many failed.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> ../build/sim/HeadGesturesSim.app
//     xcrun simctl launch --console-pty <udid> com.vitrine.headgesturessim
//
// With an argument it runs no checks and stops on a view to screenshot: `page` (the page, switch on, a nod
// learned and a try's answer), `sheet` (the sheet at 2 of 5, recording on and off), `done` (All set) or `live`
// (head motion in real time, nods and then shakes, for the ring).
#import <UIKit/UIKit.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/HeadGestures/HeadGestures.h"
#import "Shared/Player/PlayerState.h"

static int failures;
static void check(BOOL ok, NSString *what) {
    if (!ok) failures++;
    NSLog(@"[harness] %@ %@", ok ? @"ok  " : @"FAIL", what);
}

#pragma mark - Spotify stood in for

@interface FakeTrack : NSObject
@property (nonatomic, strong) id URI;
@end
@implementation FakeTrack
@end

@interface FakeOptions : NSObject
@property (nonatomic) BOOL shufflingContext, repeatingContext, repeatingTrack;
@end
@implementation FakeOptions
@end

@interface FakeState : NSObject
@property (nonatomic, strong) FakeTrack *track;
@property (nonatomic, strong) FakeOptions *options;
@property (nonatomic) BOOL isPlaying, isPaused;
@property (nonatomic) double position, positionAsOfTimestamp, duration;
@end
@implementation FakeState
@end

static FakeState *sg_state;
static __weak id<SGPlayerStateObserver> sg_observer;
static NSMutableArray<NSString *> *sg_calls;

NSString *SGURIString(id uri) {
    if ([uri isKindOfClass:NSURL.class]) return [uri absoluteString];
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) { sg_observer = observer; }
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)sg_state; }

// The player's commands the actions send, each written down as it comes.
@interface FakePlayer : NSObject
@end
@implementation FakePlayer
- (FakeState *)state { return sg_state; }
- (void)seekTo:(double)seconds { [sg_calls addObject:[NSString stringWithFormat:@"seek %.0f", seconds]]; }
- (id)pause:(id)options { [sg_calls addObject:@"pause"]; return nil; }
- (id)resume:(id)options { [sg_calls addObject:@"resume"]; return nil; }
- (id)skipToNextTrackWithOptions:(id)options { [sg_calls addObject:@"skip"]; return nil; }
- (id)skipToPreviousTrackWithOptions:(id)options { [sg_calls addObject:@"previous"]; return nil; }
- (id)setShufflingContext:(BOOL)on { [sg_calls addObject:[NSString stringWithFormat:@"shuffle %d", on]]; return nil; }
- (id)setRepeatingContext:(BOOL)on { [sg_calls addObject:[NSString stringWithFormat:@"repeat context %d", on]]; return nil; }
- (id)setRepeatingTrack:(BOOL)on { [sg_calls addObject:[NSString stringWithFormat:@"repeat track %d", on]]; return nil; }
@end
static FakePlayer *sg_player;
id SGKaraokePlayer(void) { return sg_player; }

// The class HeadGestures.x hooks, with the selectors Spotify's has.
@interface SPTCollectionPlatformImplementation : NSObject
@end
@implementation SPTCollectionPlatformImplementation
- (id)stateProvider { return nil; }
- (void)addURL:(NSURL *)url showUIConfirmation:(BOOL)show completion:(void (^)(void))completion {
    [sg_calls addObject:[NSString stringWithFormat:@"add %@ %@", url.absoluteString, show ? @"toast" : @"quiet"]];
    completion();
}
@end

#pragma mark - the headphones stood in for

@interface FakeAttitude : NSObject
@property (nonatomic) double pitch, yaw;
@end
@implementation FakeAttitude
@end

@interface FakeMotion : NSObject
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic, strong) FakeAttitude *attitude;
@end
@implementation FakeMotion
@end

static CMHeadphoneDeviceMotionHandler sg_handler;
static NSOperationQueue *sg_motionQueue;
static BOOL sg_active;
static int sg_starts, sg_stops;
static double sg_clock = 100;

static void fakeStart(id self, SEL _cmd, NSOperationQueue *queue, CMHeadphoneDeviceMotionHandler handler) {
    sg_handler = handler;
    sg_motionQueue = queue;
    sg_active = YES;
    sg_starts++;
}
static void fakeStop(id self, SEL _cmd) {
    sg_active = NO;
    sg_stops++;
}
static BOOL fakeActive(id self, SEL _cmd) { return sg_active; }
static BOOL fakeAvailable(id self, SEL _cmd) { return YES; }
static CMAuthorizationStatus fakeAuthorized(id self, SEL _cmd) { return CMAuthorizationStatusAuthorized; }

static void takeOverMotion(void) {
    Class manager = CMHeadphoneMotionManager.class;
    method_setImplementation(class_getInstanceMethod(manager, @selector(startDeviceMotionUpdatesToQueue:withHandler:)), (IMP)fakeStart);
    method_setImplementation(class_getInstanceMethod(manager, @selector(stopDeviceMotionUpdates)), (IMP)fakeStop);
    method_setImplementation(class_getInstanceMethod(manager, @selector(isDeviceMotionActive)), (IMP)fakeActive);
    method_setImplementation(class_getInstanceMethod(manager, @selector(isDeviceMotionAvailable)), (IMP)fakeAvailable);
    // Asked already: the page's first-time start for the permission prompt stays out of the counts.
    method_setImplementation(class_getClassMethod(manager, @selector(authorizationStatus)), (IMP)fakeAuthorized);
}

// 25 attitudes a second, as AirPods send them, onto the manager's queue while it listens.
static void send(double pitch, double yaw) {
    sg_clock += 1.0 / 25;
    if (!sg_active) return;
    FakeMotion *motion = [FakeMotion new];
    motion.timestamp = sg_clock;
    motion.attitude = [FakeAttitude new];
    motion.attitude.pitch = pitch;
    motion.attitude.yaw = yaw;
    CMHeadphoneDeviceMotionHandler handler = sg_handler;
    [sg_motionQueue addOperationWithBlock:^{ handler((CMDeviceMotion *)motion, nil); }];
}
static void hold(double seconds) {
    for (int n = (int)(seconds * 25); n > 0; n--) send(0.1, 3.0);
}
static void nods(int count, double depth, double length) {
    for (int k = 0; k < count; k++)
        for (int n = 0, steps = (int)(length * 25); n < steps; n++) {
            double s = sin(M_PI * n / steps);
            send(0.1 - depth * s * s, 3.0);
        }
    hold(1);
}
static void doubleNod(double depth, double length) {
    nods(2, depth, length);
    hold(1);
}
static void shake(double width, double hertz) {
    for (int n = 0, steps = (int)(4 / (2 * hertz) * 25); n < steps; n++) send(0.1, remainder(3.0 + width * sin(2 * M_PI * hertz * n / 25), 2 * M_PI));
    hold(2);
}

#pragma mark - the run

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

typedef BOOL (^Step)(void);   // YES once done

static NSInteger sg_nodBefore;

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) SPTCollectionPlatformImplementation *platform;
@property (nonatomic, copy) NSArray<Step> *steps;
@property (nonatomic) NSUInteger current;
@property (nonatomic, strong) NSDate *stepStarted;
// What the sheet's recordings are fed, one a recording, in order; the last is fed on and on.
@property (nonatomic, strong) NSMutableArray<void (^)(void)> *feeds;
@property (nonatomic) BOOL fedThisRecording;
@end

@implementation AppDelegate

- (SGModPage *)page {
    return (SGModPage *)self.nav.viewControllers.firstObject;
}

- (UITableView *)table {
    return self.page.tableView;
}

- (SGModRow *)rowAt:(NSInteger)row section:(NSInteger)section {
    return [self.page performSelector:@selector(rowAt:) withObject:[NSIndexPath indexPathForRow:row inSection:section]];
}

- (void)tapRow:(NSInteger)row section:(NSInteger)section {
    [self.table.delegate tableView:self.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}

- (void)setPlaying:(BOOL)playing {
    sg_state.isPlaying = YES;   // Spotify's stays on while a loaded track is paused
    sg_state.isPaused = !playing;
    [sg_observer playerStateDidChange:(SPTPlayerState *)sg_state];
}

- (NSString *)alertTitle {
    UIViewController *shown = self.nav.presentedViewController;
    return [shown isKindOfClass:UIAlertController.class] ? shown.title : nil;
}

// The alert's button of that style, pressed: the alert goes and its handler runs.
- (void)press:(UIAlertActionStyle)style {
    UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
    for (UIAlertAction *action in alert.actions) {
        if (action.style != style) continue;
        void (^handler)(UIAlertAction *) = [action valueForKey:@"handler"];
        [self.nav dismissViewControllerAnimated:NO completion:^{ if (handler) handler(action); }];
    }
}

// The teaching sheet's controller, when it is up.
- (UIViewController *)teach {
    UINavigationController *sheet = (UINavigationController *)self.nav.presentedViewController;
    return [sheet isKindOfClass:UINavigationController.class] ? sheet.viewControllers.firstObject : nil;
}

- (id)teachValue:(NSString *)key {
    return [self.teach valueForKey:key];
}

- (NSString *)teachCount {
    return [[self teachValue:@"dial"] valueForKey:@"accessibilityValue"];
}

- (NSString *)teachText:(NSString *)key {
    return ((UILabel *)[self teachValue:key]).text;
}

// The ring's dot and its center, in the ring's own coordinates, and one tick's light: 0 is the top, 15 the
// right, 30 the bottom, 45 the left.
- (CGPoint)ringDot {
    return ((CALayer *)[[self teachValue:@"dial"] valueForKey:@"dot"]).position;
}

- (CGPoint)ringCentre {
    UIView *ring = [self teachValue:@"dial"];
    return CGPointMake(CGRectGetMidX(ring.bounds), CGRectGetMidY(ring.bounds));
}

- (float)tick:(NSInteger)index {
    return ((NSArray<CALayer *> *)[[self teachValue:@"dial"] valueForKey:@"ticks"])[index].opacity;
}

- (void)teachButton:(NSString *)key {
    [(UIButton *)[self teachValue:key] sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}

// One gesture through the page's own pull-down, then made: the calls it sends to the player.
- (NSArray<Step> *)action:(SGHeadAction)action makes:(NSArray<NSString *> *)want named:(NSString *)name {
    return @[
        ^BOOL {
            [sg_calls removeAllObjects];
            [self rowAt:0 section:1].chosen(action);
            doubleNod(0.35, 0.4);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:want], [NSString stringWithFormat:@"double nod set to %@ sends [%@]: %@", name, [want componentsJoinedByString:@", "],[sg_calls componentsJoinedByString:@", "]]);
            return YES;
        },
    ];
}

// Waits until `done` says yes; the harness fails it after 20 s.
static Step until(BOOL (^done)(void)) {
    return done;
}

static Step waitFor(double seconds) {
    __block NSDate *end;
    return ^BOOL {
        if (!end) end = [NSDate dateWithTimeIntervalSinceNow:seconds];
        return end.timeIntervalSinceNow <= 0;
    };
}

- (NSArray<Step> *)checks {
    NSMutableArray<Step> *steps = [NSMutableArray array];
    [steps addObjectsFromArray:@[
        ^BOOL {
            check(sg_starts == 0, @"switch off, playing: not listening");
            UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            NSMutableArray<UISwitch *> *switches = [NSMutableArray array];
            findViews(cell, UISwitch.class, switches);
            [switches.firstObject setOn:YES animated:YES];
            [switches.firstObject sendActionsForControlEvents:UIControlEventValueChanged];
            return YES;
        },
        waitFor(1),
        ^BOOL {
            check(sg_active, @"switch on, playing: listening");
            check([self.table numberOfRowsInSection:2] == 3, @"nothing learned: no Forget row");
            check([[self rowAt:0 section:1].value() isEqualToString:@"Like"], @"a double nod likes until changed");
            check([[self rowAt:1 section:1].value() isEqualToString:@"Next track"], @"a shake skips until changed");
            NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
            findViews([self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]], UIButton.class, buttons);
            check(buttons.firstObject.menu.children.count == SGHeadActionCount, [NSString stringWithFormat:@"the pull-down offers %ld actions", (long)buttons.firstObject.menu.children.count]);
            doubleNod(0.35, 0.4);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:@[@"add spotify:track:4uLU6hMCjMI75M1A2tKUQC toast"]],
                  [NSString stringWithFormat:@"a double nod adds the track, calls %@", [sg_calls componentsJoinedByString:@", "]]);
            [sg_calls removeAllObjects];
            shake(0.21, 2.5);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:@[@"skip"]], [NSString stringWithFormat:@"a shake skips, calls %@", [sg_calls componentsJoinedByString:@", "]]);
            [sg_calls removeAllObjects];
            sg_state.track.URI = [NSURL URLWithString:@"spotify:episode:512ojhOuo1ktJprKbVcKyQ"];
            doubleNod(0.35, 0.4);
            return YES;
        },
        ^BOOL {
            check(sg_calls.count == 0, [NSString stringWithFormat:@"a double nod on an episode saves nothing, calls %@", [sg_calls componentsJoinedByString:@", "]]);
            sg_state.track.URI = @"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
            sg_state.position = sg_state.positionAsOfTimestamp = 100;
            sg_state.duration = 110;
            return YES;
        },
    ]];
    // Every action, through the nod's pull-down.
    [steps addObjectsFromArray:[self action:SGHeadActionNothing makes:@[] named:@"Nothing"]];
    [steps addObjectsFromArray:[self action:SGHeadActionSeekBack makes:@[@"seek 85"] named:@"Back 15 seconds"]];
    [steps addObjectsFromArray:[self action:SGHeadActionSeekForward makes:@[@"seek 110"] named:@"Forward 15 seconds, at most to the end"]];
    [steps addObjectsFromArray:[self action:SGHeadActionPlayPause makes:@[@"pause"] named:@"Play or pause, playing"]];
    [steps addObjectsFromArray:[self action:SGHeadActionNext makes:@[@"skip"] named:@"Next track"]];
    [steps addObjectsFromArray:[self action:SGHeadActionPrevious makes:@[@"previous"] named:@"Previous track"]];
    [steps addObjectsFromArray:[self action:SGHeadActionShuffle makes:@[@"shuffle 1"] named:@"Shuffle, off"]];
    [steps addObject:^BOOL { sg_state.options.shufflingContext = YES; return YES; }];
    [steps addObjectsFromArray:[self action:SGHeadActionShuffle makes:@[@"shuffle 0"] named:@"Shuffle, on"]];
    [steps addObjectsFromArray:[self action:SGHeadActionRepeat makes:@[@"repeat context 1"] named:@"Repeat, off"]];
    [steps addObject:^BOOL { sg_state.options.repeatingContext = YES; return YES; }];
    [steps addObjectsFromArray:[self action:SGHeadActionRepeat makes:@[@"repeat track 1"] named:@"Repeat, the context"]];
    [steps addObject:^BOOL { sg_state.options.repeatingTrack = YES; return YES; }];
    [steps addObjectsFromArray:[self action:SGHeadActionRepeat makes:@[@"repeat track 0", @"repeat context 0"] named:@"Repeat, the track"]];
    [steps addObjectsFromArray:@[
        ^BOOL {
            // Play or pause listens with the song paused, so the nod can resume it.
            [self rowAt:0 section:1].chosen(SGHeadActionPlayPause);
            [self setPlaying:NO];
            check(sg_active, @"paused, a gesture set to Play or pause: listening");
            sg_state.positionAsOfTimestamp = 40;
            sg_state.position = 1000;   // a paused state's position runs on; the seek must not read it
            [sg_calls removeAllObjects];
            doubleNod(0.35, 0.4);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:@[@"resume"]], [NSString stringWithFormat:@"paused, a double nod resumes: %@", [sg_calls componentsJoinedByString:@", "]]);
            [self rowAt:0 section:1].chosen(SGHeadActionSeekBack);
            check(!sg_active, @"paused, nothing set to Play or pause: stopped");
            [self setPlaying:YES];
            [sg_calls removeAllObjects];
            sg_state.position = 30;
            doubleNod(0.35, 0.4);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:@[@"seek 15"]], [NSString stringWithFormat:@"playing at 30 s, back 15: %@", [sg_calls componentsJoinedByString:@", "]]);
            [self rowAt:0 section:1].chosen(SGHeadActionLike);
            [self rowAt:1 section:1].chosen(SGHeadActionNothing);
            [sg_calls removeAllObjects];
            shake(0.21, 2.5);
            return YES;
        },
        ^BOOL {
            check(sg_calls.count == 0, [NSString stringWithFormat:@"a shake set to Nothing sends nothing: %@", [sg_calls componentsJoinedByString:@", "]]);
            [self rowAt:1 section:1].chosen(SGHeadActionNext);
            check([[self rowAt:1 section:1].value() isEqualToString:@"Next track"], @"the shake's pull-down reads Next track again");
            // Try it, while the switch is on and a song plays: it says what it picked up and does nothing.
            [self tapRow:2 section:2];
            check([[self rowAt:2 section:2].value() isEqualToString:@"Listening…"], [NSString stringWithFormat:@"Try it listens: %@", [self rowAt:2 section:2].value()]);
            doubleNod(0.35, 0.4);
            return YES;
        },
        until(^BOOL { return ![[self rowAt:2 section:2].value() isEqualToString:@"Listening…"]; }),
        ^BOOL {
            check([[self rowAt:2 section:2].value() isEqualToString:@"Double nod"], [NSString stringWithFormat:@"Try it picked up %@", [self rowAt:2 section:2].value()]);
            check(sg_calls.count == 0, [NSString stringWithFormat:@"and liked nothing: %@", [sg_calls componentsJoinedByString:@", "]]);
            [self tapRow:2 section:2];
            shake(0.21, 2.5);
            return YES;
        },
        until(^BOOL { return ![[self rowAt:2 section:2].value() isEqualToString:@"Listening…"]; }),
        ^BOOL {
            check([[self rowAt:2 section:2].value() isEqualToString:@"Shake"], [NSString stringWithFormat:@"Try it picked up %@", [self rowAt:2 section:2].value()]);
            check(sg_calls.count == 0, [NSString stringWithFormat:@"and skipped nothing: %@", [sg_calls componentsJoinedByString:@", "]]);
            [self tapRow:2 section:2];
            hold(2);
            return YES;
        },
        until(^BOOL { return ![[self rowAt:2 section:2].value() isEqualToString:@"Listening…"]; }),
        ^BOOL {
            check([[self rowAt:2 section:2].value() isEqualToString:@"Nothing"], [NSString stringWithFormat:@"a still head: %@", [self rowAt:2 section:2].value()]);
            [self setPlaying:NO];
            [self tapRow:2 section:2];
            return YES;
        },
        until(^BOOL { return ![[self rowAt:2 section:2].value() isEqualToString:@"Listening…"]; }),
        ^BOOL {
            check([[self rowAt:2 section:2].value() isEqualToString:@"No motion"], [NSString stringWithFormat:@"no headphones sending: %@", [self rowAt:2 section:2].value()]);
            check(!sg_active, @"the try over, paused: stopped");
            // The teaching sheet, with a song playing, to show no gesture does anything meanwhile.
            [self setPlaying:YES];
            [sg_calls removeAllObjects];
            [self tapRow:0 section:2];
            return YES;
        },
        until(^BOOL { return self.teach.viewIfLoaded.window != nil; }),
        waitFor(0.5),
        // The ring, live: the head held still, then down as in a nod's dip.
        ^BOOL {
            hold(1);
            for (int n = 0; n < 5; n++) send(0.1 - 0.25, 3.0);
            return YES;
        },
        waitFor(0.4),
        ^BOOL {
            CGPoint dot = [self ringDot], centre = [self ringCentre];
            check(dot.y > centre.y + 30 && fabs(dot.x - centre.x) < 4, [NSString stringWithFormat:@"a nod's dip takes the dot down: %.0f, %.0f from the center", dot.x - centre.x, dot.y - centre.y]);
            check([self tick:30] > 0.4 && [self tick:0] == 0 && [self tick:15] == 0,
                  [NSString stringWithFormat:@"the ticks below light, not above or beside: below %.2f, above %.2f, right %.2f", [self tick:30], [self tick:0], [self tick:15]]);
            hold(1.5);
            return YES;
        },
        waitFor(1.5),
        ^BOOL {
            CGPoint dot = [self ringDot], centre = [self ringCentre];
            check(hypot(dot.x - centre.x, dot.y - centre.y) < 12, [NSString stringWithFormat:@"still again: the dot comes back, %.0f, %.0f", dot.x - centre.x, dot.y - centre.y]);
            check([self tick:30] < 0.05, [NSString stringWithFormat:@"and the ticks fade back: below %.2f", [self tick:30]]);
            // A shake's swing to the left: yaw rising.
            for (int n = 0; n < 5; n++) send(0.1, 3.0 + 0.18);
            return YES;
        },
        waitFor(0.4),
        ^BOOL {
            CGPoint dot = [self ringDot], centre = [self ringCentre];
            check(dot.x < centre.x - 30, [NSString stringWithFormat:@"a swing left takes the dot left: %.0f, %.0f", dot.x - centre.x, dot.y - centre.y]);
            check([self tick:45] > 0.4 && [self tick:15] == 0, [NSString stringWithFormat:@"the ticks on the left light: left %.2f, right %.2f", [self tick:45], [self tick:15]]);
            hold(1.5);
            return YES;
        },
        waitFor(1.5),
        ^BOOL {
            check([[self teachText:@"heading"] isEqualToString:@"Double nod"], [NSString stringWithFormat:@"the sheet asks for nods first: %@", [self teachText:@"heading"]]);
            check([[self teachCount] isEqualToString:@"0 of 5"], [NSString stringWithFormat:@"none yet: %@", [self teachCount]]);
            self.feeds = [@[
                ^{ doubleNod(0.35, 0.4); },
                ^{ doubleNod(0.30, 0.45); },
                ^{ nods(1, 0.35, 0.4); },   // one nod: not counted
                ^{ doubleNod(0.28, 0.45); },
                ^{ doubleNod(0.32, 0.4); },
                ^{ doubleNod(0.26, 0.45); },
                ^{ doubleNod(0.30, 0.4); },
                ^{ shake(0.21, 2.5); },
                ^{ shake(0.18, 2.2); },
                ^{ shake(0.15, 2.0); },
                ^{ shake(0.2, 2.4); },
                ^{ shake(0.17, 2.2); },
            ] mutableCopy];
            [self teachButton:@"primaryButton"];
            return YES;
        },
        until(^BOOL { return [[self teachText:@"line"] hasPrefix:@"That didn't read"]; }),
        ^BOOL {
            check([[self teachCount] isEqualToString:@"2 of 5"], [NSString stringWithFormat:@"one nod is not counted: %@", [self teachCount]]);
            return YES;
        },
        until(^BOOL { return [[self teachCount] isEqualToString:@"3 of 5"]; }),
        ^BOOL {
            [self teachButton:@"redoButton"];
            check([[self teachCount] isEqualToString:@"2 of 5"], [NSString stringWithFormat:@"Redo last takes one off: %@", [self teachCount]]);
            check(SGInt(SGKeyHeadNod, 0) == 0, @"nothing stored before five");
            return YES;
        },
        until(^BOOL { return [[self teachText:@"heading"] isEqualToString:@"Shake"]; }),
        ^BOOL {
            sg_nodBefore = SGInt(SGKeyHeadNod, 0);
            check(sg_nodBefore > 0, [NSString stringWithFormat:@"five nods in, the nod is stored before the shakes: %ld", (long)sg_nodBefore]);
            return YES;
        },
        until(^BOOL { return [[self teachText:@"heading"] isEqualToString:@"All set"]; }),
        ^BOOL {
            check(SGInt(SGKeyHeadShake, 0) > 0, [NSString stringWithFormat:@"five shakes in, the shake is stored: %ld", (long)SGInt(SGKeyHeadShake, 0)]);
            check(sg_calls.count == 0, [NSString stringWithFormat:@"with a song playing, no gesture did anything while it taught: %@", [sg_calls componentsJoinedByString:@", "]]);
            check(self.teach.navigationItem.leftBarButtonItem == nil, @"All set: no Cancel, Done instead");
            self.feeds = nil;
            [self teachButton:@"primaryButton"];
            return YES;
        },
        until(^BOOL { return self.nav.presentedViewController == nil; }),
        waitFor(0.6),
        ^BOOL {
            check([self.table numberOfRowsInSection:2] == 4, @"something learned: the Forget row shows");
            check([[self rowAt:0 section:2].value() isEqualToString:@"Learned"], [NSString stringWithFormat:@"Teach reads %@", [self rowAt:0 section:2].value()]);
            check(sg_active, @"the sheet gone, playing: listening for the gestures again");
            // The smallest of the five nods it was taught, at what it learned.
            doubleNod(0.26, 0.45);
            return YES;
        },
        ^BOOL {
            check([sg_calls isEqualToArray:@[@"add spotify:track:4uLU6hMCjMI75M1A2tKUQC toast"]],
                  [NSString stringWithFormat:@"the smallest taught nod likes the song: %@", [sg_calls componentsJoinedByString:@", "]]);
            [sg_calls removeAllObjects];
            // Teaching again, canceled after one nod: the stored nod stays, and the motion stops.
            [self setPlaying:NO];
            self.feeds = [@[^{ doubleNod(0.2, 0.45); }, ^{}] mutableCopy];
            [self tapRow:0 section:2];
            return YES;
        },
        until(^BOOL { return self.teach.viewIfLoaded.window != nil; }),
        waitFor(0.5),
        ^BOOL {
            check(sg_active, @"paused, the sheet up: it holds the motion");
            [self teachButton:@"primaryButton"];
            return YES;
        },
        until(^BOOL { return [[self teachCount] isEqualToString:@"1 of 5"]; }),
        ^BOOL {
            UIBarButtonItem *cancel = self.teach.navigationItem.leftBarButtonItem;
            [UIApplication.sharedApplication sendAction:cancel.action to:cancel.target from:cancel forEvent:nil];
            return YES;
        },
        until(^BOOL { return self.nav.presentedViewController == nil; }),
        waitFor(0.6),
        ^BOOL {
            self.feeds = nil;
            check(SGInt(SGKeyHeadNod, 0) == sg_nodBefore, [NSString stringWithFormat:@"Cancel keeps the nod %ld: %ld", (long)sg_nodBefore, (long)SGInt(SGKeyHeadNod, 0)]);
            check(!sg_active, @"canceled, paused: stopped");
            [self tapRow:3 section:2];
            return YES;
        },
        waitFor(0.5),
        ^BOOL {
            check([[self alertTitle] isEqualToString:@"Forget your nod and shake?"], [NSString stringWithFormat:@"Forget asks first: %@", [self alertTitle]]);
            [self press:UIAlertActionStyleDestructive];
            return YES;
        },
        waitFor(0.6),
        ^BOOL {
            check(SGInt(SGKeyHeadNod, 0) == 0 && SGInt(SGKeyHeadShake, 0) == 0, @"Forget clears both");
            check([self.table numberOfRowsInSection:2] == 3, @"nothing learned again: the Forget row goes");
            NSLog(@"[harness] %@", failures ? [NSString stringWithFormat:@"%d failed", failures] : @"all passed");
            return YES;
        },
    ]];
    return steps;
}

// Views to screenshot, no checks.
- (NSArray<Step> *)shot:(NSString *)name {
    Step switchOn = ^BOOL {
        SGSetEnabled(SGKeyHeadGestures, YES);
        SGHeadGesturesSettingsChanged();
        [self.table reloadData];
        return YES;
    };
    if ([name isEqualToString:@"page"]) return @[switchOn, ^BOOL {
        SGSetInt(SGKeyHeadNod, 1200);
        [self.page refreshVisibility];
        [self tapRow:2 section:2];
        doubleNod(0.35, 0.4);
        return YES;
    }];
    if ([name isEqualToString:@"live"]) return @[switchOn, ^BOOL {
        [self tapRow:0 section:2];
        return YES;
    }, waitFor(1), ^BOOL {
        // Head motion in real time, 25 samples a second: double nods while the sheet asks for nods, then shakes.
        __block double t = 0;
        [NSTimer scheduledTimerWithTimeInterval:0.04 repeats:YES block:^(NSTimer *timer) {
            t += 0.04;
            BOOL nodding = [[self teachText:@"heading"] isEqualToString:@"Double nod"];
            double phase = fmod(t, 1.9);
            if (nodding) {
                double s = phase < 0.9 ? sin(M_PI * phase / 0.45) : 0;
                send(0.1 - 0.3 * s * s, 3.0);
            } else {
                send(0.1, remainder(3.0 + (phase < 0.9 ? 0.2 * sin(2 * M_PI * 2.2 * phase) : 0), 2 * M_PI));
            }
        }];
        [self teachButton:@"primaryButton"];
        return YES;
    }];
    NSMutableArray<void (^)(void)> *feeds = [@[^{ doubleNod(0.35, 0.4); }, ^{ doubleNod(0.3, 0.45); }, ^{ hold(2); }] mutableCopy];
    if ([name isEqualToString:@"done"]) {
        [feeds removeLastObject];
        for (int i = 0; i < 3; i++) [feeds addObject:^{ doubleNod(0.32, 0.4); }];
        for (int i = 0; i < 5; i++) [feeds addObject:^{ shake(0.2, 2.4); }];
    }
    return @[switchOn, ^BOOL {
        [self tapRow:0 section:2];
        return YES;
    }, waitFor(1), ^BOOL {
        self.feeds = feeds;
        [self teachButton:@"primaryButton"];
        return YES;
    }];
}

// Feeds the sheet's recording, once each, whenever one is open.
- (void)feed {
    if (!self.feeds.count) return;
    BOOL recording = [[self teachValue:@"listening"] boolValue];
    if (!recording) {
        self.fedThisRecording = NO;
        return;
    }
    if (self.fedThisRecording) return;
    self.fedThisRecording = YES;
    void (^next)(void) = self.feeds.firstObject;
    if (self.feeds.count > 1) [self.feeds removeObjectAtIndex:0];
    // A moment in, as someone moves after the tone.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), next);
}

- (void)tick {
    [self feed];
    if (self.current >= self.steps.count) return;
    if (!self.stepStarted) self.stepStarted = [NSDate date];
    BOOL done = self.steps[self.current]();
    if (!done && -self.stepStarted.timeIntervalSinceNow > 20) {
        check(NO, [NSString stringWithFormat:@"step %lu timed out", (unsigned long)self.current]);
        done = YES;
    }
    if (!done) return;
    self.current++;
    self.stepStarted = nil;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation.allKeys)
        if ([key hasPrefix:@"spotifyglass.headgestures"]) [store removeObjectForKey:key];
    takeOverMotion();
    sg_calls = [NSMutableArray array];
    sg_player = [FakePlayer new];
    sg_state = [FakeState new];
    sg_state.track = [FakeTrack new];
    sg_state.options = [FakeOptions new];
    sg_state.track.URI = @"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
    // Spotify reaching for its platform's state provider is what the hook keeps it from.
    self.platform = [SPTCollectionPlatformImplementation new];
    [self.platform stateProvider];
    [self setPlaying:YES];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGHeadGesturesSettingsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];

    NSString *shot = NSProcessInfo.processInfo.arguments.count > 1 ? NSProcessInfo.processInfo.arguments[1] : nil;
    self.steps = [@[waitFor(1.5)] arrayByAddingObjectsFromArray:shot ? [self shot:shot] : [self checks]];
    [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
