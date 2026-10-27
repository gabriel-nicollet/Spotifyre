// The album redesign: Spotify's album page kept, with its header, its track list and its controls, and laid
// out the way the Music app lays an album out -- the same page the playlist redesign gives a playlist, so
// the two read as one app.
//
// The album page is not the playlist's. It is built by the Creative Work Platform out of the element
// framework (trees/clean/album/01.txt: CreativeWorkPlatform.CreativeWorkTemplateView, a header element over
// one list), its header is a column of stack views rather than a plain block, and its play and shuffle
// float over the page instead of scrolling with the header. So none of Redesigned/Playlist/ is shared: only
// the Kit is, which is what keeps the look the same.
//
//     AlbumField.x     the artwork field behind the whole page, the artwork it is read from, the flags the
//                      screen forces
//     AlbumHeader.x    the header: the cover full bleed at the top dissolving into the field, and the Kit's
//                      SGRHeaderInfo over it -- title, artist, kind and date, shuffle, a white Play, add
//     AlbumRows.x      the track rows on the field with no surface of their own and a hairline between them,
//                      and no artist line where it only repeats the album's (AlbumCredits.m decides)
//     AlbumSections.x  everything under the tracks dropped but the album's own line and its copyright: no
//                      more by the artist, no videos, no concerts, no merch, no you might also like, each
//                      back once its switch is off
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI); the native look's do not then.
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Apple Music's animated cover at the top of an album; on until switched off (AlbumSettings.m).
#define SGRKeyAlbumMotion @"spotifyglass.redesign.album.motion"
UIViewController *SGRAlbumSettingsPage(void);

// AlbumSections.x. The sections under the tracks, one switch each, all dropped until switched off; the last
// is every section none of the others names.
#define SGRKeyAlbumHideMoreBy @"spotifyglass.redesign.album.hide.moreBy"
#define SGRKeyAlbumHideVideos @"spotifyglass.redesign.album.hide.videos"
#define SGRKeyAlbumHideConcerts @"spotifyglass.redesign.album.hide.concerts"
#define SGRKeyAlbumHideMerch @"spotifyglass.redesign.album.hide.merch"
#define SGRKeyAlbumHideYouMightLike @"spotifyglass.redesign.album.hide.youMightLike"
#define SGRKeyAlbumHideOther @"spotifyglass.redesign.album.hide.other"

// AlbumRows.x. A track row's artist line goes when it only repeats the album's artist, with the explicit badge
// moved up beside the title; on until switched off (AlbumSettings.m).
#define SGRKeyAlbumHideTrackArtists @"spotifyglass.redesign.album.hide.trackArtists"
// The album's artist as the header of the page `view` is on shows it, for the rows to compare theirs with. A
// change lays the page's track rows out again; the same artist again is a no-op.
void SGRAlbumSetArtist(UIView *view, NSString *artist);
// AlbumCredits.m. Whether a row's artist line says nothing the album's header does not: it is the album's
// artist, or the album's artist and the guests the title names after "feat.", "ft.", "featuring" or "with".
BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title);

// The album page `view` is on, or nil: the CreativeWorkTemplateView that carries the header, the list and
// the two floating controls (trees/clean/album/01.txt:22).
UIView *SGRAlbumPageOf(UIView *view);

// AlbumField.x. The field belongs to the page `view` is on, found by walking up from it, so two album pages
// on the navigation stack keep a field each.
//
// The color the page's field is showing, SGRNeutralField() before one has been read: what the header's
// cover has to dissolve into for there to be no seam.
UIColor *SGRAlbumFieldColor(UIView *view);
// The cover of the page `view` is on, for its field to take its color from. The same image again is a no-op.
void SGRAlbumSetArtwork(UIView *view, UIImage *image);
// The color Spotify picked for the album, read off the wash it paints behind the header: the field shows it
// until the cover's own main color has been read, and not after.
void SGRAlbumSetSpotifyColor(UIView *view, UIColor *color);
// The page comes in whole once its cover has been read (Kit/SGRField.h). Called from the album header's pass
// only, so a podcast's episode page, the same template with no cover for the field to read, is never held.
void SGRAlbumHoldPage(UIView *page);
