# Album harness

Spotify's album page mocked under its own class names and accessibility identifiers
(from `trees/clean/album/03.txt`), so `Redesigned/Album/` can be laid out and looked at
on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/AlbumHarness.app
    xcrun simctl launch booted com.vojta.albumharness
    xcrun simctl io booted screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over the four `.x` files and links them with the
real `Core/` and `Redesigned/Kit/` sources; `stubs.m` stands in for the two hook files the harness
does not compile (`SGRAccent.x`, `SGRRepaint.x`).

The mock is the page as Spotify builds it: the color wash behind the header, the header itself down
its four stack views, the metadata row as a real collection view with its own cells, the action row of
explore, add, download and more, the two controls Spotify floats over the page outside the scroll
(shuffle and play), and a list of track cells followed by the footer Spotify sends — the album's own
line, the copyright, and the headings and carousels of more by, videos, merch and you might also like,
each with the 16pt spacer between them.

At 1.5 s it measures the footer the way the page's collection does, asking every cell
`preferredLayoutAttributesFittingAttributes:` and stacking the answers: that is where `AlbumSections.x`
answers 0 for what it drops, and the log says how much footer was left (108pt of 1489pt, the album's
own line and its copyright). A switch is turned off from the launch line, as an argument default, and
brings its section back: `-spotifyglass.redesign.album.hide.merch NO` measures 374pt, `.moreBy` 371pt,
`.videos` 412pt, `.youMightLike` 370pt, and `.other` 367pt for Fans also like, the section no switch names.

Since 2026-09-18 the header is the Kit's `SGRHeaderInfo` over Spotify's blanked column, so what follows no
longer tests anything the redesign moves; it still shows Spotify's column staying blank. The metadata row's
cells arrive after the header's pass, which is what `AlbumHeader.x`'s re-read answers.

`late` on the launch line (`xcrun simctl launch booted com.vojta.albumharness late`) opens the album the way a
first open has it, with no add in the row, and adds it at 2.5 s as an arranged subview of the row, which lays out
nothing above the row. At 3 s the log says what the row shows on Play's right: "Add" once `AlbumHeader.x` watches
the row, "Download" before it did (issue #19).

At 3.5 s it puts Spotify's own frames back on the title block, its stack and the action row and asks
both groups for a layout pass, which is what the redesign's `SGRObserveLayout` watches have to survive.
The log says what the redesign answered with.

`motion` on the launch line, with `SIMCTL_CHILD_HARNESS_CANVAS_FILE` set to any mp4, hands the hero that clip at
2 s the way Apple Music's catalog would. The log says the clip was added at opacity 0 and not yet fading, that by
2.5 s its first frame was ready and it had faded in and was playing, and that taken out of the window at 4.5 s it
stopped and put back it played again.

`SGLog` goes to the unified log rather than stdout, so the redesign's own lines are read with

    xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "spotifyglass"' --style compact

What it does not cover: the real element framework's autolayout and the heights it measures, the page
scrolling (Spotify fades the header out by alpha as it goes, which the mock does not), and the flags
`AlbumField.x` forces.

`download` on the launch line plays the download button's states instead of the header's (issue #65), from
`../download-mock.h`: Spotify's button drawn by Lottie with no image view, its state in its accessibility
identifier and in a mock of the Encore object behind it (`currentState`, `progress`), and shuffle's "on" dot.
None, waiting, downloading (held at 50%), downloaded, shuffle on, removed with shuffle off, error, each held a
few seconds and announced with a `[harness] state:` line to take a screenshot on. Nothing in it lays anything
out, as on the phone.

The track rows carry Spotify's explicit badge on some of them and two guests the header does not explain (one named
in the title with no "feat.", one not at all). At 2.5 s the log says, row by row, whether its artist line was
dropped, how far the title moved and where the badge was drawn against the end of the title's text; at 4 s the first
row is prepared for reuse and has to come back as Spotify drew it, then be dropped again by its next pass. At 3 s
the log also says the first card of each carousel, painted the base surface, was cleared and the gray one was not.

The artist row's picture (an `Encore.ImageView`) gets its image at 1.5 s, after the header has laid out. At 2.2 s the
log says where the redesign drew it: a round picture a line high just before the name, the two centered together
(`{{139, 368}, {21, 21}}` and the name at `{{168, 368}, {96, 21}}` on an iPhone 17 Pro).

`stubs.m` also stands in for `SGRegisterCustomFont`, which `Shared/Fonts/Fonts.x` calls and which lives in a file
that pulls in the settings rows.
