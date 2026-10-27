# Add a Tab harness

The Add a Tab sheet (`Shared/Navigation/AddTabSheet.m`) and the icon catalogs (`TabIcons.m`) run for
real in the simulator, over a stand-in for Spotify's `SPTEncoreIcon` (eight glyphs drawn as SF Symbols,
plus class methods that are not glyphs) and `SPTEncoreIconView`. `Links.x` is compiled as it is; with no
link dispatcher every route is "unknown", which lets a link through as it does before Spotify sets the
dispatcher up.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/AddTabHarness.app
    xcrun simctl launch <udid> com.vitrine.addtabharness added
    xcrun simctl io <udid> screenshot shot.png
    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'process == "AddTabHarness" AND (eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "add tab")'

Launch words: `sheet` the sheet as it opens; `preset` Liked Songs picked, which fills the name and the
icon; `glyphs` Choose an Icon on Encore; `symbols` Choose an Icon searching SF Symbols for "heart";
`pick` one of those results tapped while the search is up, then the page it lands on logged; `added`
Liked Songs with the SF Symbol music.mic added, the tab logged. The glyphs the enumeration kept and how
long the SF Symbol list took to read are logged on every launch.

The redesign's Tab bar page (`Redesigned/Navbar/NavbarSettings.m`, with `NavbarLayout.m`) runs here too, over a
sample bar: Spotify's four tabs, Liked Songs added after Search, Create hidden and Search split apart. `stubs.m`
draws Spotify's own tabs' glyphs as SF Symbols where TabBar.x reads them off the bar. Launch words: `navbar` the
page; `icons` Icons only picked on its card; `links` the page scrolled to its end; `off` Custom tab bar switched
off; `hide` Home's circle tapped; `edit` Liked Songs tapped, which opens Edit Tab; `remove` Remove Tab on that
sheet, confirmed. Each step logs what the preview shows and what each tab row reads.

2026-10-06, iPhone 17 Pro on iOS 27.0: the preview shows Home, Liked Songs and Your Library on the main bar and
Search on a bar of its own; Icons only stores the key and drops the names; Custom tab bar off shows Spotify's four
tabs in Spotify's order; Home's circle hides it on the list and the preview; Remove Tab asks, then takes Liked
Songs off the list, the preview and the stored layout.

What it does not cover: Spotify's real Encore classes and router, the glyphs TabBar.x reads off Spotify's bar,
a drag on the list, a real finger (the steps call the
table's delegate and set the search text), the keyboard over the compact detent, and iPad.
