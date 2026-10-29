#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "SGRSingButton.h"

static const CGFloat kGlyph = 17, kRingWidth = 2.5, kRingInset = 1.5;
// The capsule is the button's own glass grown upward: a circle at rest that opens into a pill kPanelHeight tall, the
// mic fused into its foot, and closes into the circle again (Spotifyre's). The level reads out to the left of the mic.
static const CGFloat kPanelHeight = 168, kLevelGap = 12, kLevelWidth = 120, kLevelHeight = 20;
static const NSTimeInterval kPanelStays = 3;   // Spotifyre's: three seconds after the last touch
static const float kLevelStep = 0.05f;
// As sung (1) holds the thumb this close either side, 4% of the slider's travel: a detent caught with a tick, as the
// Sing page's tall slider ticks there.
static const float kAsSungCatch = 0.08f;
static const CGFloat kMarkWidth = 14;
// The fill's white, and the green of the very top, where the vocals stand alone (Spotifyre's slider).
static const CGFloat kFillWhite = 0.88;
static char kButtonGlassKey, kPanelGlassKey;

static UIColor *vocalsOnlyGreen(void) {
    return [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1];
}

// Spotifyre's vocal slider: no thumb, the capsule is the track and a fill rises in it to the level, white, and green
// at the very top where the vocals stand alone. Its value is the level as Sing.h has it, 0 (vocals gone) through 1
// (the song as sung, the capsule's middle) to 2 (the vocals alone). It only shows the level: the drag is the
// panel's (SGRVocalPan), measured from where the level is, so a finger anywhere on the capsule moves it.
@interface SGRVocalSlider : UIView
@property (nonatomic) float value;
@end

@implementation SGRVocalSlider {
    UIView *_fill;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    [self addSubview:_fill];
    [self paint];
    return self;
}

- (void)setValue:(float)value {
    value = isfinite(value) ? fmaxf(0, fminf(2, value)) : 1;
    if (value < 0.01f) value = 0;
    if (value > 1.99f) value = 2;
    _value = value;
    [self paint];
}

- (void)paint {
    _fill.backgroundColor = [(_value >= 2 ? vocalsOnlyGreen() : UIColor.whiteColor) colorWithAlphaComponent:kFillWhite];
    CGFloat height = self.bounds.size.height, filled = height * _value / 2;
    _fill.frame = CGRectMake(0, height - filled, self.bounds.size.width, filled);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Round at the top only: the foot meets the mic's circle, which the capsule's glass rounds itself.
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    self.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    [self paint];
}

@end

// Spotify's player also pans to dismiss. A drag that starts on the capsule is the vocal level's, not the player's.
@interface SGRVocalPan : UIPanGestureRecognizer
@end

@implementation SGRVocalPan
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
@end

@interface SGRSingButton () <UIGestureRecognizerDelegate>
@end

@implementation SGRSingButton {
    UIButton *_button;   // holds no glass, so its alpha is free to fade
    CAShapeLayer *_ring;
    BOOL _ringShown;
    NSString *_glyph;
    UIView *_panel;
    SGRVocalSlider *_slider;
    UIView *_mark;       // across the capsule at As sung
    UISelectionFeedbackGenerator *_feedback;
    BOOL _caught;        // the level is held at As sung
    BOOL _atTop;         // the level is at the vocals alone, which ticks once as it arrives
    float _dragFrom;     // the level a drag started from
    UILabel *_level;
    NSTimer *_hide;
    BOOL _panelShown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // The Kit's glass behind a plain button (layoutSubviews), the same material as the pronunciation and
    // translation button across from it, so the glass can be faded by its effect when the controls go.
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:kGlyph weight:UIImageSymbolWeightSemibold];
    _button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    _button.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _button.tintColor = UIColor.whiteColor;
    _button.isAccessibilityElement = NO;
    [_button addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    [_button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    [self addSubview:_button];
    // A drag on the capsule, or on the mic while Sing is on, sets the level; the player's own pan to dismiss does not
    // get to take it (SGRVocalPan).
    SGRVocalPan *pan = [[SGRVocalPan alloc] initWithTarget:self action:@selector(dragged:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [self addGestureRecognizer:pan];

    // VoiceOver has the mic itself as one adjustable button: the slider shows only for a held finger and
    // goes again on a timer, which a swipe up or down never holds open.
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Karaoke";
    self.accessibilityHint = @"Turns the vocals down";
    self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitAdjustable;

    _ring = [CAShapeLayer layer];
    _ring.fillColor = UIColor.clearColor.CGColor;
    _ring.strokeColor = UIColor.whiteColor.CGColor;
    _ring.lineWidth = kRingWidth;
    _ring.lineCap = kCALineCapRound;
    _ring.opacity = 0;
    [self.layer addSublayer:_ring];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:SGSingChangedNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_hide invalidate];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _button.frame = bounds;
    SGRShowGlass(SGRGlassInside(self, &kButtonGlassKey, MIN(bounds.size.width, bounds.size.height)), !_tucked && !_panelShown);
    _ring.frame = bounds;
    // Starting at the top and running clockwise, as a download ring does.
    CGFloat radius = MIN(bounds.size.width, bounds.size.height) / 2 - kRingInset - kRingWidth / 2;
    _ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds)) radius:radius
                                            startAngle:-M_PI_2 endAngle:3 * M_PI_2 clockwise:YES].CGPath;
    [self layoutPanel];
}

