# Updates harness

`SGUpdatePage()` and the launch notice on the simulator, running the real check against the repo's
GitHub Releases: the state rows, the changelog of every release newer than the build, the page
rebuilding itself when a check lands, and the sheet `SGWatchForUpdates()` brings up over a plain
screen. Only `Update.m`, `UpdatePage.m`, `UpdateNotice.m` and the page style are compiled; nothing of
Spotify's is needed, so the page looks as it does on the phone apart from the fonts, which Mod
Settings takes off Spotify's own list at runtime.

    ./build.sh [version]        # what the page believes it is running, 0.18.0 by default
    xcrun simctl install booted build/UpdateHarness.app
    xcrun simctl launch --console-pty booted com.vojta.updateharness [wipe] [notice] [recheck]

`wipe` clears what an earlier run stored, so it starts as a phone that has never checked does;
`notice` puts a plain screen up and watches for updates over it, the way the settings %ctor does
inside Spotify, and the sheet follows about seven seconds in -- a second run without `wipe` stays
quiet, because a release is told about once; `recheck` taps Check now five seconds in. A version behind the newest release (`0.18.0`)
shows the update and everything since; the newest one (`0.19.0`) shows "up to date" and what went
into this build; an old one (`0.17.0`) shows several releases, newest first.

`releases` checks, without the network, what a reply and a stored list leave for the build: run it
built as `1.0.0` and as `1.0.0-beta.1`. A release build keeps no beta, neither from GitHub's reply
nor from a list a beta stored, and a reply of betas only reads "up to date"; a beta keeps them. With
Include betas switched the other way, each keeps what the other would. A table of stored lists then
names the version offered with the switch on and off: beta to beta to release, a beta after a
release only with the switch on, never a version below the build's.

`versions` checks the ordering itself, including the chain 1.0.0-beta.1, 1.0.0-beta.2, 1.0.0,
1.0.1-beta.1, 1.0.1 and that no step back counts as newer.
