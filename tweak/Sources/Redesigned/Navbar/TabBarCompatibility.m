#import "Navbar.h"

// Spotifyre's navbar does not minimize into the player slot. Keep Vitrine's callers safe while its player
// and now-playing bar continue using their own layouts.
BOOL SGRTabBarMinimized(void) {
    return NO;
}

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    (void)minimized;
    (void)animated;
}

CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height) {
    (void)host;
    (void)height;
    return CGRectNull;
}
