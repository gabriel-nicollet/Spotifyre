# Visualizer harness

The player's Visualizer background reads Spotify's sound through `Redesigned/Player/SGRSpectrum.m`. `main.m`
runs it on the Mac as the tweak compiles it, fed in IO buffers of 1024 the way `PlayerVisualiser.x` is fed by
`AudioEffects.x`'s reader:

    ./build.sh && build/spectrum

It checks that nothing is analyzed before the tables are made, that a full scale 1 kHz sine reads 0 dB in its band
(and a tenth of it -20 dB) with every band more than one away at least 30 dB under, that 56 Hz and 10 kHz land in
the lowest band and the last but one at 48 and 44.1 kHz, that silence reads the floor, that white noise rises
about 3 dB an octave over the bands, and that it analyzes about 47 times a second at 48 kHz. The log ends with
`spectrum checks: n of 11 right -- PASS` or `FAIL`.

The view itself is laid out in the player harness (`harness/player`, scenario `visualiser`).
