// How the redesign's lyrics are set, from the Lyrics page: size, spacing, distant blur, held-word glow and
// wave, inactive-text opacity, and bloom around the sung line. A preset sets them all; the sliders apply
// changes at once to every lyrics view, including the Lyrics page's preview (LyricsLookSettings.m).
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// size and spacing in points; blur, glow and wave are shares of Apple Music's; opacity is the dim lyric alpha,
// and bloom is the sung line's halo from 0 to 1.
typedef struct {
    CGFloat size, spacing, blur, glow, wave, opacity, bloom;
} SGRLyricsLook;

// All seven as one dictionary; unset is the first preset, Apple Music's.
#define SGRKeyLyricsLook @"spotifyglass.redesign.lyricsLook"

// Posted on the main queue when the look changes; the object is whoever changed it, nil for none named.
extern NSNotificationName const SGRLyricsLookDidChangeNotification;

SGRLyricsLook SGRLyricsLookNow(void);
void SGRSetLyricsLook(SGRLyricsLook look, id changer);

// The presets, by name, Apple Music's first.
NSArray<NSString *> *SGRLyricsLookPresetNames(void);
SGRLyricsLook SGRLyricsLookPreset(NSUInteger index);
// The preset the look is, or -1 for a look of the sliders' own.
NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look);

// A few lines of the preview's own, words timed, one held long enough to glow and wave, and how long
// they take to come round again.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void);
NSInteger SGRLyricsSampleLength(void);

// LyricsLookSettings.m: the Lyrics page in the redesign, leading with the preview, the presets under it
// and their sliders in a sheet, then `sections`.
@class SGModSection;
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections);
