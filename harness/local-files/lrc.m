// Checks LocalLyrics.m as the tweak compiles it: an .lrc file imported (the refusals, the name kept, a
// taken name numbered), read into lines (several stamps on a line, the fraction's forms, the offset,
// untimed text), linked to a local file and matched by title and artist, folded, with the sides of an
// "Artist - Title" name worked out from the track. Runs in its own home, so nothing of the Mac's is
// touched. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What LyricsSources.m and KaraokeSource.x give the tweak, here as little as the file needs.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
@implementation SGLyricsProvider
@end
static NSArray<NSString *> *sg_order;
NSArray<NSString *> *SGLyricsOrder(void) { return sg_order ?: @[]; }
void SGLyricsSetOrder(NSArray<NSString *> *keys) { sg_order = keys; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    SGLyricsProvider *provider = [SGLyricsProvider new];
    provider.key = key;
    return provider;
}
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }

static NSURL *fileNamed(NSString *name, NSData *data) {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name];
    [data writeToURL:url atomically:YES];
    return url;
}

static NSURL *lrc(NSString *name, NSString *text) {
    return fileNamed(name, [text dataUsingEncoding:NSUTF8StringEncoding]);
}

int main(void) {
    @autoreleasepool {
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [NSFileManager.defaultManager removeItemAtPath:[documents stringByAppendingPathComponent:@"Vitrine/Lyrics"] error:nil];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
        sg_order = @[@"lrclib"];
        NSError *error = nil;

        // Refusals: empty, too large, no "]".
        CHECK(!SGImportLRC(lrc(@"empty.lrc", @""), nil, &error) && error);
        CHECK(!SGImportLRC(fileNamed(@"big.lrc", [NSMutableData dataWithLength:1024 * 1024 + 1]), nil, &error));
        CHECK(!SGImportLRC(lrc(@"words.lrc", @"just some words"), nil, &error));
        CHECK(SGImportedLRCFiles().count == 0);

        // Several stamps on a line, every fraction form, an offset, a line with no text skipped.
        NSString *sheet = @"﻿[ti:Halo]\n[ar:Beyoncé]\n[offset:+500]\n[00:10.5][01:00:250]Remember\n[00:20.25]those walls\n[00:30]\n[1:05.123]I built\n";
        NSString *name = SGImportLRC(lrc(@"halo.lrc", sheet), nil, &error);
        CHECK([name isEqualToString:@"halo.lrc"]);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // the first import goes on top
        SGLyricsResult *found = SGImportedLRCFor(@"spotify:track:x", @"HALO", @"beyonce");
        CHECK(found.synced && found.karaokeLines.count == 4);
        NSArray<NSNumber *> *starts = [found.karaokeLines valueForKey:@"start"];
        CHECK([starts isEqualToArray:(@[@10000, @19750, @59750, @64623])]);
        CHECK([SGKaraokeLineText(found.karaokeLines[2]) isEqualToString:@"Remember"]);
        CHECK([found.title isEqualToString:@"Halo"] && [found.provider isEqualToString:@"Imported LRC"]);
        CHECK(!SGImportedLRCFor(@"spotify:track:x", @"Halo", @"Someone else"));
        CHECK(!SGImportedLRCFor(@"spotify:track:x", nil, @"Beyoncé"));   // never without a title

        // A taken name is numbered.
        CHECK([SGImportLRC(lrc(@"halo.lrc", sheet), nil, &error) isEqualToString:@"halo (2).lrc"]);
        CHECK(SGDeleteImportedLRC(@"halo (2).lrc"));

        // "Artist - Title" and "Title – Artist" with no tags: the sides come from the track.
        SGImportLRC(lrc(@"Daft Punk - One More Time.lrc", @"[00:01.00]One more time"), nil, &error);
        SGImportLRC(lrc(@"Around the World – Daft Punk.lrc", @"[00:01.00]Around the world"), nil, &error);
        CHECK(SGImportedLRCFor(@"spotify:track:y", @"one more time!", @"DAFT PUNK"));
        CHECK(SGImportedLRCFor(@"spotify:track:y", @"Around The World", @"Daft Punk"));
        CHECK(!SGImportedLRCFor(@"spotify:track:y", @"One More Time", @"Justice"));
        CHECK(!SGImportedLRCFor(@"spotify:track:y", @"Discovery", @"Daft Punk"));

        // A local file named by its URI; one linked has its file whatever the names say, and keeps it
        // through a rename's lyrics key. Untimed text drops the lines that open with "[".
        NSString *uri = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
        CHECK(SGImportedLRCFor(uri, nil, nil));
        NSString *other = @"spotify:local:::Track+01:200";
        CHECK(!SGImportedLRCFor(other, nil, nil));
        sg_order = @[@"lrclib", SGImportedLRCKey];
        NSString *plain = SGImportLRC(lrc(@"notes.lrc", @"[by:me]\nFirst line\n\nSecond line\n[x] dropped"), other, &error);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // a link goes on top
        CHECK([SGImportedLRCLinkedTo([other stringByAppendingString:@"#123"]) isEqualToString:plain]);
        found = SGImportedLRCFor(other, nil, nil);
        CHECK(found && !found.synced && found.karaokeLines.count == 2 && [found.title isEqualToString:@"Track 01"]);
        CHECK(!SGImportLRC(lrc(@"skip.lrc", @"[00:01]x"), @"spotify:track:z", &error) || !SGImportedLRCLinkedTo(@"spotify:track:z"));

        // Deleting the file takes its link and its lyrics.
        CHECK(SGDeleteImportedLRC(plain));
        CHECK(!SGImportedLRCLinkedTo(other) && !SGImportedLRCFor(other, nil, nil));
        CHECK(![[NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks] count]);

        // UTF-16 is read and kept as UTF-8.
        NSString *utf16 = SGImportLRC(fileNamed(@"wide.lrc", [@"[ti:Wide]\n[00:02.00]wide" dataUsingEncoding:NSUTF16StringEncoding]), nil, &error);
        NSString *kept = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:[@"Vitrine/Lyrics" stringByAppendingPathComponent:utf16]]
                                                   encoding:NSUTF8StringEncoding error:nil];
        CHECK([kept hasPrefix:@"[ti:Wide]"]);
        printf("lrc: all checks passed\n");
    }
    return 0;
}
