# Native player harness

The native look's player fixes on the simulator, without the phone: `Native/Player/PlayerScrub.x` and
`PlayerDeclutter.x` run through `logos.pl -c generator=internal` over mocks under Spotify's class names,
linked with the real `Core/`.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/NativePlayerHarness.app
    xcrun simctl launch <udid> com.vojta.nativeplayerharness
    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'process == "NativePlayerHarness"' | grep harness

`SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other sources, for example
main before the fixes, to see the checks fail.

It checks, a line each with `ok` or `WRONG`:

- the scrub (issue #172): the player list's pan off while a mock of the progress bar's slider tracks, back
  at its end, at a cancel and when the slider leaves the window, a pan off already left off, and a sideways
  list between the slider and the player's list left alone.
- the cover's room (issue #77): with Lyrics preview shown nothing moves; with it hidden the preview takes
  no room and the cover is the centered square of the view it sits in, again after a later pass of
  Spotify's; a small cover and a tilt view outside the player's cover cell are left alone.

The log ends with `native player checks: n of 11 right -- PASS` or `FAIL`. On main before the fixes it
reads 7 of 11.

What it does not cover: Spotify's real Auto Layout in the cover cell, its open and close transition, and
a real touch on the slider.
