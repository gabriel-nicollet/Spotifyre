// Checks Presets and Headphones (Shared/AudioEffects/AudioEffectsPresets.h) on the Mac: INDEX.md's parsing on
// lines written to be awkward, the raw addresses made from them, search, the built-in and saved presets
// through the real settings, and, with `online`, AutoEq's real index fetched, cached and one headphone applied.
//
//     ./build.sh && build/autoeq-check [online]
//
// Every line prints ok or FAIL; the exit status is the number of failures. The settings live in the check's
// own defaults domain, cleared before and after.
#import <Foundation/Foundation.h>
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    failures += !ok;
}

// The engine is not here: what it was handed is counted instead.
static NSCountedSet<NSString *> *applied;
void SGDSPApply(NSString *effect) {
    [applied addObject:effect];
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

// Runs the main queue until `done` says so, the way the app's run loop would.
static void waitFor(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done() && limit.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

static void checkParsing(void) {
    NSString *index =
        @"# Index\n"
        @"This is a list of all equalization profiles. Target is in parentheses if there are results with multiple targets\n"
        @"from the same source.\n\n"
        @"- [1Custom SA02](./crinacle/711%20in-ear/1Custom%20SA02) by crinacle on 711\n"
        @"- [1MORE Aero (ANC Off)](./HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)) by HypetheSonics on GRAS RA0045\n"
        @"- [Sennheiser HD 600](./oratory1990/over-ear/Sennheiser%20HD%20600) by oratory1990\n"
        @"- [AKG K371 [Harman] (Bass)](./Rtings/over-ear/AKG%20K371%20(Bass)) by Rtings\n"
        @"- [Sennheiser HD 600](./crinacle/GRAS%2043AG-7%20over-ear/Sennheiser%20HD%20600) by crinacle on GRAS 43AG-7\n"
        @"- [Sony WH-1000XM4 & $50 tips](./Super%20Review/over-ear/Sony%20WH-1000XM4%20&%20$50%20tips) by Super Review\n"
        @"- not a link\n"
        @"- [Broken](./no/closing by nobody\n";
    NSArray<SGAutoEqHeadphone *> *all = SGAutoEqParseIndex(index);
    check(all.count == 6, [NSString stringWithFormat:@"6 headphones parsed, the heading and the broken lines skipped (%lu)", (unsigned long)all.count]);
    if (all.count < 6) return;
    check([all[1].name isEqualToString:@"1MORE Aero (ANC Off)"] && [all[1].path isEqualToString:@"HypetheSonics/GRAS%20RA0045%20in-ear/1MORE%20Aero%20(ANC%20Off)"]
          && [all[1].source isEqualToString:@"HypetheSonics on GRAS RA0045"], @"parentheses in the name and the folder");
    check([all[3].name isEqualToString:@"AKG K371 [Harman] (Bass)"] && [all[3].path isEqualToString:@"Rtings/over-ear/AKG%20K371%20(Bass)"],
          @"brackets in the name");
    check([SGAutoEqGraphicEqURL(all[2].path).absoluteString isEqualToString:
           @"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/oratory1990/over-ear/Sennheiser%20HD%20600/Sennheiser%20HD%20600%20GraphicEQ.txt"],
          @"the raw address of a GraphicEQ file");
    NSString *aero = SGAutoEqGraphicEqURL(all[1].path).absoluteString;
    check([aero hasSuffix:@"/1MORE%20Aero%20(ANC%20Off)/1MORE%20Aero%20(ANC%20Off)%20GraphicEQ.txt"], aero);
    NSString *sony = SGAutoEqGraphicEqURL(all[5].path).absoluteString;
    check([sony hasSuffix:@"/Sony%20WH-1000XM4%20&%20$50%20tips%20GraphicEQ.txt"] && [NSURL URLWithString:sony], sony);
    check([SGAutoEqNameOf(all[2].path) isEqualToString:@"Sennheiser HD 600"], @"a folder's name for the page's row");

    check(SGAutoEqSearch(all, @"hd 600").count == 2, @"search: two HD 600s");
    check(SGAutoEqSearch(all, @"  HD600 ").count == 0, @"search: words, not a squashed name");
    check(SGAutoEqSearch(all, @"600 ORATORY").count == 1, @"search: any order, any case, the source too");
    check(SGAutoEqSearch(all, @"").count == 6, @"search: empty shows all");
}

static void checkPresets(void) {
    clearDefaults();
    NSString *line = SGDSPGraphicEqLine(@"  GraphicEQ: 20 -1.2;\n 21 -1.1;\n\n");
    check([line isEqualToString:@"GraphicEQ: 20 -1.2; 21 -1.1;"], @"a GraphicEQ file's text onto one line");
    check(SGDSPGraphicEqLine(@"Preamp: -6 dB") == nil, @"other text is not a GraphicEQ line");

    // A headphone's correction in place, and other effects on.
    check(SGAutoEqApplyText(@"oratory1990/over-ear/Sennheiser%20HD%20600", @"GraphicEQ: 20 -1.2; 21 -1.1;\n"), @"a GraphicEQ file applied");
    check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 20 -1.2; 21 -1.1;"]
          && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@"oratory1990/over-ear/Sennheiser%20HD%20600"],
          @"the Graphic EQ on, with the nodes and the headphone");
    check([applied countForObject:SGKeyDSPGraphicEq] > 0, @"the Graphic EQ handed to the engine");
    check(SGDSPSwitch(SGKeyDSP) && [applied countForObject:SGKeyDSP] > 0, @"the effects' master switch on with the headphone");
    check(!SGAutoEqApplyText(@"a/b", @"<html>404</html>"), @"a page that is not GraphicEQ is refused");
    SGDSPSetSwitch(SGKeyDSPTube, YES);
    SGDSPSetSwitch(SGKeyDSP, NO);

    NSArray<NSString *> *names = SGDSPBuiltInPresetNames();
    check(names.count >= 4 && [names containsObject:@"Concert hall"] && [names containsObject:@"Late night"], @"built-in presets");
    for (NSUInteger i = 0; i < names.count; i++) check(SGDSPBuiltInPresetDetail((NSInteger)i).length > 0, [@"a detail for " stringByAppendingString:names[i]]);

    SGDSPLoadBuiltInPreset((NSInteger)[names indexOfObject:@"Bass boost"]);
    check(SGDSPSwitch(SGKeyDSPBass) && SGDSPNumber(SGKeyDSPBassGain) == 8, @"Bass boost: bass on at 8 dB");
    check(!SGDSPSwitch(SGKeyDSPTube), @"Bass boost: the tube, on before, off");
    check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) hasPrefix:@"GraphicEQ: 20 -1.2"]
          && SGDSPString(SGKeyDSPGraphicEqHeadphone).length, @"Bass boost: the headphone's correction kept");
    check(SGDSPSwitch(SGKeyDSP), @"Bass boost: the master switch on with it");

    SGDSPLoadBuiltInPreset((NSInteger)[names indexOfObject:@"Vocal clarity"]);
    check(SGDSPSwitch(SGKeyDSPEqualizer) && [SGDSPGains(SGKeyDSPEqualizerGains) isEqualToArray:SGDSPEqualizerPreset(4)]
          && !SGDSPSwitch(SGKeyDSPBass), @"Vocal clarity: the equalizer's Vocal curve, bass off");
    SGDSPLoadBuiltInPreset((NSInteger)[names indexOfObject:@"Concert hall"]);
    check(SGDSPSwitch(SGKeyDSPReverb) && SGDSPNumber(SGKeyDSPReverbPreset) == 7
          && [SGDSPReverbPresetNames()[7] isEqualToString:@"Large hall"], @"Concert hall: the Large hall reverb");
    // The user's own: everything, the Graphic EQ too.
    SGDSPLoadBuiltInPreset((NSInteger)[names indexOfObject:@"Late night"]);
    NSArray<NSNumber *> *eq = SGDSPGains(SGKeyDSPEqualizerGains);
    SGDSPSetNumber(SGKeyDSPPostGain, 2.5);
    SGDSPSaveUserPreset(@"Mine");
    SGDSPSaveUserPreset(@"another");
    check([SGDSPUserPresetNames() isEqualToArray:(@[@"another", @"Mine"])], @"saved presets listed by name");
    SGDSPResetAll();
    SGDSPSetSwitch(SGKeyDSP, NO);
    SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 1000 3;");
    check(SGDSPLoadUserPreset(@"Mine"), @"a saved preset loads");
    check(SGDSPSwitch(SGKeyDSP), @"the master switch on with it");
    check(SGDSPSwitch(SGKeyDSPCompander) && [SGDSPGains(SGKeyDSPEqualizerGains) isEqualToArray:eq] && SGDSPNumber(SGKeyDSPPostGain) == 2.5,
          @"its effects and values back");
    check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) hasPrefix:@"GraphicEQ: 20 -1.2"]
          && SGDSPString(SGKeyDSPGraphicEqHeadphone).length, @"its Graphic EQ back");
    check(![[NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPUserPresets][@"Mine"] objectForKey:SGKeyDSP],
          @"the master switch not in it");
    check(!SGDSPLoadUserPreset(@"nobody's"), @"an unknown name loads nothing");
    SGDSPDeleteUserPreset(@"another");
    check([SGDSPUserPresetNames() isEqualToArray:@[@"Mine"]], @"a preset deleted");
}

