#import "SGSingAlternateModels.h"
#import "SGSingModel.h"
#import "Core/SGPrefs.h"
#import "Core/SGLog.h"
#import <CommonCrypto/CommonDigest.h>

#ifndef SGSingModelRoot
#define SGSingModelRoot nil
#endif

NSString *const SGKeySingModelVariant = @"spotifyglass.sing.modelVariant";
static NSString *const kBase = @"https://huggingface.co/My-Name-Is-Jeff/vitrine-sing/resolve/main/";
static NSString *const kNotification = @"spotifyglass.singModelChanged";

typedef struct { const char *path; int64_t size; const char *hash; } SGAltFile;
static const SGAltFile kANEFiles[] = {
    {"separator-ane.mlmodelc/metadata.json", 2333, "101714d1a37ad29c70bf1705ec25ec99584c3cbce27f2245858ace06dacbfb44"},
    {"separator-ane.mlmodelc/coremldata.bin", 388, "bcfd38a8b121681dfb9fdfe6f9d88ffb29068e0dd6d24d4012f4c3a7bdcbc81b"},
    {"separator-ane.mlmodelc/analytics/coremldata.bin", 243, "55f78aab64f5b1250ce4d6016dff23aee43fb97feb77bbceab4e36b3d9ccffb3"},
    {"separator-ane.mlmodelc/model.mil", 1346642, "957024c1075fe331f7ca3410b8bf5e2f83a58c61763caf154729829ce0a92d08"},
    {"separator-ane.mlmodelc/weights/weight.bin", 209077208, "bb4a0effafb5121b9aaa5ea96371fa14d0d8dc30a5ae44a93e0c15a2f4077635"},
};
static const SGAltFile kLightFiles[] = {
    {"separator-light.mlmodelc/metadata.json", 2383, "757200c870bd4c5e5b70130c9edbd60029bd81c779b504c57ddcd624597f30e9"},
    {"separator-light.mlmodelc/coremldata.bin", 484, "e533e0c22c3f185e5b8871d2b897111e64420736daa7dc7c239206ca2519d428"},
    {"separator-light.mlmodelc/analytics/coremldata.bin", 243, "205b1d1d16603c69b4abdfa54b29df71164a16ca4f16a1cf436e7e33ce0b1407"},
    {"separator-light.mlmodelc/model.mil", 715945, "d3b62a7972344d1a8eec5de8a21130a19272738bce1135871d8bab098585a841"},
    {"separator-light.mlmodelc/weights/weight.bin", 30040968, "ad460549f68898eab7fe946e9675efaa2551d37b93f73796958c73d4881897fc"},
};
enum { kCount = 5 };

