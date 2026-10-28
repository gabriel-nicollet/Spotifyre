// The Sing page (Shared/Sing/SingSettings.m) and the Spatial voice page under it, with its preview
// (SGSpatialPreview.m), on the real Settings/ framework; stubs.m stands in for Sing's state and plays the head's
// motion. The launch line sets things up and then plays actions, one every 0.7 s from 1 s in; screenshot after.
//
//     ./build.sh && xcrun simctl install <udid> build/SpatialPageHarness.app
//     xcrun simctl launch <udid> com.vojta.spatialpageharness [setup...] [action...]
//
// Setup: keep (the stored Sing keys stay; otherwise they are cleared first), on (spatial voice on), allowed or
// denied (what Motion & Fitness answers; unasked otherwise, so the preview never listens), head=sweep (the head
// turning 45 degrees each way every 6 s), head=<degrees> (still, then turned that far left at 2 s and held), width=<points>
// (the window that narrow, centered), slow (animations at a tenth of their speed).
// Actions: spatial (the Spatial voice row tapped), toggle=<section>.<row> (that row's switch flipped the way a tap
// does), pop, dump (the rows, the header's height and what VoiceOver reads on the preview, to the log), lag (how far
// the disc on screen trails the head over the next 3 s, to the log), lines (how the Sing card's lines move over the
// next 5 s: the frames where they jump back or ahead, to the log).
// The Sing page's card: state=<SGSingState number> (Sing on for the states that are on), level=<0 to 2>, playing,
// paused=<MB> (no model, a stopped download that kept that much), title=<text> (the track's title, _ for a space), none (no track
// and none ever played), last (no track, Holocene the last one played), chunk=<ms> (the engine's tenths moving on in
// renders this long), busy (the main thread held up to 30 ms at a time).
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Sing/Sing.h"

extern CMAuthorizationStatus sg_motionAllowed;
extern SGSingState sg_singState;
extern long long sg_pausedBytes;
extern BOOL sg_playing;
extern double (^sg_headYaw)(double seconds);
extern CFTimeInterval sg_headStarted;
extern double sg_renderChunk;
extern NSString *sg_trackTitle;
extern long sg_newestTenth;
extern BOOL sg_noTrack;
extern double sg_sentYaw;

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

@interface LagProbe : NSObject
@property (nonatomic, weak) UIView *preview;
@end

@implementation LagProbe {
    double _behind, _off, _most, _speed;
    int _frames;
}
// The voice's true angle now is the one in the last motion the preview heard, moved on by as far as the head has
// turned since that motion was sent (the preview's ivars, read through KVC: _heard, or _angle before it had one).
// The drawn one is the disc layer's on screen. Behind counts the gap the way the head is turning.
- (void)tick:(CADisplayLink *)link {
    UIView *preview = self.preview;
    BOOL hears = class_getInstanceVariable(preview.class, "_heard") != NULL;
    double heard = [[preview valueForKey:hears ? @"heard" : @"angle"] doubleValue];
    CALayer *field = [preview valueForKey:@"field"];
    NSNumber *shown = [field.presentationLayer valueForKeyPath:@"transform.rotation.z"];
    double t = CACurrentMediaTime() - sg_headStarted;
    if (!shown || !sg_headStarted) return;
    double truth = heard + sg_headYaw(t) - sg_sentYaw, turning = (sg_headYaw(t + 0.001) - sg_headYaw(t)) / 0.001;
    double gap = remainder(truth - shown.doubleValue, 2 * M_PI) * 180 / M_PI;
    _behind += turning >= 0 ? gap : -gap;
    _off += fabs(gap);
    _most = fmax(_most, fabs(gap));
    _speed += fabs(turning) * 180 / M_PI;
    _frames++;
}
- (void)report {
    double behind = _frames ? _behind / _frames : 0, off = _frames ? _off / _frames : 0, speed = _frames ? _speed / _frames : 0;
    NSLog(@"[harness] lag over %d frames: %.2f deg behind the head on average (%.2f off either way, %.2f at most), the head at "
          @"%.0f deg/s, so %.0f ms behind", _frames, behind, off, _most, speed, speed > 0 ? 1000 * behind / speed : 0);
}
@end

// The Sing card's lines read every frame: where one tenth of the song is on screen (its place in the levels drawn,
// from the newest tenth the stub handed out at the card's last read, and the line's slide on screen), and how it
// moved from the frame before: back to the right, or on by more than twice the pace, is a jump.
@interface LinesProbe : NSObject
@property (nonatomic, weak) UIView *card;
@end

