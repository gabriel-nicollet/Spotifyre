// The native player's scrub and cover room on the simulator: Native/Player/PlayerScrub.x and
// PlayerDeclutter.x run over mocks under Spotify's class names, and each check logs ok or WRONG. The log
// ends with `native player checks: n of m right -- PASS` or `FAIL`.
//
//     scrub   a mock of the progress bar's slider tracked in code (issue #172): the player list's pan off
//             while it tracks, back at its end, at a cancel and when the slider leaves the window, a pan
//             that was off already left off, and a sideways list between them left alone
//     cover   Spotify's layout for a track with lyrics, a smaller cover over the preview (issue #77):
//             untouched with Lyrics preview shown, the cover a centered square of its room with it hidden,
//             and a small cover and a tilt view outside the cover cell untouched
#import <UIKit/UIKit.h>
#import "Native/Player/NowPlaying.h"

#pragma mark - Spotify's classes, mocked

// Hooked by PlayerDeclutter.x but not looked at here.
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end
@interface _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl28PlaybackControlsElementsUnit @end
@interface _TtC20NowPlaying_ModesImpl18FooterElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl18FooterElementsUnit @end
@interface _TtC20NowPlaying_ModesImpl23InformationElementsUnit : UIViewController @end
@implementation _TtC20NowPlaying_ModesImpl23InformationElementsUnit @end

@interface _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl : UIView @end
@implementation _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl @end
@interface _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView : UIView @end
@implementation _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView @end
@interface _TtC22Lyrics_NPVContainerKit19LyricsContainerView : UIView @end
@implementation _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 64); }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 64); }
@end

// The progress bar's slider, tracking without a touch so it can be scrubbed in code.
@interface _TtCO17NowPlaying_ECMKit11ProgressBar6Slider : UISlider @end
@implementation _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {}
- (void)cancelTrackingWithEvent:(UIEvent *)event {}
@end

#pragma mark - checks

static NSUInteger sg_right, sg_checks;

static void check(NSString *step, BOOL ok, NSString *detail) {
    sg_checks++;
    if (ok) sg_right++;
    NSLog(@"[harness] %@: %@ -- %@", step, detail ?: @"", ok ? @"ok" : @"WRONG");
}

static void hideLyricsPreview(BOOL hidden) {
    [NSUserDefaults.standardUserDefaults setBool:hidden forKey:SGHideLyricsInline];
}

static void runScrubChecks(UIWindow *window) {
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:window.bounds];
    list.accessibilityIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";
    list.contentSize = CGSizeMake(window.bounds.size.width, window.bounds.size.height * 3);
    [window addSubview:list];
    // A sideways list between the slider and the player's, which the scrub must not take for it.
    UIScrollView *sideways = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 500, window.bounds.size.width, 60)];
    sideways.contentSize = CGSizeMake(window.bounds.size.width * 2, 60);
    [list addSubview:sideways];
    UISlider *slider = [[_TtCO17NowPlaying_ECMKit11ProgressBar6Slider alloc] initWithFrame:CGRectMake(24, 20, 300, 20)];
    [sideways addSubview:slider];
    UIPanGestureRecognizer *pan = list.panGestureRecognizer;
    UITouch *none = nil;

    [slider beginTrackingWithTouch:none withEvent:nil];
    check(@"scrub held while scrubbing", !pan.enabled && sideways.panGestureRecognizer.enabled,
          [NSString stringWithFormat:@"list pan %d, sideways pan %d", pan.enabled, sideways.panGestureRecognizer.enabled]);
    [slider endTrackingWithTouch:none withEvent:nil];
    check(@"scrub back at the end", pan.enabled, nil);
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider cancelTrackingWithEvent:nil];
    check(@"scrub back at a cancel", pan.enabled, nil);
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider removeFromSuperview];
    check(@"scrub back when the slider left the window", pan.enabled, nil);
    [sideways addSubview:slider];
    pan.enabled = NO;
    [slider beginTrackingWithTouch:none withEvent:nil];
    [slider endTrackingWithTouch:none withEvent:nil];
    check(@"scrub, a pan off already left off", !pan.enabled, nil);
    [list removeFromSuperview];
}

