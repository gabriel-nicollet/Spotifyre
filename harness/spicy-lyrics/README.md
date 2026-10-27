# Spicy Lyrics check

`./build.sh` reads made-up responses of the Spicy Lyrics API (a Syllable sync with a duet, a
backing vocal, a split word and a translation; a Line sync with a gap; a Static one) through the real
`SGSpicyLyricsResult` and checks the lines and the credit each one gets, and that a translation is
left out once the Lyrics page asks for a language. It also checks the pronunciations (from each syllable, estimated from
the line's, left out when they read the same), the translations joined from the backing groups, the
credit's links, the ♪ between a Static sync's stanzas, the key check (publishable only), the wait a
429, 503 or spent RateLimit-Remaining asks for, and the ask itself on a stubbed reply: ids that are not
base62 never sent, answers and misses kept, a rate limit skipped and counted as lost, a refused key left
alone. It runs on the Mac as a
Mac Catalyst binary, with no simulator and no network.

It does not cover the real request, the key in the Keychain, the reason a refused key shows on its
row, or the credit on the lyrics view (harness/lyrics/ with `-credit "Spicy Lyrics, ..."` shows it).
