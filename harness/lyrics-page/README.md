# Lyrics page harness

The redesign's Lyrics page as `App/Pages.m` opens it (`Redesigned/Lyrics/LyricsLookSettings.m`): the preview
playing the sample song in the real lyrics view, the presets under it, the sliders' sheet, and one stand-in
section under them, on the real Settings/ framework. `../lyrics/stubs.m` stands in for the player.

    ./build.sh
    xcrun simctl install <udid> build/LyricsPageHarness.app
    xcrun simctl launch --console <udid> com.vojta.lyricspageharness -check 1
    xcrun simctl launch <udid> com.vojta.lyricspageharness -preset 4 -sheet 1
    xcrun simctl io <udid> screenshot shot.png

`main.m` lists the arguments. `-check 1` taps the presets, opens the sheet and moves a slider, and checks
what the preview, the presets and the sliders read after each.

2026-10-05, iPhone 17 Pro on iOS 27.0: all checks pass; the sheet rests at half height under the preview,
which plays on undimmed.

What it does not cover: Spotify's navigation stack around the page, the other Lyrics rows, and a finger
on the sliders (the check sets their value as a drag would).
