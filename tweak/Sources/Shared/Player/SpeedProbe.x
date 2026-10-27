// FLEX builds only: the speed-rebuffer test (notes/speed-rebuffer.md). Every line is "speed-probe:" with t, seconds on
// the mach clock, so the mixer's silent runs line up with the player's buffering and speed-0 reports.
#if SG_DRIVER
#import <mach/mach_time.h>
#import "Core/SGCore.h"
#import "PlayerState.h"
#import "SpeedPitch.h"

static const int kMaxLines = 400;

static double seconds(uint64_t host) {
    static mach_timebase_info_data_t base;
    if (!base.denom) mach_timebase_info(&base);
    return (double)host * base.numer / base.denom / 1e9;
}

static void probeLog(NSString *line) {
    static int lines;
    if (lines++ < kMaxLines) SGLog(@"speed-probe: t %.3f %@", seconds(mach_absolute_time()), line);
}

@interface SGSpeedProbe : NSObject <SGPlayerStateObserver>
@end

@implementation SGSpeedProbe {
    int _buffering;   // -1 unknown
    BOOL _stalled;
}
- (instancetype)init {
    if ((self = [super init])) _buffering = -1;
    return self;
}
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    int buffering = [state respondsToSelector:NSSelectorFromString(@"isBuffering")] ? [[state valueForKey:@"isBuffering"] boolValue] : -1;
    BOOL stalled = state.isPlaying && !state.isPaused && state.playbackSpeed == 0;
    if (buffering != _buffering || stalled != _stalled) {
        probeLog([NSString stringWithFormat:@"report buffering %d speed %.2f playing %d paused %d position %.2f", buffering,
                  state.playbackSpeed, state.isPlaying, state.isPaused, state.position]);
    }
    _buffering = buffering;
    _stalled = stalled;
}
@end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGSpeedProbe *probe;
        probe = [SGSpeedProbe new];
        SGAddPlayerStateObserver(probe);
        static uint64_t seen;
        static double speed = 1;
        [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
            double now = SGPlayerSpeed();
            if (now != speed) probeLog([NSString stringWithFormat:@"speed %.2f -> %.2f", speed, now]);
            speed = now;
            uint64_t host;
            double ms;
            bool silentNow;
            uint64_t runs = SGSpeedProbeSilence(&host, &ms, &silentNow);
            if (runs != seen && speed != 1) {
                probeLog([NSString stringWithFormat:@"silent run %llu: %.0f ms from t %.3f%@", runs, ms, seconds(host),
                          runs - seen > 1 ? [NSString stringWithFormat:@" (%llu more since last)", runs - seen - 1] : @""]);
            }
            seen = runs;
        }];
    });
}
#endif
