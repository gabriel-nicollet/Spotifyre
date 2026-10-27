// Mod Settings > Listening stats (Shared/ListeningStats) in the simulator: the page on the real Settings/ framework,
// the recorder of ListeningStats.x fed player states by hand, and an export picked through the page's own picker
// delegate. The launch line plays actions, one every 0.7 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build-sim.sh && xcrun simctl install <udid> build/sim/ListeningStatsHarness.app
//     xcrun simctl launch <udid> com.vitrine.listeningstatsharness [action...]
//
// Actions: erase (the log emptied), seed (a week, a month and a year of plays merged in), record (a track played
// 31 s, one played 5 s, one paused after 10 s for 10 s and played 25 s more, then playback stopped: takes 82 s, so put it
// last), pick (an extended export and a zip of a basic one handed to the picker's delegate as if picked),
// select=<section>.<row> (a tap on a row of the page on top), pop, bottom, dump (the rows each section shows).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"

extern id<SGPlayerStateObserver> SGHarnessObserver;

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

static SGPlay *play(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    SGPlay *p = [SGPlay new];
    p.end = end; p.ms = ms; p.title = title; p.artist = artist; p.album = album; p.uri = @"";
    return p;
}

static SPTPlayerState *state(NSString *uri, NSString *title, NSString *artist, double duration, BOOL playing) {
    SPTPlayerTrack *track = [SPTPlayerTrack new];
    [track setValue:uri forKey:@"URI"];
    [track setValue:title forKey:@"trackTitle"];
    [track setValue:artist forKey:@"artistName"];
    [track setValue:@{@"artist_name": artist ?: @"", @"album_title": @"Harness Album"} forKey:@"metadata"];
    SPTPlayerState *s = [SPTPlayerState new];
    [s setValue:track forKey:@"track"];
    [s setValue:@(playing) forKey:@"isPlaying"];
    [s setValue:@(!playing) forKey:@"isPaused"];
    [s setValue:@(duration) forKey:@"duration"];
    return s;
}

// The simulator's picker is a remote service that may never appear, so the page's picker is kept rather than
// presented, and pick hands its delegate the files.
static UIDocumentPickerViewController *SGHarnessPicker;

@implementation UIViewController (Harness)
- (void)harness_present:(UIViewController *)page animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([page isKindOfClass:UIDocumentPickerViewController.class]) SGHarnessPicker = (UIDocumentPickerViewController *)page;
    else [self harness_present:page animated:animated completion:completion];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    method_exchangeImplementations(class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:)),
                                   class_getInstanceMethod(UIViewController.class, @selector(harness_present:animated:completion:)));
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSArray<NSString *> *actions = [args subarrayWithRange:NSMakeRange(1, args.count - 1)];
    // erase and seed go before the page is built, so it opens on them.
    for (NSString *action in actions) if ([@[@"erase", @"seed"] containsObject:action]) [self run:action];
    self.nav = [[UINavigationController alloc] initWithRootViewController:SGListeningStatsPage()];
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    __block NSUInteger i = 0;
    for (NSString *action in actions) {
        if ([@[@"erase", @"seed"] containsObject:action]) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.7 * i++) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

// Each step of the script after the one before, in seconds from now.
- (void)after:(double)seconds do:(void (^)(void))block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)record {
    id<SGPlayerStateObserver> o = SGHarnessObserver;
    NSUInteger before = SGListeningLog().plays.count;
    [o playerStateDidChange:state(@"spotify:track:long", @"Played Long", @"Recorder", 200, YES)];
    [self after:31 do:^{ [o playerStateDidChange:state(@"spotify:track:skip", @"Skipped", @"Recorder", 200, YES)]; }];
    [self after:36 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, YES)]; }];
    [self after:46 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, NO)]; }];
    [self after:56 do:^{ [o playerStateDidChange:state(@"spotify:track:paused", @"Paused Between", @"Recorder", 200, YES)]; }];
    [self after:81 do:^{ [o playerStateDidChange:state(nil, nil, nil, 0, NO)]; }];
    [self after:82 do:^{
        NSArray<SGPlay *> *plays = SGListeningLog().plays;
        NSLog(@"[harness] record: %lu new plays (expected 2: Played Long about 31 s, Paused Between about 35 s; timers run late by up to a few percent)", (unsigned long)(plays.count - before));
        for (SGPlay *p in [plays subarrayWithRange:NSMakeRange(before, plays.count - before)]) {
            NSLog(@"[harness] recorded %@ / %@ / %@ / %@, %lld ms", p.uri, p.title, p.artist, p.album, p.ms);
        }
        [self.table reloadData];
    }];
}

