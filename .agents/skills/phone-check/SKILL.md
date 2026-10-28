---
name: phone-check
description: >
  Install a Vitrine build on the paired iPhone and check it there: relaunch, drive it with the phone driver,
  take screenshots, read the view tree and stream the log. Use whenever a change has to be seen or measured
  on the phone, or the user reports something on the phone that needs evidence.
---

# Checking a build on the phone

Values that belong to one person's phone live in `.phone.env` at the repo root (gitignored; copy
`.phone.env.example`). Load them first:

    set -a; . ./.phone.env; set +a    # PHONE_UDID, PHONE_HOST, APP_BUNDLE

## Install

- `make quick` rebuilds only the tweak and installs it in seconds. It needs a full build with FLEX first:
  `scripts/pipeline.sh ipa/Spotify-9.1.78.ipa`, then `make quick`.
- The full build fails inside the sandbox at the App Intents step ("Exception during writing compiled
  data"); run it outside the sandbox.
- `make quick` refuses when the extension, a plist or an icon changed since the full build. Run the full
  build again.
- An install quits the app. Relaunch it and wait for the driver:

      xcrun devicectl device process launch --terminate-existing --device "$PHONE_UDID" "$APP_BUNDLE"
      for i in $(seq 1 15); do sleep 2; scripts/phone.py state >/dev/null 2>&1 && break; done

- After a version change, What's New covers the screen. Close it with `scripts/phone.py tap --text Continue`.
- A launch on a locked phone fails with `BSErrorCodeDescription = Locked`, and every driver call after it
  says the app did not answer. That is not a crash. Ask the user to unlock the phone.

## Drive

`scripts/phone.py` (its header lists every command) talks to the driver in FLEX builds. Over Wi-Fi it
needs `PHONE_HOST` and the token the app logs at launch, which it reads from the log file below.

- Check `scripts/phone.py state` before anything else. Its `top` and `presented` say what is on screen.
- `settings.page` finds only rows on screen. Scroll first. After two failed lookups, stop and ask the
  user to open the page instead of probing further.
- A swipe that only sets `contentOffset` (`scroll`) does not trigger scroll-driven behavior like the tab
  bar's minimize. Use `swipe` with a duration for that.
- There is no previous-track command. `scripts/phone.py seek 0`, then
  `scripts/phone.py tap --id SPTNowPlayingPreviousTrackButton` with the player open.
- `ls` in this shell is eza, which takes other flags (`ls -t` fails). Use `/bin/ls`.
- `seek --by -15` moves relative to where the song plays (Spotify's `relative:` 2; 1 counts from the end and
  skips past it into the next song).
- The glass tab bar is not the driver's: `tab` may fail in the redesign. Tap the glass bar's icon by position
  from a screenshot, after a scroll to the top so the bar is not minimized.
- Spotify's own lyrics switch (the preview under the cover) is the track ⋯ menu's "Lyrics • On/Off", under More
  in the redesign's menu.
- `state` failing with "Connection reset" while the app runs means the phone is locked or Spotify is not in
  front; it is not a broken build.
- Read a setting before a test changes it and put it back after: Vitrine prefs, the tab layout, shuffle (three
  states on a playlist page), repeat, saved songs, Spotify's lyrics switch.

## Simulator

`scripts/sim-build.sh` runs a Spotify IPA with the tweak in the iOS Simulator, for a second Spotify version and for
layout checks the phone is not needed for. Run it from a separate worktree: it writes the flag table for its IPA's
version, which would break the phone's `make quick` of another version. `SG_DRIVER=1` builds the driver on port
8086: `PHONE_PORT=8086 scripts/phone.py …`, and `xcrun simctl io <udid> screenshot` for screenshots. Prefs are read
at launch, so `simctl terminate` and `launch` after a `pref`. In Xcode 27 the window is
`Xcode.app/Contents/Applications/DeviceHub.app`. It cannot show the volume slider, haptics, the Live Activity or the
Neural Engine; those stay checks for the phone.

## Screenshots

The driver's `screenshot` can come back blank. Take them through the tunnel instead, which needs
`sudo pymobiledevice3 remote tunneld` running (the user starts it):

    uvx pymobiledevice3 developer dvt screenshot --tunnel "$PHONE_UDID" "$TMPDIR/shot.png"
    uv run -q --no-project --with pillow python -c "from PIL import Image; im=Image.open('$TMPDIR/shot.png'); w,h=im.size; im.crop((0,int(h*.8),w,h)).save('$TMPDIR/crop.png')"

Read the cropped file with the Read tool. A full-height image is hard to judge; crop to the part in question.

Measure from the full-resolution PNG (3 px to the point on this phone) when the question is "a little off":

- Alignment: the first and last rows in a column band that have pixels brighter than a threshold give an
  element's vertical center. The volume glyphs sat at y 2271 against the track's 2264.5, 2 pt low.
- Blur: the mean absolute difference between pixels 3 px apart, across a band of rows. The redesigned
  player's header row read 0.72 blurred and about 5 sharp.

Privacy: a tunnel screenshot captures whatever is on screen. Check `scripts/phone.py state` first, and do
not take one while the user is in another app.

## Log

- `scripts/phone.py log` holds only the latest lines of the current launch. A background screen dump
  floods it, and every relaunch starts it over. For anything across a relaunch or a lock, stream the log
  instead, in the background:

      uvx pymobiledevice3 syslog live --tunnel "$PHONE_UDID" -m '[spotifyglass]' >> /tmp/claude-501/device.log 2>&1

  `scripts/phone.py` reads the Wi-Fi token from that file. `idevicesyslog -n` often cannot find the phone
  over Wi-Fi.
- Grep the file for the feature's log prefix (`lock lyrics:`, `sing:`, `redesign home:`). When a feature
  says nothing about why it did nothing, add one log line per track or per change and rebuild, rather than
  guessing.

## Crashes

When the driver stops answering and the app's process is gone (`xcrun devicectl device info processes
--device "$PHONE_UDID" | grep Spotify.app`), copy the crash reports off the phone, outside the sandbox:

    mkdir -p out/rep/crash && idevicecrashreport -k -f Spotify out/rep/crash

Every copied file gets the same modification time, so `ls -t` does not find the newest. Pick it by the
timestamp in its name (`Spotify-2026-10-10-171127.ips`), then print the faulting thread:

    python3 - out/rep/crash/Spotify-<stamp>.ips <<'EOF'
    import json, sys
    d = json.loads(open(sys.argv[1]).read().split('\n', 1)[1])
    print(d['captureTime'], d['exception'])
    images = d['usedImages']
    for f in d['threads'][d['faultingThread']]['frames'][:20]:
        print(images[f['imageIndex']].get('name'), f.get('symbol'), hex(f['imageOffset']))
    EOF

Frames in `spotifyglass.dylib` carry symbols. Frames in `Spotify` carry only an offset: add `0x100000000` and
find the method with the nearest start address at or below it in that version's `di-objc-<ver>.txt`
(`spotify-version-check`). A 9.1.90 crash at `0x105DBA98C` sat in `internalNavigateToURI:…`, which starts at
`0x105DBA91C`.

## View tree

`scripts/phone.py tree` prints the visible screen's tree as indented text with frames, `hidden`, `a=` (alpha)
and `clips`. To see a view's ancestors, walk up by indentation:

    n=$(grep -n 'SGRBarText' tree.txt | head -1 | cut -d: -f1)
    awk -v n=$n 'NR<=n {match($0,/^ */); d[NR]=RLENGTH; l[NR]=$0} END{w=d[n]; for(i=n;i>0;i--) if(i==n||d[i]<w){print l[i]; w=d[i]}}' tree.txt

Capture the tree in the exact state being judged. A tree taken after another gesture describes a different
layout.

## Before blaming the code

- Spotify playing on another device through Connect (a laptop or speaker glyph on the bar) leaves the phone
  a remote. The lock screen's full-screen artwork and anything that needs local audio do nothing then.
- `sing: the iPhone is hot` means Karaoke holds back on purpose.
- Karaoke rests (0 windows, its status "As sung") when the vocals are at 1 and Spatial voice is off: nothing to
  change. Lower `spotifyglass.sing.level` for a test.
- A label `find` reports as shown can sit in a card collapsed to 0 pt (the redesign drops every card under the
  player). Check the cell's height in the tree before calling it visible.
- FLEX's toolbar can cover the top of the screen. The user closes it with its ✕.
- A log line on a path that runs per event, per packet or per tick floods the in-app log (it pushed every
  other line out at about fifty a second) and costs battery for every user. Log the first few of a launch
  and a count once a minute, and take debug lines out or cap them before committing.
- Say what the phone showed and what it did not. A build that compiled is not a check on the phone.
