// The lock screen's full-screen artwork as the lyrics, a clip per line (SGLyricsClip.h draws it). A timer
// works out the line being sung and hands the lock screen a new artwork under a new ID each time it
// changes. Nothing is drawn until the lock screen asks for that artwork's video, so lines sung with the
// screen off cost nothing. It rides on Spotify's now playing info as an extra (NowPlayingExtras.h), like
// the moving artwork it takes the place of.
//
// Moving artwork with lyrics draws the lines over the track's moving artwork instead, which
// LockScreenMotion.x finds and hands over (SGLyricsArtworkSetMotion): each line's clip is the stretch of it
// the song is at while the line shows, taken round its length, with the line sung last dimmed above. Until the
// clip comes, and for a track that has none, the lines are drawn as Lyrics draws them; the clip coming
// changes every ID, so the line showing is offered again over it.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "LockScreenLyrics.h"
#import "SGLyricsClip.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"

static const NSTimeInterval kTick = 0.25;
// Past a line's sung end by this much, with the next line at least this far off, the line is let go and
// only the next one shows, dimmed (as the artist row does in LockScreenLyrics.x).
static const NSInteger kBreakMs = 4000;
// A line's clip over moving artwork lasts from the line's start to the next one's, a second longer for the
// lock screen showing it late, and between these: the cost of a clip is its length.
static const double kShortest = 2, kLongest = 8;

// What a line's artwork shows, kept by its request blocks.
@interface SGLockLine : NSObject
@property (nonatomic, copy) NSString *previous, *line, *next;   // nil for none
@property (nonatomic) UIImage *cover;
@property (nonatomic) SGLyricsClipStyle style;
@property (nonatomic) NSURL *motion;          // the moving artwork under the words, nil for the blurred cover
@property (nonatomic) double from, seconds;   // where in the song the clip starts and how long it is
@end

@implementation SGLockLine
@end

static dispatch_source_t sg_timer;
static NSString *sg_motionURI;   // the track the moving artwork is for, and its file (SGLyricsArtworkSetMotion)
static NSURL *sg_motion;
// Paths of moving artwork that would not draw (turned, its frames another size than it states, cut short, or
// gone from the store), so each line goes straight to the cover; a file handed over again is tried again. Read
// on main and both queues, so only under its own lock.
static NSMutableSet<NSString *> *sg_failedMotion;

static BOOL motionFailed(NSURL *file) {
    @synchronized (sg_failedMotion) {
        return [sg_failedMotion containsObject:file.path];
    }
}

static void markMotionFailed(NSURL *file, NSString *artworkID) {
    @synchronized (sg_failedMotion) {
        if ([sg_failedMotion containsObject:file.path]) return;
        [sg_failedMotion addObject:file.path];
    }
    SGLog(@"lock lyrics: %@ would not draw for %@, the lines go over the cover for it", file.lastPathComponent, artworkID);
}
static NSString *sg_track;     // the track the clips are for
static UIImage *sg_cover;      // its cover, once Spotify's now playing info has one for it
static NSString *sg_shownID;   // the artwork handed over last, nil for none; read on sg_queue too
static NSObject *sg_lock;
static dispatch_queue_t sg_queue;   // writes the clips, one at a time
// Draws the previews, apart from the clips: one waiting behind a clip that takes seconds left the lock screen blank.
static dispatch_queue_t sg_previewQueue;

static NSURL *folder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"Vitrine/Lyrics" isDirectory:YES];
}

// The blurred cover, made once per cover and shared by both queues; the caller releases it.
static CGImageRef copyBackdropFor(UIImage *cover, CGSize size) {
    static id made;
    static CGImageRef backdrop;
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    @synchronized (lock) {
        id key = cover ?: NSNull.null;
        if (!backdrop || made != key) {
            CGImageRelease(backdrop);
            backdrop = SGLyricsClipBackdrop(cover.CGImage, size);
            made = key;
        }
        return CGImageRetain(backdrop);
    }
}

static BOOL stillShown(NSString *artworkID) {
    @synchronized (sg_lock) {
        return [artworkID isEqualToString:sg_shownID];
    }
}

static void setShown(NSString *artworkID) {
    @synchronized (sg_lock) {
        sg_shownID = artworkID;
    }
}

// The lock screen's last asks, as absolute times: lines are drawn ahead only while it is showing them, previews and
// clips each by their own asks, as it asks for clips far less often.
static CFAbsoluteTime sg_askedAt, sg_previewAskedAt;
// Previews drawn ahead, by artwork ID.
static NSCache<NSString *, UIImage *> *sg_previews;

