# Listening stats harness

`SGPlayLog.m` run on the Mac against synthetic files in both shapes of Spotify's data export
(`StreamingHistory_music_*.json` and the extended `Streaming_History_Audio_*.json`), loose and inside zips
made by `/usr/bin/zip` both stored and deflated. Checks podcasts, nulls and plays under 30 s are left out,
that a play already recorded, the same play in both shapes and a second import of the same files add
nothing, that the log reads back what it wrote, and that the week, month, year and all-time tops add up.
It also times parsing, merging, loading and adding up 100k extended rows.

    ./build.sh && build/listening-stats

## The page and the recorder in the simulator (`sim/`)

`ListeningStatsPage.m` on the real Settings/ framework, `ListeningStats.x` through Logos with `sim/stubs.m` standing in
for PlayerState.x and Spotify's player classes, and the page's picker kept rather than presented (the simulator's
picker is a remote service), so `pick` hands its delegate a JSON file and a zip as the system would.

    THEOS=$HOME/theos ./build-sim.sh
    xcrun simctl install <udid> build/sim/ListeningStatsHarness.app
    xcrun simctl launch <udid> com.vitrine.listeningstatsharness erase seed select=1.0 dump
    xcrun simctl spawn <udid> log show --last 2m --predicate 'eventMessage CONTAINS "[harness]"' --style compact

2026-10-05, iPhone 17 Pro on iOS 27.0: the page with seeded plays (week 1 h 36 min, month 2 h 12 min, as the seed
adds up), the Past week and All time pages (a long title wraps), an import of an extended file and a zip holding
`Spotify Account Data/StreamingHistory_music_0.json` (2 added, 1 skipped; the same again adds 0; the import row reads
Importing… until the merge, a second tap on it ignored meanwhile), and `record`: a
31 s play and one of 35 s around a 10 s pause written down (32.5 s and 36.8 s, `dispatch_after` running late), a
5 s skip left out.

What it does not cover: Spotify's real player reporting, and a real export from Spotify.
