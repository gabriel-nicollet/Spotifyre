#import <os/lock.h>
#import "SGFlagForce.h"
#import "SGLog.h"
#import "SGPrefs.h"

@interface SGFlagForcerEntry : NSObject
@property (nonatomic) BOOL beatsOverride;
@property (nonatomic, copy) SGFlagForcer atLaunch, locked;
@end

@implementation SGFlagForcerEntry
@end

// Swapped whole under the lock, so a reader walks an immutable array.
static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;
static NSArray<SGFlagForcerEntry *> *sg_forcers;

void SGRegisterFlagForcer(BOOL beatsOverride, SGFlagForcer atLaunch, SGFlagForcer locked) {
    if (!atLaunch) return;
    SGFlagForcerEntry *entry = [SGFlagForcerEntry new];
    entry.beatsOverride = beatsOverride;
    entry.atLaunch = atLaunch;
    entry.locked = locked;
    os_unfair_lock_lock(&sg_lock);
    sg_forcers = [(sg_forcers ?: @[]) arrayByAddingObject:entry];
    os_unfair_lock_unlock(&sg_lock);
}

static NSArray<SGFlagForcerEntry *> *forcers(void) {
    os_unfair_lock_lock(&sg_lock);
    NSArray *list = sg_forcers;
    os_unfair_lock_unlock(&sg_lock);
    return list;
}

// The All flags overrides as they were at launch, the prefix taken off: Spotify asks for its flags
// once each, many as it starts, and one dictionary read from these costs a fraction of a defaults lookup each
// (harness/launch). An override set later shows after a restart, as every flag does.
static NSDictionary<NSString *, id> *overridesAtLaunch(void) {
    static NSDictionary<NSString *, id> *overrides;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, id> *found = [NSMutableDictionary dictionary];
        [NSUserDefaults.standardUserDefaults.dictionaryRepresentation enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if ([key hasPrefix:SGFlagOverridePrefix]) found[[key substringFromIndex:SGFlagOverridePrefix.length]] = value;
        }];
        overrides = [found copy];
    });
    return overrides;
}

// The overrides Spotify has asked for, with the answer it got. Only an override's key takes the lock,
// so the reads of every other flag cost what they did.
static os_unfair_lock sg_askedLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, id> *sg_asked;
static BOOL sg_reported;

static void noteAsked(NSString *key, id override, id answer) {
    os_unfair_lock_lock(&sg_askedLock);
    BOOL first = !sg_asked[key];
    if (first) {
        if (!sg_asked) sg_asked = [NSMutableDictionary dictionary];
        sg_asked[[key copy]] = answer;
    }
    BOOL late = first && sg_reported;
    os_unfair_lock_unlock(&sg_askedLock);
    if (!late) return;
    if ([answer isEqual:override]) SGLog(@"flags: Spotify asked for %@ only now, and got the override %@", key, answer);
    else SGLog(@"flags: Spotify asked for %@ only now, and got %@ from another switch, not the override %@", key, answer, override);
}

id SGForcedFlagValue(NSString *key) {
    if (!key) return nil;
    NSArray<SGFlagForcerEntry *> *list = forcers();
    id value = nil;
    for (SGFlagForcerEntry *entry in list) {
        if (!entry.beatsOverride) continue;
        value = entry.atLaunch(key);
        if (value) break;
    }
    id override = overridesAtLaunch()[key];
    if (override) noteAsked(key, override, value ?: override);
    if (value) return value;
    if (override) return override;
    for (SGFlagForcerEntry *entry in list) {
        if (entry.beatsOverride) continue;
        value = entry.atLaunch(key);
        if (value) return value;
    }
    return nil;
}

id SGLockedFlagValue(NSString *key, BOOL *beatsOverride) {
    if (beatsOverride) *beatsOverride = NO;
    if (!key) return nil;
    NSArray<SGFlagForcerEntry *> *list = forcers();
    for (int pass = 0; pass < 2; pass++) {
        BOOL first = pass == 0;
        for (SGFlagForcerEntry *entry in list) {
            if (entry.beatsOverride != first || !entry.locked) continue;
            id value = entry.locked(key);
            if (!value) continue;
            if (beatsOverride) *beatsOverride = first;
            return value;
        }
    }
    return nil;
}

NSString *SGFlagOverrideReport(void) {
    NSDictionary<NSString *, id> *overrides = overridesAtLaunch();
    os_unfair_lock_lock(&sg_askedLock);
    NSDictionary<NSString *, id> *asked = [sg_asked copy];
    sg_reported = YES;
    os_unfair_lock_unlock(&sg_askedLock);
    NSUInteger forced = 0;
    NSMutableArray<NSString *> *beaten = [NSMutableArray array], *notAsked = [NSMutableArray array];
    for (NSString *key in [overrides.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        id answer = asked[key];
        if (!answer) [notAsked addObject:key];
        else if ([answer isEqual:overrides[key]]) forced++;
        else [beaten addObject:[NSString stringWithFormat:@"%@ (%@, not %@)", key, answer, overrides[key]]];
    }
    NSMutableString *text = [NSMutableString stringWithFormat:@"%lu overrides stored, %lu asked for and forced",
                             (unsigned long)overrides.count, (unsigned long)forced];
    if (beaten.count) [text appendFormat:@", %lu answered by another switch: %@", (unsigned long)beaten.count, [beaten componentsJoinedByString:@", "]];
    [text appendFormat:@", %lu not asked for yet", (unsigned long)notAsked.count];
    if (notAsked.count) [text appendFormat:@": %@", [notAsked componentsJoinedByString:@", "]];
    return text;
}
