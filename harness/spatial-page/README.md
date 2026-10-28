# Spatial voice page harness

The Sing page (`tweak/Sources/Shared/Sing/SingSettings.m`) and the Spatial voice page under it, with its preview
(`SGSpatialPreview.m`), on the real Settings/ framework. `stubs.m` stands in for Sing's state (a model on the
phone, Sing off) and for HeadGestures' motion, which it plays from a script of the head's yaw at 25 motions a
second while the preview listens; it also answers Motion & Fitness's permission as the launch line says.

    ./build.sh
    xcrun simctl install <udid> build/SpatialPageHarness.app
    xcrun simctl launch <udid> com.vojta.spatialpageharness on allowed head=60 spatial
    xcrun simctl io <udid> screenshot shot.png

Other agents use the simulator too: make a device of your own (`xcrun simctl create`) and address it by UDID.
`main.m` lists the setup words (`on`, `allowed`, `denied`, `head=sweep`, `head=<degrees>`, `width=<points>`,
`slow`) and the actions, played one every 0.7 s from 1 s in: `spatial` opens the page, `toggle`, `pop`, and `dump`,
which logs the rows, the header's size and what VoiceOver reads on the preview, and `lag`, which reads the disc on
screen every frame for 3 s against where the head's script has the voice then and logs how far behind it is. The
stub logs each listener coming and going:

    xcrun simctl launch --console-pty <udid> com.vojta.spatialpageharness on allowed head=sweep spatial dump pop dump
    xcrun simctl launch --console-pty <udid> com.vojta.spatialpageharness on allowed head=sweep spatial wait wait wait lag

2026-10-06, `lag` with head=sweep (30 degrees a second on average): 4.6 degrees, 155 ms, behind when each motion was
animated to over a fixed 0.12 s; 0.5 degrees, 16 to 18 ms, once each is animated over the motions' interval to
where the head will be by the next. With head=60 (150 degrees a second at its fastest) the gap is 4.4 at most and
0.4 on average.

The Sing page's card: `state=7 playing` has Sing on and a made-up song's levels traced; `chunk=<ms>` moves the
song's tenths on in renders that long, a part of a tenth out of step with the wall clock, as the engine's own do;
`busy` holds the main thread up to 30 ms at a time; `none` is no track and none ever played, `last` no track with
Holocene the last one played, `title=<text>` the playing track's title. `lines` reads the lines every frame for
5 s and logs the frames where they jumped back or ahead:

    xcrun simctl launch --console-pty <udid> com.vojta.spatialpageharness chunk=85 state=7 playing wait wait lines

2026-10-06, `lines` with chunk=85: the card that slid the lines one tenth on every wall-clock tenth jumped 8 times
back and 11 ahead in 5 s (49 of its 200 draws over 20 s slid a tenth when the levels had not, or not when they had);
drawn as the levels move on and glided from where they are on screen, 0 back and 2 ahead (a catch-up past two
tenths). With chunk=0 both are smooth, and so is the old card under `busy`: its timer stayed in step.

Reduce Motion: `xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`,
then launch again (and `false` after).

2026-10-06, iPhone 17 Pro on iOS 27.0: the Sing page's Spatial voice row reading On and opening the page; the
preview swaying with no permission, with Motion & Fitness denied (its caption), and following a head turned 60
degrees left (the voice 60 degrees right, back to about 36 after 10 s as the front follows); the listener taken
out on pop and back on push; Reduce Motion holding the disc still, the ripples gone, the turn faded to in steps;
the header growing with its caption at the largest text sizes, and the disc fitting a 320-point window.

What it does not cover: real AirPods (the yaw's sign is not yet heard, see SGSpatialVoiceAngle), how often they
send motion, and what the preview costs on a phone's battery.