@implementation LinesProbe {
    long _tenth;
    double _lastX, _lastTime, _travelled, _time;
    int _frames, _back, _ahead, _resting;
}
- (void)tick:(CADisplayLink *)link {
    // What the card drew in this turn of the run loop, committed, so the slide on screen goes with the levels read.
    [CATransaction flush];
    UIView *graph = [self.card valueForKey:@"graph"];
    CALayer *line = [self.card valueForKey:@"vocals"];
    NSNumber *slide = [line.presentationLayer valueForKeyPath:@"transform.translation.x"];
    CGFloat step = graph.bounds.size.width / 47;
    if (!_tenth) _tenth = sg_newestTenth - 10;
    double x = (_tenth - sg_newestTenth + 48) * step + slide.doubleValue, now = CACurrentMediaTime();
    if (_lastTime > 0) {
        double dx = x - _lastX, pace = step * (now - _lastTime) / 0.1;
        if (dx > 0.5) _back++;
        else if (-dx > 2 * pace + 0.5) _ahead++;
        else if (fabs(dx) < 0.05) _resting++;
        _travelled -= dx;
        _time += now - _lastTime;
        _frames++;
    }
    _lastX = x;
    _lastTime = now;
}
- (void)report {
    CGFloat step = ((UIView *)[self.card valueForKey:@"graph"]).bounds.size.width / 47;
    NSLog(@"[harness] lines over %d frames: %d jumped back, %d jumped ahead, %d resting, at %.2f tenths a tenth of a second",
          _frames, _back, _ahead, _resting, _time > 0 ? _travelled / step / (_time / 0.1) : 0);
}
@end

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
            if ([key hasPrefix:@"spotifyglass.sing"]) [store removeObjectForKey:key];
        }
    }
    CGFloat width = 0;
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"on"]) SGSetEnabled(SGKeySingSpatial, YES);
        else if ([arg isEqualToString:@"allowed"]) sg_motionAllowed = CMAuthorizationStatusAuthorized;
        else if ([arg isEqualToString:@"denied"]) sg_motionAllowed = CMAuthorizationStatusDenied;
        else if ([arg isEqualToString:@"head=sweep"]) sg_headYaw = ^double(double t) { return M_PI_4 * sin(2 * M_PI * t / 6); };
        else if ([arg hasPrefix:@"head="]) {
            double turn = [arg substringFromIndex:5].doubleValue * M_PI / 180;
            sg_headYaw = ^double(double t) {
                double s = fmin(1, fmax(0, (t - 2) / 0.6));
                return turn * s * s * (3 - 2 * s);
            };
        } else if ([arg hasPrefix:@"width="]) width = [arg substringFromIndex:6].doubleValue;
        else if ([arg hasPrefix:@"state="]) {
            sg_singState = (SGSingState)[arg substringFromIndex:6].integerValue;
            SGSetEnabled(SGKeySing, sg_singState > SGSingStateOff);
        } else if ([arg hasPrefix:@"level="]) SGSetSingLevel([arg substringFromIndex:6].floatValue);
        else if ([arg hasPrefix:@"paused="]) {
            sg_singState = SGSingStateNoModel;
            sg_pausedBytes = [arg substringFromIndex:7].longLongValue * 1000 * 1000;
        } else if ([arg isEqualToString:@"playing"]) sg_playing = YES;
        else if ([arg hasPrefix:@"chunk="]) sg_renderChunk = [arg substringFromIndex:6].doubleValue / 1000;
        else if ([arg hasPrefix:@"title="]) sg_trackTitle = [[arg substringFromIndex:6] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        else if ([arg isEqualToString:@"none"] || [arg isEqualToString:@"last"]) {
            sg_noTrack = YES;
            if ([arg isEqualToString:@"none"]) [store removeObjectForKey:SGKeyLastTrack];
            else [store setObject:@{@"uri": @"spotify:track:last", @"title": @"Holocene", @"artist": @"Bon Iver"} forKey:SGKeyLastTrack];
        }
        else if (![@[@"keep", @"slow", @"on", @"busy"] containsObject:arg]) [actions addObject:arg];
    }
    // busy: the main thread held up to 30 ms at a time, about every 50 ms, as Spotify's own work holds it.
    if ([args containsObject:@"busy"]) {
        NSTimer *busy = [NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { usleep(arc4random_uniform(30000)); }];
        [NSRunLoop.mainRunLoop addTimer:busy forMode:NSRunLoopCommonModes];
    }

    CGRect screen = UIScreen.mainScreen.bounds;
    self.window = [[UIWindow alloc] initWithFrame:width > 0 ? CGRectMake((screen.size.width - width) / 2, 0, width, screen.size.height) : screen];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGSingSettingsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    if ([args containsObject:@"slow"]) self.window.layer.speed = 0.1;

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

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"spatial"]) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
    } else if ([verb isEqualToString:@"toggle"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@"."];
        UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue]];
        NSMutableArray<UISwitch *> *switches = [NSMutableArray array];
        findViews(cell, UISwitch.class, switches);
        UISwitch *toggle = switches.firstObject;
        [toggle setOn:!toggle.on animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"lag"]) {
        // How far the disc drawn on screen trails the head's last angle, read every frame for 3 s: the mean and the
        // largest gap in degrees, and the mean as time at the head's speed then.
        NSMutableArray<UIView *> *previews = [NSMutableArray array];
        findViews(self.window, SGSpatialPreview.class, previews);
        if (!previews.count) return;
        LagProbe *probe = [LagProbe new];
        probe.preview = previews.firstObject;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:probe selector:@selector(tick:)];
        link.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [link invalidate];
            [probe report];
        });
    } else if ([verb isEqualToString:@"lines"]) {
        NSMutableArray<UIView *> *cards = [NSMutableArray array];
        findViews(self.window, NSClassFromString(@"SGSingCard"), cards);
        if (!cards.count) return;
        LinesProbe *probe = [LinesProbe new];
        probe.card = cards.firstObject;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:probe selector:@selector(tick:)];
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [link invalidate];
            [probe report];
        });
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"dump"]) {
        UIView *header = table.tableHeaderView;
        NSLog(@"[harness] header %@ %.0fx%.0f; VoiceOver reads \"%@\", \"%@\"", NSStringFromClass(header.class), header.bounds.size.width,
              header.bounds.size.height, header.accessibilityLabel, header.accessibilityValue);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.contentView, UILabel.class, labels);
                NSMutableArray<NSString *> *texts = [NSMutableArray array];
                for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
                [rows addObject:[texts componentsJoinedByString:@" / "]];
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
