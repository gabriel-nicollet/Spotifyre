# Player harness

Spotify's full screen player mocked under its own class names and accessibility identifiers
(from `trees/clean/player/01.txt`), so the redesign's player can be laid out, animated and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerHarness.app
    SIMCTL_CHILD_HARNESS_SCENARIO=artwork xcrun simctl launch --console-pty <udid> com.vojta.playerharness
    xcrun simctl io <udid> screenshot shot.png

Launch it on a simulator by UDID; it has a scene delegate (`../scene.m`), so the iOS 27 runtime runs it
too. `SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other
sources, for example an older commit, to see a bug before its fix.

`build.sh` runs `logos.pl -c generator=internal` over `PlayerLyrics.x`, `PlayerArtwork.x`,
`PlayerControls.x`, `PlayerFooter.x`, `PlayerScroll.x`, `PlayerField.x`, `PlayerHeader.x` (the glass circles of
the down arrow and the ⋯, in a mocked `HeaderElementsUnit`, and their press) and the Kit's `SGRBridges.x`, and links them with
the real `Core/`, `Redesigned/Kit/`, `SGRKaraokeView`, `Settings/`, the Player page and the Visualizer (`PlayerVisualiser.m`, `SGRSpectrum.m`). `stubs.m` stands in for the hooks the harness
does not compile (the Kit's accent and repaint, the rest of the player, the lyrics store, the haptics,
Sing's mic) and plays a mock player: `SGRHarnessSetTrack` reports a track, with the image ids Spotify's
metadata carries, to every state observer. A song of ten timed lines plays on from launch. `main.m` also answers
for i.scdn.co through an `NSURLProtocol` handed to every session, so each picture the Kit fetches can
come late, out of order, or not at all.

`HARNESS_SCENARIO` picks what the harness does:

- `lyrics` (default) opens the lyrics at 2 s, closes them at 6 and opens them again at 10.
- `look` plays one track, then a track from another album at 8 s, whose picture reaches the screens
  0.4 s later. It shows the field, the moving background and its crossfade, and the footer row. At 3 s
  it logs whether touches on the lowered footer row (issue #54) still reach it.
- `artwork` is issue #58. Tracks change while the covers on screen lag behind (3.5 s late, past the
  Kit's last look), two skips come in a row with the older picture answering last, and one track plays
  offline. Each step checks by color that the Kit and the field show that track's picture, and the log
  ends with `artwork checks: n of 4 right -- PASS` or `FAIL`. Before the fix it read 1 of 4.
- `landscape` turns the lyrics sideways at 3 s, puts a line's meanings over them (the real
  `MeaningSheet.m`) at 4 s and takes them away at 9, then pauses at 14.5 and resumes at 15.5. Each step
  logs whether the controls are up and whether a touch on the lines lands on the lines or on the shield
  that brings the controls back, with `ok` or `WRONG`. At 6 s it logs the sheet's frame: a card inside
  the safe area with a grabber, where the sheet before it covered the whole screen. It also logs that the
  window comes up clear and fades in, dark, that every button has a label and 44pt, and at 22 s that
  VoiceOver's escape takes the screen away and gives the key back to the player.
- `scroll` moves the list up and down in code and logs whether it stayed at its top, then scrubs a mock of
  the progress bar's slider in code (issue #172): the list's pan off while it tracks, back at its end, at a
  cancel and when the slider leaves the window, and a pan that was off already left off. The log ends
  with `scrub checks: ... -- PASS` or `FAIL`.
- `cover` is issue #77. The cover is checked untouched first, then given Spotify's layout for a track with
  lyrics, a smaller cover over the lyric preview, and must take its room back as a centered square the
  Kit also reports. The log ends with `cover checks: n of 4 right -- PASS` or `FAIL`.
- `immersive` opens the lyrics and waits past the rest: only the bottom stack under the title row
  (progress bar, buttons, volume row, footer) fades, the lines grow down only, a touch where the buttons
  were lands on the lines, the thumbnail takes its own, and the lines' tap is off. Then the tap that
  wakes them (fired in code), a scroll that hides them again and the thumbnail closing the lyrics. Then,
  opened again, a sheet over the player keeps the controls up past the rest and they fade once it has
  gone, Sing's mic stays with the lines and takes its own touch, and a finger held on the player (its
  touch watcher driven in code) keeps the controls up until it lifts. The log ends with
  `immersive checks: n of 15 right -- PASS` or `FAIL`.
- `badge` shows the hold's 2× badge on the cover by hand, holds again while it fades out and lets go.
  The log ends with `badge checks: n of 3 right -- PASS` or `FAIL`.

- `motion` is Animated artwork. The clip, `HARNESS_CANVAS_FILE` (any mp4, `harness/fluid-clip` writes one),
  is served as the track's Canvas before the player's background has laid out; then the background lays
  out, the lyrics open and close, the background is built again, and the ⋯ menu's switch goes off, on, and
  off with the player out of its window. Each step is checked (the clip on the field, the cover hidden, the
  poster under the video and the Fluid field held under it, the foot and the blur, the thumbnail, the clip
  and the cover crossing over half way through the switch). Then the song pauses and plays (the clip's rate
  0, then 1), a mock of Spotify's video unit attaches and detaches its video (the clip goes and comes back),
  a track comes with no Canvas and then again with one (the clip comes in late), and a skip to a track whose
  clip is in the store keeps the last clip until the new one is over it, the cover hidden throughout. The clip's
  dim is checked over the clip and 0.15 darker under the lyrics, with the rule at its ends; `HARNESS_DIM` is the
  dim the clip should get (`ffmpeg -f lavfi -i "color=c=white:s=360x640:d=4"` gives 0.54, black 0.10). Uninstall
  the app between clips, or the store answers with the last one. Then Low Power Mode, which the process is made
  to report (the simulator has none; Reduce Motion takes the same path), takes the clip away for the cover over
  Fluid and gives it back once off, and a track change with the app made to report the background takes the clip
  away at once, with no fade. The log ends with `motion checks: n of 25 right -- PASS` or `FAIL`.
  `HARNESS_CANVAS_FAILS=n` fails the first n requests for the clip on the way: with 1 the store tries again and
  every check passes, with 2 the clip never comes.
- `catalog` is Apple Music's catalog (`SGMotionCatalog.m`) behind a stub of its search: the names searched
  without their edition, an album search for "Midnights (3am Edition)" asking "Taylor Swift Midnights" and taking
  the edition of that same name before the standard album, then a 429 and the next album finding nothing at once
  with nothing asked. The log ends with `catalog checks: n of 5 right -- PASS` or `FAIL`.

- `settings` opens the redesign's Player page (`PlayerSettings.m`, with the real `Settings/` framework) over the
  player at 3 s, with the clip of `motion` in. It checks the card leads the page with the five backgrounds'
  segmented control under it, every name whole, the Mini player section's three rows are on the page, and then,
  as the control picks each in turn, that the card shows Animated (the clip, the sources and Low Data Mode's rows
  in), Fluid, Colors, Still, Visualizer (the hills over Fluid held still) and Animated again, with a note for
  each and the header the same height throughout. The log ends with `settings checks: n of 8 right -- PASS` or
  `FAIL`.
- `preview` opens the Player page with the background Still at launch, so the player looks up no clip, and picks
  Animated on it. The card looks the track's clip up itself: nothing is asked for before the page or while Still
  shows, the card is Fluid while the clip comes (`HARNESS_CANVAS_DELAY`, 2 s), then the clip is in it with its
  poster and the field held, the player still without one, and the file in the store, where `SGMotionFile` finds
  it without asking the server again. Fluid and then Animated again bring it back at once. The clip's address is
  the run's own, so the store never has it from a run before. The log ends with
  `preview checks: n of 7 right -- PASS` or `FAIL`; on the sources before the fix it read 5 of 7.
- `card` plays nothing and opens the Player page at 1 s, then logs the card's title, artist and cover size: with
  no track ever played, Not Playing over the accent's gradient; with `HARNESS_LAST=1`, a last track played with a
  long title (gliding), its cover from the picture server and a Canvas of the run's own (`HARNESS_CANVAS_FILE`).
  `HARNESS_BACKGROUND` is the background's index, Fluid if unset. For screenshots: 2026-10-06 on an iPhone 17 Pro,
  iOS 27.0, the card read Not Playing over a dim green field, and Holocene with its cover over Fluid.
- `visualiser` plays the Visualizer background, fed by `stubs.m`'s stand-in for the audio effects' reader: a song
  of its own at 120 beats a minute, handed over in buffers of 1024 at 48 kHz. It checks the hills stand on the
  Fluid field held still with the reader on and the link at up to 60 fps, blur behind the lyrics with the link at
  30, settle and stop with the reader off on a pause, come back on play, and go and come back through the ⋯
  menu's switch to Fluid and back. The log ends with `visualizer checks: n of 7 right -- PASS` or `FAIL`.

- `header` is the glass circles' press (`PlayerHeader.x`): a finger (`../tabbar/touch.m`) held half a second on
  the down arrow and then on the ⋯, each a `UIControl` under Spotify's identifier. It checks each has a 44pt glass
  circle first among its subviews, that a touch at its middle lands on the button, that the circle is pressed
  in (scale 0.92) while the finger is down and whole again once it lifts. The log ends with
  `header checks: n of 9 right -- PASS` or `FAIL`. The ⋯'s press on the phone comes through the mod's button
  over it, which this harness does not build; `harness/system-menu`'s `arrow` run covers that button's events.

- `seek` is the tap around the progress bar (`PlayerControls.x`): a mock slider with Spotify's identifier and
  the two times beside it. It checks that a tap counts below the bar and up to 12 pt past its ends, not on the
  thumb or the times, that the ends of the thumb's travel are the song's start and end, that a tap is played
  to the slider as touch down, value changed and touch up with the slider still tracking, that a drag nobody
  seeks for is seeked directly after a second, and that the slider lets go once the position is there. The
  log ends with `seek checks: n of 9 right -- PASS` or `FAIL`.

`HARNESS_VOLUME=0` leaves out the volume row that the phone has and the tree does not.

A screen recording is the way to see a move:

    xcrun simctl io <udid> recordVideo -f run.mp4      # ^C to stop
    ffmpeg -ss 7.4 -t 2.2 -i run.mp4 -vf "fps=5,scale=180:-1,tile=11x1" -frames:v 1 strip.png

It also lays every unit out once a second, which is what the transforms on Spotify's title row and the
narrowed marquee labels have to survive.

What it does not cover: the real element framework's autolayout, Spotify's own scrolled layout, the
player's open and close transition, and Spotify's real image loading.