// An extended export and a zip holding a basic one with one play the extended has and one it has not.
- (void)pick {
    NSString *dir = NSTemporaryDirectory();
    int64_t now = time(NULL);
    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    NSString *ts = [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 3600]];
    NSArray *extended = @[@{@"ts": ts, @"ms_played": @180000, @"master_metadata_track_name": @"Imported Song",
                            @"master_metadata_album_artist_name": @"Exporter", @"master_metadata_album_album_name": @"Export Album",
                            @"spotify_track_uri": @"spotify:track:imported"}];
    NSURL *json = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"Streaming_History_Audio_2026.json"]];
    [[NSJSONSerialization dataWithJSONObject:extended options:0 error:nil] writeToURL:json atomically:YES];
    // A stored zip of one file, written by hand: the simulator has no zip tool to run.
    f.dateFormat = @"yyyy-MM-dd HH:mm";
    NSArray *basic = @[@{@"endTime": [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 3600]], @"artistName": @"Exporter",
                         @"trackName": @"Imported Song", @"msPlayed": @180000},
                       @{@"endTime": [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:now - 7200]], @"artistName": @"Exporter",
                         @"trackName": @"Only In Basic", @"msPlayed": @90000}];
    NSData *body = [NSJSONSerialization dataWithJSONObject:basic options:0 error:nil];
    NSData *name = [@"Spotify Account Data/StreamingHistory_music_0.json" dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = 0;   // not checked by the reader
    NSMutableData *zip = [NSMutableData data];
    void (^u16)(uint32_t) = ^(uint32_t v) { uint16_t x = (uint16_t)v; [zip appendBytes:&x length:2]; };
    void (^u32)(uint32_t) = ^(uint32_t v) { [zip appendBytes:&v length:4]; };
    u32(0x04034b50); u16(10); u16(0); u16(0); u16(0); u16(0); u32(crc); u32((uint32_t)body.length); u32((uint32_t)body.length);
    u16((uint32_t)name.length); u16(0); [zip appendData:name]; [zip appendData:body];
    uint32_t central = (uint32_t)zip.length;
    u32(0x02014b50); u16(20); u16(10); u16(0); u16(0); u16(0); u16(0); u32(crc); u32((uint32_t)body.length); u32((uint32_t)body.length);
    u16((uint32_t)name.length); u16(0); u16(0); u16(0); u16(0); u32(0); u32(0); [zip appendData:name];
    uint32_t centralSize = (uint32_t)zip.length - central;
    u32(0x06054b50); u16(0); u16(0); u16(1); u16(1); u32(centralSize); u32(central); u16(0);
    NSURL *zipURL = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"my_spotify_data.zip"]];
    [zip writeToURL:zipURL atomically:YES];

    // The import row presents the picker; it is handed the files the way the system would.
    UIDocumentPickerViewController *picker = SGHarnessPicker;
    NSLog(@"[harness] presented %@, multiple %d", NSStringFromClass(picker.class), picker.allowsMultipleSelection);
    [picker.delegate documentPicker:picker didPickDocumentsAtURLs:@[json, zipURL]];
    // The import row while the files are read, before the merge comes back, and the guard against a second pick.
    UITableView *table = self.table;
    UITableViewCell *row = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    SGHarnessPicker = nil;
    [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
    NSLog(@"[harness] importing: the row reads \"%@\", a second tap %@", [(UILabel *)row.accessoryView text],
          SGHarnessPicker ? @"opens the picker again" : @"is ignored");
    [self after:1.5 do:^{
        UITableViewCell *after = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:2]];
        NSLog(@"[harness] imported: the row reads \"%@\"", [(UILabel *)after.accessoryView text]);
    }];
    [self after:2 do:^{
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        NSLog(@"[harness] import says \"%@\": %@", alert.title, alert.message);
    }];
}

- (void)run:(NSString *)action {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"erase"]) {
        [SGListeningLog() erase];
    } else if ([verb isEqualToString:@"seed"]) {
        int64_t now = time(NULL), day = 86400;
        NSMutableArray *plays = [NSMutableArray array];
        for (int i = 0; i < 12; i++) [plays addObject:play(now - day - i * 400, 210000, @"Midnight City", @"M83", @"Hurry Up, We're Dreaming")];
        for (int i = 0; i < 7; i++) [plays addObject:play(now - 2 * day - i * 400, 250000, @"Windowlicker", @"Aphex Twin", @"Windowlicker")];
        for (int i = 0; i < 5; i++) [plays addObject:play(now - 3 * day - i * 400, 300000, @"Teardrop", @"Massive Attack", @"Mezzanine")];
        for (int i = 0; i < 9; i++) [plays addObject:play(now - 20 * day - i * 400, 240000, @"Angel", @"Massive Attack", @"Mezzanine")];
        for (int i = 0; i < 30; i++) [plays addObject:play(now - 200 * day - i * 400, 200000, @"Xtal", @"Aphex Twin", @"Selected Ambient Works 85-92")];
        [plays addObject:play(now - 500 * day, 3600000, @"A Very Long Title That Will Not Fit On One Line Of The Row", @"Someone With A Long Name", @"")];
        NSLog(@"[harness] seeded %lu", (unsigned long)[SGListeningLog() merge:plays]);
    } else if ([verb isEqualToString:@"record"]) {
        [self record];
    } else if ([verb isEqualToString:@"pick"]) {
        [self pick];
    } else if ([verb isEqualToString:@"select"]) {
        NSArray<NSString *> *at = [value componentsSeparatedByString:@"."];
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue]];
    } else if ([verb isEqualToString:@"pop"]) {
        [self.nav popViewControllerAnimated:YES];
    } else if ([verb isEqualToString:@"bottom"]) {
        CGFloat max = MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom);
        [table setContentOffset:CGPointMake(0, max) animated:NO];
    } else if ([verb isEqualToString:@"dump"]) {
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell, UILabel.class, labels);
                NSMutableArray<NSString *> *texts = [NSMutableArray array];
                for (UILabel *label in labels) if (label.text.length) [texts addObject:label.text];
                [rows addObject:[texts componentsJoinedByString:@" | "]];
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
