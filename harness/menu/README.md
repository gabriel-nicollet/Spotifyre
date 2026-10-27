# Menu harness

Spotify's context menu sheet (`ContextMenu_InternalImpl.ContextMenuViewController`) mocked under its
class name and presented from a now playing controller on a tap of the player's more button (a mock
`NowPlaying_ModesImpl.HeaderElementsUnit` holding a button with the identifier `Context menu`), so
`SpeedPitchMenu.x`'s hooks find the button and add Speed and pitch the way they would on the phone. Speed and pitch themselves are stubs that log.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/MenuHarness.app
    xcrun simctl launch --console-pty <udid> com.vojta.menuharness [footer] [nospeed] [loading] [stuck] [open] [animated] [sleep] [notap] [minute]

It has a scene delegate, so it runs on the iOS 27 simulator as well as 26. The mod's own lines
(`SGLog`) go to the unified log: `xcrun simctl spawn <udid> log stream --predicate 'eventMessage CONTAINS "[spotifyglass]"'`.

The plain run opens the menu at 1 s, the block at 3 s, moves the three sliders at 5 s, and at 6 s logs
`PASS` or `FAIL` for what the block then says: the Reverb thumb where it was let go, the Pitch reading
"Follows speed" (its reset off) while Pitch follows speed is on at 1.25x, and the switch enabled. It
closes the block at 7 s and at 8 s checks the closed row reads "1.25×  Reverb", no semitones claimed.
`footer` gives the mock table a header of Spotify's, so the block goes to the footer;
`nospeed` has the player refuse speed: the speed slider is left alone, the switch must be disabled, and
the Pitch and the row read "−3 st".

- `loading` builds the sheet the way Spotify's is laid out (a header, a content container holding a
  table sized to its content by KVO on `contentSize`, a spinner) and gives it its rows 4 s after it is
  up, the way Spotify does once its item factories have answered. It reports the sheet while loading
  and once the rows are in: they show under the block.
- `stuck` never gives it rows; the mod logs `no rows of Spotify's N s after the menu appeared`.
- `open` opens the block on a first menu, closes that menu and brings up a second one with the block
  already open, as it stays for the session.
- `animated` offers the redesign's Animated artwork switch (stubbed): it flips the switch with the block
  closed and again with it open, and reports where its row sits each time, `PASS` when the row is inside
  the block and the switch shows what was set.

- `sleep` opens the ⋯ card, checks it has the block, then pushes a second sheet into it with no tap, as
  the card's Sleep timer row does: `PASS` when that sheet has no block.
- `notap` presents a sheet from the player with no tap on the more button: `PASS` when it has no block.
- `minute` runs `MinuteLabel.x` on Spotify's two sleep timer cells, mocked under their class names: a label
  reading "1 minutes" in each reads "1 minute" in the font it had, and "5 minutes", "1 minuto" and a label
  outside those cells stay as they were.

For the first second the block is on screen, every frame is checked for anything it draws in the
system tint (`tint check: 0 of the block's first N frames ...`).
