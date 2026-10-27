# Local files check

`./build.sh` checks `Shared/LocalFiles/LocalFiles.m` as the tweak compiles it: a `spotify:local:` URI
read back into its names (form decoded, a `%3A` in a title too), an edit laid over them, and the lyrics
key each edit gives. A rename gets a new key (`<uri>#<number>`), the same names saved again or a new
cover with them keep it, a cover alone on an unedited file leaves the bare URI, and names back to the
file's own go back to it. It also checks a stored cover's `spotify:localfileimage:` address and its way
back, that no other path comes back through it, and that a replaced or dropped cover's file is removed.

It runs on the Mac as a Mac Catalyst binary with `CFFIXED_USER_HOME` set to `build/home`, so its
defaults and its covers never reach the Mac's own.

It then builds `lrc.m` against `LocalLyrics.m` and the engine's line timing: an `.lrc` import (empty,
over 1 MB and tagless files refused, UTF-16 kept as UTF-8, a taken name numbered), the stamps read
(several on a line, every fraction form, `[offset:]`, untimed text), a file linked to a local file through
a rename's key and gone with a delete, and the match by title and artist, folded, with an
"Artist - Title" name's sides worked out from the track.

It does not cover the hooks in `LocalFileInfo.x`, the lyrics engine asking for the new key
(`Shared/Lyrics/KaraokeSource.x`) or the Imported LRC files page.

## Edit info in the simulator

`sim/build-sim.sh <udid>` builds `EditInfoMenu.x` and `LocalFiles.m` as the tweak compiles them into an
app with a mock of Spotify's context menu sheet over a player that plays a local file, runs it, and saves
a screenshot at each step into `build/sim/shots/`. The script taps Edit info, which closes the menu and
brings up the editor sheet. Then it types a name and picks a cover (neither is stored before Save),
saves, opens the editor again, restores the file's info and saves, and last tries to swipe away
unsaved changes, which must ask first. Each step logs `PASS` or `FAIL`. `large` runs it once at the
largest accessibility text size, where each label goes above its field, and sets the size back.

    THEOS=$HOME/theos sim/build-sim.sh <udid> [large]

It does not cover the pickers themselves, the keyboard over the sheet, or Spotify's own menu closing.

## The lyrics pages in the simulator

`lyrics/build.sh <udid>` builds the native look's lyrics page for a local file
(`Native/LocalFiles/LocalLyricsPage.m`) with `LocalLyrics.m` as the tweak compiles them, over a stand-in
player whose clock runs at four times the song's speed. It imports and links an `.lrc` file, opens the
page, checks that every line shows and that the line being sung is the one lit, then moves to a track with
no file and checks that the lines go. `settings` as the second argument shows the Imported LRC files page
instead. Screenshots go into `build/lyrics/shots/`.

    lyrics/build.sh <udid> [settings]

It does not cover the button on Spotify's footer, Files, or a swipe to delete.
