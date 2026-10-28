// Checks Clean shared links (Shared/Privacy/CleanLinks.m) on the Mac: the links Spotify copies, the tracking
// taken off them and everything else left as it came.
//
//     ./build.sh && build/clean-links-check
//
// Every line prints ok or FAIL; the exit status is the number of failures.
#import <Foundation/Foundation.h>
#import "Privacy.h"

static int failures;

static void check(NSString *got, NSString *wanted, NSString *what) {
    BOOL ok = [got isEqualToString:wanted];
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) printf("     got    %s\n     wanted %s\n", got.UTF8String, wanted.UTF8String);
    failures += !ok;
}

static NSString *url(NSString *link) {
    return SGCleanLinkURL([NSURL URLWithString:link]).absoluteString;
}

int main(void) {
    @autoreleasepool {
        NSString *track = @"https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC";
        check(url([track stringByAppendingString:@"?si=a1b2c3"]), track, @"si alone goes, and the ? with it");
        check(url([track stringByAppendingString:@"?si=a1b2c3&utm_source=copy-link&utm_medium=x"]), track,
              @"si and utm_* go");
        check(url([track stringByAppendingString:@"?SI=a1&UTM_Campaign=x&nd=1&pt=abc&context=spotify%3Aplaylist%3Ax"]), track,
              @"names compared without case; nd, pt and context go");
        check(url(@"https://open.spotify.com/episode/abc?si=x&t=30"), @"https://open.spotify.com/episode/abc?t=30",
              @"t stays");
        check(url(@"https://open.spotify.com/episode/abc?t=30&go=1&si=x"), @"https://open.spotify.com/episode/abc?t=30&go=1",
              @"what stays keeps its order");
        check(url(@"https://open.spotify.com/intl-de/album/abc?si=x#frag"), @"https://open.spotify.com/intl-de/album/abc#frag",
              @"intl-xx/ path and the fragment stay");
        check(url(@"https://OPEN.Spotify.com/track/abc?si=x"), @"https://OPEN.Spotify.com/track/abc",
              @"host compared without case");
        check(url(@"https://example.com/track/abc?si=x"), @"https://example.com/track/abc?si=x", @"another host is left alone");
        check(url(@"https://spotify.link/abc?si=x"), @"https://spotify.link/abc?si=x", @"a spotify.link short link is left alone");
        check(url(@"https://open.spotify.com/track/abc?q=a%26b&si=x"), @"https://open.spotify.com/track/abc?q=a%26b",
              @"a kept value stays encoded as it came");
        check(url(@"mailto:a@b.c?si=x"), @"mailto:a@b.c?si=x", @"a link with no host is left alone");
        check(url(@"/track/abc?si=x"), @"/track/abc?si=x", @"a relative link is left alone");
        check(url(@"https://open.spotify.com/track/abc"), @"https://open.spotify.com/track/abc", @"nothing to take off");

        check(SGCleanLinksInText(@"spotify:track:abc"), @"spotify:track:abc", @"a spotify: URI is left alone");
        check(SGCleanLinksInText(@"just words"), @"just words", @"text with no link is left alone");
        check(SGCleanLinksInText([track stringByAppendingString:@"?si=abc"]), track, @"a string that is a link");
        check(SGCleanLinksInText(@"Listen: https://open.spotify.com/track/a?si=1&utm_source=copy-link and "
                                 @"https://open.spotify.com/album/b?si=2&t=5."),
              @"Listen: https://open.spotify.com/track/a and https://open.spotify.com/album/b?t=5.",
              @"two links in a sentence, the full stop after the last kept");
        check(SGCleanLinksInText(@"(https://open.spotify.com/track/a?si=1)"), @"(https://open.spotify.com/track/a)",
              @"a closing bracket after a link is kept");
        check(SGCleanLinksInText(@"https://example.com/x?si=1 https://open.spotify.com/track/a?si=1"),
              @"https://example.com/x?si=1 https://open.spotify.com/track/a", @"only the Spotify link of two is cleaned");
        check(SGCleanLinksInText(@"Écoute ça 🎧 https://open.spotify.com/track/a?si=1 👍"),
              @"Écoute ça 🎧 https://open.spotify.com/track/a 👍", @"text around the link keeps its characters");

        NSURL *object = SGCleanLinkObject([NSURL URLWithString:@"https://open.spotify.com/track/a?si=1"]);
        check([object isKindOfClass:NSURL.class] ? object.absoluteString : @"not a URL", @"https://open.spotify.com/track/a",
              @"an NSURL comes back an NSURL");
        NSData *bytes = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
        check(SGCleanLinkObject(bytes) == bytes ? @"same" : @"changed", @"same", @"anything else comes back as it is");
    }
    printf("%d failed\n", failures);
    return failures;
}