// Goes with the host's controls, in the host's animation: the glass dematerializes, the glyph and the ring
// fade, and an open slider goes with them.
- (void)setTucked:(BOOL)tucked {
    _tucked = tucked;
    if (tucked && _panelShown) {
        _panelShown = NO;
        [_hide invalidate];
        _hide = nil;
    }
    _button.alpha = tucked ? 0 : 1;
    [self showRing];
    self.userInteractionEnabled = !tucked;
    // The capsule closes with the rest, and the button's glass is the one left, or none.
    [self layoutPanel];
}

#pragma mark - what Sing is doing

- (void)refresh {
    SGSingState state = SGSingCurrentState();
    NSString *glyph = @"mic.fill";
    UIColor *tint = UIColor.whiteColor;
    CGFloat alpha = 1;
    double progress = -1;   // a ring at a fraction; 2 for a turning one, -1 for none
    switch (state) {
        case SGSingStateUnavailable: glyph = @"mic.slash"; alpha = 0.5; break;
        case SGSingStateNoModel: glyph = @"mic"; alpha = 0.7; break;
        case SGSingStateDownloading:
            // Offline, the ring stays where the download stopped and the glyph says why, dimmed like the other
            // states that wait.
            if (SGSingModelWaitingForNetwork()) {
                glyph = @"wifi.slash";
                alpha = 0.7;
            } else {
                glyph = @"arrow.down";
            }
            progress = SGSingModelProgress();
            break;
        case SGSingStateOff: glyph = @"mic"; break;
        case SGSingStatePreparing:
        case SGSingStateBuffering: progress = 2; break;
        case SGSingStateWaiting: alpha = 0.7; break;
        case SGSingStateSinging: tint = SGRAccentColor() ?: UIColor.systemGreenColor; break;
        case SGSingStateBehind: glyph = @"tortoise.fill"; break;
        case SGSingStateHot: glyph = @"thermometer.high"; tint = UIColor.systemOrangeColor; break;
        case SGSingStateFailed: glyph = @"exclamationmark.triangle.fill"; tint = UIColor.systemYellowColor; break;
    }
    // One glyph replaces the other in place, as the Kit's download glyph does (none under Reduce Motion),
    // and the color crossfades. Set only on a change: the download's progress refreshes many times a second.
    if (![glyph isEqualToString:_glyph]) {
        _glyph = glyph;
        UIButtonConfiguration *config = _button.configuration;
        if (@available(iOS 26.0, *)) {
            config.symbolContentTransition = SGRReduceMotion() || !self.window ? nil
                : [UISymbolContentTransition transitionWithContentTransition:[NSSymbolReplaceContentTransition replaceDownUpTransition]];
        }
        config.image = [UIImage systemImageNamed:glyph];
        _button.configuration = config;
    }
    UIColor *color = [tint colorWithAlphaComponent:alpha];
    if (![color isEqual:_button.tintColor]) {
        if (self.window) SGRAnimate(SGRMotionFade, ^{ self->_button.tintColor = color; }, nil);
        else _button.tintColor = color;
    }

    // A turning ring under Reduce Motion is a quarter of one standing still: repetitive motion is what it asks
    // to be left out.
    _ringShown = progress >= 0;
    BOOL turns = progress > 1 && !SGRReduceMotion();
    if (progress > 1) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _ring.strokeEnd = 0.25;
        [CATransaction commit];
    } else if (progress >= 0) {
        _ring.strokeEnd = progress;
    }
    if (turns && ![_ring animationForKey:@"turn"]) {
        CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        turn.fromValue = @0;
        turn.toValue = @(2 * M_PI);
        turn.duration = 1;
        turn.repeatCount = HUGE_VALF;
        turn.removedOnCompletion = NO;
        [_ring addAnimation:turn forKey:@"turn"];
    } else if (!turns && progress >= 0) {
        [_ring removeAnimationForKey:@"turn"];
    }
    [self showRing];
}

