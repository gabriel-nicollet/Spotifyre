// Screen dumps for FLEX builds: the visible screen's view tree, served over the phone's loopback
// and logged when the app goes to the background.
#import <UIKit/UIKit.h>

BOOL SGIsDebugBuild(void);
NSString *SGScreenTree(void);
void SGDumpScreen(NSString *reason);
// Runs `block` on the main thread and waits for it at most `timeout` seconds; for any thread but main,
// where it just runs the block. NO when main did not get to it in time (the block still runs later).
BOOL SGRunOnMain(NSTimeInterval timeout, dispatch_block_t block);
// The app's SPTEsperantoPlayer, nil until something asked it for its state (PlayerState.x).
id SGDiagnosticsPlayer(void);

#if SG_DRIVER
// The phone driver (Driver.m): whether `command`, a request path without its slash, is one of its
// commands, and running one with the request's query items, answering JSON. Called off the main thread.
BOOL SGDriverHandles(NSString *command);
NSData *SGDriverRun(NSString *command, NSDictionary<NSString *, NSString *> *params);
// Defined in App/ModSettings.x: declared low, defined high.
void SGOpenModSettings(UIView *source);
// Defined in Shared/Player/SpeedPitch.x.
double SGPlayerSpeed(void);
void SGSetPlayerSpeed(double speed);
// Defined in Shared/Sing/Sing.x.
void SGSetSingOn(BOOL on);
// Defined in Redesigned/Player/PlayerLandscape.x: the landscape lyrics, for a Simulator that cannot turn.
void SGRPlayerShowLandscape(BOOL show);
// Defined in Shared/Lossless/LosslessProbe.m: lossless anchor --path P, check, stop. Nil with *error on failure.
NSDictionary *SGLosslessProbe(NSString *verb, NSDictionary *p, NSString **error);
// Defined in Shared/AutoMix/AutoMix.x: Spotify's Automix and Crossfade settings, read or written.
NSDictionary *SGAutoMixProbeCommand(NSDictionary *p, NSString **error);
#endif
