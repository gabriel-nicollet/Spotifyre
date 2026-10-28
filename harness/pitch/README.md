# Pitch harness

`SGTimePitch.m` run on the Mac both ways the tweak runs it: in place over IO buffers of 1024, 4096
and odd sizes (pitch alone), and pulling a source at rates from 0.5 to 2 (speed). Checks a 440 Hz sine
comes out at the pitch asked for and the source is consumed at the rate asked for, and reports the
unit's pulls, underruns, delay and cost. Then one unit through the changes the menu makes while it is in
(a return to 1x, pitch set at 1x, Pitch follows speed switched), checking which ones change between
Varispeed and the stretch, the longest silence each leaves and the pitch after; a failed one exits 1. With a song path it also writes the song shifted up 3 and down 4
semitones into `build/` to listen to.

    ./build.sh && build/pitch ../../../song.mp3