static void checkOnline(void) {
    clearDefaults();
    __block NSArray<SGAutoEqHeadphone *> *all;
    __block NSString *error;
    __block BOOL done = NO;
    SGAutoEqLoadIndex(YES, ^(NSArray<SGAutoEqHeadphone *> *headphones, NSString *why) {
        all = headphones, error = why, done = YES;
    });
    waitFor(^BOOL { return done; });
    check(all.count > 5000 && !error, [NSString stringWithFormat:@"AutoEq's index fetched: %lu headphones (%@)", (unsigned long)all.count, error ?: @"no error"]);
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *cache = [caches URLByAppendingPathComponent:@"Vitrine/AutoEq/INDEX.md"].path;
    check([NSFileManager.defaultManager fileExistsAtPath:cache], @"and cached");

    done = NO;
    __block NSArray<SGAutoEqHeadphone *> *cached;
    SGAutoEqLoadIndex(NO, ^(NSArray<SGAutoEqHeadphone *> *headphones, NSString *why) {
        cached = headphones, done = YES;
    });
    waitFor(^BOOL { return done; });
    check(cached.count == all.count, @"read back from the cache");

    NSArray<SGAutoEqHeadphone *> *found = SGAutoEqSearch(all, @"Sennheiser HD 600 oratory1990");
    check(found.count == 1, [NSString stringWithFormat:@"search: Sennheiser HD 600 by oratory1990 (%lu)", (unsigned long)found.count]);
    if (!found.count) return;
    done = NO;
    error = nil;
    SGAutoEqApply(found[0], ^(NSString *why) {
        error = why, done = YES;
    });
    waitFor(^BOOL { return done; });
    NSString *nodes = SGDSPString(SGKeyDSPGraphicEqNodes);
    check(!error && SGDSPSwitch(SGKeyDSPGraphicEq) && [nodes hasPrefix:@"GraphicEQ: 20 "] && [nodes componentsSeparatedByString:@";"].count > 100
          && [SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:found[0].path],
          [NSString stringWithFormat:@"HD 600's GraphicEQ downloaded and applied (%@, %lu points)", error ?: @"no error",
           (unsigned long)[nodes componentsSeparatedByString:@";"].count - 1]);

    // Spot-check the rest of the index: each GraphicEQ file is where the address says.
    NSUInteger reached = 0, tried = 0;
    for (NSUInteger i = 0; i < all.count; i += all.count / 12) {
        tried++;
        NSURL *url = SGAutoEqGraphicEqURL(all[i].path);
        NSData *data = [NSData dataWithContentsOfURL:url];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (SGDSPGraphicEqLine(text)) reached++;
        else printf("     missing: %s\n", url.absoluteString.UTF8String);
    }
    check(reached == tried, [NSString stringWithFormat:@"%lu of %lu headphones across the index have their GraphicEQ file", (unsigned long)reached, (unsigned long)tried]);
    [NSFileManager.defaultManager removeItemAtPath:cache error:nil];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        applied = [NSCountedSet set];
        checkParsing();
        checkPresets();
        if (argc > 1 && !strcmp(argv[1], "online")) checkOnline();
        clearDefaults();
        printf("%d failed\n", failures);
    }
    return failures;
}
