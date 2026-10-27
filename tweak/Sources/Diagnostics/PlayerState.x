// Debug builds only: the player the driver reads its state from (Driver.m).
#import "Core/SGCore.h"
#import "Diagnostics.h"
#import "Headers/SPTPlayer.h"

static __weak id sg_player;

id SGDiagnosticsPlayer(void) {
    return sg_player;
}

%hook SPTEsperantoPlayer
- (id)state {
    sg_player = self;
    return %orig;
}
%end

%ctor {
    if (!SGIsDebugBuild()) return;
    %init;
    SGRequireClasses(@[@"SPTEsperantoPlayer"]);
}
