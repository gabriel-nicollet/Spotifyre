// The voice model's download (SGSingModel.m) as the tweak compiles it, run on the Mac against Hugging Face: what the
// old model's download left, stood in by files of their sizes, is deleted at launch; the four small files of
// separator-ane.mlmodelc and part of its weights come in, the download is stopped, and the next one carries the weights
// on from where the stop left them (a 206 from the server) through to the move into place.
//
//     ./build.sh && CFFIXED_USER_HOME=<empty dir> ../build/download [stop at, 0 to 1 of the weights]
//
// `update` starts from the old model (separator.mlmodelc, stood in by files of its sizes) instead: kept and used until
// the new one is downloaded, then deleted.
//
//     ./build.sh && CFFIXED_USER_HOME=<empty dir> ../build/download update
//
// `dev` checks the dev folder instead: used only with every file in it and only on a FLEX build (a FLEXManager class),
// the model then Ready without a download.
//
//     ./build.sh && CFFIXED_USER_HOME=<empty dir> ../build/download dev
//
// `light` chooses the light model (separator-light.mlmodelc) with the full one on the iPhone, downloads it, switches
// back and forth and removes each (checkLight).
//
//     ./build.sh && CFFIXED_USER_HOME=<empty dir> ../build/download light
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Shared/Sing/Sing.h"

static int failures;
#define CHECK(ok, ...) do { BOOL _ok = (ok); if (!_ok) failures++; printf("%s %s\n", _ok ? "PASS" : "FAIL", [NSString stringWithFormat:__VA_ARGS__].UTF8String); } while (0)

static void runUntil(BOOL (^done)(void), NSTimeInterval limit) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!done() && end.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
}

// Files of these sizes, sparse, at these paths under `folder`.
static void standIn(NSURL *folder, NSDictionary<NSString *, NSNumber *> *files) {
    for (NSString *path in files) {
        NSURL *file = [folder URLByAppendingPathComponent:path];
        [NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager createFileAtPath:file.path contents:nil attributes:nil];
        truncate(file.fileSystemRepresentation, files[path].longLongValue);
    }
}

