// Checks the corrections remembered per output (AutoEq.m) on the Mac, through the real settings: what a route
// change to each kind of output does to the Graphic EQ, with AVAudioSession's part played by direct calls.
//
//     ./build.sh route && build/route-check
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

// The engine is not here.
void SGDSPApply(NSString *effect) {
}

static void clearDefaults(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSString *key in store.dictionaryRepresentation) {
        if ([key hasPrefix:@"spotifyglass."]) [store removeObjectForKey:key];
    }
}

static NSString *const kAirPods = @"AA-BB-tacl", *const kSony = @"CC-DD-tacl", *const kSpeaker = @"Speaker";
static NSString *const kLine = @"GraphicEQ: 20 -1.0; 1000 0.0; 20000 2.0";
static NSString *const kSonyLine = @"GraphicEQ: 20 3.0; 1000 0.0; 20000 -2.0";

// What the Graphic EQ plays: the headphone's folder, or "" for nothing; "off" when its switch is off.
static NSString *playing(void) {
    if (!SGDSPSwitch(SGKeyDSPGraphicEq)) return @"off";
    return SGDSPString(SGKeyDSPGraphicEqHeadphone);
}

int main(void) {
    @autoreleasepool {
        clearDefaults();

        // Launch on the speaker: nothing remembered, nothing changes.
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], @"launch on the speaker: the Graphic EQ stays off");

        // AirPods connect, the user picks a correction and turns Use for AirPods on.
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGAutoEqApplyText(@"crinacle/AirPods%20Pro", kLine);
        check(!SGAutoEqOutputRemembered(kAirPods), @"a pick alone remembers nothing");
        SGAutoEqRememberOutput(YES);
        check(SGAutoEqOutputRemembered(kAirPods), @"Use for AirPods Pro remembers it");
        check(SGDSPSwitch(SGKeyDSP), @"the pick turned Audio effects on");

        // Back to the speaker: the AirPods' correction goes off.
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"off"], [NSString stringWithFormat:@"speaker: the AirPods' correction is off (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqHeadphone) isEqualToString:@""], @"speaker: no headphone named");

        // AirPods again: their correction comes back, nodes and all, with no download.
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 20 0.0");
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], [NSString stringWithFormat:@"AirPods again: their correction is on (%@)", playing()]);
        check([SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kLine], @"AirPods again: their own curve");

        // The same output again (a category change, not a new route): nothing happens.
        SGDSPSetSwitch(SGKeyDSPGraphicEq, NO);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"off"], @"the same output again changes nothing");
        SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);

        // Another pair, remembered with its own correction, then the AirPods: each gets its own.
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"a new pair with nothing remembered: the AirPods' correction goes off");
        SGAutoEqRememberOutput(YES);
        SGAutoEqApplyText(@"oratory1990/Sony%20WH-1000XM5", kSonyLine);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods: theirs");
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"oratory1990/Sony%20WH-1000XM5"] && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:kSonyLine],
              @"Sony: its own pick, not the AirPods'");

        // None remembered for the Sony: a pick of None on it sticks.
        SGAutoEqTakeOff();
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"off"], @"None picked for the Sony stays None for it");

        // A correction picked on the speaker, with nothing remembered there, is the user's: it stays everywhere.
        SGAutoEqForgetOutput(kSony);
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        SGAutoEqApplyText(@"someone/Speaker%20Fix", kLine);
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        check([playing() isEqualToString:@"someone/Speaker%20Fix"], @"a pick made with nothing remembered is not taken off");

        // A curve of the user's own is never taken off by a route change.
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        SGDSPSetString(SGKeyDSPGraphicEqNodes, @"GraphicEQ: 100 6.0");
        SGDSPSetString(SGKeyDSPGraphicEqHeadphone, @"");
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check(SGDSPSwitch(SGKeyDSPGraphicEq) && [SGDSPString(SGKeyDSPGraphicEqNodes) isEqualToString:@"GraphicEQ: 100 6.0"],
              @"a hand-made curve stays on the speaker");

        // A route change never turns the effects on.
        SGDSPSetSwitch(SGKeyDSP, NO);
        SGAutoEqOutputChanged(kAirPods, @"AirPods Pro");
        check(!SGDSPSwitch(SGKeyDSP) && [playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"AirPods with Audio effects off: correction set, effects left off");

        // Forgetting the AirPods: listed no more, and their correction stays until the next change.
        NSUInteger before = SGAutoEqRememberedOutputs().count;
        SGAutoEqRememberOutput(NO);
        check(!SGAutoEqOutputRemembered(kAirPods) && SGAutoEqRememberedOutputs().count == before - 1, @"Use for AirPods Pro off forgets them");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"forgetting leaves what plays");
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        check([playing() isEqualToString:@"crinacle/AirPods%20Pro"], @"once forgotten, the speaker keeps it: it is a plain pick now");

        // A renamed output keeps its pick under its new name.
        SGAutoEqOutputChanged(kSony, @"WH-1000XM5");
        SGAutoEqRememberOutput(YES);
        SGAutoEqOutputChanged(kSpeaker, @"Speaker");
        SGAutoEqOutputChanged(kSony, @"Sony at work");
        check([SGAutoEqRememberedOutputs().firstObject[@"name"] isEqualToString:@"Sony at work"], @"a renamed output is listed by its new name");

        clearDefaults();
        printf("%d failed\n", failures);
    }
    return failures;
}
