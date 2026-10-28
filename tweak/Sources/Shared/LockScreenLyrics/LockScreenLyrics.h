// The line being sung in place of the artist in the system's now playing: lock screen, Dynamic Island,
// Control Center, CarPlay. There is a Live Activity for it too (Shared/LiveActivity). The
// lines and the clock come from Karaoke.
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

#define SGKeyLockScreenLyrics @"spotifyglass.lockScreenLyrics"
#define SGKeyLockScreenLyricsCover @"spotifyglass.lockScreenLyrics.cover"   // off until switched on

@interface SGLyricsCoverArtwork : MPMediaItemArtwork
@end

UIImage *SGLyricsCoverImage(UIImage *cover, NSString *previous, NSString *current, NSString *next, CGSize size);

// Moving artwork with lyrics: the moving artwork clip found for the track `uri`, a local file, which
// LyricsArtwork.x draws the lines over while that track plays. Main queue.
void SGLyricsArtworkSetMotion(NSString *uri, NSURL *file);