static BOOL exists(NSURL *url) {
    return [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

// The dev folder: not loaded with a file missing (Core ML would crash on it), nor outside a FLEX build; on one it is
// the model, Ready without a download.
static int checkDev(NSURL *sing) {
    NSURL *dev = [[sing URLByAppendingPathComponent:@"dev"] URLByAppendingPathComponent:@"separator-ane.mlmodelc"];
    standIn(dev, @{@"metadata.json": @2333, @"coremldata.bin": @388, @"analytics/coremldata.bin": @243, @"model.mil": @1346642});
    CHECK(!SGSingModelURL() && SGSingModelCurrentState() == SGSingModelMissing, @"a dev copy missing weights/weight.bin is not loaded");
    standIn(dev, @{@"weights/weight.bin": @209077208});
    SGSingCancelModelDownload();   // nothing to stop: it has the folders looked at again
    CHECK(!SGSingModelURL(), @"a whole dev copy is not loaded outside a FLEX build");
    objc_registerClassPair(objc_allocateClassPair(NSObject.class, "FLEXManager", 0));
    SGSingCancelModelDownload();
    CHECK(SGSingModelCurrentState() == SGSingModelReady && [SGSingModelURL().path isEqualToString:dev.path],
          @"on a FLEX build it is the model, Ready without a download (%@)", SGSingModelURL().path);
    printf("%s\n", failures ? "FAILED" : "all passed");
    return failures ? 1 : 0;
}

// The old model on the iPhone, the new one not: the old one is kept, is the model Karaoke loads and reads as an update
// available; it stays so while the update downloads, and goes as soon as the update is in. A launch that finds both
// deletes the old one.
static int checkUpdate(NSURL *sing) {
    NSURL *old = [sing URLByAppendingPathComponent:@"separator.mlmodelc"];
    NSDictionary *oldFiles = @{@"metadata.json": @2431, @"coremldata.bin": @507, @"analytics/coremldata.bin": @243, @"model.mil": @669061,
                               @"weights/weight.bin": @488986336};
    standIn(old, oldFiles);
    SGSingRemoveOldModel();
    CHECK(exists(old), @"at launch, with the new model not in, the old one is kept");
    CHECK(SGSingModelCurrentState() == SGSingModelReady && [SGSingModelURL().path isEqualToString:old.path] && SGSingModelUpdateAvailable(),
          @"it is the model, Ready, and the download reads as its update (%@)", SGSingModelURL().lastPathComponent);
    CHECK(SGSingModelProgress() == 0 && SGSingModelPausedBytes() == 0, @"the update is not downloaded");
    printf("the model on the iPhone reads %s, its update %s\n", SGSingModelInUseSizeText().UTF8String, SGSingModelSizeText().UTF8String);

    SGSingDownloadModelOverCellular();
    __block BOOL readyThroughout = YES, sawUpdating = NO;
    runUntil(^BOOL {
        readyThroughout &= SGSingModelCurrentState() == SGSingModelReady;
        if (SGSingModelUpdateDownloading()) {
            sawUpdating = YES;
            readyThroughout &= [SGSingModelURL().path isEqualToString:old.path];
        }
        return !SGSingModelUpdateDownloading() && sawUpdating;
    }, 1800);
    CHECK(sawUpdating && readyThroughout, @"while the update downloads the old model stays the model, Ready");
    CHECK(!exists(old), @"the update in, the old model is deleted at once (%@)", SGSingModelError() ?: @"no error");
    CHECK(SGSingModelCurrentState() == SGSingModelReady && [SGSingModelURL().lastPathComponent isEqualToString:@"separator-ane.mlmodelc"] && !SGSingModelUpdateAvailable(),
          @"and the model is separator-ane.mlmodelc, no update left (%@)", SGSingModelURL().lastPathComponent);
    NSArray *left = [NSFileManager.defaultManager contentsOfDirectoryAtPath:sing.path error:nil];
    CHECK([left isEqualToArray:@[@"separator-ane.mlmodelc"]], @"nothing else in Sing/ (%@)", [left componentsJoinedByString:@", "]);

    standIn(old, oldFiles);
    SGSingRemoveOldModel();
    CHECK(!exists(old) && exists([sing URLByAppendingPathComponent:@"separator-ane.mlmodelc"]), @"a launch that finds both deletes the old one");
    printf("%s\n", failures ? "FAILED" : "all passed");
    return failures ? 1 : 0;
}

// Light chosen, with the full model and the old one on the iPhone (stood in by files of their sizes): the light model
// downloads from its own folder and is the model; the launch's cleanup leaves it alone; switching back and forth needs
// no download; removing the other model leaves the chosen one, and removing the chosen one leaves Sing/ empty.
static int checkLight(NSURL *sing) {
    NSURL *full = [sing URLByAppendingPathComponent:@"separator-ane.mlmodelc"], *light = [sing URLByAppendingPathComponent:@"separator-light.mlmodelc"];
    NSURL *old = [sing URLByAppendingPathComponent:@"separator.mlmodelc"];
    standIn(full, @{@"metadata.json": @2333, @"coremldata.bin": @388, @"analytics/coremldata.bin": @243, @"model.mil": @1346642,
                    @"weights/weight.bin": @209077208});
    standIn(old, @{@"model.mil": @669061});
    CHECK(SGSingChosenModel() == SGSingModelFull && [SGSingModelURL().path isEqualToString:full.path], @"the full model is the default");
    // The key changed another way (a settings import), with no generation bump: Light, not downloaded, is checked anyway.
    [NSUserDefaults.standardUserDefaults setInteger:SGSingModelLight forKey:SGKeySingModel];
    CHECK(!SGSingModelURL(), @"a key changed by another way is checked again: Light reads missing, not its folder unchecked (%@)", SGSingModelURL().path);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModel];
    CHECK([SGSingModelURL().path isEqualToString:full.path], @"and the full model again once the key goes back");

    // Light's download stopped by a switch and Light removed at once: the stop's resume data, written later, does not
    // bring a file of it back.
    SGSetSingChosenModel(SGSingModelLight);
    SGSingDownloadModelOverCellular();
    runUntil(^BOOL { return SGSingModelProgress() >= 0.3 || SGSingModelCurrentState() != SGSingModelDownloading; }, 600);
    CHECK(SGSingModelCurrentState() == SGSingModelDownloading, @"Light's download runs into its weights (%.0f%%)", SGSingModelProgress() * 100);
    SGSetSingChosenModel(SGSingModelFull);
    SGSingDeleteOtherModel();
    runUntil(^BOOL { return NO; }, 5);
    NSArray *after = [NSFileManager.defaultManager contentsOfDirectoryAtPath:sing.path error:nil];
    CHECK(SGSingOtherModelBytes() == 0 && ![[after componentsJoinedByString:@" "] containsString:@"light"],
          @"switched and removed mid-download, nothing of Light is left (%@)", [after componentsJoinedByString:@", "]);
    SGSetSingChosenModel(SGSingModelLight);
    CHECK(SGSingModelPausedBytes() == 0, @"and Light has no paused bytes");
    CHECK(SGSingModelCurrentState() == SGSingModelMissing && !SGSingModelURL(), @"chosen, Light reads missing: the full model does not stand in for it");
    CHECK(SGSingOtherModelBytes() > 209077208, @"the other model's bytes count the full model and the old one (%lld)", SGSingOtherModelBytes());
    printf("Light's size reads %s, the full model's %s\n", SGSingModelSizeText().UTF8String, SGSingModelSizeTextOf(SGSingModelFull).UTF8String);

    SGSingDownloadModelOverCellular();
    runUntil(^BOOL { return SGSingModelCurrentState() != SGSingModelDownloading; }, 900);
    CHECK(SGSingModelCurrentState() == SGSingModelReady && [SGSingModelURL().path isEqualToString:light.path],
          @"Light downloads from separator-light.mlmodelc, checked, and is the model (%@)", SGSingModelError() ?: SGSingModelURL().lastPathComponent);
    CHECK(exists(full), @"the full model is kept");
    SGSingRemoveOldModel();
    CHECK(exists(light) && SGSingModelCurrentState() == SGSingModelReady, @"the launch's cleanup leaves the light model alone");

    SGSetSingChosenModel(SGSingModelFull);
    CHECK([SGSingModelURL().path isEqualToString:full.path] && SGSingModelPausedBytes() == 0, @"switched back, the full model is the model at once");
    SGSetSingChosenModel(SGSingModelLight);
    CHECK([SGSingModelURL().path isEqualToString:light.path], @"and Light again");

    SGSingDeleteOtherModel();
    CHECK(!exists(full) && !exists(old) && exists(light) && SGSingOtherModelBytes() == 0, @"removing the other model removes the full one and the old one, not Light");
    SGSingDeleteModel();
    NSArray *left = [NSFileManager.defaultManager contentsOfDirectoryAtPath:sing.path error:nil];
    CHECK(!left.count && SGSingModelCurrentState() == SGSingModelMissing, @"removing Light leaves Sing/ empty (%@)", [left componentsJoinedByString:@", "]);
    printf("%s\n", failures ? "FAILED" : "all passed");
    return failures ? 1 : 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        double stopAt = argc > 1 ? atof(argv[1]) : 0.2;
        NSURL *sing = [[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
            URLByAppendingPathComponent:@"Vitrine"] URLByAppendingPathComponent:@"Sing"];
        printf("the model goes to %s\n", sing.path.UTF8String);
        // The defaults outlive CFFIXED_USER_HOME's folder (cfprefsd keeps them): every check starts on the full model.
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModel];
        if (argc > 1 && !strcmp(argv[1], "dev")) return checkDev(sing);
        if (argc > 1 && !strcmp(argv[1], "light")) return checkLight(sing);

        if (argc > 1 && !strcmp(argv[1], "update")) return checkUpdate(sing);

        // A paused download of the old model, never finished.
        standIn([sing URLByAppendingPathComponent:@"download"], @{@"model.mil": @669061});
        standIn(sing, @{@"download-4.resume": @1000});
        [NSUserDefaults.standardUserDefaults setInteger:97000000 forKey:@"spotifyglass.sing.downloadPaused"];
        CHECK(SGSingModelCurrentState() == SGSingModelMissing && SGSingModelPausedBytes() == 97000000,
              @"no model, and the old model's paused download reads %lld bytes", SGSingModelPausedBytes());
        SGSingRemoveOldModel();
        CHECK(!exists([sing URLByAppendingPathComponent:@"download"]) && !exists([sing URLByAppendingPathComponent:@"download-4.resume"]),
              @"at launch the old download's staging folder and resume data are deleted");
        CHECK(SGSingModelPausedBytes() == 0, @"and the paused bytes, which were the old model's, are forgotten");
        printf("the model's size reads %s\n", SGSingModelSizeText().UTF8String);

        // The small files are 0.65% of the bytes, so the progress is nearly the weights' own. This Mac's network may count
        // as expensive, which the download otherwise waits out.
        SGSingDownloadModelOverCellular();
        runUntil(^BOOL { return SGSingModelProgress() >= stopAt || SGSingModelCurrentState() != SGSingModelDownloading; }, 900);
        double stopped = SGSingModelProgress();
        CHECK(SGSingModelCurrentState() == SGSingModelDownloading, @"the download runs into the weights (%.0f%%)", stopped * 100);
        SGSingCancelModelDownload();
        NSURL *resume = [sing URLByAppendingPathComponent:@"download-ane-4.resume"];
        runUntil(^BOOL { return exists(resume); }, 10);
        CHECK(exists(resume), @"the stop keeps the weights' resume data");
        CHECK(SGSingModelCurrentState() == SGSingModelMissing, @"stopped, the model is still missing");
        SGSingRemoveOldModel();
        CHECK(exists(resume) && exists([sing URLByAppendingPathComponent:@"download-ane"]), @"the launch's cleanup leaves this model's stopped download alone");

        // Started over, the first bytes read well under 1%; carried on, the stop's share.
        SGSingDownloadModel();
        __block double first = -1;
        runUntil(^BOOL {
            if (first < 0 && SGSingModelProgress() > 0.01) first = SGSingModelProgress();
            return SGSingModelCurrentState() != SGSingModelDownloading;
        }, 1800);
        CHECK(first >= stopped - 0.01, @"the next download carries on from %.0f%%, not from the start", first * 100);
        CHECK(!exists(resume), @"the resume data is used once");
        CHECK(SGSingModelCurrentState() == SGSingModelReady, @"the model is in place and checked (%@)", SGSingModelError() ?: @"no error");
        CHECK([SGSingModelURL().lastPathComponent isEqualToString:@"separator-ane.mlmodelc"], @"it is separator-ane.mlmodelc (%@)", SGSingModelURL().path);
        NSArray *inside = [NSFileManager.defaultManager contentsOfDirectoryAtPath:SGSingModelURL().path error:nil];
        CHECK(inside && ![[inside componentsJoinedByString:@" "] containsString:@"resume"], @"nothing but the model in its folder (%@)",
              [inside componentsJoinedByString:@", "]);
        NSArray *left = [NSFileManager.defaultManager contentsOfDirectoryAtPath:sing.path error:nil];
        CHECK([left isEqualToArray:@[@"separator-ane.mlmodelc"]], @"and nothing else in Sing/ (%@)", [left componentsJoinedByString:@", "]);
        printf("%s\n", failures ? "FAILED" : "all passed");
        return failures ? 1 : 0;
    }
}
