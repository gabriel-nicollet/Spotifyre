// What ListeningStats.x takes from Shared/Player/PlayerState.x and Spotify: the observer is kept so main.m can
// report states to it, and the player's classes are plain objects main.m fills through KVC.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"

@implementation SPTPlayerTrack
@end

@implementation SPTPlayerState
@end

@implementation SPTPlayerOptions
@end

id<SGPlayerStateObserver> SGHarnessObserver;

void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    SGHarnessObserver = observer;
}

NSString *SGURIString(id uri) {
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}
