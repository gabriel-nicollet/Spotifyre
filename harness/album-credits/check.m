// Checks which artist lines an album page drops (Redesigned/Album/AlbumCredits.m) on the Mac: the line that only
// repeats the album's artist, or the album's artist and the guests the title names after a featured-artist
// marker, and every case that has to keep its line.
//
//     ./build.sh && build/album-credits-check
//
// Every line prints ok or FAIL; the exit status is the number of failures.
#import <Foundation/Foundation.h>

// Album.h's, which brings UIKit along.
BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title);

static int failures;

static void check(BOOL hides, BOOL wanted, NSString *what) {
    printf("%s %s: %s\n", hides == wanted ? "ok  " : "FAIL", wanted ? "hidden" : "kept  ", what.UTF8String);
    failures += hides != wanted;
}

int main(void) {
    @autoreleasepool {
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"The Weeknd", @"Cry For Me"), YES, @"the album's artist again");
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"the  weeknd ", @"Cry For Me"), YES, @"case and white space");
        NSString *composed = @"Beyoncé", *decomposed = @"Beyoncé";
        check(SGRCreditRepeatsAlbum(composed, decomposed, @"Halo"), YES, @"composed and decomposed é");
        check(SGRCreditRepeatsAlbum(@"Beyoncé", @"Beyonce", @"Halo"), NO, @"accents are not stripped");
        check(SGRCreditRepeatsAlbum(@"A • B • C", @"A, B, C", @"Song"), YES, @"three co-artists, • against ,");
        check(SGRCreditRepeatsAlbum(@"A • B", @"B, A", @"Song"), NO, @"co-artists in another order");
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"The Weeknd, Justice", @"Wake Me Up (feat. Justice)"), YES,
              @"(feat. guest)");
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"The Weeknd, Anitta", @"São Paulo - with Anitta"), YES, @"- with guest");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y", @"Song [ft Y]"), YES, @"[ft guest]");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y", @"Song (Featuring Y)"), YES, @"(Featuring guest)");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y, Z", @"Song (feat. Y, Z)"), YES, @"two guests named the same way");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Tyler, The Creator", @"Song (feat. Tyler, The Creator)"), YES,
              @"a comma inside one guest's name");
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"The Weeknd, Justice", @"Wake Me Up"), NO, @"a guest the title does not name");
        check(SGRCreditRepeatsAlbum(@"The Weeknd", @"The Weeknd, Justice", @"Wake Me Up Justice"), NO,
              @"a guest named with no marker");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Anne", @"Song (feat. Ann)"), NO, @"Ann is not Anne");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y", @"Song (feat. Z)"), NO, @"a different guest");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y, Z", @"Song (feat. Z, Y)"), NO, @"guests in another order");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y, Z", @"Song (feat. Y & Z)"), NO, @"& against ,");
        check(SGRCreditRepeatsAlbum(@"X", @"X, Y", @"Song (feat. Y) [Remastered]"), NO, @"the marker not at the end");
        check(SGRCreditRepeatsAlbum(@"X", @"X & Y", @"Song"), NO, @"another separator");
        check(SGRCreditRepeatsAlbum(@"Various Artists", @"Adele", @"Hello"), NO, @"a compilation");
        check(SGRCreditRepeatsAlbum(nil, @"Adele", @"Hello"), NO, @"no header artist yet");
        check(SGRCreditRepeatsAlbum(@"Adele", @"", @"Hello"), NO, @"no row artist");
        check(SGRCreditRepeatsAlbum(@"X", @"X, ", @"Song (feat. )"), NO, @"an empty guest");
    }
    printf("%d failed\n", failures);
    return failures;
}
