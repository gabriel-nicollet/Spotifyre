// SPTEsperantoPlayer, the app's player, and the state it reports.
// The URIs are typed id: the runtime says only that they are objects, so a reader takes NSURL or NSString.
#import <Foundation/Foundation.h>

@interface SPTPlayerTrack : NSObject
@property (nonatomic, readonly) id URI;
@property (nonatomic, readonly) id artistURI;
@property (nonatomic, readonly) NSString *artistName;
@property (nonatomic, readonly) NSString *trackTitle;
// Every credited artist: artist_uri and artist_name, then artist_uri:1, artist_name:1 and on.
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *metadata;
// Where the track came from in the tracks to come: the album or playlist, a hand queue, autoplay
// (Shared/Player/SleepTimer.m reads it).
@property (nonatomic, readonly, copy) NSString *provider;
@end

@interface SPTPlayerOptions : NSObject
@property (nonatomic, readonly) BOOL shufflingContext;
@property (nonatomic, readonly) BOOL repeatingContext;
@property (nonatomic, readonly) BOOL repeatingTrack;
@end

// Spotify's own sleep timer as the player core reports it: es_sleep_timer.proto's oneof, which the state
// builder maps (hasSleepTimer, then setSleepTimer:) to type 0 none, 1 at `timestamp` (the proto's ms since
// 1970), 2 at the end of the track (Shared/Player/SpotifySleepTimer.m reads it).
@interface SPTSleepTimer : NSObject
@property (nonatomic, readonly) NSUInteger type;
@property (nonatomic, readonly) NSDate *timestamp;
@end

@interface SPTPlayerState : NSObject
@property (nonatomic, readonly) SPTPlayerTrack *track;
// Nil while the core reports none.
@property (nonatomic, readonly) SPTSleepTimer *sleepTimer;
@property (nonatomic, readonly) id contextURI;
@property (nonatomic, readonly) SPTPlayerOptions *options;
@property (nonatomic, readonly) BOOL isPaused;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isLoading;
// Seconds. position runs on from positionAsOfTimestamp by the time elapsed since timestamp, when the player reported.
@property (nonatomic, readonly) double position;
@property (nonatomic, readonly) double positionAsOfTimestamp;
@property (nonatomic, readonly) NSDate *timestamp;
// What position runs on at: 1, or Speed and pitch's speed (Shared/Player/SpeedPitch.x hooks it).
@property (nonatomic, readonly) double playbackSpeed;
// The track's length, in the same unit as position.
@property (nonatomic, readonly) double duration;
// The tracks to come and the ones played, nearest first; SPTPlayerTrack each, read with a type check.
@property (nonatomic, readonly) NSArray *future;
@property (nonatomic, readonly) NSArray *reverse;
@end

@protocol SPTPlayer <NSObject>
@property (nonatomic, readonly) SPTPlayerState *state;
- (void)addPlayerObserver:(id)observer;
- (void)skipToNextTrack;
- (void)seekTo:(double)seconds;
// The commands below take Spotify's options object, nil for the defaults, and return the command's
// pending result.
- (id)pause:(id)options;
- (id)resume:(id)options;
- (id)skipToNextTrackWithOptions:(id)options;
- (id)skipToPreviousTrackWithOptions:(id)options;
// Skips ahead to `track`, one of the state's future tracks.
- (id)skipToNextTrackWithOptions:(id)options track:(SPTPlayerTrack *)track;
- (id)setShufflingContext:(BOOL)on;
- (id)setRepeatingContext:(BOOL)on;
- (id)setRepeatingTrack:(BOOL)on;
@end