// CoverArtCellImpl > a plain view (the room) > the tilt view and the preview under it, the tilt view
// holding the cover pinned to its size, as Spotify's ElementView is.
static UIView *coverCell(UIWindow *window, Class cellClass, CGRect roomFrame, UIView **tiltOut, UIView **previewOut) {
    UIView *cell = [[cellClass alloc] initWithFrame:window.bounds];
    [window addSubview:cell];
    UIView *room = [[UIView alloc] initWithFrame:roomFrame];
    [cell addSubview:room];
    CGFloat side = roomFrame.size.width;
    CGFloat small = round(side * 0.8);
    UIView *tilt = [[_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView alloc]
                    initWithFrame:CGRectMake(round((side - small) / 2), 0, small, small)];
    UIView *cover = [[UIView alloc] initWithFrame:tilt.bounds];
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [tilt addSubview:cover];
    [room addSubview:tilt];
    UIView *preview = [[_TtC22Lyrics_NPVContainerKit19LyricsContainerView alloc] initWithFrame:CGRectMake(0, small + 8, side, 64)];
    [room addSubview:preview];
    *tiltOut = tilt;
    *previewOut = preview;
    return cell;
}

static void runCoverChecks(UIWindow *window) {
    Class cellClass = _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl.class;
    CGRect roomFrame = CGRectMake(24, 120, 354, 430);
    CGRect square = CGRectMake(0, round((430 - 354) / 2.0), 354, 354);
    UIView *tilt, *preview;

    hideLyricsPreview(NO);
    UIView *cell = coverCell(window, cellClass, roomFrame, &tilt, &preview);
    CGRect before = tilt.frame, previewBefore = preview.frame;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    [tilt setNeedsLayout];
    [tilt layoutIfNeeded];
    check(@"cover, preview shown, untouched", CGRectEqualToRect(tilt.frame, before) && CGRectEqualToRect(preview.frame, previewBefore)
          && !preview.hidden, [NSString stringWithFormat:@"cover %@, preview %@", NSStringFromCGRect(tilt.frame), NSStringFromCGRect(preview.frame)]);
    [cell removeFromSuperview];

    hideLyricsPreview(YES);
    cell = coverCell(window, cellClass, roomFrame, &tilt, &preview);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    check(@"cover, preview hidden takes no room", preview.hidden && CGSizeEqualToSize(preview.frame.size, CGSizeZero)
          && CGSizeEqualToSize(preview.intrinsicContentSize, CGSizeZero) && CGSizeEqualToSize([preview sizeThatFits:roomFrame.size], CGSizeZero),
          [NSString stringWithFormat:@"frame %@, intrinsic %@", NSStringFromCGRect(preview.frame), NSStringFromCGSize(preview.intrinsicContentSize)]);
    UIView *picture = tilt.subviews.firstObject;
    check(@"cover, preview hidden, fills its room", CGRectEqualToRect(tilt.frame, square) && CGSizeEqualToSize(picture.bounds.size, square.size),
          [NSString stringWithFormat:@"cover %@, picture %@", NSStringFromCGRect(tilt.frame), NSStringFromCGSize(picture.bounds.size)]);
    // Spotify sizing the tilt view again on a pass of its own, without the cell laying out.
    tilt.frame = CGRectMake(40, 0, 280, 280);
    [tilt setNeedsLayout];
    [tilt layoutIfNeeded];
    check(@"cover, a later pass of Spotify's", CGRectEqualToRect(tilt.frame, square), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];

    // The bar's 40pt cover, and a tilt view outside the player's cover cell (an album header), stay as they are.
    cell = coverCell(window, cellClass, CGRectMake(16, 16, 40, 52), &tilt, &preview);
    before = tilt.frame;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    check(@"cover, a small one untouched", CGRectEqualToRect(tilt.frame, before), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];
    cell = coverCell(window, UIView.class, roomFrame, &tilt, &preview);
    before = tilt.frame;
    [tilt setNeedsLayout];
    [tilt layoutIfNeeded];
    check(@"cover, outside the cover cell untouched", CGRectEqualToRect(tilt.frame, before), NSStringFromCGRect(tilt.frame));
    [cell removeFromSuperview];
    hideLyricsPreview(NO);
}

#pragma mark - app

@interface Delegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation Delegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    self.window.backgroundColor = UIColor.blackColor;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        runScrubChecks(self.window);
        runCoverChecks(self.window);
        NSLog(@"[harness] native player checks: %lu of %lu right -- %@", (unsigned long)sg_right, (unsigned long)sg_checks,
              sg_right == sg_checks ? @"PASS" : @"FAIL");
    });
    return YES;
}
@end

// Before every %ctor, so the native look's gate reads on.
__attribute__((constructor(101))) static void sg_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(Delegate.class));
    }
}
