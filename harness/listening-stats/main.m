// Runs SGPlayLog.m on the Mac against synthetic export files, loose and zipped, and checks what the stats
// page would read out. Exits non-zero when a check fails.
//
//     ./build.sh && build/listening-stats
#import <Foundation/Foundation.h>
#import "Shared/ListeningStats/SGPlayLog.h"

static int failures = 0;
#define CHECK(cond, ...) do { if (cond) printf("ok    "); else { printf("FAIL  "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

static NSData *json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSString *stamp(int64_t t, BOOL extended) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = extended ? @"yyyy-MM-dd'T'HH:mm:ss'Z'" : @"yyyy-MM-dd HH:mm";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static NSDictionary *extendedRow(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    return @{@"ts": stamp(end, YES), @"platform": @"ios", @"ms_played": @(ms), @"conn_country": @"CZ",
             @"master_metadata_track_name": title ?: (id)NSNull.null, @"master_metadata_album_artist_name": artist ?: (id)NSNull.null,
             @"master_metadata_album_album_name": album ?: (id)NSNull.null,
             @"spotify_track_uri": title ? [@"spotify:track:" stringByAppendingString:title] : (id)NSNull.null,
             @"episode_name": NSNull.null, @"spotify_episode_uri": NSNull.null, @"reason_end": @"trackdone"};
}

static NSDictionary *basicRow(int64_t end, int64_t ms, NSString *title, NSString *artist) {
    return @{@"endTime": stamp(end, NO), @"artistName": artist, @"trackName": title, @"msPlayed": @(ms)};
}

static SGPlay *play(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    SGPlay *p = [SGPlay new];
    p.end = end; p.ms = ms; p.title = title; p.artist = artist; p.album = album ?: @""; p.uri = @"";
    return p;
}

static void zip(NSString *dir, NSString *out, NSArray<NSString *> *names, BOOL stored) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/zip"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-q", stored ? @"-0" : @"-9", out, nil];
    [args addObjectsFromArray:names];
    task.arguments = args;
    [task launchAndReturnError:nil];
    [task waitUntilExit];
}

