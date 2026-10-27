// The voice model on the phone (Sing.h): the one Voice model chooses (SGKeySingModel), the full separator-ane.mlmodelc
// or the light separator-light.mlmodelc, each the five files of a compiled model, downloaded one by one from the
// Hugging Face repo's folder of that name, each kept only once its size and SHA-256 are the ones pinned here, then
// moved together into Application Support/Vitrine/Sing/<folder>, which backups leave out (210 or 31 MB that can be
// downloaded again). Each model has its own staging folder, resume data and paused bytes, so either can be on the
// iPhone, downloaded or removed without the other. A dropped connection carries on from where it stopped, three times
// per file, and a stopped download keeps the file it was in the middle of (NSURLSession's resume data, kept beside the
// staging folder) for the next one to carry on from. A resumed request is answered 206, with the whole file handed
// over all the same. On a FLEX build a copy put in Sing/dev/<folder> by hand comes first.
//
// The model Karaoke downloaded before (separator.mlmodelc, 489 MB, the same checkpoint with operations in float32 that
// the Neural Engine does not run) is kept and loaded until this one is in, so Karaoke works through the update: it is
// then the model, on the CPU alone, and this one's download an update (SGSingModelUpdateAvailable). Once this one is in,
// at launch or as its download ends, the old one is deleted (SGSingRemoveOldModel); what its own download left goes at
// launch either way.
//
// Threading: main thread, but for SGSingRemoveOldModel; the session's delegate runs on a queue of its own and hands
// back to the main thread.
#import <CommonCrypto/CommonDigest.h>
#import "Core/SGCore.h"
#import "Sing.h"

static NSString *const kRepo = @"https://huggingface.co/My-Name-Is-Jeff/vitrine-sing/resolve/main/";
static const int kRetries = 3;
// Room the download leaves on the disk besides itself.
static const long long kSpareSpace = 64ll * 1000 * 1000;

typedef struct {
    NSString *__unsafe_unretained path;
    long long size;
    const char *sha256;
} SGSingFile;

// The repo's folders (each with the README's table and, for the light one, a manifest.json; upload those exact
// files, as a recompile changes coremldata.bin), the weights last so the small files fail first.
enum { kFileCount = 5 };
static const SGSingFile kFullFiles[kFileCount] = {
    {@"metadata.json", 2333, "101714d1a37ad29c70bf1705ec25ec99584c3cbce27f2245858ace06dacbfb44"},
    {@"coremldata.bin", 388, "bcfd38a8b121681dfb9fdfe6f9d88ffb29068e0dd6d24d4012f4c3a7bdcbc81b"},
    {@"analytics/coremldata.bin", 243, "55f78aab64f5b1250ce4d6016dff23aee43fb97feb77bbceab4e36b3d9ccffb3"},
    {@"model.mil", 1346642, "957024c1075fe331f7ca3410b8bf5e2f83a58c61763caf154729829ce0a92d08"},
    {@"weights/weight.bin", 209077208, "bb4a0effafb5121b9aaa5ea96371fa14d0d8dc30a5ae44a93e0c15a2f4077635"},
};
// Mini-BS-RoFormer-18M's vocals, harness/sing/export_light.py.
static const SGSingFile kLightFiles[kFileCount] = {
    {@"metadata.json", 2383, "757200c870bd4c5e5b70130c9edbd60029bd81c779b504c57ddcd624597f30e9"},
    {@"coremldata.bin", 484, "e533e0c22c3f185e5b8871d2b897111e64420736daa7dc7c239206ca2519d428"},
    {@"analytics/coremldata.bin", 243, "205b1d1d16603c69b4abdfa54b29df71164a16ca4f16a1cf436e7e33ce0b1407"},
    {@"model.mil", 715945, "d3b62a7972344d1a8eec5de8a21130a19272738bce1135871d8bab098585a841"},
    {@"weights/weight.bin", 30040968, "ad460549f68898eab7fe946e9675efaa2551d37b93f73796958c73d4881897fc"},
};

