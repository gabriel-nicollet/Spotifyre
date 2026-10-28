// Home redesign: a shortcut tile the way an Apple list row holds artwork. The cover sits inset from the tile's
// edges with its own corners, the title follows it in, and the tile is a dark surface tinted faintly toward the
// cover's dominant color (Kit/SGRPalette.h, +tintForImage:), so the grid is not one gray and white text always
// reads. Until the cover has loaded, the tile is the untinted surface.
//
// The surface sits behind Spotify's stack, over the tile's own fill, so the title, the playing indicator and
// the button's touches stay Spotify's. The inset and the title's move are transforms, which Spotify's layout
// never reads, so its constraints are left as they are. The tint is worked out off the main thread once per
// picture and follows the cover as Spotify sets it (SGRObserveImage), since a cover lands after layout.
//
// Tree (trees/home 3 more scrolled.txt:36-50, 2026-09-17): InteractableLayoutBackingButton id=Shortcut.Card.Home
// 181x48 clips > UIView 181x48 bg=#FFFFFF@0.10 (the fill), then Encore.StackView > AutoLayoutStackView >
// UIView 173x48 (the row) > UIView {0, 0} 48x48 bg=#000000@0.90 r=4 (the cover's square) > Encore.ImageView >
// UIImageView 48x48 and the PlaceholderView; then the row's 8pt spacer and the title's stack at x 56.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// How far the cover sits in from the tile's top, bottom and leading edges, and its corners there (the reference's
// 37pt covers at 5pt in, with corners of about 6).
static const CGFloat kInset = 5, kCoverRadius = 6, kCoverRadiusBefore = 4;   // Before: with the Home look off.
const CGFloat SGRHomeTileRadius = 14;
// The glass rim: a hairline of white around the tile, lit at the top and bottom edges and faint along the sides,
// as the reference's pills are (brightness 178 over a fill of 65 in the first pixel row, none at the sides).
static const CGFloat kRimAlpha = 0.5, kRimSideShare = 0.3;

static char kSurfaceKey, kImageKey, kShownKey, kTitleKey, kMineKey, kPlayingKey, kRimKey;
static void rim(UIView *surface);
// The tile's trailing padding, after the title or the playing indicator.
static const CGFloat kTrailing = 12;

// Tints already worked out, by the image object while it lives (main thread only).
static NSMapTable<UIImage *, UIColor *> *tints(void) {
    static NSMapTable *table;
    if (!table) table = [NSMapTable weakToStrongObjectsMapTable];
    return table;
}

static UIColor *untinted(void) {
    static UIColor *color;
    if (!color) color = SGRElevated(UIColor.blackColor);
    return color;
}

@interface SGRTileParts : NSObject
@property (nonatomic, weak) UIView *fill;
@property (nonatomic, weak) UIView *square;
@property (nonatomic, weak) UIImageView *cover;
@end

@implementation SGRTileParts
@end

static SGRTileParts *partsOf(UIView *tile) {
    UIView *holder = SGRFindByIdentifier(tile, @"Encore.ImageView", &kImageKey);
    SGRTileParts *parts = [SGRTileParts new];
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) parts.cover = (UIImageView *)sub;
    }
    parts.square = holder.superview;
    UIView *first = tile.subviews.firstObject;
    if (object_getClass(first) == UIView.class && CGRectEqualToRect(first.frame, tile.bounds)) parts.fill = first;
    return parts;
}

