// Checks what is new in the lyrics sources and their words without the phone or the network: lines in
// Thai and the scripts like it split at the dictionary's words (KaraokeTiming.m), KuGou's KRC unpacked
// and read (KuGou.m, through NetEase.m's parser), and the QQ Music and KuGou asks matching a track
// against made-up search replies. The requests are answered here, by host. Any file named on the
// command line is a real KuGou download or QQ lyrics reply, saved as JSON, and only its line count is
// printed. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import <zlib.h>
#import "Shared/LyricsSources/LyricsSources.h"

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAILED line %d: %s\n", __LINE__, #cond); exit(1); } } while (0)

// What the sources reach outside themselves for: the requests, answered by sg_answer.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {}
NSURL *SGLyricsURL(NSString *base, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray array];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    return url.URL;
}
static id (^sg_answer)(NSURL *url, id body);
void SGLyricsGetJSON(NSURL *url, NSDictionary *headers, void (^done)(id root)) { done(sg_answer(url, nil)); }
void SGLyricsPostJSON(NSURL *url, NSDictionary *headers, id body, void (^done)(id root)) { done(sg_answer(url, body)); }

static NSString *param(NSURL *url, NSString *name) {
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:name]) return item.value;
    }
    return nil;
}

static NSArray<SGKaraokeWord *> *piecesOf(NSString *text) {
    return SGKaraokeStaticLines(@[text]).firstObject.words;
}

// The words of an unspaced token come back flush, so the line reads as it was written.
static void checkSplit(NSString *text, BOOL split) {
    NSArray<SGKaraokeWord *> *words = piecesOf(text);
    printf("%lu pieces: %s\n", (unsigned long)words.count, [[words valueForKey:@"text"] componentsJoinedByString:@"|"].UTF8String);
    CHECK([SGKaraokeLineText(SGKaraokeStaticLines(@[text]).firstObject) isEqualToString:text]);
    CHECK(!split || words.count > 1);
}

