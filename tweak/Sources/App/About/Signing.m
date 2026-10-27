// Whether the lock screen can open this build at all. MediaRemote launches the now playing app by
// the App ID in its application-identifier entitlement, not by CFBundleIdentifier, so a build signed
// under a profile whose App ID is not the bundle id installs and plays but cannot be opened from the
// now playing card: iOS asks for a bundle that is not installed and offers the App Store instead.
// The signature decides this and nothing in the app can change it, so all the mod does is say so --
// once on the first launch under a signature, and from a red row at the top of Mod Settings for as
// long as it lasts. Both land on the same sheet, which names the bundle id to sign under and copies
// it, because that one string is the whole fix.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import <dlfcn.h>


static NSString *const kWarned = @"spotifyglass.signing.warned";
static BOOL sg_fixPending;

// SecTaskCopyValueForEntitlement is not in the iOS SDK, so it is resolved at runtime like the rest
// of the private API the mod uses. A build that cannot read its own entitlement stays quiet.
NSString *SGSigningAppIdentifier(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (!security) return;
        CFTypeRef (*createFromSelf)(CFAllocatorRef) = dlsym(security, "SecTaskCreateFromSelf");
        CFTypeRef (*copyValue)(CFTypeRef, CFStringRef, CFErrorRef *) = dlsym(security, "SecTaskCopyValueForEntitlement");
        if (!createFromSelf || !copyValue) return;
        CFTypeRef task = createFromSelf(NULL);
        if (!task) return;
        CFTypeRef value = copyValue(task, CFSTR("application-identifier"), NULL);
        CFRelease(task);
        if (!value) return;
        if (CFGetTypeID(value) == CFStringGetTypeID()) {
            NSString *identifier = (__bridge NSString *)value;
            NSRange dot = [identifier rangeOfString:@"."];   // drop the team prefix
            cached = dot.location == NSNotFound ? [identifier copy]
                                               : [identifier substringFromIndex:dot.location + 1];
        }
        CFRelease(value);
    });
    return cached;
}

// Unreadable counts as fine: a guess here would cry wolf at a build that works.
BOOL SGSigningOpensFromLockScreen(void) {
    NSString *appID = SGSigningAppIdentifier();
    return !appID || [appID isEqualToString:NSBundle.mainBundle.bundleIdentifier];
}

// The fix is one string, so the sheet leads with it and Copy is the first action: whoever reads this
// is on their way back to Feather to paste it into the identifier field.
static void showFix(void) {
    NSString *appID = SGSigningAppIdentifier();
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"?";
    UIViewController *top = SGTopController();
    if (!appID || !top) return;
    NSString *message = [NSString stringWithFormat:
        @"Sign Spotify again with the bundle id set to\n\n%@\n\n"
        @"In Feather that is the Identifier field; leave PPQ protection off, it appends a random "
        @"string and breaks this again.\n\n"
        @"Why: this build is installed as %@ but signed under the App ID %@. iOS opens the now "
        @"playing card by the App ID, so it asks for an app that is not there. Nothing else in the "
        @"mod is affected.", appID, bundleID, appID];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"The lock screen cannot open Spotify"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy the bundle id" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = appID;
    }]];
    if (SGRepoURL) [sheet addAction:[UIAlertAction actionWithTitle:@"Read more" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGOpenURL([SGRepoURL stringByAppendingString:@"#signing"]);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:YES completion:nil];
}

// nil while the signature is sound, which is what keeps the row out of Mod Settings entirely.
SGModRow *SGSigningWarningRow(void) {
    if (SGSigningOpensFromLockScreen()) return nil;
    return SGWarningRow(@"The lock screen cannot open Spotify",
                        @"Tap for the fix",
                        ^{ showFix(); });
}

// Said once per signature: re-signing under a different App ID is a new mistake and says so again,
// but a build that is simply left broken does not nag on every launch. The row stays either way.
void SGCheckSigningOnce(void) {
    if (SGSigningOpensFromLockScreen()) return;
    NSString *appID = SGSigningAppIdentifier();
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGLog(@"signing: installed as %@ but signed under %@; the now playing card cannot open this build",
          NSBundle.mainBundle.bundleIdentifier, appID);
    if ([[store stringForKey:kWarned] isEqualToString:appID]) return;
    [store setObject:appID forKey:kWarned];

    // The first activation, plus a moment for Spotify's own start-up screens to get out of the way.
    __block id token = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                                      object:nil
                                                                       queue:nil
                                                                  usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:token];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // The welcome tour has the screen; it shows the fix when it goes.
            if (SGOnboardingShowing()) sg_fixPending = YES;
            else showFix();
        });
    }];
}

#pragma mark - when the signature runs out

// embedded.mobileprovision is a CMS envelope around a plain XML plist, so the plist is cut out by its
// first "<?xml" and its last "</plist>" rather than taken through a CMS decoder. No profile is a build
// installed without one (TrollStore, a jailbreak), which never runs out.
static NSDictionary *profile(void) {
    static NSDictionary *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
        NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
        if (!data) return;
        NSData *open = [@"<?xml" dataUsingEncoding:NSUTF8StringEncoding], *close = [@"</plist>" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange start = [data rangeOfData:open options:0 range:NSMakeRange(0, data.length)];
        NSRange end = [data rangeOfData:close options:NSDataSearchBackwards range:NSMakeRange(0, data.length)];
        if (start.location == NSNotFound || end.location == NSNotFound || NSMaxRange(end) <= start.location) return;
        NSData *plist = [data subdataWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)];
        id parsed = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:NULL];
        if ([parsed isKindOfClass:NSDictionary.class]) cached = parsed;
    });
    return cached;
}

static NSDate *dateIn(NSString *key) {
    id date = profile()[key];
    return [date isKindOfClass:NSDate.class] ? date : nil;
}

static NSDate *expiry(void) {
    return dateIn(@"ExpirationDate");
}

// A free Apple ID's profile lasts seven days, a paid account's up to a year; a day over a week allows
// for the clock the profile was cut by.
BOOL SGSigningWeekLong(void) {
    NSDate *created = dateIn(@"CreationDate"), *expires = expiry();
    return created && expires && [expires timeIntervalSinceDate:created] < 8 * 24 * 60 * 60;
}

// The row's value has little room, so it is the day; a week-long profile, which runs out at an hour of
// a day this week, gives the hour under the title.
SGModRow *SGSigningExpiryRow(void) {
    NSDate *expires = expiry();
    if (!expires) return nil;
    BOOL week = SGSigningWeekLong();
    NSDateFormatter *day = [NSDateFormatter new];
    if (week) [day setLocalizedDateFormatFromTemplate:@"EEEMMMd"];   // "Mon, Oct 12"
    else day.dateStyle = NSDateFormatterMediumStyle;                 // "Oct 6, 2027"
    NSString *value = [day stringFromDate:expires];
    SGModRow *row = SGStatRow(@"Signed until", ^NSString *{ return value; });
    if (week) row.subtitle = [NSString stringWithFormat:@"At %@. A free Apple ID signs for 7 days.",
                              [NSDateFormatter localizedStringFromDate:expires dateStyle:NSDateFormatterNoStyle
                                                             timeStyle:NSDateFormatterShortStyle]];
    return row;
}

void SGShowSigningFixIfPending(void) {
    if (!sg_fixPending) return;
    sg_fixPending = NO;
    showFix();
}