static UIView *surfaceIn(UIView *tile, UIView *fill) {
    UIView *surface = objc_getAssociatedObject(tile, &kSurfaceKey);
    if (!surface) {
        surface = [UIView new];
        surface.userInteractionEnabled = NO;
        surface.accessibilityElementsHidden = YES;
        surface.backgroundColor = untinted();
        objc_setAssociatedObject(tile, &kSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (surface.superview != tile) {
        if (fill) [tile insertSubview:surface aboveSubview:fill];
        else [tile insertSubview:surface atIndex:0];
    }
    if (!CGRectEqualToRect(surface.frame, tile.bounds)) surface.frame = tile.bounds;
    if (SGRHomeLook()) rim(surface);
    return surface;
}

// The rim is a 1pt white border on a layer over the surface, its mask a vertical gradient opaque at the top and
// bottom edges and kRimSideShare in between, so the sides carry a faint line and the edges the lit one.
static void rim(UIView *surface) {
    CALayer *border = objc_getAssociatedObject(surface, &kRimKey);
    if (!border) {
        border = [CALayer layer];
        // Half of it lies outside the tile's own corner mask.
        border.borderWidth = 1.5;
        border.borderColor = [UIColor colorWithWhite:1 alpha:kRimAlpha].CGColor;
        border.cornerCurve = kCACornerCurveContinuous;
        CAGradientLayer *mask = [CAGradientLayer layer];
        UIColor *edge = UIColor.whiteColor, *side = [UIColor colorWithWhite:1 alpha:kRimSideShare];
        mask.colors = @[(id)edge.CGColor, (id)side.CGColor, (id)side.CGColor, (id)edge.CGColor];
        mask.locations = @[@0, @0.2, @0.8, @1];
        border.mask = mask;
        [surface.layer addSublayer:border];
        objc_setAssociatedObject(surface, &kRimKey, border, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(border.frame, surface.bounds)) border.frame = border.mask.frame = surface.bounds;
    if (border.cornerRadius != SGRHomeTileRadius) border.cornerRadius = SGRHomeTileRadius;
    [CATransaction commit];
}

// The square scaled about its center so it clears the tile's edges by kInset, and everything after it in the
// row moved in by what that took off its trailing side.
static void inset(UIView *square) {
    CGFloat side = square.bounds.size.height;
    if (side <= kInset * 4) return;
    CGFloat scale = (side - kInset * 2) / side;
    CGAffineTransform shrink = CGAffineTransformMakeScale(scale, scale);
    if (!CGAffineTransformEqualToTransform(square.transform, shrink)) square.transform = shrink;
    CALayer *layer = square.layer;
    // The radius is drawn scaled with the square.
    CGFloat radius = (SGRHomeLook() ? kCoverRadius : kCoverRadiusBefore) / scale;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;

    CGAffineTransform follow = CGAffineTransformMakeTranslation(-square.bounds.size.width * (1 - scale) / 2, 0);
    BOOL after = NO;
    for (UIView *sibling in square.superview.subviews) {
        if (sibling == square) {
            after = YES;
            continue;
        }
        if (after && !CGAffineTransformEqualToTransform(sibling.transform, follow)) sibling.transform = follow;
    }
}

// The title in semibold on up to two lines, a label of the Kit's own over Spotify's one, which goes transparent
// (it keeps the tile's layout and the button's accessibility label). The playing indicator, which Spotify sets
// right after its own title, moves to the tile's trailing edge once Spotify has laid it out (HomeCards.x asks
// for this pass again when it does; moved before that, the move and Spotify's own placing added up and put it
// past the tile's edge), and the title ends before it.
static void retitle(UIView *tile) {
    UIView *theirs = SGRFindByIdentifier(tile, @"Shortcut.Card.Home.Content.title-internal", &kTitleKey);
    if (![theirs isKindOfClass:UILabel.class]) return;
    UILabel *mine = objc_getAssociatedObject(tile, &kMineKey);
    if (!mine) {
        mine = [UILabel new];
        mine.numberOfLines = 2;
        mine.lineBreakMode = NSLineBreakByTruncatingTail;
        mine.textColor = SGRPrimary();
        mine.userInteractionEnabled = NO;
        mine.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(tile, &kMineKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 13pt: the reference's "DRIP" is 27px of cap height at 3px/pt.
    UIFont *font = SGRFont(UIFontTextStyleFootnote, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    if (![mine.font isEqual:font]) mine.font = font;
    NSString *text = ((UILabel *)theirs).text;
    if (text ? ![mine.text isEqualToString:text] : mine.text != nil) mine.text = text;
    if (theirs.alpha != 0) theirs.alpha = 0;
    if (mine.superview != tile) [tile addSubview:mine];

    CGFloat x = CGRectGetMinX([theirs convertRect:theirs.bounds toView:tile]);
    CGFloat end = tile.bounds.size.width - kTrailing;
    UIView *playing = SGRFindByIdentifier(tile, @"Shortcut.Card.Home.Content.playback", &kPlayingKey);
    if (playing && !playing.hidden) {
        CGAffineTransform was = playing.transform;
        playing.transform = CGAffineTransformIdentity;
        CGRect base = [playing.superview convertRect:playing.frame toView:tile];
        // Laid out by Spotify: after the title, with a size. Before that it sits at the row's origin.
        if (base.size.width > 0 && CGRectGetMinX(base) > x) {
            CGAffineTransform moved = CGAffineTransformMakeTranslation(end - CGRectGetMaxX(base), 0);
            playing.transform = CGAffineTransformEqualToTransform(was, moved) ? was : moved;
            end = CGRectGetMinX(base) + moved.tx - SGRGrid;
        } else {
            playing.transform = was;
        }
    }
    CGRect frame = CGRectMake(x, 0, MAX(0, end - x), tile.bounds.size.height);
    if (!CGRectEqualToRect(mine.frame, frame)) mine.frame = frame;
}

void SGRHomeUnstyleTile(UIView *button) {
    UIView *surface = objc_getAssociatedObject(button, &kSurfaceKey);
    UILabel *mine = objc_getAssociatedObject(button, &kMineKey);
    if (!surface && !mine) return;
    [surface removeFromSuperview];
    [mine removeFromSuperview];
    objc_setAssociatedObject(button, &kSurfaceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kMineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *theirs = SGRFindByIdentifier(button, @"Shortcut.Card.Home.Content.title-internal", &kTitleKey);
    if (theirs.alpha == 0) theirs.alpha = 1;
    UIView *square = partsOf(button).square;
    for (UIView *sibling in square.superview.subviews) {
        if (!CGAffineTransformIsIdentity(sibling.transform)) sibling.transform = CGAffineTransformIdentity;
    }
}

static void tint(UIView *tile, UIView *surface, UIColor *color, BOOL animated) {
    color = color ?: untinted();
    if ([surface.backgroundColor isEqual:color]) return;
    if (!animated || !tile.window) {
        surface.backgroundColor = color;
        return;
    }
    SGRAnimate(SGRMotionFade, ^{ surface.backgroundColor = color; }, nil);
}

static void refresh(UIView *tile) {
    SGRTileParts *parts = partsOf(tile);
    UIImageView *cover = parts.cover;
    UIView *square = parts.square;
    if (!cover || !square || square.bounds.size.width < 20 || tile.bounds.size.width <= square.bounds.size.width) return;
    UIView *surface = surfaceIn(tile, parts.fill);
    inset(square);
    if (SGRHomeLook()) retitle(tile);

    UIImage *image = cover.image;
    if (!image) {
        objc_setAssociatedObject(tile, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tint(tile, surface, nil, NO);
        return;
    }
    if (objc_getAssociatedObject(tile, &kShownKey) == image) return;
    objc_setAssociatedObject(tile, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak UIView *weakTile = tile;
    SGRHomeTintForCover(image, ^(UIColor *color) {
        UIView *strongTile = weakTile;
        // A tile reused for another cover in the meantime has asked for that one.
        if (!strongTile || objc_getAssociatedObject(strongTile, &kShownKey) != image) return;
        tint(strongTile, surfaceIn(strongTile, partsOf(strongTile).fill), color, YES);
    });
}

void SGRHomeTintForCover(UIImage *image, void (^completion)(UIColor *color)) {
    SGRHomeProbeEnd(SGRHomeProbeTint, SGRHomeProbeBegin());
    UIColor *known = [tints() objectForKey:image];
    if (known) {
        completion(known);
        return;
    }
    [SGRPalette tintForImage:image surface:untinted() strong:SGRHomeLook() completion:^(UIColor *color) {
        if (color) [tints() setObject:color forKey:image];
        completion(color);
    }];
}

void SGRHomeStyleTile(UIView *tile) {
    CFTimeInterval began = SGRHomeProbeBegin();
    UIImageView *cover = partsOf(tile).cover;
    if (!cover) return;
    __weak UIView *weakTile = tile;
    // The block is replaced on every pass, so a cover taken into another tile tells the tile it is in now.
    SGRObserveImage(cover, ^(UIImageView *view) {
        UIView *strongTile = weakTile;
        if (strongTile && [view isDescendantOfView:strongTile]) refresh(strongTile);
    });
    refresh(tile);
    SGRHomeProbeEnd(SGRHomeProbeTiles, began);
}
