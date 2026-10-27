// Touches made in the app, the way a finger's arrive: a UITouch and the touches event, each carrying the
// IOHIDEvent UIKit's gesture recognizers read since iOS 9. The private calls are the ones KIF has made for
// years; they let the harness tap the glass bar and fling the list with UIKit's own recognizers and
// scrolling, not by calling the delegate. Checked on iOS 27.0 in the simulator only.
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef double IOHIDFloat;
IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t type, uint32_t index, uint32_t identity, uint32_t mask,
                                             uint32_t buttons, IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat pressure,
                                             IOHIDFloat barrel, Boolean range, Boolean touch, uint32_t options);
IOHIDEventRef IOHIDEventCreateDigitizerFingerEventWithQuality(CFAllocatorRef, uint64_t, uint32_t index, uint32_t identity, uint32_t mask,
                                                              IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat pressure, IOHIDFloat twist,
                                                              IOHIDFloat minor, IOHIDFloat major, IOHIDFloat quality, IOHIDFloat density,
                                                              IOHIDFloat irregularity, Boolean range, Boolean touch, uint32_t options);
void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, long value);

@interface UITouch (SGHarness)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setPhase:(UITouchPhase)phase;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setTapCount:(NSUInteger)count;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)first;
- (void)_setHidEvent:(IOHIDEventRef)event;
- (void)setGestureView:(UIView *)view;
@end

@interface UIEvent (SGHarness)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(IOHIDEventRef)event;
@end

@interface UIApplication (SGHarness)
- (UIEvent *)_touchesEvent;
@end

static const uint32_t kDigitizer = 11, kHand = 3, kRange = 1 << 0, kTouch = 1 << 1, kPosition = 1 << 2;
static const uint32_t kDisplayIntegrated = (kDigitizer << 16) + 25;

static IOHIDEventRef hidFor(UITouch *touch) {
    uint64_t now = mach_absolute_time();
    IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, kHand, 0, 0, kTouch, 0, 0, 0, 0, 0, 0, 0, 1, 0);
    IOHIDEventSetIntegerValue(hand, kDisplayIntegrated, 1);
    BOOL moved = touch.phase == UITouchPhaseMoved, down = touch.phase != UITouchPhaseEnded;
    CGPoint at = [touch locationInView:touch.window];
    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEventWithQuality(kCFAllocatorDefault, now, 1, 2, moved ? kPosition : kRange | kTouch,
                                                                           at.x, at.y, 0, 0, 0, 5, 5, 1, 1, 1, down, down, 0);
    IOHIDEventSetIntegerValue(finger, kDisplayIntegrated, 1);
    IOHIDEventAppendEvent(hand, finger, 0);
    CFRelease(finger);
    return hand;
}

static void deliver(UITouch *touch) {
    IOHIDEventRef hid = hidFor(touch);
    [touch _setHidEvent:hid];
    UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
    [event _clearTouches];
    [event _setHIDEvent:hid];
    [event _addTouch:touch forDelayedDelivery:NO];
    CFRelease(hid);
    [UIApplication.sharedApplication sendEvent:event];
}

static UITouch *touchDown(UIWindow *window, CGPoint point) {
    UITouch *touch = [UITouch new];
    UIView *view = [window hitTest:point withEvent:nil];
    [touch setWindow:window];
    [touch _setLocationInWindow:point resetPrevious:YES];
    [touch setView:view];
    if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:view];
    [touch setPhase:UITouchPhaseBegan];
    [touch _setIsFirstTouchForView:YES];
    [touch setTapCount:1];
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    deliver(touch);
    return touch;
}

static void touchTo(UITouch *touch, CGPoint point, UITouchPhase phase) {
    [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
    [touch _setLocationInWindow:point resetPrevious:NO];
    [touch setPhase:phase];
    deliver(touch);
}

// A finger held at `point` for `seconds`, then lifted.
void SGHarnessHold(UIWindow *window, CGPoint point, NSTimeInterval seconds) {
    UITouch *touch = touchDown(window, point);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        touchTo(touch, point, UITouchPhaseEnded);
    });
}

// A tap at `point`, down and up 0.08 s apart.
void SGHarnessTap(UIWindow *window, CGPoint point) {
    SGHarnessHold(window, point, 0.08);
}

// A finger from `from` to `to` over `seconds`, a move every 1/60 s, let go while still moving: a fling.
void SGHarnessDrag(UIWindow *window, CGPoint from, CGPoint to, NSTimeInterval seconds) {
    UITouch *touch = touchDown(window, from);
    NSUInteger steps = MAX(2, (NSUInteger)(seconds * 60));
    for (NSUInteger i = 1; i <= steps; i++) {
        CGFloat t = (CGFloat)i / steps;
        CGPoint at = CGPointMake(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * NSEC_PER_SEC / 60)), dispatch_get_main_queue(), ^{
            touchTo(touch, at, i == steps ? UITouchPhaseEnded : UITouchPhaseMoved);
        });
    }
}