// KRC as KuGou packs it: "krc1", then the zlib of the text XORed with the key, all in base64.
static NSString *packed(NSString *krc, NSString *magic) {
    NSData *text = [krc dataUsingEncoding:NSUTF8StringEncoding];
    uLongf length = compressBound(text.length);
    NSMutableData *zipped = [NSMutableData dataWithLength:length];
    compress(zipped.mutableBytes, &length, text.bytes, text.length);
    zipped.length = length;
    static const uint8_t key[16] = {64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105};
    uint8_t *bytes = zipped.mutableBytes;
    for (NSUInteger i = 0; i < zipped.length; i++) bytes[i] ^= key[i % 16];
    NSMutableData *all = [[magic dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [all appendData:zipped];
    return [all base64EncodedStringWithOptions:0];
}

static NSString *const kKRC = @"﻿[id:$00000000]\r\n[ar:Someone]\r\n"
    "[1000,2000]<0,500,0>Hel<500,300,0>lo <800,700,0>world\r\n"
    "[4000,1500]<0,400,0>你<400,400,0>好<800,0,0>啊\r\n"
    "[7000,100]<0,300,0>late\r\n";

static void checkLive(NSString *path) {
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
    if (root[@"content"]) {
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(root[@"content"]);
        printf("%s: KRC, %lu word timed lines; first \"%s\" at %ld\n", path.lastPathComponent.UTF8String, (unsigned long)lines.count,
               SGKaraokeLineText(lines.firstObject).UTF8String, (long)lines.firstObject.start);
        CHECK(lines.count);
        return;
    }
    id lyric = root[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"data"][@"lyric"];
    NSString *lrc = [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:lyric options:0] encoding:NSUTF8StringEncoding];
    SGLyricsResult *result = SGLyricsLRCResult(lrc);
    printf("%s: QQ LRC, %lu timed lines\n", path.lastPathComponent.UTF8String, (unsigned long)result.karaokeLines.count);
    CHECK(result.synced && result.karaokeLines.count);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // Thai, Lao, Khmer and Burmese, long lines with no space, and Thai among Latin and brackets.
        checkSplit(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้และจะอยู่เคียงข้างเธอตลอดไป", YES);
        checkSplit(@"วันนี้อากาศดีมากเราไปเดินเล่นที่สวนสาธารณะด้วยกันไหมนะที่รัก", YES);
        checkSplit(@"Baby(ที่รัก)ฉันคิดถึงเธอทุกวันทุกคืนไม่เคยลืมเลย,ok?", YES);
        checkSplit(@"ฉันรักเธอ, เธอรักฉัน... (ด้วยหัวใจ)", YES);
        CHECK([piecesOf(@"(ด้วยหัวใจ)").firstObject.text isEqualToString:@"(ด้วย"]);   // what comes before the first word stays with it
        checkSplit(@"ຂ້ອຍຮັກເຈົ້າຫຼາຍທີ່ສຸດໃນໂລກນີ້ແລະຈະຢູ່ນຳເຈົ້າຕະຫຼອດໄປ", NO);
        checkSplit(@"ខ្ញុំស្រលាញ់អ្នកខ្លាំងណាស់ហើយនឹងនៅជាមួយអ្នកជារៀងរហូត", NO);
        checkSplit(@"ကျွန်တော်မင်းကိုအရမ်းချစ်တယ်ထာဝရမင်းနဲ့အတူရှိနေမယ်", NO);
        CHECK(piecesOf(@"๏๚").count == 1);   // Thai punctuation alone: no word, one piece
        CHECK(piecesOf(@"hello world").count == 2 && !piecesOf(@"hello world")[1].joined);
        CHECK(piecesOf(@"日本語の歌").count == 5 && piecesOf(@"日本語の歌")[4].joined);
        NSArray<SGKaraokeWord *> *thai = piecesOf(@"ฉันรักเธอมากกว่าสิ่งใดในโลกนี้");
        CHECK(!thai[0].joined && thai[1].joined);

        // The keys the two catalogs are matched by.
        CHECK([SGLyricsMatchKey(@"晴天（Live版）") isEqualToString:SGLyricsMatchKey(@"晴天 (Live版)")]);
        CHECK([SGLyricsMatchKey(@"Hello,　World!") isEqualToString:@"helloworld"]);
        CHECK([SGLyricsMatchKey(@"《稻香》") isEqualToString:@"稻香"]);
        CHECK([SGLyricsLeadArtist(@"周杰伦 feat. 费玉清") isEqualToString:@"周杰伦"]);
        CHECK(SGLyricsSameArtist(@"周杰伦、费玉清", @"周杰伦 Feat. Someone") && !SGLyricsSameArtist(@"林俊杰", @"周杰伦"));
        CHECK(!SGLyricsSameArtist(@"", @"周杰伦") && !SGLyricsSameArtist(nil, @"x"));

        // KRC: pieces timed from their line's start, a spaced word's pieces run together, a syllable each
        // in Chinese, a piece of no length shown for 1 ms, a line ending at its last word when that is later.
        NSArray<SGKaraokeLine *> *lines = SGKuGouLines(packed(kKRC, @"krc1"));
        CHECK(lines.count == 3);
        CHECK([SGKaraokeLineText(lines[0]) isEqualToString:@"Hello world"] && lines[0].words.count == 2);
        CHECK(lines[0].words[0].start == 1000 && lines[0].words[0].end == 1800 && lines[0].words[1].start == 1800);
        CHECK(lines[0].start == 1000 && lines[0].end == 3000 && lines[0].timing == SGKaraokeTimingWords);
        CHECK(lines[1].words.count == 3 && [SGKaraokeLineText(lines[1]) isEqualToString:@"你好啊"]);
        CHECK(lines[1].words[1].joined && lines[1].words[2].start == 4800 && lines[1].words[2].end == 4801);
        CHECK(lines[2].end == 7300);
        CHECK(!SGKuGouLines(packed(kKRC, @"krc2")) && !SGKuGouLines(@"bm90IGtyYw==") && !SGKuGouLines(nil));
        CHECK(!SGKuGouLines(packed(@"[ar:only tags]", @"krc1")));

        // KuGou: the user uploads, another title, another singer, a length 21 s off and a candidate with
        // no key are passed over; the rest are tried closest in length first, three at most.
        NSArray *candidates = @[
            @{@"id": @"a", @"accesskey": @"k", @"product_from": @"ugc", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"b", @"accesskey": @"k", @"song": @"晴天 (Live)", @"singer": @"周杰伦", @"duration": @269000},
            @{@"id": @"c", @"accesskey": @"k", @"song": @"晴天", @"singer": @"Other", @"duration": @269000},
            @{@"id": @"d", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @290000},
            @{@"id": @"e", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @265000},
            @{@"id": @7, @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @269500},
            @{@"id": @"g", @"accesskey": @"k", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @262000},
            @{@"id": @"h", @"song": @"晴天", @"singer": @"周杰伦", @"duration": @270000},
            @{@"id": @"i", @"accesskey": @"k", @"song": @" 晴天！", @"singer": @"周杰伦、费玉清", @"duration": @"268000"},
        ];
        NSMutableArray<NSString *> *tried = [NSMutableArray array];
        __block NSString *keyword, *duration, *good = @"e";
        sg_answer = ^id(NSURL *url, id body) {
            if ([url.host isEqualToString:@"krcs.kugou.com"]) {
                keyword = param(url, @"keyword");
                duration = param(url, @"duration");
                return @{@"status": @200, @"candidates": candidates};
            }
            NSString *song = param(url, @"id");
            [tried addObject:song];
            if ([song isEqualToString:good]) return @{@"status": @200, @"content": packed(kKRC, @"krc1")};
            return [song isEqualToString:@"7"] ? @{@"status": @200, @"content": @"garbage"} : @{@"status": @404};
        };
        SGLyricsQuery *query = [SGLyricsQuery new];
        query.title = @"晴天";
        query.artist = @"周杰伦 feat. Someone";
        query.seconds = 269;
        __block SGLyricsResult *got = nil;
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([keyword isEqualToString:@"周杰伦 - 晴天"] && [duration isEqualToString:@"269000"]);
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])]);
        CHECK(got.synced && got.wordTimed && got.karaokeLines.count == 3 && got.texts.count == 3);
        [tried removeAllObjects];
        good = @"g";   // fourth in line: never asked
        got = [SGLyricsResult new];
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([tried isEqualToArray:(@[@"7", @"i", @"e"])] && !got);
        query.artist = @"";
        got = [SGLyricsResult new];
        [tried removeAllObjects];
        SGKuGouAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK(!got && !tried.count);

        // QQ Music: the first result with the title, a singer and the length is taken, and its LRC read.
        NSString *lrc = @"[ti:x]\n[ar:y]\n[00:01.00]第一行\n[00:03.50]第二行\n";
        __block NSDictionary *asked = nil;
        sg_answer = ^id(NSURL *url, NSDictionary *body) {
            if (body[@"req"]) return @{@"req": @{@"data": @{@"body": @{@"song": @{@"list": @[
                @{@"title": @"晴天", @"interval": @269, @"singer": @[@{@"name": @"Someone Else"}], @"id": @1},
                @{@"title": @"晴天", @"interval": @300, @"singer": @[@{@"name": @"周杰伦"}], @"id": @2},
                @{@"title": @"雨天", @"interval": @269, @"singer": @[@{@"name": @"周杰伦"}], @"id": @3},
                @{@"songname": @"晴天", @"interval": @270, @"singer": @[@{@"name": @"x"}, @{@"name": @"周杰伦"}], @"id": @97773},
            ]}}}}};
            asked = body[@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo"][@"param"];
            NSString *encoded = [[lrc dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            return @{@"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo": @{@"data": @{@"lyric": encoded}}};
        };
        query.artist = @"周杰伦";
        got = nil;
        SGQQMusicAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK([asked[@"songID"] isEqual:@97773] && [asked[@"qrc"] isEqual:@0] && [asked[@"crypt"] isEqual:@0]);
        CHECK(got.synced && !got.wordTimed && got.karaokeLines.count == 2 && got.karaokeLines[1].start == 3500);
        query.seconds = 200;   // no recording that long: nothing asked for lyrics
        asked = nil;
        got = [SGLyricsResult new];
        SGQQMusicAsk(query, ^(SGLyricsResult *result) { got = result; });
        CHECK(!got && !asked);

        for (int i = 1; i < argc; i++) checkLive(@(argv[i]));
        printf("lyrics-sources: all checks passed\n");
    }
    return 0;
}
