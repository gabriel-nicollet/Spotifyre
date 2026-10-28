// What a redesigned page takes from its artwork, worked out off the main thread in one pass: the
// color along the artwork's bottom edge, the field color made from it (or from the artwork's main
// color, for a page), and the blurred bitmaps the field (SGRField.h) draws instead of a live blur.
//
// The field color is the edge or main color with its saturation held to 0.55 and its relative luminance to
// 0.07 (0.04 with Increase Contrast). On anything that dark white text is past 8:1 and SGRSecondary
// (white 65%) past 4.5:1, WCAG AA, whatever the hue.
//
// Threading: +paletteForImage: may be called from the main thread only and calls back on it. The work
// runs on one serial background queue; UIImage and CoreImage are read there, UIKit views are not.
#import <UIKit/UIKit.h>

typedef struct {
    // The area a backdrop bitmap covers, in points; CGSizeZero when none is wanted. The bitmap is the
    // artwork filling that area, blurred, dimmed from 0.25 black at the top to 0.45 (0.55 with
    // AMOLED) at 55% of the height, and transparent from 55% down to the bottom, so the field color
    // under it shows through with no edge.
    CGSize backdropSize;
    // A blurred copy at the artwork's own aspect, transparent down to 55% of its height and opaque
    // from 85%, to lay over the sharp picture with the same aspect fill.
    BOOL dissolve;
    BOOL amoled;
    // The colors of a moving field (SGRFlow.h): the artwork's main color in each quarter and overall.
    BOOL flow;
    // The field color from the artwork's main color (the one +tintForImage: finds) rather than its bottom
    // edge: for a page, whose cover dissolves into the field across its whole width, where the bottom edge
    // is a scanned cover's pale border or whatever strip happens to sit at the foot of the picture.
    BOOL mainColor;
} SGRPaletteRequest;

@interface SGRPalette : NSObject
@property (nonatomic, readonly) UIColor *edgeColor;
@property (nonatomic, readonly) UIColor *fieldColor;
@property (nonatomic, readonly) UIImage *backdrop;   // nil unless asked for, at most 160px wide
@property (nonatomic, readonly) UIImage *dissolve;   // nil unless asked for, 96px wide
// nil unless asked for: top left, top right, bottom left, bottom right, then the whole artwork's, each
// the dominant color there, its saturation lifted a little and its luminance held between
// kFlowLuminanceMin and kFlowLuminanceMax, so white text keeps better than 5.5:1 on any of them.
@property (nonatomic, readonly) NSArray<UIColor *> *flowColors;
// nil to the completion when the image has no bitmap to read (a symbol, a CIImage).
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion;

// The artwork's dominant color as a surface: its saturation lifted a fifth, brought down to a luminance of 0.04
// (the reference's card and tile surfaces), so a tile or card wears its cover's color while white text on it
// keeps better than 11:1. Never dimmer than `surface`: a color that came out darker is lifted back to its
// luminance keeping its hue, so a near-black cover cannot cost the tile the step of elevation it stands on,
// nor sink it into the gray band SGRAmoled.x turns pure black. nil to the completion when the image has no
// bitmap to read.
// `strong` NO is the tint as it was before the Home look (2026-10-11): the dominant color at a luminance of 0.05
// with 35% of it mixed into `surface`, a faint cast rather than the cover's color.
+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface strong:(BOOL)strong completion:(void (^)(UIColor *tint))completion;
@end

// Any color made fit to be a field, the same way the edge color is: for a color Spotify hands over
// before the artwork is read. Main thread.
UIColor *SGRFieldColorFor(UIColor *color);
