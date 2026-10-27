# Clean shared links checks

Two checks for `Shared/Privacy/`'s Clean shared links.

    ./build.sh && build/clean-links-check

runs `CleanLinks.m` on the Mac: si, nd, pt, context and utm_* taken off open.spotify.com links, t and every
other parameter kept in order, the intl-xx/ path and the fragment kept, other hosts, spotify.link and spotify:
URIs left alone, and links found in a sentence without the full stop or bracket after them.

    THEOS=$HOME/theos SIM=<udid> ./build-sim.sh

builds `CleanLinks.x` with logos.pl's internal generator and runs `sim/main.m` in that simulator with
`simctl spawn`: each pasteboard setter on a pasteboard of its own (never the general one), a share sheet's
string and URL items, a provider's `-item`, a subclass's, an item source's answer, and the switch turned off.

Both print ok or FAIL per line and exit with the number of failures. What neither covers: which of these
Spotify's own Copy link and share sheet take on a phone.
