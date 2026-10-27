# AirPods gestures harness

`SGHeadDetector.m` (Shared/HeadGestures) as the tweak compiles it, on the Mac, over head motion made up to
look like what AirPods report through `CMHeadphoneMotionManager`: 25 attitudes a second, pitch and yaw in
radians, with a little noise. Each trace says what it should fire, and the run fails when one does not.
The negatives (one nod, three nods, a glance each way, a turn, running, dancing, a gap in the samples)
matter as much as the gestures. Learning is run on a small slow nod and shake: the defaults miss them, what
was learned catches them, and a walk still fires nothing at what was learned. Learning keeps a threshold only
when the detector, set to it, fires on the recording: three nods and a double nod of 2 s learn nothing, and a
double nod with a hard settle, which the first margin reads as six swings, learns a closer threshold that fires.
Teaching (SGHeadLearnSamples) is run on five recordings the way the sheet takes them: five double nods of
different sizes teach a threshold under the smallest, which fires on each of the five while a walk fires nothing;
four double nods and three nods still teach; three and two of three nods teach nothing; five shakes of different
widths teach a shake threshold that fires on each.

    ./build.sh && build/head-gestures                 # the synthetic traces
    build/head-gestures <trace.csv> [nod] [shake]     # a recording, one "time,pitch,yaw" a line

The traces are synthetic. No recording from real AirPods has been run through it yet: one, logged as
`time,pitch,yaw` from `CMDeviceMotion.attitude`, goes through the second form.

## The hook and the page in the simulator (`sim/`)

The real `HeadGestures.x` (through Logos), its settings page, its teaching sheet and the detector, with Spotify's
player and collection platform stood in for and `CMHeadphoneMotionManager`'s start and stop taken over, so made-up
motion reaches the handler on the manager's own queue. It checks that nothing listens until the switch is on, the
pull-downs read Like and Next track and offer the nine actions, a double nod adds the playing track with Spotify's
toast, a shake skips, an episode is not saved, and then each action through the nod's pull-down sends its player
command: back and forward 15 s (forward stopping at the end), pause, next, previous, shuffle on and off, repeat
through its three states. Set to Play or pause, the gestures listen with the song paused and resume it, and stop
listening once nothing is set to it; a seek while paused reads the paused position; a shake set to Nothing sends
nothing. Try it names a double nod, a shake, a still head (Nothing) and no headphones (No motion) while the switch is
on and a song plays, and sends nothing to the player. The sheet's ring follows the head: a nod's dip takes the dot
down and lights the ticks below it, not those above or beside, a still head brings the dot back and the ticks fade,
and a swing to the left takes the dot left and lights the ticks there. The sheet asks for nods first, does not count one nod, Redo last
takes one off, stores the nod before the shakes and the shake at the end, with a song playing and nothing sent to
the player meanwhile, and swaps Cancel for Done; the smallest nod it was taught then likes the song. A second
sheet holds the motion while paused, and its Cancel after one nod keeps the stored nod and stops the motion. Forget
shows only while something is learned, and asks before it clears both.

    THEOS=$HOME/theos sim/build.sh && xcrun simctl install <udid> build/sim/HeadGesturesSim.app
    xcrun simctl launch <udid> com.vitrine.headgesturessim    # then read the [harness] lines from the log
    xcrun simctl launch <udid> com.vitrine.headgesturessim live    # no checks: page, sheet, done or live, to screenshot

`live` feeds double nods and then shakes in real time, 25 samples a second, so screenshots catch the ring mid-gesture.

The steps wait on what they check rather than on a clock (each fails after 20 s), and the sheet's recordings are
fed as they open, so the run takes about a minute and a half.

2026-10-05, iPhone 17 Pro on iOS 27.0: all 15 checks pass, three runs in a row, with the cue's tones played
through AVAudioPlayer (the harness checks the calls, not the sound). With Cancel and Forget, all 24 pass; a simulator
slow enough to hold the alert's presentation for seconds makes the timed steps fail.
Since Cancel ends learning at once and Forget shows only while something is learned: all 30 pass, three runs in a
row, on the same simulator.
2026-10-06, the same: with the actions, Try it and the teaching sheet in place of the learning alerts, all 53
pass, three runs in a row.
With the live ring in place of the progress arcs: all 59 pass, one run, on the same simulator.