typedef struct {
    NSString *__unsafe_unretained folder;      // the compiled model, in the repo and in Sing/
    NSString *__unsafe_unretained staging;     // its download's folder in Sing/, and its resume data's prefix
    NSString *__unsafe_unretained pausedKey;   // bytes a stopped download kept, for the row that offers to carry on
    const SGSingFile *files;
} SGSingModelFiles;

// Indexed by SGSingModelKind. The full model's names are the ones it had before there was a choice.
static const SGSingModelFiles kModels[] = {
    {@"separator-ane.mlmodelc", @"download-ane", @"spotifyglass.sing.downloadPaused", kFullFiles},
    {@"separator-light.mlmodelc", @"download-light", @"spotifyglass.sing.light.downloadPaused", kLightFiles},
};
// The old model's, checked by size only: it was checked as it came in.
static const SGSingFile kOldFiles[] = {
    {@"metadata.json", 2431, NULL},
    {@"coremldata.bin", 507, NULL},
    {@"analytics/coremldata.bin", 243, NULL},
    {@"model.mil", 669061, NULL},
    {@"weights/weight.bin", 488986336, NULL},
};

NSString *const SGSingChangedNotification = @"SGSingChangedNotification";

// Counts the changes to the model's folder, so SGSingModelURL checks it again only after one.
static NSUInteger sg_modelGeneration;

SGSingModelKind SGSingChosenModel(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:SGKeySingModel] == SGSingModelLight ? SGSingModelLight : SGSingModelFull;
}

static const SGSingModelFiles *chosen(void) {
    return &kModels[SGSingChosenModel()];
}

static long long totalBytes(const SGSingModelFiles *model) {
    long long total = 0;
    for (int i = 0; i < kFileCount; i++) total += model->files[i].size;
    return total;
}

static NSURL *singFolder(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"Vitrine" isDirectory:YES] URLByAppendingPathComponent:@"Sing" isDirectory:YES];
}

static NSURL *modelFolder(const SGSingModelFiles *model) {
    return [singFolder() URLByAppendingPathComponent:model->folder isDirectory:YES];
}

// A FLEX build's hand-put copy of `model` (SGSingModelURL).
static NSURL *devFolder(const SGSingModelFiles *model) {
    return [[singFolder() URLByAppendingPathComponent:@"dev" isDirectory:YES] URLByAppendingPathComponent:model->folder isDirectory:YES];
}

static NSURL *oldFolder(void) {
    return [singFolder() URLByAppendingPathComponent:@"separator.mlmodelc" isDirectory:YES];
}

static NSURL *stagingFolder(const SGSingModelFiles *model) {
    return [singFolder() URLByAppendingPathComponent:model->staging isDirectory:YES];
}

// A stopped download's resume data for file `index`, beside the staging folder: everything in that folder is moved
// into the model.
static NSURL *resumeFile(const SGSingModelFiles *model, int index) {
    return [singFolder() URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%d.resume", model->staging, index]];
}

static long long sizeOf(NSURL *url) {
    return [[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil][NSFileSize] longLongValue];
}

// Whether every file of `files` is in `folder` at its size; the hashes were checked as each came in.
static BOOL completeWith(NSURL *folder, const SGSingFile *files, int count) {
    for (int i = 0; i < count; i++) {
        if (sizeOf([folder URLByAppendingPathComponent:files[i].path]) != files[i].size) return NO;
    }
    return YES;
}

static BOOL complete(const SGSingModelFiles *model) {
    return completeWith(modelFolder(model), model->files, kFileCount);
}

static BOOL oldComplete(void) {
    return completeWith(oldFolder(), kOldFiles, sizeof kOldFiles / sizeof kOldFiles[0]);
}

// The file's SHA-256, read a megabyte at a time: the weights are too big to read whole.
static NSString *sha256Of(NSURL *url) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!handle) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [handle readDataUpToLength:1 << 20 error:nil];
            if (!chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [handle closeFile];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:2 * CC_SHA256_DIGEST_LENGTH];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static void announce(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingChangedNotification object:nil];
}

#pragma mark - the download

@interface SGSingDownloader : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic) const SGSingModelFiles *model;   // the one chosen when it started; a switch stops it
@property (nonatomic) int file;               // the index of the file coming in
@property (nonatomic) long long received;     // its bytes so far
@property (nonatomic, copy) NSString *error;
@property (atomic, strong) NSURLSessionDownloadTask *task;   // the one running, so a stop (on the main thread) can keep what it has
@end

