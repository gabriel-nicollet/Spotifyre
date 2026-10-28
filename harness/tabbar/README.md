# Tab bar harness

The bottom of Spotify's main screen mocked under its own class names, so `Redesigned/Navbar/TabBar.x`
and `Redesigned/NowPlayingBar/NowPlayingBar.x` run for real over it on the Mac without the phone: the
tab bar container with Spotify's bar and its row of tabs, a page with a list on the tab's stack, the
now playing bar's page with its card, and Spotify's message bar (`LimitedExperienceIndicatorBar`, what
Offline and Private Session show) under the tab bar. It plays issue #33.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/TabBarHarness.app
    xcrun simctl launch <udid> com.vojta.tabbarharness shown
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `TabBar.x` and `NowPlayingBar.x` from the
checkout it sits in and links them with the real `Core/` and `SGRTokens.m`; `SRC=<other tweak/Sources>
./build.sh` builds an older tree instead, to compare. `stubs.m` stands in for the accent and repaint
hooks, the tab bar's composition and Mod Settings. iOS 27 ends an app with no scene delegate at
launch, so the harness has one.

The layout is the one 9.1.78 makes in a compact width, with the addresses it was read from:

- `TabBarContainerImpl`'s view has a guide from 49 pt above its safe area's bottom to its bottom
  (`viewDidLoad`, 0x1008409a8); the stack holding the tab bar is as tall as the guide and stands on
  the view's bottom, and the tab bar is as tall as the stack (0x106fabb7c).
- The page on the tab's stack gets 49 pt of safe area on top of the container's (0x10707bde4). The now
  playing bar's share of the pages' inset comes another way in Spotify; here it is a stand-in of 64 pt
  on the page, so the list's end marks where Spotify thinks the bars begin.
- The chrome puts the tab bar container above the message bar, and the now playing bar's page (64 pt,
  its content 8 pt above its bottom, 0x105345190) on the container's guide's top, which is the bottom
  anchor `MainUIContainer` gives the chrome (0x100ae0178).
- The message bar is its message plus the safe area it pads the message by, 22 pt here.

Launch words: `none` no message bar; `shown` one sliding in at 1.5 s; `away` one there from the start,
sliding away at 1.5 s; `cycle` in at 1.5 s and out at 4.5 s, for a recording. At 2.5 s everything is
logged in window points, with the gap between the bottom of the now playing card and the top of the
glass bar's platter (8 pt is the redesign's own, on a Face ID phone with nothing under the bar), and
half way through a slide what the screen shows of the message bar, the tab bar and the now playing bar:

`split` after the first word makes Search a split tab (stubs.m answers `SGRTabIsApart` for it), so it
stands on a glass bar of its own, and the platters of both bars are logged. `pick` picks Search at 2 s and
Home at 4 s through the system bar's delegate, the mock tab repainting its label white as Spotify's does,
and logs which bar selects what after each: `xcrun simctl launch <udid> com.vojta.tabbarharness pick split`.
`lit` has Your Library stand in for a tab of the mod's own whose page is up (stubs.m answers `SGRNavbarLitTab`
with it) at 2 s, while Home's label stays white: the selection logged at 2.5 s should be Your Library. Home is
picked at 3.5 s, which forgets the lit tab, and the selection at 4.5 s should be Home.

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "tab bar:"'

