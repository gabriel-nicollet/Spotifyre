// The pure steps of Native iOS Music Haptics (Shared/Haptics/SGHapticTrack.m) on the Mac: the ISRC check,
// TRACK_V4 replies built by hand (a good one, one for another URI, one whose entity is not 200, one cut short,
// one from a provider that failed, one with no ISRC), and Apple's catalog songs matched and each rejection.
//     ./build.sh && build/track
#import "Shared/Haptics/SGHapticTrack.h"
#import "Shared/AdBlock/Protobuf.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    if (!ok) failures++;
    printf("%s %s\n", ok ? "  ok  " : "FAILED", what.UTF8String);
}

static NSData *message(NSArray<SGPBField *> *fields) {
    return SGPBSerialize(fields);
}

// A BatchedExtensionResponse with one array of one entry, as Spotify 9.1.78 sends it.
static NSData *reply(NSString *uri, uint64_t entityStatus, NSString *isrc, NSNumber *providerStatus) {
    NSMutableArray *externals = [NSMutableArray arrayWithObject:SGPBBytes(10, message(@[SGPBString(1, @"upc"), SGPBString(2, @"00602547288233")]))];
    if (isrc) [externals addObject:SGPBBytes(10, message(@[SGPBString(1, @"isrc"), SGPBString(2, isrc)]))];
    NSData *track = message([@[SGPBString(2, @"Song"), SGPBVarint(7, 215000)] arrayByAddingObjectsFromArray:externals]);
    NSData *any = message(@[SGPBString(1, @"type.googleapis.com/spotify.metadata.Track"), SGPBBytes(2, track)]);
    NSData *entry = message(@[SGPBBytes(1, message(@[SGPBVarint(1, entityStatus), SGPBString(2, @"etag")])), SGPBString(2, uri), SGPBBytes(3, any)]);
    NSMutableArray *array = [NSMutableArray array];
    if (providerStatus) [array addObject:SGPBBytes(1, message(@[SGPBVarint(1, providerStatus.unsignedLongLongValue)]))];
    [array addObjectsFromArray:@[SGPBVarint(2, 10), SGPBBytes(3, entry)]];
    return message(@[SGPBBytes(1, [NSData data]), SGPBBytes(2, message(array))]);
}