static NSURL *clipFile(NSString *artworkID) {
    return [folder() URLByAppendingPathComponent:[artworkID stringByAppendingPathExtension:@"mp4"]];
}

// On sg_previewQueue. Over moving artwork that will not read, the blurred cover's.
static UIImage *previewFor(NSString *artworkID, SGLockLine *line, CGSize size) {
    UIImage *preview = [sg_previews objectForKey:artworkID];
    if (preview) return preview;
    BOOL tryMotion = line.motion && !motionFailed(line.motion);
    CGImageRef frame = tryMotion ? SGLyricsClipMotionFrame(line.motion, line.previous, line.line, line.next, line.from) : NULL;
    if (tryMotion && !frame) markMotionFailed(line.motion, artworkID);
    if (!frame) {
        CGImageRef backdrop = copyBackdropFor(line.cover, size);
        frame = SGLyricsClipFrame(backdrop, line.line, line.next, size);
        CGImageRelease(backdrop);
    }
    if (frame) [sg_previews setObject:(preview = [UIImage imageWithCGImage:frame]) forKey:artworkID];
    CGImageRelease(frame);
    return preview;
}

// On sg_queue. A clip drawn ahead is found on disk and handed over at once. Over moving artwork that will not
// read, it is drawn over the blurred cover.
static BOOL writeClip(NSString *artworkID, SGLockLine *line, CGSize size) {
    NSURL *file = clipFile(artworkID);
    if ([NSFileManager.defaultManager fileExistsAtPath:file.path]) return YES;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    BOOL tryMotion = line.motion && !motionFailed(line.motion);
    BOOL over = tryMotion && SGLyricsClipWriteOverMotion(file, line.motion, line.previous, line.line, line.next, line.from, line.seconds);
    if (tryMotion && !over) markMotionFailed(line.motion, artworkID);
    BOOL ok = over;
    if (!ok) {
        CGImageRef backdrop = copyBackdropFor(line.cover, size);
        ok = SGLyricsClipWrite(file, backdrop, line.line, line.next, size, line.style);
        CGImageRelease(backdrop);
    }
    // The first few of a launch of each kind, and any that fails: one a line would fill the log.
    static NSUInteger told[2];
    if (!ok || told[over]++ < 5) {
        SGLog(@"lock lyrics: %@ %@ in %.0f ms%@", artworkID, ok ? @"written" : @"not written", (CFAbsoluteTimeGetCurrent() - start) * 1000,
              over ? [NSString stringWithFormat:@", up to %.1f s of %@ from %.1f s", line.seconds, line.motion.lastPathComponent, line.from] : @"");
    }
    return ok;
}

// The next line's preview and clip, drawn while this one shows: a line change then hands both over at once, where
// drawing them on request left the lock screen on the plain cover for half a second.
static void drawAhead(NSString *artworkID, SGLockLine *line) {
    CFAbsoluteTime time = CFAbsoluteTimeGetCurrent();
    CGSize size = SGLyricsClipSize(SGMotionPixels());
    if (time - sg_previewAskedAt <= 15) dispatch_async(sg_previewQueue, ^{ previewFor(artworkID, line, size); });
    if (time - sg_askedAt <= 15) dispatch_async(sg_queue, ^{ writeClip(artworkID, line, size); });
}

API_AVAILABLE(ios(26.0))
static MPMediaItemAnimatedArtwork *artworkFor(NSString *artworkID, SGLockLine *line) {
    CGSize size = SGLyricsClipSize(SGMotionPixels());
    return [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:artworkID
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
            sg_previewAskedAt = CFAbsoluteTimeGetCurrent();
            // One drawn ahead is handed over at once, as Apple asks of a preview; only a miss waits for drawing.
            UIImage *ready = [sg_previews objectForKey:artworkID];
            if (ready) {
                completion(ready);
                return;
            }
            dispatch_async(sg_previewQueue, ^{
                completion(previewFor(artworkID, line, size));
                static NSUInteger told;
                if (told++ < 10) SGLog(@"lock lyrics: preview of %@ was not drawn ahead", artworkID);
            });
        }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            sg_askedAt = CFAbsoluteTimeGetCurrent();
            dispatch_async(sg_queue, ^{
                // A line already sung by the time its turn comes is not drawn.
                if (!stillShown(artworkID)) {
                    completion(nil);
                    return;
                }
                completion(writeClip(artworkID, line, size) ? clipFile(artworkID) : nil);
            });
        }];
}

