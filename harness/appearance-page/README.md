# Appearance page harness

Mod Settings > Appearance as `App/Pages.m` builds it: either look's accent rows (`Native/Appearance/AppearanceSettings.m`,
`Redesigned/Kit/SGRAppearanceSettings.m`), the Font rows and their import (`Shared/Fonts/FontImport.m`) and the real
Settings/ framework (the pull-down menu row, the swatch, the color sheet), with `stubs.m` reading the accent and
font keys the way the Logos files do.

    ./build.sh
    xcrun simctl install <udid> build/AppearancePageHarness.app
    xcrun simctl launch --console <udid> com.vojta.appearancepageharness accent=123456 menu=1.1:0 dump menu=1.1:2 dump
    xcrun simctl io <udid> screenshot shot.png

Make a simulator of your own (`xcrun simctl create`) and address it by UDID. `main.m` lists the setup words
(`redesign`, `accent=`, `raccent=`, `font=`, `keep`) and the actions: a menu item picked, a row tapped, the
color sheet moved, confirmed or closed, a font file handed to the import as Files would, and `dump`, which logs the
stored keys, the color in effect, what the launch would register for the font and what every row reads.

2026-10-05, iPhone 17 Pro on iOS 27.0: an old Apple Music red reads Apple Music, an old #123456 reads Custom, nothing
stored reads Spotify (native) or Custom #37F200 (redesign); Custom → Spotify → Custom brings #123456 back; the sheet's
close keeps the color, its checkmark stores it as Custom; a text file named .ttf is refused with nothing stored;
Chalkduster.ttf (a face iOS already has) and then a Noto .otf import, the second replacing the first, and a deleted
file registers nothing.

What it does not cover: a finger on the pull-down (UIKit opens it only from a touch), the document picker itself,
and Fonts.x's hooks, which only Spotify can show.
