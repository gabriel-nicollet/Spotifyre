#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <stdatomic.h>
#import "Shared/Lossless/SGPCMReplacement.h"

// SpeedPitch.x reads the player for its clock away from 1x; the harness has no player.
void *SGPlayerState(void) { return NULL; }

static int failures;
static SGPreparedPCM *asset;
static atomic_uint_fast64_t decoded, selected, stageFrames, badSamples, lastSourceEnd;
static atomic_bool mute;
static float expectedFirst;
static BOOL replacedBlock;
static AudioUnit output, mixer, converter;
static uint64_t stallEpoch, stallSelected;

static void expect(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", name); fflush(stdout);
    if (!ok) ++failures;
}
static void check(OSStatus status, const char *name) { expect(status == noErr, name); }
@interface SPTPlayerState : NSObject
@property(nonatomic) double positionAsOfTimestamp;
@property(nonatomic,strong) NSDate *timestamp;
@end
@implementation SPTPlayerState
- (double)playbackSpeed { return 1; }
- (double)position { return self.positionAsOfTimestamp-self.timestamp.timeIntervalSinceNow; }
@end

static OSStatus original(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                         UInt32 bus, UInt32 frames, AudioBufferList *data) {
    atomic_fetch_add(&decoded, frames);
    BOOL silent = atomic_load(&mute);
    for (UInt32 b=0;b<data->mNumberBuffers;++b) for (UInt32 i=0;i<frames;++i)
        ((float *)data->mBuffers[b].mData)[i] = silent ? 0 : 0.02;
    if (silent) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}
