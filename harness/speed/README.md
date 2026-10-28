# Speed harness

Spotify's audio chain (AudioUnitDriver2: a converter fed by a render callback, a mixer and RemoteIO, wired
with MakeConnection, slices of 4096) rebuilt with real units in the simulator, with `PlayerSpeedPitch.x`
compiled in: its AudioUnitSetProperty rebinding takes over the mixer-to-output connection exactly as on
the phone (the harness is the main executable), and its SPTPlayerState hook runs on a mock state that
computes -position the way Spotify's does.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/SpeedHarness.app
    xcrun simctl launch --console-pty booted com.vojta.speedharness [rate]

The script plays a quiet sine and steps through normal, 1.5x, 1.5x at +3 semitones, 0.75x and back,
logging how fast the converter's callback (the decoder) was drained and how far the state's position is
from the content played. 2026-09-18: drained 1.00x, 1.50x, 1.50x, 0.75x, 1.00x; position within 12 ms.

`rate` sets the output's input side to 48 kHz while it runs, halfway through the 1.5x step, with no new
`AudioOutputUnitStart`, while the mixer stays at 44.1 kHz. The mod's format listener sees the mixer and the
output disagree and gives Spotify's own connection back (`given Spotify's own connection back`), which sets the
output's input to the mixer's 44.1 kHz again; the formats agree, and the callback takes over again. 2026-10-06:
drained 1.00x, 1.50x, 1.50x, 0.75x, 1.00x through the change. Before, the callback pulled the 44.1 kHz mixer
for the 48 kHz output, and the drain read 1.09x.

`two` runs Spotify's chain twice at once, 44.1 and 48 kHz, the way Spotify runs a chain per sample rate when a
local file has another rate than the stream before it. Each chain's drain is measured in seconds of its own
rate for each second its output played (the simulator's output stalls now and then), and each step prints
PASS or FAIL: both at 1.00x side by side; 1.5x on the chain started last only; its stop moving the 1.5x to the
other and its start bringing it back; a third unit fed by a render callback of its own (voice search's kind)
started without taking it; a silent decoder giving it up to the chain with sound within 1.5 s, and
keeping it there when the sound comes back; a disposed mixer, then a disposed running output, with nothing else
changed. 2026-10-06, iOS 27.0 simulator: all PASS. The same run on the code before this record of outputs:
the 48 kHz mixer drained 1.92x with both chains started (both outputs pulled it), 2.88x at 1.5x, and the
44.1 kHz chain not at all, then silence once the 48 kHz one stopped.

    xcrun simctl launch --console-pty <udid> com.vojta.speedharness two

Last it sets the sleep timer's gain (`SGPlayerSetGain`) to 0.25 and back to 1, and each line reads the loudest
sample the speaker unit played over the step's last second, through a notify the harness adds after the mod's:
0.05 at 1, 0.0125 at 0.25.