// The ring fades rather than popping in and out; a turning one keeps turning until it is gone.
- (void)showRing {
    float opacity = _ringShown && !_tucked ? 1 : 0;
    if (_ring.opacity == opacity) return;
    [CATransaction begin];
    [CATransaction setAnimationDuration:SGRCrossfade];
    [CATransaction setCompletionBlock:^{
        if (self->_ring.opacity == 0) [self->_ring removeAnimationForKey:@"turn"];
    }];
    _ring.opacity = opacity;
    [CATransaction commit];
}

#pragma mark - VoiceOver

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:@"%@. Vocals level: %@", SGSingStatusText(), SGSingLevelText(SGSingLevel())];
}

- (BOOL)accessibilityActivate {
    [self tapped];
    return YES;
}

// Two of the slider's steps at a time, so the whole range is twenty swipes.
- (void)accessibilityIncrement {
    [self stepLevel:1];
}

- (void)accessibilityDecrement {
    [self stepLevel:-1];
}

- (void)stepLevel:(int)direction {
    SGSetSingLevel(roundf((SGSingLevel() + direction * 2 * kLevelStep) / kLevelStep) * kLevelStep);
    if (_panel) {
        _slider.value = SGSingLevel();
        [self showLevel];
    }
}

#pragma mark - the tap