static double since(NSDate *start) {
    return -start.timeIntervalSinceNow * 1000;
}

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"listening-stats-harness"];
        NSString *exportDir = [dir stringByAppendingPathComponent:@"export"];
        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:[exportDir stringByAppendingPathComponent:@"__MACOSX"] withIntermediateDirectories:YES attributes:nil error:nil];

        // A fixed "now" on a whole minute, so the basic export's minute stamps land exactly.
        int64_t now = 1790000000 - 1790000000 % 60, day = 86400;

        // Extended: Song A twice and Song B 3 days ago, Song C 20 days ago, Song D 200 days ago, Song A
        // 2 years ago; then a podcast row (nulls), a 10 s skip and a row without a ts.
        NSArray *extended = @[
            extendedRow(now - 3 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 300, 180000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 600, 60000, @"Song B", @"Artist 2", @"Album Y"),
            extendedRow(now - 20 * day, 240000, @"Song C", @"Artist 1", @"Album Z"),
            extendedRow(now - 200 * day, 210000, @"Song D", @"Artist 3", @"Album W"),
            extendedRow(now - 730 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 4 * day, 1800000, nil, nil, nil),
            extendedRow(now - 4 * day + 100, 10000, @"Song E", @"Artist 4", @"Album V"),
            @{@"ms_played": @50000, @"ts": NSNull.null},
        ];
        NSArray<SGPlay *> *ext = SGPlaysFromExport(json(extended));
        CHECK(ext.count == 6, "extended: 6 music plays kept of 9 rows (podcast, skip, no ts out): %lu", (unsigned long)ext.count);
        CHECK(ext.firstObject.end == now - 3 * day, "extended: ts read as UTC to the second");
        CHECK([ext.firstObject.album isEqualToString:@"Album X"] && [ext.firstObject.uri isEqualToString:@"spotify:track:Song A"],
              "extended: album and URI read");

        // Basic: the same two Song A plays 20 s later than the extended ts (minute stamps and drift), a play
        // only the basic file has, a 5 s skip and a podcast-shaped row.
        NSArray *basic = @[
            basicRow(now - 3 * day + 20, 200000, @"Song A", @"Artist 1"),
            basicRow(now - 3 * day + 300 + 20, 180000, @"Song A", @"Artist 1"),
            basicRow(now - 1 * day, 100000, @"Song F", @"Artist 2"),
            basicRow(now - 1 * day + 400, 5000, @"Song F", @"Artist 2"),
            @{@"endTime": stamp(now, NO), @"podcastName": @"Pod", @"episodeName": @"Ep", @"msPlayed": @900000},
        ];
        NSArray<SGPlay *> *bas = SGPlaysFromExport(json(basic));
        CHECK(bas.count == 3, "basic: 3 music plays kept of 5 rows: %lu", (unsigned long)bas.count);
        CHECK(bas.firstObject.end == now - 3 * day, "basic: endTime read as UTC, to the minute");
        CHECK(SGPlaysFromExport(json(@[@{@"spotify": @"settings"}])) == nil, "a JSON array that is not an export is refused");
        CHECK(SGPlaysFromExport(json(@{@"settings": @{}})) == nil, "a JSON object is refused");
        CHECK(SGPlaysFromExport([@"not json" dataUsingEncoding:NSUTF8StringEncoding]) == nil, "not JSON is refused");

        // Zips as the export arrives, stored and deflated, with a PDF and a __MACOSX twin beside the JSON.
        [json(extended) writeToFile:[exportDir stringByAppendingPathComponent:@"Streaming_History_Audio_2023.json"] atomically:YES];
        [json(basic) writeToFile:[exportDir stringByAppendingPathComponent:@"StreamingHistory_music_0.json"] atomically:YES];
        [@"readme" writeToFile:[exportDir stringByAppendingPathComponent:@"ReadMeFirst.pdf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"junk" writeToFile:[exportDir stringByAppendingPathComponent:@"__MACOSX/._StreamingHistory_music_0.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSArray *names = @[@"Streaming_History_Audio_2023.json", @"StreamingHistory_music_0.json", @"ReadMeFirst.pdf", @"__MACOSX/._StreamingHistory_music_0.json"];
        for (NSNumber *stored in @[@YES, @NO]) {
            NSString *path = [dir stringByAppendingPathComponent:stored.boolValue ? @"stored.zip" : @"deflated.zip"];
            zip(exportDir, path, names, stored.boolValue);
            NSArray<NSData *> *files = SGJSONFilesInZip([NSData dataWithContentsOfFile:path]);
            NSUInteger plays = 0;
            for (NSData *file in files) plays += SGPlaysFromExport(file).count;
            CHECK(files.count == 2 && plays == 9, "%s zip: 2 JSON files, 9 plays: %lu files, %lu plays",
                  stored.boolValue ? "stored" : "deflated", (unsigned long)files.count, (unsigned long)plays);
        }
        CHECK(SGJSONFilesInZip(json(extended)).count == 0, "a file that is not a zip has no files in it");
        NSData *deflated = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"deflated.zip"]];
        CHECK(SGJSONFilesInZip([deflated subdataWithRange:NSMakeRange(0, deflated.length / 2)]).count == 0, "a cut-off zip reads as empty");

        // The log: Song B recorded on the phone 30 s after the export's, then both files merged, twice.
        NSString *logPath = [dir stringByAppendingPathComponent:@"Vitrine/plays.tsv"];
        SGPlayLog *log = [[SGPlayLog alloc] initWithPath:logPath];
        SGPlay *recorded = play(now - 3 * day + 630, 61000, @"Song B", @"Artist 2", @"Album Y");
        recorded.uri = @"spotify:track:b";
        [log record:recorded];
        NSUInteger added = [log merge:ext];
        CHECK(added == 5, "merge extended: 5 added, the recorded Song B already there: %lu", (unsigned long)added);
        added = [log merge:bas];
        CHECK(added == 1, "merge basic: only Song F is new: %lu", (unsigned long)added);
        added = [log merge:ext] + [log merge:bas];
        CHECK(added == 0, "importing the same files again adds nothing: %lu", (unsigned long)added);
        CHECK([log merge:@[play(now, 40000, @"Tab\there", @"New\nline", @"")]] == 1, "a title with a tab and an artist with a newline merge");

        SGPlayLog *reread = [[SGPlayLog alloc] initWithPath:logPath];
        CHECK(reread.plays.count == 8, "the log reads back 8 plays: %lu", (unsigned long)reread.plays.count);
        SGPlay *last = reread.plays.lastObject;
        CHECK([last.title isEqualToString:@"Tab here"] && [last.artist isEqualToString:@"New line"], "tab and newline become spaces");
        CHECK([reread.plays.firstObject.uri isEqualToString:@"spotify:track:b"] && reread.plays.firstObject.ms == 61000, "the recorded play round-trips");

        // Periods from the fixed now. Week: Song A x2, Song B, Song F, Tab here. Month adds Song C, year
        // Song D, all time the old Song A.
        NSArray *plays = reread.plays;
        SGStats *week = SGStatsSince(plays, now - 7 * day, 10), *month = SGStatsSince(plays, now - 30 * day, 10);
        SGStats *year = SGStatsSince(plays, now - 365 * day, 10), *all = SGStatsSince(plays, 0, 10);
        CHECK(week.plays == 5 && month.plays == 6 && year.plays == 7 && all.plays == 8, "plays per period 5/6/7/8: %lu/%lu/%lu/%lu",
              (unsigned long)week.plays, (unsigned long)month.plays, (unsigned long)year.plays, (unsigned long)all.plays);
        CHECK(week.ms == 200000 + 180000 + 61000 + 100000 + 40000, "week: listening time adds up: %lld", week.ms);
        CHECK([week.tracks.firstObject.name isEqualToString:@"Song A"] && week.tracks.firstObject.plays == 2, "week: Song A tops the tracks with 2 plays");
        CHECK([week.artists[0].name isEqualToString:@"Artist 1"] && [week.artists[1].name isEqualToString:@"Artist 2"] && week.artists[1].plays == 2,
              "week: Artists 1 and 2 tie on 2 plays, and the one listened to longer leads");
        CHECK(all.tracks.firstObject.plays == 3 && [all.tracks.firstObject.name isEqualToString:@"Song A"], "all time: Song A x3");
        CHECK([all.artists.firstObject.name isEqualToString:@"Artist 1"] && all.artists.firstObject.plays == 4, "all time: Artist 1 x4");
        CHECK(all.albums.count == 4 && [all.albums.firstObject.name isEqualToString:@"Album X"], "all time: 4 albums (basic plays have none), Album X first");
        CHECK(SGStatsSince(plays, 0, 2).tracks.count == 2, "a top list is capped");

        CHECK(SGPlayCounts(30, 300) && !SGPlayCounts(29, 300) && SGPlayCounts(20, 40) && !SGPlayCounts(19, 40) && !SGPlayCounts(10, 0),
              "a play counts past 30 s or half the track");

        // An export's size: 100k extended rows.
        NSMutableArray *big = [NSMutableArray arrayWithCapacity:100000];
        for (int i = 0; i < 100000; i++) {
            [big addObject:extendedRow(now - i * 200, 120000, [NSString stringWithFormat:@"Track %d", i % 3000],
                                       [NSString stringWithFormat:@"Artist %d", i % 400], [NSString stringWithFormat:@"Album %d", i % 900])];
        }
        NSData *bigData = json(big);
        NSString *bigPath = [dir stringByAppendingPathComponent:@"big.tsv"];
        NSDate *start = [NSDate date];
        NSArray *bigPlays = SGPlaysFromExport(bigData);
        double parse = since(start);
        SGPlayLog *bigLog = [[SGPlayLog alloc] initWithPath:bigPath];
        start = [NSDate date];
        NSUInteger bigAdded = [bigLog merge:bigPlays];
        double merge = since(start);
        start = [NSDate date];
        NSUInteger again = [bigLog merge:bigPlays];
        double remerge = since(start);
        start = [NSDate date];
        SGPlayLog *bigReread = [[SGPlayLog alloc] initWithPath:bigPath];
        NSUInteger readBack = bigReread.plays.count;
        double load = since(start);
        start = [NSDate date];
        SGStatsSince(bigReread.plays, 0, 10);
        double stats = since(start);
        CHECK(bigAdded == 100000 && again == 0 && readBack == 100000, "100k rows: all added, none twice, all read back");
        printf("      100k rows (%.1f MB JSON): parse %.0f ms, merge %.0f ms, merge again %.0f ms, load %.0f ms, add up %.0f ms\n",
               bigData.length / 1e6, parse, merge, remerge, load, stats);

        printf(failures ? "\n%d FAILED\n" : "\nall passed\n", failures);
        return failures ? 1 : 0;
    }
}