static SGSingDownloader *sg_downloader;   // while a download runs
static NSString *sg_lastError;
static double sg_progress;
static BOOL sg_waitingForNetwork;   // offline, or on cellular unless allowed: the session holds the request
static BOOL sg_cellular;            // the download may use cellular and Low Data Mode networks
static BOOL sg_checking;            // the weights' checksum is being read
// Removals of each model (kModels' order), main thread: a stopped download's late resume data checks it.
static NSUInteger sg_removals[2];

@implementation SGSingDownloader {
    NSURLSession *_session;
    BOOL _resumed;                     // it carries on from resume data
    BOOL _restart;                     // resume data the server no longer takes: the file again from the start
    int _attempts;
    BOOL _cancelled;
}

- (void)start {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest = 60;
    // Offline, a request (a retry too) waits for the network rather than failing at once; and so it does on cellular
    // or a Low Data Mode network, 210 MB being a lot of a plan, until the user says it may use them.
    configuration.waitsForConnectivity = YES;
    configuration.allowsExpensiveNetworkAccess = sg_cellular;
    configuration.allowsConstrainedNetworkAccess = sg_cellular;
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    NSError *error;
    [NSFileManager.defaultManager createDirectoryAtURL:stagingFolder(self.model) withIntermediateDirectories:YES attributes:nil error:&error];
    NSURL *folder = singFolder();
    [folder setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    [queue addOperationWithBlock:^{ [self next]; }];
}

// Stopped, the file coming in is kept as resume data for the next download; the session goes once it is written.
- (void)cancel {
    _cancelled = YES;
    NSURLSession *session = _session;
    NSURLSessionDownloadTask *task = self.task;
    if (!task) {
        [session invalidateAndCancel];
        return;
    }
    NSURL *resume = resumeFile(self.model, self.file);
    NSUInteger index = (NSUInteger)(self.model - kModels), removals = sg_removals[index];
    [task cancelByProducingResumeData:^(NSData *data) {
        [session invalidateAndCancel];
        // On the main thread, where models are removed: a removal since the stop wins, as the resume data would bring
        // back a file of the model it removed.
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL removed = sg_removals[index] != removals;
            if (data && !removed) [data writeToURL:resume atomically:YES];
            SGLog(@"sing: the download is stopped%@", removed ? @", and what came in is dropped with its model" : data ? @", what came in is kept" : @"");
        });
    }];
}

- (void)download:(NSURL *)url resumeData:(NSData *)resume {
    _resumed = resume != nil;
    NSURLSessionDownloadTask *task = resume ? [_session downloadTaskWithResumeData:resume] : [_session downloadTaskWithURL:url];
    self.task = task;
    [task resume];
}

- (NSURL *)fileURL {
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@%@/%@", kRepo, self.model->folder, self.model->files[self.file].path]];
}

// The first file not already in the staging folder from an earlier try, or the move into place.
- (void)next {
    if (_cancelled) return;
    while (self.file < kFileCount && sizeOf([stagingFolder(self.model) URLByAppendingPathComponent:self.model->files[self.file].path]) == self.model->files[self.file].size) self.file++;
    self.received = 0;
    _attempts = 0;
    [self report];
    if (self.file == kFileCount) {
        [self finish];
        return;
    }
    // A stop's resume data is used once: if it fails, the file starts over.
    NSData *resume = [NSData dataWithContentsOfURL:resumeFile(self.model, self.file)];
    [NSFileManager.defaultManager removeItemAtURL:resumeFile(self.model, self.file) error:nil];
    [self download:[self fileURL] resumeData:resume];
    SGLog(@"sing: downloading %@/%@%@", self.model->folder, self.model->files[self.file].path, resume ? @", carrying on from the last download" : @"");
}