static NSString *nameFor(SGSingAlternateModel model) { return model == SGSingAlternateModelANE ? @"ane" : @"light"; }
static NSString *sessionID(SGSingAlternateModel model) { return [@"spotifyglass.sing.model." stringByAppendingString:nameFor(model)]; }
static NSString *downloadKey(SGSingAlternateModel model) { return [@"spotifyglass.sing.modelDownload." stringByAppendingString:nameFor(model)]; }
static const SGAltFile *filesFor(SGSingAlternateModel model) { return model == SGSingAlternateModelANE ? kANEFiles : kLightFiles; }
static NSURL *singRoot(void) {
    NSString *override=SGSingModelRoot;
    NSURL *base = override ? [NSURL fileURLWithPath:override isDirectory:YES]
        : [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"spoti.pw/Sing" isDirectory:YES];
}
static NSURL *modelRoot(SGSingAlternateModel model) { return [singRoot() URLByAppendingPathComponent:nameFor(model) isDirectory:YES]; }
static NSURL *modelURL(SGSingAlternateModel model) {
    NSString *name=model == SGSingAlternateModelANE ? @"separator-ane.mlmodelc" : @"separator-light.mlmodelc";
    return [singRoot() URLByAppendingPathComponent:name isDirectory:YES];
}
static NSMutableDictionary<NSString *, NSURLSession *> *sessions(void) { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [NSMutableDictionary dictionary]; }); return x; }
static NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSURLSessionDownloadTask *> *> *tasks(void) { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [NSMutableDictionary dictionary]; }); return x; }
static NSMutableDictionary<NSString *, NSMutableDictionary<NSNumber *, NSNumber *> *> *progresses(void) { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [NSMutableDictionary dictionary]; }); return x; }
static NSMutableDictionary<NSString *, NSNumber *> *checking(void) { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [NSMutableDictionary dictionary]; }); return x; }
static NSMutableDictionary<NSString *, void (^)(void)> *completions(void) { static id x; static dispatch_once_t once; dispatch_once(&once, ^{ x = [NSMutableDictionary dictionary]; }); return x; }
static CFTimeInterval sgLastProgressPost;
static void stopTasksFor(NSString *sid) {
    for (NSURLSessionTask *other in tasks()[sid].allValues) [other cancel];
    [tasks()[sid] removeAllObjects];
}
static NSString *hexHash(NSURL *url) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path]; if (!handle) return nil;
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    for (;;) { @autoreleasepool { NSData *data = [handle readDataOfLength:1 << 20]; if (!data.length) break; CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length); } }
    [handle closeFile]; unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &ctx);
    NSMutableString *out = [NSMutableString string]; for (int i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [out appendFormat:@"%02x", digest[i]]; return out;
}
static BOOL complete(SGSingAlternateModel model) {
    const SGAltFile *files = filesFor(model); NSURL *root = modelURL(model);
    NSString *modelPrefix=model==SGSingAlternateModelANE?@"separator-ane.mlmodelc/":@"separator-light.mlmodelc/";
    for (int i=0;i<kCount;i++) {
        NSString *path=[NSString stringWithUTF8String:files[i].path];
        NSString *relative=[path substringFromIndex:modelPrefix.length];
        NSURL *file = [root URLByAppendingPathComponent:relative];
        NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil][NSFileSize];
        if (size.longLongValue != files[i].size) return NO;
    }
    return YES;
}
static int64_t modelSize(SGSingAlternateModel model) { int64_t n=0; const SGAltFile *files=filesFor(model); for(int i=0;i<kCount;i++) n+=files[i].size; return n; }
static void post(void) { dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:kNotification object:nil]; }); }
static void postProgress(void) {
    CFTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if(now-sgLastProgressPost<0.25)return;
    sgLastProgressPost=now; post();
}

@interface SGAltDownloadDelegate : NSObject <NSURLSessionDownloadDelegate>
@property (nonatomic) SGSingAlternateModel model;
- (instancetype)initWithModel:(SGSingAlternateModel)model;
@end
@implementation SGAltDownloadDelegate
- (instancetype)initWithModel:(SGSingAlternateModel)model { if ((self=[super init])) _model=model; return self; }
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    const SGAltFile *files=filesFor(_model); int idx=(int)task.taskDescription.integerValue;
    if(idx>=0&&idx<kCount) { NSString *sid=session.configuration.identifier; if(!progresses()[sid]) progresses()[sid]=[NSMutableDictionary dictionary]; progresses()[sid][@(idx)]=@(MIN(files[idx].size,total)); } postProgress();
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    int idx=(int)task.taskDescription.integerValue; if(idx<0||idx>=kCount) return;
    if(!SGInt(downloadKey(_model),0)) return;
    const SGAltFile *files=filesFor(_model); NSFileManager *fm=NSFileManager.defaultManager;
    NSString *path=[NSString stringWithUTF8String:files[idx].path]; NSString *modelPrefix=_model==SGSingAlternateModelANE?@"separator-ane.mlmodelc/":@"separator-light.mlmodelc/";
    NSString *relative=[path substringFromIndex:modelPrefix.length]; NSURL *dest=[modelURL(_model) URLByAppendingPathComponent:relative];
    [fm createDirectoryAtURL:dest.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *temp=[modelRoot(_model) URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.part",idx]];
    [fm removeItemAtURL:temp error:nil]; NSError *error=nil; if(![fm moveItemAtURL:location toURL:temp error:&error]) { SGLog(@"Sing %@ model file move failed: %@",nameFor(_model),error); return; }
    NSString *sid=session.configuration.identifier; checking()[sid]=@([checking()[sid] integerValue]+1); post();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{
        NSNumber *size=[fm attributesOfItemAtPath:temp.path error:nil][NSFileSize];
        BOOL valid=size.longLongValue==files[idx].size && [hexHash(temp) isEqualToString:[NSString stringWithUTF8String:files[idx].hash]];
        if(valid) { [fm removeItemAtURL:dest error:nil]; valid=[fm moveItemAtURL:temp toURL:dest error:nil]; }
        if(!valid) [fm removeItemAtURL:temp error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            checking()[sid]=@(MAX(0,[checking()[sid] integerValue]-1));
            if(!valid) { SGLog(@"Sing %@ model rejected a file that failed its pinned size/hash",nameFor(_model)); [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(_model)]; stopTasksFor(sid); }
            else if(complete(_model)) { [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(_model)]; SGLog(@"Sing %@ model installed",nameFor(_model)); }
            post();
        });
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSString *sid=session.configuration.identifier; [tasks()[sid] removeObjectForKey:@(task.taskDescription.integerValue)];
    if(error && !([error.domain isEqualToString:NSURLErrorDomain] && error.code==NSURLErrorCancelled)) {
        SGLog(@"Sing %@ model download failed: %@",nameFor(_model),error);
        [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(_model)];
        stopTasksFor(sid);
    }
    if(!error && [tasks()[sid] count]==0 && !complete(_model) && [checking()[sid] integerValue]==0) [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(_model)];
    post();
}
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    NSString *sid=session.configuration.identifier; void (^done)(void)=completions()[sid]; if(done) { [completions() removeObjectForKey:sid]; done(); }
}
@end

