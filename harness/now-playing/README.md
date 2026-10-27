# Now playing harness

The two hooks of `MPNowPlayingInfoCenter`'s setter, `Shared/Player/NowPlayingExtras.x` and
`Shared/LockScreenLyrics/LockScreenLyrics.x`, through Logos and nested as in the tweak, run on the Mac as a
Mac Catalyst tool. The system's setter and getter are replaced under both, so the check reads exactly what
the system was given. Karaoke is a stub with two lines of lyrics.

It checks that:

- once lock screen lyrics let a line go, the info sent with the artist back carries the elapsed time moved
  on, not the one Spotify reported a while ago, and a later resend of an extra is not pulled back by it
- an extra cleared while the info still carries it (the next track has the same title, or Spotify copied
  it onto its next info) is taken off at once, another owner's extra stays, and nothing is sent when there
  is nothing to take off

It runs once with lock screen lyrics off and once with it on (`LSL=1`).

    THEOS=$HOME/theos ./build.sh

`SRC=<checkout>/tweak/Sources` builds another checkout instead, to see a bug before its fix.
