# Launch harness

What the mod adds to each remote-config flag Spotify reads as it starts. `Shared/Flags/Flags.x` hands
every read to `SGForcedFlagValue` (`Core/SGFlagForce.m`), which asks the redesign's forcer, the All
flags override, AdBlock.m's forcer and the lyrics sources' one. The check builds those sources as Mac
Catalyst, so the tweak's UIKit headers compile, and times passes over the generated table of every
flag Spotify 9.1.78 has, with Hide ads, Hide upsells and three overrides stored.

    cp ../../../spotifyglass-gpl/tweak/Sources/Shared/Flags/SGFlagList.m ../../tweak/Sources/Shared/Flags/   # or make flags
    ./build.sh && ./build/launch-check

It also checks that every answer is the one the live switches and overrides give, and fails if not.
Last it checks the override report Flags.x logs 15 s in (`SGFlagOverrideReport`): two overrides outside
the table, one a forcer that beats overrides answers and one asked for only after the first report.
2026-10-06: held.

On an M-series Mac, five runs each:

| | first pass | later pass | a read |
|---|---|---|---|
| every read asking the defaults (before) | 7.3 to 22.9 ms | 6.2 to 11.8 ms | 2.6 to 4.9 µs |
| switches and overrides read once (after) | 2.8 to 4.0 ms | 1.6 ms | 0.67 µs |

How many flags Spotify reads, and on which thread, is not measured here. Flags.x logs both on the
phone 15 s after launch: `flags: N reads in the first 15 s, M on the main thread, X ms in the mod's answers`.
