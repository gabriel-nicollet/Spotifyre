# Lyrics translation check

`./build.sh` checks the parts of lyrics translation that need no network: Musixmatch's community
translations matched onto a song's lines by their folded text, as copies that leave the lines kept
before untouched (`SGMusixmatchTranslatedLines`), and Gemini's reply read into one translation per line
or a reason to show (`SGGeminiTranslationsIn`): a blocked prompt, a recitation or safety stop, a line
count that does not match, the key, the limit. It runs on the Mac as a Mac Catalyst binary, with no
simulator and no network.

It does not cover the requests themselves, the lines taking the translations as they are kept
(`Shared/Lyrics/KaraokeSource.x`), or the lyrics view picking them up.
