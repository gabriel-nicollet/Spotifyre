// Sing's mic on the redesign's lyrics (Shared/Sing/Sing.h), in the bottom trailing corner of SGRKaraokeView
// across from the pronunciation and translation button, as Apple Music has it. It shows what Sing is doing
// on itself: the mic struck through where Sing cannot run, a ring filling with the voice model's download (held
// where it is under a dimmed wifi struck through while the download waits for the network), a ring turning while the model prepares and while Sing listens ahead, the mic lit in the accent color while
// the vocals are down, a thermometer while the heat holds it, a warning when it failed.
//
// A tap turns Sing on and off, or says what is missing and offers the model's download. Holding it brings up
// its slider, which takes the vocals from gone at the bottom, through the song as sung in the middle, to the
// vocals alone at the top. To VoiceOver the mic is one adjustable button: a swipe up or down moves the
// same level.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGRSingButton : UIView
// Goes with the host's controls when they are hidden, in the host's animation: its glass dematerializes
// rather than fading under an alpha, and it takes no touches while tucked.
@property (nonatomic) BOOL tucked;
@end