static void selector(AudioUnit unit, uint64_t epoch, double sourceFrame, double rate, UInt32 frames, AudioBufferList *data) {
    uint64_t before = SGPCMReplacementFrames();
    SGPCMReplacementApply(unit,epoch,sourceFrame,rate,frames,data);
    replacedBlock = SGPCMReplacementFrames() > before;
    if (replacedBlock) {
        atomic_fetch_add(&selected,frames);
        // The decoder must still advance; source epoch/counter are the real SpeedPitch callback's.
        uint64_t native=atomic_load(&decoded), end=(uint64_t)sourceFrame+frames;
        if (native < end || native-end > 4096) atomic_fetch_add(&badSamples,1);
        const float *left=asset.left, *right=asset.right;
        for (UInt32 i=0;i<frames;++i) {
            if (((float *)data->mBuffers[0].mData)[i] != left[(uint64_t)sourceFrame+i]
                || ((float *)data->mBuffers[1].mData)[i] != right[(uint64_t)sourceFrame+i])
                atomic_fetch_add(&badSamples,1);
        }
        expectedFirst=((float *)data->mBuffers[0].mData)[0];
        atomic_store(&lastSourceEnd,(uint64_t)sourceFrame+frames);
    }
}
// A stand-in stage: inspect the actual pull callback Sing receives, then alter its samples.
static OSStatus stage(UInt32 frames, AudioBufferList *data, SGPlayerPull pull, void *context) {
    replacedBlock=NO;
    OSStatus status=pull(context,frames,data,NULL);
    if (!status && replacedBlock) {
        if (((float *)data->mBuffers[0].mData)[0] != expectedFirst) atomic_fetch_add(&badSamples,1);
        atomic_fetch_add(&stageFrames,frames);
        for (UInt32 b=0;b<data->mNumberBuffers;++b) for (UInt32 i=0;i<frames;++i)
            ((float *)data->mBuffers[b].mData)[i]*=0.5;
    }
    return status;
}
static AudioUnit make(OSType type, OSType subtype) {
    AudioComponentDescription description={type,subtype,kAudioUnitManufacturer_Apple,0,0};
    AudioUnit unit=NULL;
    check(AudioComponentInstanceNew(AudioComponentFindNext(NULL,&description),&unit),"create audio unit");
    return unit;
}
static void setup(void) {
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    converter=make(kAudioUnitType_FormatConverter,kAudioUnitSubType_AUConverter);
    mixer=make(kAudioUnitType_Mixer,kAudioUnitSubType_MultiChannelMixer);
    output=make(kAudioUnitType_Output,kAudioUnitSubType_RemoteIO);
    AURenderCallbackStruct callback={original,NULL};
    check(AudioUnitSetProperty(converter,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof callback),"native input callback");
    AudioStreamBasicDescription format={44100,kAudioFormatLinearPCM,kAudioFormatFlagsNativeFloatPacked|kAudioFormatFlagIsNonInterleaved,4,1,4,2,32,0};
    AudioUnit units[]={converter,mixer,output};
    for(int i=0;i<3;++i) {
        check(AudioUnitSetProperty(units[i],kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,sizeof format),"input format");
        if(i<2) check(AudioUnitSetProperty(units[i],kAudioUnitProperty_StreamFormat,kAudioUnitScope_Output,0,&format,sizeof format),"output format");
        UInt32 slice=4096;
        check(AudioUnitSetProperty(units[i],kAudioUnitProperty_MaximumFramesPerSlice,kAudioUnitScope_Global,0,&slice,sizeof slice),"slice");
    }
    AudioUnitConnection a={converter,0,0}, b={mixer,0,0};
    check(AudioUnitSetProperty(mixer,kAudioUnitProperty_MakeConnection,kAudioUnitScope_Input,0,&a,sizeof a),"connect converter");
    check(AudioUnitSetProperty(output,kAudioUnitProperty_MakeConnection,kAudioUnitScope_Input,0,&b,sizeof b),"connect mixer");
    for(int i=0;i<3;++i) check(AudioUnitInitialize(units[i]),"initialize");
    check(AudioOutputUnitStart(output),"start");
}
static void later(double seconds, dispatch_block_t action) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
static void directTests(void) {
    NSError *error=nil;
    NSURL *url=[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"fixture.flac"];
    SGPCMDecodeCancellation *token=[SGPCMDecodeCancellation new];
    asset=[SGPreparedPCM prepareURL:url sampleRate:44100 maxBytes:8*1024*1024 cancellation:token error:&error];
    expect(asset && !error && asset.frameCount==529200,"native FLAC -> complete planar PCM");
    if(!asset) exit(1);
    double maxError=0;
    for(uint64_t i=0;i<asset.frameCount;++i) {
        maxError=fmax(maxError,fabs(asset.left[i]-0.08*sin(2*M_PI*440*i/44100.0)));
        maxError=fmax(maxError,fabs(asset.right[i]-0.06*sin(2*M_PI*997*i/44100.0)));
    }
    expect(maxError<0.00004,"decoded stereo waveform matches generated recording");
    SGPreparedPCM *exact=[SGPreparedPCM prepareURL:url sampleRate:44100 maxBytes:529200*8 cancellation:token error:&error];
    expect(exact && !error && exact.frameCount==529200,"a file exactly filling its PCM budget is accepted");
    SGPreparedPCM *alac=[SGPreparedPCM prepareURL:[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"fixture.m4a"]
        sampleRate:48000 maxBytes:8*1024*1024 cancellation:token error:&error];
    expect(alac && !error && alac.frameCount==576000,"ALAC converts to planar 48 kHz");
    expect(![SGPreparedPCM prepareURL:url sampleRate:44100 maxBytes:8192 cancellation:token error:&error],"PCM budget rejects oversized decode");
    [token cancel];
    expect(![SGPreparedPCM prepareURL:url sampleRate:44100 maxBytes:8*1024*1024 cancellation:token error:&error]
           && error.code==1,"cancelled preparation returns no asset");
    token=[SGPCMDecodeCancellation new];
    expect(![SGPreparedPCM prepareURL:[NSURL URLWithString:@"https://invalid.example/audio.flac"] sampleRate:44100 maxBytes:8192 cancellation:token error:&error],"decoder rejects network URL");
    SGPCMReplacementEnable();
    AudioUnit fake=(AudioUnit)(uintptr_t)0x1234;
    uint64_t epoch=SGPlayerSourceEpoch();
    expect(SGPCMReplacementInstall(asset,fake,epoch,100,200),"publish source/asset anchor");
    float l[256],r[256];
    struct {AudioBufferList list;AudioBuffer second;} buffers={{2,{{1,sizeof l,l}}},{1,sizeof r,r}};
    for(int i=0;i<256;++i) l[i]=r[i]=0.02;
    SGPCMReplacementApply(fake,epoch,110,44100,256,&buffers.list);
    expect(!memcmp(l,asset.left+210,sizeof l) && !memcmp(r,asset.right+210,sizeof r),"frame-aligned replacement, both channels");
    for(int test=0;test<7;++test) {
        for(int i=0;i<256;++i) l[i]=r[i]=0.02;
        uint64_t e=epoch; double frame=110,rate=44100; AudioUnit unit=fake;
        if(test==0) e--;
        if(test==1) unit=NULL;
        if(test==2) rate=48000;
        if(test==3) frame=NAN;
        if(test==4) frame=99;
        if(test==5) frame=asset.frameCount-200+100-128;
        if(test==6) buffers.second.mDataByteSize=4;
        SGPCMReplacementApply(unit,e,frame,rate,256,&buffers.list);
        BOOL untouched=YES;
        for(int i=0;i<256;++i) untouched &= l[i]==(float)0.02 && r[i]==(float)0.02;
        expect(untouched,"invalid generation/output/rate/anchor/EOF/layout preserves native span");
        buffers.second.mDataByteSize=sizeof r;
    }
    SGPCMReplacementCancel();
    expect(!SGPCMReplacementInstall(asset,fake,epoch,0,0),"late publication rejected after cancellation");
    __weak SGPreparedPCM *weakAsset;
    @autoreleasepool {
        SGPreparedPCM *temporary=[SGPreparedPCM prepareURL:url sampleRate:44100 maxBytes:8*1024*1024 cancellation:token error:&error];
        weakAsset=temporary;
        expect(SGPCMReplacementInstall(temporary,fake,SGPlayerSourceEpoch(),0,0),"publish independently owned PCM");
    }
    expect(weakAsset!=nil,"published snapshot retains decoded storage");
    SGPCMReplacementCancel();
    expect(weakAsset==nil,"cancel releases storage after readers leave");
    // Race live readers against replacement, cancellation and reclamation; every returned block must
    // be wholly native or wholly one of two valid asset spans, never torn between generations.
    dispatch_group_t group=dispatch_group_create();
    __block atomic_int torn; atomic_init(&torn,0);
    dispatch_group_async(group,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        float a[256],b[256];
        struct {AudioBufferList list;AudioBuffer second;} block={{2,{{1,sizeof a,a}}},{1,sizeof b,b}};
        for(int i=0;i<20000;++i) {
            for(int j=0;j<256;++j) a[j]=b[j]=0.02;
            SGPCMReplacementApply(fake,SGPlayerSourceEpoch(),0,44100,256,&block.list);
            BOOL native=YES;
            for(int j=0;j<256;++j) native &= a[j]==(float)0.02 && b[j]==(float)0.02;
            BOOL first=!memcmp(a,asset.left,sizeof a)&&!memcmp(b,asset.right,sizeof b);
            BOOL second=!memcmp(a,asset.left+500,sizeof a)&&!memcmp(b,asset.right+500,sizeof b);
            if(!native&&!first&&!second) atomic_fetch_add(&torn,1);
        }
    });
    for(int i=0;i<2000;++i) {
        if(i%3==0) SGPCMReplacementCancel();
        SGPCMReplacementInstall(asset,fake,SGPlayerSourceEpoch(),0,i%2?500:0);
    }
    dispatch_group_wait(group,DISPATCH_TIME_FOREVER);
    expect(atomic_load(&torn)==0,"concurrent publication/cancel keeps whole snapshots");
    SGPCMReplacementCancel();
}
static void realTests(void) {
    SGPlayerSetSourceSelector(selector);
    setup();
    later(0.5,^{
        expect(SGPlayerSpeedAllowed() && SGPlayerMusicOutput()==output,"real mixer-to-RemoteIO seam reached");
        expect(SGPCMReplacementInstall(asset,output,SGPlayerSourceEpoch(),0,0),"prepare real output source");
    });
    later(1.2,^{
        expect(atomic_load(&selected)>0,"replacement runs with no Sing stage registered");
        SGPlayerSetStage(stage);
    });
    later(2.0,^{
        expect(atomic_load(&stageFrames)>0,"existing stage receives replacement PCM");
        expect(atomic_load(&badSamples)==0,"source waveform and native advancement agree");
        SGSetPlayerSpeed(1.5);
    });
    later(2.8,^{
        expect(atomic_load(&badSamples)==0,"speed processing pulls the same source before the stage");
        SGSetPlayerSpeed(1);
        SGPCMReplacementCancel();
        later(0.1,^{
            uint64_t at=atomic_load(&selected);
            later(0.15,^{expect(atomic_load(&selected)==at,"cancelled source stops replacement");});
        });
    });
    later(3.3,^{
        uint64_t epoch=SGPlayerSourceEpoch();
        expect(SGPCMReplacementInstall(asset,output,epoch,0,0),"re-arm current occurrence");
        SGPlayerInvalidateSource(); // the playback owner must do this on seek/skip, even on the same URI
        expect(!SGPCMReplacementInstall(asset,output,epoch,0,0),"seek/repeat generation rejects late preparation");
    });
    later(3.8,^{
        SGPCMReplacementCancel();
        check(AudioOutputUnitStop(output),"pause original output");
        uint64_t d=atomic_load(&decoded);
        later(0.2,^{expect(atomic_load(&decoded)==d,"pause stops native decoder advancement");});
    });
    later(4.2,^{
        check(AudioOutputUnitStart(output),"resume original output");
        expect(SGPCMReplacementInstall(asset,output,SGPlayerSourceEpoch(),0,0),"re-arm after output restart");
        stallEpoch=SGPlayerSourceEpoch();
        atomic_store(&mute,true);
    });
    later(4.6,^{
        uint64_t at=atomic_load(&selected);
        expect(SGPlayerSourceEpoch()!=stallEpoch,"native stall invalidates the recording/frame anchor");
        later(0.2,^{
            expect(atomic_load(&selected)==at,"native silent/stalled spans cannot be replaced");
            stallSelected=atomic_load(&selected);
            atomic_store(&mute,false);
        });
    });
    later(5.0,^{
        expect(atomic_load(&selected)==stallSelected,"native recovery cannot reuse the pre-stall anchor");
        uint64_t epoch=SGPlayerSourceEpoch();
        AudioStreamBasicDescription format={44100,kAudioFormatLinearPCM,kAudioFormatFlagsNativeFloatPacked|kAudioFormatFlagIsNonInterleaved,4,1,4,2,32,0};
        check(AudioUnitSetProperty(output,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,sizeof format),"format notification");
        expect(SGPlayerSourceEpoch()!=epoch,"format notification invalidates prepared source");
    });
    later(5.5,^{
        uint64_t epoch=SGPlayerSourceEpoch();
        check(AudioComponentInstanceDispose(mixer),"dispose mixer during running output"); mixer=NULL;
        expect(SGPlayerSourceEpoch()!=epoch,"mixer disposal invalidates source");
    });
    later(6.0,^{
        SGPCMReplacementCancel(); SGPlayerSetStage(NULL); SGPlayerSetSourceSelector(NULL);
        AudioOutputUnitStop(output); AudioComponentInstanceDispose(output); AudioComponentInstanceDispose(converter);
        printf("RESULT failures=%d nativeFrames=%llu replacementFrames=%llu stageFrames=%llu\n",failures,
            (unsigned long long)atomic_load(&decoded),(unsigned long long)atomic_load(&selected),
            (unsigned long long)atomic_load(&stageFrames)); fflush(stdout); exit(failures?1:0);
    });
}
@interface LosslessHandoff : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation LosslessHandoff
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[UIViewController new];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        directTests(); dispatch_async(dispatch_get_main_queue(),^{realTests();});
    });
    later(30,^{printf("FAIL watchdog\n"); fflush(stdout); exit(124);});
    return YES;
}
@end
int main(int argc,char **argv) { @autoreleasepool{return UIApplicationMain(argc,argv,nil,@"LosslessHandoff");} }