static NSURLSession *sessionFor(SGSingAlternateModel model) {
    NSString *sid=sessionID(model); NSURLSession *value=sessions()[sid]; if(value) return value;
    NSURLSessionConfiguration *cfg=[NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sid]; cfg.sessionSendsLaunchEvents=YES; cfg.discretionary=NO;
    value=[NSURLSession sessionWithConfiguration:cfg delegate:[[SGAltDownloadDelegate alloc] initWithModel:model] delegateQueue:NSOperationQueue.mainQueue]; sessions()[sid]=value; tasks()[sid]=[NSMutableDictionary dictionary]; return value;
}
BOOL SGSingAlternateModelInstalled(SGSingAlternateModel model) { return model==SGSingAlternateModelFull ? SGSingModelCurrentState()==SGSingModelInstalled : complete(model); }
BOOL SGSingAlternateModelDownloading(SGSingAlternateModel model) { return model!=SGSingAlternateModelFull && SGInt(downloadKey(model),0)!=0; }
double SGSingAlternateModelProgress(SGSingAlternateModel model) {
    if(model==SGSingAlternateModelFull) return SGSingModelCurrentState()==SGSingModelDownloading ? (double)SGSingModelReceived()/MAX(1,SGSingModelSize()) : -1;
    NSString *sid=sessionID(model); int64_t got=0; const SGAltFile *files=filesFor(model);
    for(int i=0;i<kCount;i++) { NSString *path=@(files[i].path); NSString *prefix=model==SGSingAlternateModelANE?@"separator-ane.mlmodelc/":@"separator-light.mlmodelc/"; NSString *rel=[path substringFromIndex:prefix.length]; NSURL *file=[modelURL(model) URLByAppendingPathComponent:rel]; NSNumber *sz=[NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil][NSFileSize]; if(sz.longLongValue==files[i].size) got+=files[i].size; else got+=MIN(files[i].size,[progresses()[sid][@(i)] longLongValue]); }
    return MIN(1.0,(double)got/MAX(1,modelSize(model)));
}
int64_t SGSingAlternateModelSize(SGSingAlternateModel model) { return model==SGSingAlternateModelFull?SGSingModelSize():modelSize(model); }
NSString *SGSingAlternateModelSpaceProblem(SGSingAlternateModel model) {
    if(model==SGSingAlternateModelFull)return SGSingModelSpaceProblem();
    int64_t needed=(int64_t)((1.0-SGSingAlternateModelProgress(model))*modelSize(model))+(64ll<<20);
    NSURL *folder=singRoot(); while(folder.path.length>1&&![NSFileManager.defaultManager fileExistsAtPath:folder.path]) folder=folder.URLByDeletingLastPathComponent;
    NSNumber *free=nil; [folder getResourceValue:&free forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
    if(!free||free.longLongValue>=needed)return nil;
    return [NSString stringWithFormat:@"This model needs about %@ of free space, and this iPhone has %@.",SGSingModelBytesText(needed),SGSingModelBytesText(free.longLongValue)];
}
NSString *SGSingAlternateModelPath(SGSingAlternateModel model) { return model==SGSingAlternateModelFull?nil:complete(model)?modelURL(model).path:nil; }
void SGSingAlternateModelDownload(SGSingAlternateModel model, BOOL metered) {
    if(model==SGSingAlternateModelFull||complete(model)||SGInt(downloadKey(model),0)) return;
    NSURL *root=modelRoot(model); NSError *error=nil; [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error];
    if(error) { SGLog(@"Sing %@ model folder failed: %@",nameFor(model),error); return; }
    [singRoot() setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    SGSetInt(downloadKey(model),metered?2:1); NSString *sid=sessionID(model); NSURLSession *session=sessionFor(model); const SGAltFile *files=filesFor(model);
    for(int i=0;i<kCount;i++) {
        NSString *path=@(files[i].path); NSString *prefix=model==SGSingAlternateModelANE?@"separator-ane.mlmodelc/":@"separator-light.mlmodelc/"; NSString *rel=[path substringFromIndex:prefix.length]; NSURL *dest=[modelURL(model) URLByAppendingPathComponent:rel]; NSNumber *sz=[NSFileManager.defaultManager attributesOfItemAtPath:dest.path error:nil][NSFileSize]; if(sz.longLongValue==files[i].size) continue;
        NSURL *url=[NSURL URLWithString:path relativeToURL:[NSURL URLWithString:kBase]].absoluteURL; NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url]; req.allowsExpensiveNetworkAccess=metered; req.allowsConstrainedNetworkAccess=metered;
        if(tasks()[sid][@(i)]) continue;
        NSURLSessionDownloadTask *task=[session downloadTaskWithRequest:req]; task.taskDescription=[NSString stringWithFormat:@"%d",i]; task.countOfBytesClientExpectsToReceive=files[i].size; tasks()[sid][@(i)]=task; [task resume];
    }
    post();
}
void SGSingAlternateModelCancel(SGSingAlternateModel model) { if(model==SGSingAlternateModelFull)return; NSString *sid=sessionID(model); [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(model)]; for(NSURLSessionTask *task in tasks()[sid].allValues) [task cancel]; [tasks()[sid] removeAllObjects]; post(); }
void SGSingAlternateModelRemove(SGSingAlternateModel model) { if(model==SGSingAlternateModelFull)return; SGSingAlternateModelCancel(model); dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ [NSFileManager.defaultManager removeItemAtURL:modelRoot(model) error:nil]; [NSFileManager.defaultManager removeItemAtURL:modelURL(model) error:nil]; post(); }); }
void SGSingAlternateModelSelect(SGSingAlternateModel model) { if(model<SGSingAlternateModelFull||model>SGSingAlternateModelLight)return; SGSetInt(SGKeySingModelVariant,model); post(); }
NSString *SGSingEffectiveModelPath(NSString *fullModelPath) {
    SGSingAlternateModel selected=(SGSingAlternateModel)SGInt(SGKeySingModelVariant,SGSingAlternateModelFull);
    NSString *path=selected==SGSingAlternateModelFull?fullModelPath:SGSingAlternateModelPath(selected); if(path)return path;
    if(fullModelPath)return fullModelPath;
    path=SGSingAlternateModelPath(SGSingAlternateModelANE); return path?:SGSingAlternateModelPath(SGSingAlternateModelLight);
}
BOOL SGSingAlternateModelsHandlesSession(NSString *identifier, void (^completion)(void)) {
    for(NSInteger i=1;i<=2;i++) { SGSingAlternateModel model=(SGSingAlternateModel)i; if([identifier isEqualToString:sessionID(model)]) { completions()[identifier]=[completion copy]; sessionFor(model); return YES; } }
    return NO;
}
void SGSingAlternateModelsReconnect(void) {
    for(NSInteger i=1;i<=2;i++) { SGSingAlternateModel model=(SGSingAlternateModel)i; NSInteger mode=SGInt(downloadKey(model),0); if(!mode)continue; if(complete(model)) { [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(model)]; continue; } NSString *sid=sessionID(model); NSURLSession *session=sessionFor(model); [session getAllTasksWithCompletionHandler:^(NSArray<NSURLSessionTask *> *all) {
        dispatch_async(dispatch_get_main_queue(), ^{ for(NSURLSessionTask *task in all) { NSInteger idx=task.taskDescription.integerValue; if(idx>=0&&idx<kCount&&[task isKindOfClass:NSURLSessionDownloadTask.class]) { tasks()[sid][@(idx)]=(id)task; if(!progresses()[sid]) progresses()[sid]=[NSMutableDictionary dictionary]; progresses()[sid][@(idx)]=@(task.countOfBytesReceived); } else [task cancel]; }
            [NSUserDefaults.standardUserDefaults removeObjectForKey:downloadKey(model)]; SGSingAlternateModelDownload(model,mode==2); post(); });
    }]; }
}