`mini` minimizes the bar at 1 s through `SGRSetTabBarMinimized`, logs at 2.5 s and expands it again at 3.5 s,
logging at 5 s. Minimized, the platters should be two 62 pt circles 21 pt in from each side, the card
between them 8 pt from each, centered on them, and a touch at the card's middle should land in the now
playing bar (through the hook on the page's `TouchPassthroughView`); expanded again, all as `none` has
it. Every report also gives the frame of the fade under the bars. The mock card's labels have fixed
frames, so how Spotify's own content takes the narrower card is not shown here.

`names` logs every title the glass bars show and whether UIKit cut it short ("CUT", against the width the text
needs at the smallest size its label may shrink to): at rest, as the bar starts to expand from minimized, mid-way,
once expanded, after four turns 0.1 s apart, after a minimize and an expand with no animation (the player opening
and closing), and after another layout pass. Each line ends with how many are cut, which should be 0. `split2`
sets Create apart as well as Search, `five` adds a fifth tab and `long` gives two tabs long names (`names split2`,
`names split five long`). The log is read most reliably from the console:
`xcrun simctl launch --console-pty <udid> com.vojta.tabbarharness names split2`.

2026-10-06, iPhone 17 Pro on iOS 27.0, before the fix: every name read "…" while the bar grew (8 cut), Search and Your Library stayed cut after the minimize and expand with no animation, and with two
split tabs their names stayed "Sea…" and "Cre…" at rest for good. A split Search (32 pt for 35) and long names
were cut at rest. After it, 0 everywhere, except a name that does not fit even at 8 pt ("Your Library and
Downloads" beside a split tab), which UIKit still cuts.

`touch.m` makes touches the way a finger's arrive (a `UITouch` and the touches event with the IOHIDEvent
UIKit's gesture recognizers read, the private calls KIF makes), so the scenarios below tap the glass bar and
fling the list through UIKit's own recognizers and scrolling. Checked on iOS 27.0 in the simulator only.

`tap` minimizes the bar at 1 s, logs at 2.5 s what a finger on the leading circle lands on (and with `split`
on the trailing one), and taps it. Both should land on a `_UITabButton` of their own glass bar, and after
the tap at 3.5 s and 5 s the bar should be expanded with Home selected, as `none` has it. 2026-10-06, iPhone
17 Pro on iOS 27.0, before the fix: the leading circle's touch landed on the now playing bar's container
view (a plain `UIView` here), which the hook on `TouchPassthroughView` handed it because that view keeps the
screen's width when the card is narrowed into the row; the bar stayed minimized. After it, `_UITabButton`,
and the bar expanded.

`turns` flings the list for real: down from its top to minimize, back up and down again half way through
that, back up with a finger stopping the list, and four turns 0.15 s apart. `nested` minimizes the bar from
inside a property animator left paused a third of the way (as a header that follows the scroll keeps one)
and expands it inside a 3 s animation block. Each check says whether the bar and the card agree (the
circle 21 pt in and the card in its row, or the whole platter and the card above it), what the screen
shows, how many animations are left, and IN STEP or OUT OF STEP. 2026-10-06, iPhone 17 Pro on iOS 27.0,
before the fix: `nested` stopped with the circle at x 107 on its way along the row and the card 22 of its
67 pt down, 50 animations held, the phone's screenshot of a bar left half minimized; the expand took
the block's 3 s. After it, every check IN STEP with one animation (UIKit's own), at rest at once.

`motion` samples what the screen shows (the presentation layers) every 1/60 s: the main bar's platter, its
leftmost glyph, the split bar's platter and the card's glass, across six stretches of 1 s: a minimize, an
expand, each of them turned back 0.15 s in, a minimize again, and four turns 0.1 s apart. Each logs the largest
change in x, y, width or height from one frame to the next (a frame the simulator skipped counts as that many)
and how often the view watched was a new one, then a check and the names. `timeline` logs every sample. The
stretches run one after another and time their turns from their own start: dispatch_after may run a block a
tenth of its delay late, so steps timed from the launch, as `names` times its quick turns and `tap` its tap and
the report after it, can fall together (one `tap` run in three reported the bar before the tap's touch-up).
A critically damped spring moving the platter's 298 pt peaks at some 50 pt a frame over 0.34 s; more is a jump.
A single sample off its neighbors at a turn is one read in the turn's own run loop pass, before its animations
are committed.

2026-10-06, iPhone 17 Pro on iOS 27.0. Before the fix, every minimize laid the circle's one item out in the
full bar first: the platter went from 360 pt wide at x 21 to 100 pt at x 145 in one frame (259.7 pt) and the
Home glyph from x 40 to 183 (142.7 pt), then slid back to the leading end; an expand turned back jumped 108 pt
and four quick turns 191.6 pt. The tabs' titles were made again after the spring had started. After it: the
largest step 49 pt for the platter (36 with a split tab), 16 for the card (27), 3.8 for the glyph away from the
turns, no title cut at any point, every check IN STEP. Under Reduce Motion (`defaults write
com.apple.Accessibility ReduceMotionEnabled` in the simulator) the bar and the card change in the same frame.

`minimize-check.c` runs the scroll's steps (`MinimizeStep.h`) on the Mac:

    cc -I../../tweak/Sources/Redesigned/Navbar minimize-check.c -o build/minimize-check && build/minimize-check

`jam` plays a Jam: a strip under the class name of Spotify's (a SwiftUI hosting view of
`Jam_AttachmentsImpl.JamHatElement`, 44 pt) over the card, both in a view painted the album color too,
the bar 44 pt taller, and the strip gone again at 3.5 s. The log then lists the bar's glass panes. The
card's glass should be the track card's (386x56), the strip's pane 36 pt above it with a 4 pt gap, and
once the Jam is over the card's glass should still be 386x56 and the strip's pane should have no effect.
Before the fix the card's glass was the painted view around both, cut to 80 pt, over the strip and
the top 36 pt of the track. How Spotify really nests the strip is not known; this is one way the spec's description
allows.

Before the fix the gap was -26 pt with nothing under the bar on an iPhone SE, and with the message bar
up on any phone: UIKit's glass bar is 83 pt, Spotify's bar was its 49 pt row with no inset under it,
and the glass bar stood the difference above it, over the now playing bar.

What it does not cover: Spotify's own chrome, which is Swift with no symbols (the constraints above
are read from its code, not run), the real now playing bar's content and its page's inset, the tab
bar hidden by a page, the player's open and close over the bars, and a regular width.
