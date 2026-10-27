# Mod Settings harness

Mod Settings' main page as `App/ModSettings.x` builds it, opened through `SGOpenModSettings` and pushed onto a
navigation stack as on the phone, with the real `App/Pages.m` behind the Redesigned UI switch and the real
`Settings/` framework. `build.sh` runs `ModSettings.x` through `logos.pl -c generator=internal`; its hooks on
Spotify's settings list and side drawer find no class here and do nothing. `stubs.m` stands in for every page a
row opens (an empty page of that name), the values beside the chevrons (Off) and the update and signing checks.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/ModSettingsHarness.app
    xcrun simctl launch --console-pty <udid> com.vitrine.modsettingsharness redesign warning dump
    xcrun simctl io <udid> screenshot shot.png

Make a simulator of your own (`xcrun simctl create`) and address it by UDID. `main.m` lists the setup words
(`redesign`, `warning`, `keep`) and the actions: `toggle=<section>.<row>` flips a switch the way a tap does,
`cancel` closes the alert it brings up, `bottom` scrolls to the end, and `dump` logs the rows of every section.

`gated` pushes a page of `SGModPage` itself: a switch over ten rows, then a section with a heading and a note
whose twelve rows show only while the switch is on, then a row that `later` lets come by itself. `layout` logs
the scroll offset and each section's rows, heading and note heights; `top` scrolls back up.

    xcrun simctl launch --console-pty <udid> com.vitrine.modsettingsharness gated layout toggle=0.0 layout later dump layout top toggle=0.0 layout

2026-10-06, iPhone 17 Pro on iOS 27.0: with the switch off the gated section has 0 pt of heading and note; the
switch brings it in with its 38 pt heading and 28 pt note and scrolls 362 pt, half the 724 pt of room; the
ticker brings the later row within a second without moving the page; the switch off takes the heading and note
away again.

`rows` on the launch line makes Spotify's settings list controller and the side drawer's list class under their own
names before the hooks are set, then lays a drawer list out and a settings list out under its controller, empties
each of its subviews as Spotify can, and lays it out again. It logs how many Mod Settings rows each has: 1 and 1 for
both. With main's ModSettings.x before the fix it read 0 and 0 for the drawer and 1 then 0 for the settings list.

`needs` pushes the Lock screen page's artwork section as iOS 18 to 25 get it (the real
`AnimatedArtworkSettings.m`'s `SGLockScreenArtworkNeedsRow`), and `tap=<section>.<row>` selects a row and logs the
alert it brings up: "Full-screen artwork", "Needs iOS 26", and an alert naming the iOS version.

2026-10-06, iPhone 17 Pro on iOS 27.0: the warning row leads; then Redesigned UI (glowing, with its ⓘ), Appearance
and Tab bar; Player, Lyrics, Albums and Artists (Home & Library in the native look); Sing, Spatial voice, Audio
effects, Vibrations, Live Activity, AirPods gestures and Listening stats; Lock screen and Premium, ads & privacy; Labs and
All flags; Mod with the version. Flipping Redesigned UI on in the native look offers the restart and swaps Home &
Library for Albums and Artists in place.

`App/About/Signing.m` is the real one. A free Apple ID's "Signed until" row joins the top section once the
.app holds an `embedded.mobileprovision` whose `ExpirationDate` is under eight days after its `CreationDate`; the
parser takes a plain XML plist as well as a signed one, so one written by hand will do (copy it in after
`build.sh`, before `simctl install`).

What it does not cover: the pages the rows open, the row the mod adds to Spotify's settings list and side drawer
in Spotify's real lists (`rows` uses stand-ins of the same names), and iOS below 26, where the switch warns first.
