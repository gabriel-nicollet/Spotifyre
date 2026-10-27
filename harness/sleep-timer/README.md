# Sleep timer harness

`SleepTimer.m` (Shared/Player) as the tweak compiles it, on the Mac, over a player stood in for (`stub/` stands
in for the three UIKit headers it imports, `main.m` answers their calls). It checks the fade's curve (1 until
the last minute, 30 dB down halfway, 60 dB at the end, falling every second), which track ends the album
(tracks queued by hand and autoplay's, by provider or by the is_queued and autoplay.is_autoplay keys, don't
count; repeating, the next track having played already does), and the timer in real time: a 2 s timer starts
faded, pauses at its end and gives the gain back a second later; 15 minutes more and Cancel bring the gain
back at once; End of track pauses half a second before the end, or at once on the next track; End of album
plays past a track with more of the album to come, fades and pauses on the last one, and pauses at once when
autoplay or another album or playlist is playing; a timer up while paused sends no pause. The Fade out choice (`SGInt`,
answered by `main.m`): each length's curve, Off at full volume all the way, none picked and one out of range
read as 30 s; a change applies to a timer already running; at the end of the track or the album the fade
spans a track shorter than it, from its start; a time fades over the last seconds before its end.

`SpotifySleepTimer.m` too, Spotify's own timer as the player's state reports it (`main.m` gives the state a
`sleepTimer` and calls the observer the file adds at load): a time fades by the choice, a later time and a
cancel bring the gain back at once; at its time, or dropped from the state at its end, the gain stays down,
with no pause from the mod, until Spotify's pause and comes back a second after it; the expired timer still
reported is not faded again; End of track fades over the track's last seconds, takes a skip mid track as the
new track's end, and holds the gain down into the next track until the pause; Off, a choice picked while it
runs, Spotify's own Fade out forced on and the mod's own timer running each leave or bring the gain right.

    ./build.sh && build/sleep-timer

2026-10-06: all held (77 checks). The gain itself is checked on Spotify's audio chain in harness/speed/.