static void clear(void) {
    if (!sg_shownID) return;
    setShown(nil);
    SGNowPlayingSetExtras(@"lyrics", nil, nil);
}

static NSString *textAt(NSArray<SGKaraokeLine *> *lines, NSInteger index) {
    return index >= 0 && index < (NSInteger)lines.count ? SGKaraokeLineText(lines[index]) : nil;
}

void SGLyricsArtworkSetMotion(NSString *uri, NSURL *file) {
    @synchronized (sg_failedMotion) {
        if (file) [sg_failedMotion removeObject:file.path];
    }
    sg_motionURI = uri;
    sg_motion = file;
}

// What the artwork for line `index` shows, `resting` once its break has come (index -1, before the first line,
// always rests). Over moving artwork, the stretch of song from when it shows until the next artwork does.
static SGLockLine *lineAt(NSArray<SGKaraokeLine *> *lines, NSInteger index, BOOL resting, NSURL *motion,
                          UIImage *cover, SGLyricsClipStyle style) {
    SGLockLine *shown = [SGLockLine new];
    // Resting, the line sung is let go and the one coming shows alone.
    shown.line = resting ? nil : textAt(lines, index);
    shown.next = textAt(lines, index + 1);
    shown.previous = motion && !resting ? textAt(lines, index - 1) : nil;
    shown.cover = cover;
    shown.style = style;
    shown.motion = motion;
    NSInteger start = index < 0 ? 0 : resting ? SGKaraokeSungEnd(lines[index]) + kBreakMs : lines[index].start;
    NSInteger end = index + 1 < (NSInteger)lines.count ? lines[index + 1].start : index < 0 ? start : SGKaraokeSungEnd(lines[index]) + kBreakMs;
    shown.from = start / 1000.0;
    shown.seconds = MIN(MAX((end - start) / 1000.0 + 1, kShortest), kLongest);
    return shown;
}