- (void)finish {
    NSFileManager *files = NSFileManager.defaultManager;
    // Resume data a stop wrote after the next download had already looked for it.
    for (int i = 0; i < kFileCount; i++) [files removeItemAtURL:resumeFile(self.model, i) error:nil];
    [files removeItemAtURL:modelFolder(self.model) error:nil];
    NSError *error;
    BOOL moved = [files moveItemAtURL:stagingFolder(self.model) toURL:modelFolder(self.model) error:&error];
    [self endWithError:moved ? nil : [NSString stringWithFormat:@"The model could not be put in place (%@)", error.localizedDescription]];
}

- (void)endWithError:(NSString *)error {
    [_session finishTasksAndInvalidate];
    if (error) SGLog(@"sing: the download of %@ failed: %@", self.model->folder, error);
    else SGLog(@"sing: %@ is downloaded and checked", self.model->folder);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_downloader != self) return;
        sg_downloader = nil;
        sg_waitingForNetwork = NO;
        sg_lastError = error;
        if (!error) [NSUserDefaults.standardUserDefaults removeObjectForKey:self.model->pausedKey];
        // The update in: the old model goes now, and Sing.x loads this one the next time it wants the model.
        if (!error) SGSingRemoveOldModel();
        sg_modelGeneration++;
        announce();
    });
}

- (void)report {
    long long done = self.received;
    for (int i = 0; i < self.file && i < kFileCount; i++) done += self.model->files[i].size;
    double progress = (double)done / totalBytes(self.model);
    // A few times a second is enough for the row and the button.
    static CFAbsoluteTime reported;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - reported < 0.25 && progress < 1) return;
    reported = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_progress = progress;
        sg_waitingForNetwork = NO;
        announce();
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)totalWritten totalBytesExpectedToWrite:(int64_t)expected {
    self.received = MIN(totalWritten, self.model->files[self.file].size);
    [self report];
}

- (void)URLSession:(NSURLSession *)session taskIsWaitingForConnectivity:(NSURLSessionTask *)task {
    SGLog(@"sing: waiting for the network to download %@", self.model->files[self.file].path);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_downloader != self) return;
        sg_waitingForNetwork = YES;
        announce();
    });
}

// The file is checked here, before the session deletes it, and kept in the staging folder if it is the one
// pinned.
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    // Stopped as the file came in: keeping it would put back a staging folder a removal may have just taken away.
    if (_cancelled) return;
    SGSingFile file = self.model->files[self.file];
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    BOOL answered = status == 200 || status == 206;
    if (!answered && _resumed) {
        // Resume data the server no longer takes, its signed address run out after a day: the file again.
        SGLog(@"sing: the server answered %ld to carrying on %@, so it starts over", (long)status, file.path);
        _restart = YES;
        return;
    }
    long long size = sizeOf(location);
    BOOL big = file.size > 1000 * 1000;
    if (big) dispatch_async(dispatch_get_main_queue(), ^{ sg_checking = YES; announce(); });
    NSString *hash = size == file.size ? sha256Of(location) : nil;
    if (big) dispatch_async(dispatch_get_main_queue(), ^{ sg_checking = NO; announce(); });
    SGLog(@"sing: %@ came in, %ld, %lld bytes", file.path, (long)status, size);
    if (!answered || size != file.size || ![hash isEqualToString:@(file.sha256)]) {
        self.error = !answered ? [NSString stringWithFormat:@"The server answered %ld for %@", (long)status, file.path]
                                 : [NSString stringWithFormat:@"%@ is not the file Karaoke expects (%lld bytes%@)", file.path, size, hash ? @", another checksum" : @""];
        return;
    }
    NSURL *target = [stagingFolder(self.model) URLByAppendingPathComponent:file.path];
    [NSFileManager.defaultManager createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtURL:target error:nil];
    NSError *error;
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:target error:&error]) {
        self.error = [NSString stringWithFormat:@"%@ could not be kept (%@)", file.path, error.localizedDescription];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (_cancelled) return;
    if (_restart) {
        _restart = NO;
        [self download:[self fileURL] resumeData:nil];
        return;
    }
    if (self.error) {
        NSString *message = self.error;
        self.error = nil;
        [self endWithError:message];
        return;
    }
    if (!error) {
        self.file++;
        [self next];
        return;
    }
    NSData *resume = error.userInfo[NSURLSessionDownloadTaskResumeData];
    if (++_attempts <= kRetries) {
        SGLog(@"sing: %@ stopped (%@), trying again%@", self.model->files[self.file].path, error.localizedDescription, resume ? @" from where it was" : @"");
        [self download:[self fileURL] resumeData:resume];
        return;
    }
    [self endWithError:error.localizedDescription];
}