static void tell(NSString *message, NSString *action, void (^then)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Karaoke" message:message preferredStyle:UIAlertControllerStyleAlert];
    // Over the player, which is dark whatever the system's appearance.
    alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    if (action) [alert addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { then(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:action ? @"Cancel" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

- (void)tapped {
    switch (SGSingCurrentState()) {
        case SGSingStateUnavailable:
            tell(SGSingMissing(), nil, nil);
            return;
        case SGSingStateNoModel:
            tell([NSString stringWithFormat:@"Karaoke turns the vocals down with a voice model that runs on this iPhone. Download it now (%@)? It is best over Wi-Fi.%@",
                  SGSingModelSizeText(), SGSingModelError() ? [NSString stringWithFormat:@"\n\nThe last try failed: %@", SGSingModelError()] : @""],
                 @"Download", ^{
                     SGSingDownloadModel();
                     // Downloaded for the mic, so the mic is on once it is in.
                     SGSetSingOn(YES);
                 });
            return;
        case SGSingStateDownloading:
            tell(SGSingStatusDetail(), @"Stop the download", ^{ SGSingCancelModelDownload(); });
            return;
        case SGSingStateFailed:
            tell(SGSingStatusDetail(), @"Turn Karaoke off", ^{ SGSetSingOn(NO); });
            return;
        default:
            // Spotifyre's: a tap turns Sing on and opens the capsule; open, a tap turns it off; closed while it is
            // on, a tap opens it again.
            if (!SGSingOn()) {
                SGSetSingOn(YES);
                [self showPanel];
            } else if (_panelShown) {
                SGSetSingOn(NO);
                [self hidePanel];
            } else {
                [self showPanel];
            }
    }
}

#pragma mark - the slider

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    [self showPanel];
}

- (void)makePanel {
    if (_panel) return;
    _panel = [UIView new];
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _slider = [SGRVocalSlider new];
    [_panel addSubview:_slider];
    _mark = [UIView new];
    _mark.userInteractionEnabled = NO;
    [_panel addSubview:_mark];   // over the fill, so it reads on both sides of the level
    _feedback = [UISelectionFeedbackGenerator new];
    _level = [UILabel new];
    _level.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _level.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _level.textAlignment = NSTextAlignmentRight;
    _level.isAccessibilityElement = NO;
    _level.alpha = 0;
    // Under the mic, whose glyph and ring stay over the capsule's foot.
    [self insertSubview:_panel belowSubview:_button];
    [self addSubview:_level];
}

// The circle grows into the pill on the Kit's layout spring (a dissolve under Reduce Motion), and the level comes in
// beside the mic.
- (void)showPanel {
    [self makePanel];
    _slider.value = SGSingLevel();
    [self showLevel];
    _panelShown = YES;
    SGRAnimateLayout(self, ^{ [self layoutPanel]; }, nil);
    [self letPanelGo];
}

// Everything of the capsule for whether it is open, set in whatever animation the caller has open. The capsule is
// bottom-anchored on the mic: closed it is the mic's circle, so its glass and the button's own swap in place.
- (void)layoutPanel {
    BOOL open = _panelShown && !_tucked;
    CGFloat width = self.bounds.size.width, side = self.bounds.size.height;
    SGRShowGlass(SGRGlassInside(self, &kButtonGlassKey, MIN(width, side)), !open && !_tucked);
    if (!_panel) return;
    CGFloat height = open ? MAX(kPanelHeight, side) : side;
    _panel.frame = CGRectMake(0, side - height, width, height);
    SGRShowGlass(SGRGlassCapsuleInside(_panel, &kPanelGlassKey, _panel.bounds.size, NO), open);
    CGFloat track = height - side;   // the slider's part, above the mic
    _slider.frame = CGRectMake(0, 0, width, MAX(0, track));
    // As sung, the middle of the level's range, is the middle of that part.
    _mark.frame = CGRectMake((width - kMarkWidth) / 2, track / 2 - 0.5, kMarkWidth, 1);
    _level.frame = CGRectMake(-kLevelGap - kLevelWidth, (side - kLevelHeight) / 2, kLevelWidth, kLevelHeight);
    _slider.alpha = _mark.alpha = _level.alpha = open ? 1 : 0;
}

- (void)showLevel {
    _level.text = SGSingLevelText(_slider.value);
    _slider.accessibilityValue = _level.text;
    // Light over the empty half, dark once the fill has reached it.
    _mark.backgroundColor = _slider.value >= 1 ? [UIColor colorWithWhite:0 alpha:0.28] : [UIColor colorWithWhite:1 alpha:0.35];
}

// A finger on the capsule moves the level from where it is, by the capsule's own height for the whole range. Near As
// sung the level holds there, with a tick as it catches; the finger drags it on out of the band. The very top ticks
// once as it is reached, as the fill turns green.
- (void)dragged:(UIPanGestureRecognizer *)pan {
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            if (!_panelShown) {
                [self showPanel];
                _slider.value = SGSingLevel();
            }
            [self holdPanel];
            _dragFrom = _slider.value;
            if (SGSingCurrentState() == SGSingStateOff) SGSetSingOn(YES);
            [self dragTo:pan];
            break;
        case UIGestureRecognizerStateChanged:
            [self dragTo:pan];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self letPanelGo];
            break;
        default:
            break;
    }
}

- (void)dragTo:(UIPanGestureRecognizer *)pan {
    CGFloat travel = [pan translationInView:self].y;   // down is positive
    float position = fmaxf(0, fminf(1, _dragFrom / 2 - (float)(travel / MAX(1, kPanelHeight - self.bounds.size.height))));
    [self setLevelFromDrag:position * 2];
}

- (void)setLevelFromDrag:(float)value {
    BOOL caught = fabsf(value - 1) <= kAsSungCatch;
    if (caught) value = 1;
    if (caught && !_caught) [_feedback selectionChanged];
    _caught = caught;
    _slider.value = value;
    BOOL top = _slider.value >= 2;
    if (top && !_atTop) {
        UIImpactFeedbackGenerator *tick = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [tick prepare];
        [tick impactOccurred];
    }
    _atTop = top;
    SGSetSingLevel(roundf(_slider.value / kLevelStep) * kLevelStep);
    [self showLevel];
}

- (void)holdPanel {
    [_hide invalidate];
    _hide = nil;
    _caught = fabsf(_slider.value - 1) <= kAsSungCatch;
    _atTop = _slider.value >= 2;
    [_feedback prepare];
}

- (void)letPanelGo {
    [_hide invalidate];
    __weak SGRSingButton *weakSelf = self;
    _hide = [NSTimer scheduledTimerWithTimeInterval:kPanelStays repeats:NO block:^(NSTimer *timer) { [weakSelf hidePanel]; }];
}

// Back into the circle, on the same spring.
- (void)hidePanel {
    if (!_panelShown) return;
    _panelShown = NO;
    [_hide invalidate];
    _hide = nil;
    SGRAnimateLayout(self, ^{ [self layoutPanel]; }, nil);
}

// A drag begins on the capsule, or on the mic while Sing is on, and goes mostly up or down.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![gesture isKindOfClass:SGRVocalPan.class]) return YES;
    if (!_panelShown && !SGSingOn()) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)gesture velocityInView:self];
    return fabs(velocity.y) >= fabs(velocity.x);
}

// The capsule sits outside the button's bounds, above it, and takes touches while it shows.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (_panelShown && CGRectContainsPoint(_panel.frame, point)) return YES;
    return [super pointInside:point withEvent:event];
}

@end