static void tick(void) {
    if (@available(iOS 26.0, *)) {
        SPTPlayerState *state = SGPlayerState();
        NSString *trackID = SGKaraokePlayingTrack();
        if (!trackID || !state) {
            clear();
            return;
        }
        if (![trackID isEqualToString:sg_track]) {
            sg_track = trackID;
            sg_cover = nil;
            // The IDs name the track, so the last track's clips are never asked for again.
            dispatch_async(sg_queue, ^{
                [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];
                [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
            });
        }
        NSArray<SGKaraokeLine *> *lines = SGKaraokeLinesForTrack(trackID);
        if (!lines) SGKaraokeRequestLyrics(trackID);
        // Plain text has no line being sung, nor has a song whose lines are not in yet: the lock screen keeps the cover,
        // or under Moving artwork with lyrics shows the moving artwork plain (LockScreenMotion.x, which has it).
        if (!lines.count || SGKaraokeLinesTiming(lines) == SGKaraokeTimingNone) {
            static NSString *told;
            if (lines && ![told isEqualToString:trackID]) {
                told = trackID;
                SGLog(@"lock lyrics: %@ has no synced lines, the lock screen keeps the cover or the moving artwork", trackID);
            }
            clear();
            SGLockMotionShowPlain(YES);
            return;
        }
        NSInteger position = SGKaraokePositionMs();
        if (position < 0) return;
        position -= SGKaraokeDelayMs();
        NSInteger index = SGKaraokeLeadLine(lines, position);
        BOOL nextFarOff = index + 1 == (NSInteger)lines.count || lines[index + 1].start - position > kBreakMs;
        BOOL resting = index < 0 || (position > SGKaraokeSungEnd(lines[index]) + kBreakMs && nextFarOff);
        SGLyricsClipStyle style = (SGLyricsClipStyle)SGInt(SGKeyLockScreenLyricsStyle, SGLyricsClipStill);
        NSURL *motion = SGLockScreenArtwork() == SGLockArtworkMotionLyrics && [sg_motionURI isEqualToString:SGURIString(state.track.URI)]
            ? sg_motion : nil;
        if (motion && motionFailed(motion)) motion = nil;
        // A line over moving artwork decodes and encodes up to 240 frames, one over the cover a still frame: a phone
        // already hot gets the cover, as Sing.x keeps its model below Serious, and the motion back once it cools.
        if (motion && NSProcessInfo.processInfo.thermalState >= NSProcessInfoThermalStateSerious) {
            static CFAbsoluteTime told;
            if (CFAbsoluteTimeGetCurrent() - told > 60) SGLog(@"lock lyrics: the phone is hot, the lines go over the cover");
            told = CFAbsoluteTimeGetCurrent();
            motion = nil;
        }
        NSString *look = SGLyricsClipLook(motion, style);
        NSString *artworkID = [NSString stringWithFormat:@"%@-%ld%@-%@", trackID, (long)index, resting ? @"r" : @"", look];
        if ([artworkID isEqualToString:sg_shownID]) return;
        // Spotify's request block for its cover, read on main and kept once it is this track's.
        if (!sg_cover) {
            NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
            MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
            if ([info[MPMediaItemPropertyTitle] isEqual:state.track.trackTitle] && [artwork isKindOfClass:MPMediaItemArtwork.class]) {
                sg_cover = [artwork imageWithSize:CGSizeMake(600, 600)];
            }
        }
        if (![sg_shownID hasPrefix:trackID]) SGLog(@"lock lyrics: lines offered for %@", trackID);
        if (motion && ![sg_shownID hasSuffix:[@"-" stringByAppendingString:look]]) SGLog(@"lock lyrics: the lines of %@ over %@", trackID, motion.lastPathComponent);
        setShown(artworkID);
        SGLockMotionShowPlain(NO);
        SGNowPlayingSetExtras(@"lyrics", @{MPNowPlayingInfoProperty3x4AnimatedArtwork:
                                               artworkFor(artworkID, lineAt(lines, index, resting, motion, sg_cover, style))},
                              state.track.trackTitle);
        if (index + 1 < (NSInteger)lines.count) {
            NSString *ahead = [NSString stringWithFormat:@"%@-%ld-%@", trackID, (long)index + 1, look];
            drawAhead(ahead, lineAt(lines, index + 1, NO, motion, sg_cover, style));
        }
    }
}

// Main thread, as everything the timer touches is.
static void setTicking(BOOL on) {
    if (on == (sg_timer != nil)) return;
    if (!on) {
        dispatch_source_cancel(sg_timer);
        sg_timer = nil;
        return;
    }
    // A strict GCD timer: the main run loop's timers are throttled while the screen is off, and the lines stood
    // still on a locked phone.
    sg_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_main_queue());
    uint64_t every = (uint64_t)(kTick * NSEC_PER_SEC);
    dispatch_source_set_timer(sg_timer, dispatch_time(DISPATCH_TIME_NOW, every), every, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(sg_timer, ^{
        static CFAbsoluteTime last;
        static int late;
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (last && now - last > 2 && late++ < 5) SGLog(@"%s: ticked %.1f s late", __FILE_NAME__, now - last - kTick);
        last = now;
        tick();
    });
    dispatch_resume(sg_timer);
}

@interface SGLyricsArtwork : NSObject <SGPlayerStateObserver>
@end

@implementation SGLyricsArtwork
// A paused player's line does not move, and the lock screen keeps the clip it was left on. Picked or not is read
// each time, so a change on the Lock screen page applies at once.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    BOOL on = SGLockArtworkShowsLyrics(SGLockScreenArtwork());
    setTicking(on && !state.isPaused);
    if (on) tick();
    else clear();
}
@end

%ctor {
    if (@available(iOS 26.0, *)) {
        sg_lock = [NSObject new];
        sg_queue = dispatch_queue_create("spotifyglass.lockscreen.lyrics", DISPATCH_QUEUE_SERIAL);
        sg_previewQueue = dispatch_queue_create("spotifyglass.lockscreen.lyrics.preview", DISPATCH_QUEUE_SERIAL);
        sg_previews = [NSCache new];
        sg_failedMotion = [NSMutableSet set];
        sg_previews.countLimit = 4;
        static SGLyricsArtwork *observer;
        observer = [SGLyricsArtwork new];
        SGAddPlayerStateObserver(observer);
        // Heard on the writing thread and handed to main without waiting (AGENTS.md).
        static SGLockArtwork choice;
        choice = SGLockScreenArtwork();
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (SGLockScreenArtwork() == choice) return;
                choice = SGLockScreenArtwork();
                SGLog(@"lock lyrics: %@", !SGLockArtworkShowsLyrics(choice) ? @"no longer picked" : choice == SGLockArtworkLyrics ? @"picked" : @"picked over the moving artwork");
                [observer playerStateDidChange:SGPlayerState()];
            });
        }];
        SGLog(@"lock lyrics: %@, the lock screen takes %@", !SGLockArtworkShowsLyrics(choice) ? @"off" : choice == SGLockArtworkLyrics ? @"on" : @"on over the moving artwork",
              MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
    }
}