@end

#pragma mark - what Sing asks

SGSingModelState SGSingModelCurrentState(void) {
    // The old model works on while its update downloads.
    if (sg_downloader && !SGSingModelUpdateAvailable()) return SGSingModelDownloading;
    return SGSingModelURL() ? SGSingModelReady : SGSingModelMissing;
}

NSURL *SGSingModelURL(void) {
    // Checked by size once a launch, and again after a download, a delete or a switch changes it, or the key changes by
    // another way (a settings import): a folder not checked could be missing a file, which crashes Core ML.
    static int known = -1, oldKnown = -1;
    static NSURL *dev;
    static NSUInteger knownGeneration = NSUIntegerMax;
    static const SGSingModelFiles *knownModel;
    const SGSingModelFiles *model = chosen();
    if (knownGeneration != sg_modelGeneration || knownModel != model) {
        knownGeneration = sg_modelGeneration;
        knownModel = model;
        known = complete(model);
        // The old model stands in for the full one alone: it is the full one's earlier export.
        oldKnown = model == &kModels[SGSingModelFull] && oldComplete();
        // FLEX builds only (Diagnostics' SGIsDebugBuild, which the harnesses do not link): a copy of the chosen model
        // put in Sing/dev/ by hand, for a model not on Hugging Face yet, neither downloaded nor checked. Core ML crashes
        // the process on a compiled model with a file missing (model.mil, weights/weight.bin; a short file fails
        // cleanly), so a copy cut off halfway is not loaded.
        NSURL *folder = devFolder(model);
        int present = 0;
        for (int i = 0; i < kFileCount; i++) present += sizeOf([folder URLByAppendingPathComponent:model->files[i].path]) > 0;
        BOOL there = present == kFileCount, flex = NSClassFromString(@"FLEXManager") != nil;
        if (there && flex && ![dev isEqual:folder]) SGLog(@"sing: DEV MODEL: the voice model is the unchecked copy in %@, not a download (a FLEX build)", folder.path);
        if (there && !flex) SGLog(@"sing: a dev model is in %@, and only a FLEX build loads it", folder.path);
        if (present && !there) SGLog(@"sing: the dev model in %@ has %d of its %d files, so it is not loaded", folder.path, present, kFileCount);
        dev = there && flex ? folder : nil;
    }
    return dev ?: known ? modelFolder(model) : oldKnown ? oldFolder() : nil;
}

void SGSetSingChosenModel(SGSingModelKind kind) {
    if (kind == SGSingChosenModel()) return;
    // The other model's download stops, keeping what came in under its own name for when it is chosen again.
    if (sg_downloader) SGSingCancelModelDownload();
    [NSUserDefaults.standardUserDefaults setInteger:kind forKey:SGKeySingModel];
    sg_lastError = nil;
    sg_modelGeneration++;
    SGLog(@"sing: the voice model is now %@ (%@)", kModels[kind].folder,
          SGSingModelURL() ? @"on the iPhone, Karaoke loads it" : @"not downloaded");
    // Sing.x loads it in place of the one before, or lets that one go if this one is not here.
    announce();
}

// This model in place, the dev copy or the download: nothing to download.
static BOOL hasModel(void) {
    return SGSingModelURL() && !SGSingModelUpdateAvailable();
}

double SGSingModelProgress(void) {
    return sg_downloader ? sg_progress : hasModel() ? 1 : 0;
}

BOOL SGSingModelWaitingForNetwork(void) {
    return sg_downloader && sg_waitingForNetwork;
}

NSString *SGSingModelError(void) {
    return sg_lastError;
}

NSString *SGSingModelSizeText(void) {
    return SGSingModelSizeTextOf(SGSingChosenModel());
}

NSString *SGSingModelSizeTextOf(SGSingModelKind kind) {
    return [NSByteCountFormatter stringFromByteCount:totalBytes(&kModels[kind]) countStyle:NSByteCountFormatterCountStyleFile];
}