int main(void) {
    @autoreleasepool {
        NSString *uri = @"spotify:track:4uLU6hMCjMI75M1A2tKUQC";
        check([SGHapticISRC(@"usrc17607839") isEqualToString:@"USRC17607839"], @"an ISRC is uppercased");
        check([SGHapticISRC(@"GBAYE0601498") isEqualToString:@"GBAYE0601498"], @"letters in the registrant");
        check(!SGHapticISRC(@"USRC1760783") && !SGHapticISRC(@"USRC176078390"), @"11 or 13 characters are not one");
        check(!SGHapticISRC(@"1SRC17607839") && !SGHapticISRC(@"USRC1760783A") && !SGHapticISRC(@"US-C17607839"), @"a digit, letter or dash out of place is not one");
        check(!SGHapticISRC(nil) && !SGHapticISRC((id)@12), @"nil or a number is not one");
        check(SGHapticIsTrackURI(uri), @"a track URI");
        check(!SGHapticIsTrackURI(@"spotify:episode:4uLU6hMCjMI75M1A2tKUQC") && !SGHapticIsTrackURI(@"spotify:local:a:b:c:215")
              && !SGHapticIsTrackURI(@"spotify:track:4uLU6hMCjMI75M1A2tKUQ"), @"an episode, a local file or a short id is not");

        NSArray<SGPBField *> *request = SGPBParse(SGHapticTrackRequest(uri));
        NSArray<SGPBField *> *entity = SGPBParse(SGPBFirst(request, 2).payload);
        NSArray<SGPBField *> *query = SGPBParse(SGPBFirst(entity, 2).payload);
        check([SGPBText(SGPBFirst(entity, 1)) isEqualToString:uri] && SGPBFirst(query, 1).varint == 10, @"the request names the URI and TRACK_V4");

        BOOL answered;
        NSString *isrc = SGHapticISRCInReply(reply(uri, 200, @"usrc17607839", @200), uri, &answered);
        check([isrc isEqualToString:@"USRC17607839"] && answered, @"a good reply gives its ISRC");
        isrc = SGHapticISRCInReply(reply(uri, 200, @"USRC17607839", nil), uri, &answered);
        check([isrc isEqualToString:@"USRC17607839"] && answered, @"a reply without a provider status is taken");
        isrc = SGHapticISRCInReply(reply(@"spotify:track:0000000000000000000000", 200, @"USRC17607839", @200), uri, &answered);
        check(!isrc && !answered, @"a reply for another URI is not");
        isrc = SGHapticISRCInReply(reply(uri, 404, @"USRC17607839", @200), uri, &answered);
        check(!isrc && !answered, @"an entity status of 404 is not");
        isrc = SGHapticISRCInReply(reply(uri, 200, @"USRC17607839", @500), uri, &answered);
        check(!isrc && !answered, @"a provider status of 500 is not");
        NSData *whole = reply(uri, 200, @"USRC17607839", @200);
        isrc = SGHapticISRCInReply([whole subdataWithRange:NSMakeRange(0, whole.length - 5)], uri, &answered);
        check(!isrc && !answered, @"a reply cut short is not");
        isrc = SGHapticISRCInReply(reply(uri, 200, nil, @200), uri, &answered);
        check(!isrc && answered, @"a good reply with no ISRC is final");
        isrc = SGHapticISRCInReply(reply(uri, 200, @"USRC1760783", @200), uri, &answered);
        check(!isrc && answered, @"a malformed ISRC is none");
        isrc = SGHapticISRCInReply([NSData data], uri, &answered);
        check(!isrc && !answered, @"an empty reply is not");

        NSDictionary *(^song)(NSString *, id, id, id) = ^NSDictionary *(NSString *identifier, id code, id length, id haptics) {
            NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
            if (code) attributes[@"isrc"] = code;
            if (length) attributes[@"durationInMillis"] = length;
            if (haptics) attributes[@"hasHaptics"] = haptics;
            return @{@"id": identifier, @"type": @"songs", @"attributes": attributes};
        };
        NSString *code = @"USRC17607839";
        check([SGHapticSongIn(@[song(@"1440857781", code, @215400, @YES)], code, 215000) isEqualToString:@"1440857781"], @"the same ISRC, 0.4 s apart, with haptics");
        check([SGHapticSongIn(@[song(@"1", @"usrc17607839", @213001, @YES)], code, 215000) isEqualToString:@"1"], @"1.999 s apart and a lowercase ISRC still match");
        check(!SGHapticSongIn(@[song(@"1", code, @212999, @YES)], code, 215000), @"2.001 s apart does not");
        check(!SGHapticSongIn(@[song(@"1", @"USRC17607840", @215000, @YES)], code, 215000), @"another ISRC does not");
        check(!SGHapticSongIn(@[song(@"1", code, @215000, @NO)], code, 215000), @"no haptic track does not");
        check(!SGHapticSongIn(@[song(@"1", code, @215000, nil)], code, 215000), @"hasHaptics missing does not");
        check(!SGHapticSongIn(@[song(@"1", nil, @215000, @YES)], code, 215000), @"an ISRC missing does not");
        check(!SGHapticSongIn(@[song(@"1", code, nil, @YES)], code, 215000), @"a length missing does not");
        check(!SGHapticSongIn(@[song(@"1", code, @215000, @YES)], code, 0), @"Spotify's length unknown does not");
        check([SGHapticSongIn(@[song(@"live", code, @260000, @YES), song(@"studio", code, @215000, @YES)], code, 215000) isEqualToString:@"studio"],
              @"of two with the ISRC, the one of the right length");
        check(!SGHapticSongIn((id)@{}, code, 215000) && !SGHapticSongIn(@[@"x", @{}], code, 215000), @"anything but songs is passed over");

        printf("%s: %d failed\n", failures ? "FAILED" : "all passed", failures);
    }
    return failures ? 1 : 0;
}
