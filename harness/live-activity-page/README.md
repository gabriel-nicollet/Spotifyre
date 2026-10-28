# Live Activity page harness

Mod Settings > Live Activity as `Shared/LiveActivity/LiveActivitySettings.m` builds it, with its preview
(`SGLiveActivityPreview.m`) and the real `Settings/` framework. `stubs.m` stands in for the activity's switch and
the sleep timer's fade names. `main.m` lists the setup words and the actions.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/LiveActivityPageHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.liveactivitypageharness view=2 dump wait wait wait dump tap dump
    xcrun simctl io <udid> screenshot shot.png

Make a simulator of your own (`xcrun simctl create`) and address it by UDID. The app takes a few seconds to show
after the launch, so wait before the screenshot.

2026-10-06, iPhone 17 Pro on iOS 27.0: the preview is 325 pt high and keeps that height in every view. Control
menu steps from Controls to Queue to Timer about every 3 s, a tap goes on to the next, and `stop` holds it.
Lyrics steps through three lines and then a track with no lyrics. Queue rests. With Control menu picked, the
lyrics' four rows are hidden. Seen in screenshots: Lyrics with translations, the no-lyrics track under Note,
Plain with Center, Track and Artwork off, Controls under Artwork colors, Queue with the bar off.

What it does not cover: Reduce Motion, which the simulator cannot switch from the command line; the real card,
which only a phone shows.
