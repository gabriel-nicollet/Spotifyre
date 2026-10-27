// Privacy: telemetry blocking (Privacy.x), an NSURLProtocol that answers the analytics endpoints
// itself and counts what it stopped, and clean shared links. Both on unless switched off.
#import <UIKit/UIKit.h>

#define SGKeyBlockTelemetry @"spotifyglass.blockTelemetry"

// Clean shared links (CleanLinks.m, CleanLinks.x): the tracking parameters taken off the open.spotify.com links
// the app copies and shares. On unless switched off, read on each copy.
#define SGKeyCleanLinks @"spotifyglass.cleanSharedLinks"
// The link without si, nd, pt, context and utm_*, or `url` itself when it is not an open.spotify.com link,
// does not parse, or has none of them.
NSURL *SGCleanLinkURL(NSURL *url);
// `text` with every open.spotify.com link in it cleaned in place, or `text` itself when there was nothing to clean.
NSString *SGCleanLinksInText(NSString *text);
// Either of the two by the object's class; anything else comes back as it is.
id SGCleanLinkObject(id object);

// The destinations it knows in the order it lists them, and how many requests to one of them it
// has answered instead of letting out (nil label for all of them).
NSArray<NSString *> *SGBlockedLabels(void);
NSUInteger SGBlockedCount(NSString *label);
void SGResetBlocked(void);

@class SGModSection;
// The telemetry and shared links switches and what the telemetry blocking has stopped, on the
// Premium, ads & privacy page.
SGModSection *SGPrivacySection(void);
SGModSection *SGPrivacyCountersSection(void);