// What is still to come: the files not in the staging folder yet.
static long long bytesToCome(void) {
    const SGSingModelFiles *model = chosen();
    long long left = 0;
    for (int i = 0; i < kFileCount; i++) {
        if (sizeOf([stagingFolder(model) URLByAppendingPathComponent:model->files[i].path]) != model->files[i].size) left += model->files[i].size;
    }
    return left;
}

void SGSingDownloadModel(void) {
    if (sg_downloader || hasModel()) return;
    // The volume Application Support is on, which the staging folder's parent may not exist on yet.
    NSURL *support = singFolder().URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    NSNumber *free = [support resourceValuesForKeys:@[NSURLVolumeAvailableCapacityForImportantUsageKey] error:nil][NSURLVolumeAvailableCapacityForImportantUsageKey];
    long long wanted = bytesToCome() + kSpareSpace;
    if (free && free.longLongValue < wanted) {
        NSByteCountFormatterCountStyle style = NSByteCountFormatterCountStyleFile;
        sg_lastError = [NSString stringWithFormat:@"The iPhone has %@ free, and the voice model needs %@ more.",
                        [NSByteCountFormatter stringFromByteCount:free.longLongValue countStyle:style],
                        [NSByteCountFormatter stringFromByteCount:wanted - free.longLongValue countStyle:style]];
        SGLog(@"sing: the download does not start: %@", sg_lastError);
        announce();
        return;
    }
    sg_lastError = nil;
    sg_progress = 0;
    sg_waitingForNetwork = NO;
    sg_downloader = [SGSingDownloader new];
    sg_downloader.model = chosen();
    [sg_downloader start];
    announce();
}

void SGSingDownloadModelOverCellular(void) {
    if (!sg_downloader) {
        sg_cellular = YES;
        SGSingDownloadModel();
        return;
    }
    if (sg_cellular) return;
    // The running download's session forbids cellular: it stops keeping what it has, and starts again allowed.
    SGSingCancelModelDownload();
    sg_cellular = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ SGSingDownloadModel(); });
}

BOOL SGSingModelOverCellular(void) {
    return sg_cellular;
}

BOOL SGSingModelChecking(void) {
    return sg_downloader && sg_checking;
}

long long SGSingModelPausedBytes(void) {
    return sg_downloader || hasModel() ? 0 : [NSUserDefaults.standardUserDefaults integerForKey:chosen()->pausedKey];
}

void SGSingCancelModelDownload(void) {
    SGSingDownloader *downloader = sg_downloader;
    if (downloader) [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)(sg_progress * totalBytes(downloader.model)) forKey:downloader.model->pausedKey];
    [downloader cancel];
    sg_downloader = nil;
    sg_modelGeneration++;
    announce();
}

static long long bytesIn(NSURL *url) {
    long long bytes = sizeOf(url);
    for (NSURL *file in [NSFileManager.defaultManager enumeratorAtURL:url includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 errorHandler:nil]) bytes += sizeOf(file);
    return bytes;
}

// Deletes what of `urls` is there, adding the bytes freed to `freed`; whether there was any.
static BOOL removeAll(NSArray<NSURL *> *urls, long long *freed) {
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL found = NO;
    for (NSURL *url in urls) {
        if (![files fileExistsAtPath:url.path]) continue;
        found = YES;
        *freed += bytesIn(url);
        [files removeItemAtURL:url error:nil];
    }
    return found;
}

// What the old model's download left: its staging folder and resume data, one per file (named one by one:
// download-ane-N.resume and download-light-N.resume are the two models' own).
static NSArray<NSURL *> *oldLeftovers(void) {
    NSMutableArray<NSURL *> *leftovers = [NSMutableArray arrayWithObject:[singFolder() URLByAppendingPathComponent:@"download"]];
    for (int i = 0; i < 5; i++) [leftovers addObject:[singFolder() URLByAppendingPathComponent:[NSString stringWithFormat:@"download-%d.resume", i]]];
    return leftovers;
}

// Everything of `model` in Sing/: the compiled model, its download's folder and resume data and a FLEX build's copy,
// and for the full model the old one it replaced, with what that one's download left.
static NSArray<NSURL *> *filesOf(const SGSingModelFiles *model) {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithObjects:modelFolder(model), stagingFolder(model), devFolder(model), nil];
    for (int i = 0; i < kFileCount; i++) [urls addObject:resumeFile(model, i)];
    if (model == &kModels[SGSingModelFull]) {
        [urls addObject:oldFolder()];
        [urls addObjectsFromArray:oldLeftovers()];
    }
    return urls;
}

static const SGSingModelFiles *unchosen(void) {
    return &kModels[SGSingChosenModel() == SGSingModelFull ? SGSingModelLight : SGSingModelFull];
}

static void removeModel(const SGSingModelFiles *model) {
    sg_removals[model - kModels]++;
    long long freed = 0;
    removeAll(filesOf(model), &freed);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:model->pausedKey];
    SGLog(@"sing: %@ is removed, %@ freed", model->folder, [NSByteCountFormatter stringFromByteCount:freed countStyle:NSByteCountFormatterCountStyleFile]);
    sg_modelGeneration++;
    announce();
}

void SGSingDeleteModel(void) {
    SGSingCancelModelDownload();
    removeModel(chosen());
}

long long SGSingOtherModelBytes(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    long long bytes = 0;
    for (NSURL *url in filesOf(unchosen())) {
        if ([files fileExistsAtPath:url.path]) bytes += bytesIn(url);
    }
    return bytes;
}

// No download of it runs: choosing the other model stopped it.
void SGSingDeleteOtherModel(void) {
    removeModel(unchosen());
}

void SGSingRemoveOldModel(void) {
    // The bytes a stopped download kept were the old model's.
    const SGSingModelFiles *full = &kModels[SGSingModelFull];
    long long freed = 0;
    BOOL left = removeAll(oldLeftovers(), &freed);
    if (left) [NSUserDefaults.standardUserDefaults removeObjectForKey:full->pausedKey];
    // The old model itself only once the full model is in: until then Karaoke runs on it. The light model is left alone.
    BOOL there = [NSFileManager.defaultManager fileExistsAtPath:oldFolder().path], replaced = complete(full);
    BOOL old = there && replaced && removeAll(@[oldFolder()], &freed);
    NSString *size = [NSByteCountFormatter stringFromByteCount:freed countStyle:NSByteCountFormatterCountStyleFile];
    if (old) SGLog(@"sing: the old voice model (separator.mlmodelc) is deleted, %@ freed; the full model is separator-ane.mlmodelc", size);
    else if (left) SGLog(@"sing: what the old voice model's download left is deleted, %@ freed", size);
    // Which model is in use: a FLEX build's dev copy of the new one comes before the old, and Light needs neither.
    if (there && !replaced) {
        SGLog(SGSingModelUpdateAvailable()
              ? @"sing: the old voice model (separator.mlmodelc) is kept until separator-ane.mlmodelc is downloaded, and Karaoke runs on it, on the CPU alone"
              : SGSingChosenModel() == SGSingModelLight
              ? @"sing: the old voice model (separator.mlmodelc) is kept until separator-ane.mlmodelc is downloaded; Voice model is Light, so it is not in use"
              : @"sing: the old voice model (separator.mlmodelc) is kept until separator-ane.mlmodelc is downloaded; the dev copy is in use");
    }
}

BOOL SGSingModelUpdateAvailable(void) {
    return [SGSingModelURL() isEqual:oldFolder()];
}

BOOL SGSingModelUpdateDownloading(void) {
    return sg_downloader && SGSingModelUpdateAvailable();
}

NSString *SGSingModelInUseSizeText(void) {
    long long total = 0;
    for (size_t i = 0; i < sizeof kOldFiles / sizeof kOldFiles[0]; i++) total += kOldFiles[i].size;
    return [NSByteCountFormatter stringFromByteCount:SGSingModelUpdateAvailable() ? total : totalBytes(chosen()) countStyle:NSByteCountFormatterCountStyleFile];
}

NSArray<NSString *> *SGSingComputeUnitNames(void) {
    return @[@"Automatic", @"CPU only"];
}

BOOL SGSingOSSupported(void) {
    if (@available(iOS 18.0, *)) return YES;
    return NO;
}
