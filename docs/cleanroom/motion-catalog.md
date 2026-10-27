# Spec: Apple Music catalog lookups (`SGMotionCatalog.m`)

A functional spec for a clean-room implementation. It says what the code must do and what the
services return, as observed on 2026-10-05. It says nothing about how any other implementation is
structured. Implement it without reading spoti.pw's or Chroma's code from after commit `c790445`.

## Where it goes

`tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m`, Objective-C with ARC, iOS 16 deployment
target. It implements these functions from `AnimatedArtwork.h`:

| Function | Contract |
|---|---|
| `SGMotionNameKey(name)` | A comparison key for an artist or album name |
| `SGMotionStreamIn(master, pixels)` | The URI of the stream to download, from an HLS master playlist |
| `SGMotionWholeFileIn(media)` | The URI of the one file a media playlist's segments all come from, or nil |
| `SGMotionAlbumCover(artist, album, shape, pixels, done)` | An album's animated cover as a local file, or nil |
| `SGMotionArtistLogo(artist, pixels, done)` | An artist's logo as a `UIImage`, or nil |

It may use:

- `SGMotionFile(remote, done)` from `SGMotionStore.m`, which downloads a remote video to a local file
- `SGFlag(SGKeyMotionLowData, NO)` from `Core/SGCore.h`
- `SGLog(format, ...)` from `Core/SGCore.h`, with every line prefixed `motion: `

Every `done` block runs on the main queue, exactly once.

## Behavior

### Name keys

- Case and diacritics do not matter.
- Punctuation does not matter. "Short n’ Sweet" and "Short n' Sweet" give the same key.
- An edition in round or square brackets does not matter: "Midnights (The Til Dawn Edition)" gives the
  same key as "Midnights".
- Anything after " - " does not matter: "Espresso - Single" gives the same key as "Espresso".
- A non-string input gives an empty key.

### Artist match

Spotify names the lead artist. Apple Music may name several, for example "Xavier Omär & ELHAE".
Two artist names match when the words of one appear, in order and as whole words, inside the other.
Empty names never match.

### Album cover

1. Return nil at once when the artist or album key is empty.
2. Search the catalog for albums with the term "artist album". Ask for `editorialVideo`.
3. Use the first result whose artist matches, whose album key equals the requested album key, and
   whose `editorialVideo` has one of the entries in step 4. Editions of one album share a key, and
   only one of them may have the motion.
4. From its `editorialVideo`, take the first that exists of:
   - tall shape: `motionTallVideo3x4`, `motionDetailTall`, `motionSquareVideo1x1`, `motionDetailSquare`
   - square shape: `motionSquareVideo1x1`, `motionDetailSquare`
5. That entry's `video` is the URL of an HLS master playlist. Download it, pick a stream with
   `SGMotionStreamIn`, download that stream's media playlist, and get its file with
   `SGMotionWholeFileIn`. Resolve each relative URI against the playlist it came from.
6. Pass the file's absolute URL to `SGMotionFile` and hand its result to `done`.

Remember each answer for the rest of the launch, per shape, artist key and album key. An album with
no animated cover is remembered as having none. A failed request (network error or non-200 status)
is not remembered, so the next call asks again.

### Stream choice

Each stream in a master playlist is an `#EXT-X-STREAM-INF:` line followed by its URI line. Its
attributes include `RESOLUTION=WxH` and `CODECS="..."`.

- Take the narrowest stream at least `pixels` wide.
- If none is that wide, take the widest.
- Between streams of the same width, prefer HEVC (`CODECS` starting `hvc1` or `hev1`) over H.264.
- Return nil when there is no usable stream.

### Whole file

A media playlist may name one file for all of its segments. `#EXT-X-MAP:URI="..."` names it for the
header, and each segment's URI line names it again, with `#EXT-X-BYTERANGE` lines giving the ranges.
Return that URI when every URI in the playlist is the same, and nil otherwise.

### Artist logo

1. Return nil at once when the artist key is empty.
2. Search the catalog for artists with the artist name. Ask for `editorialArtwork`.
3. Use the first result whose name key equals the artist key.
4. Its `editorialArtwork.musicContentColorLogoTrimmed` has `url`, `width` and `height`. The URL is a
   template that ends in `{w}x{h}bb.jpg`.
5. Fill the template for `pixels` wide, the height in the logo's own aspect, and ask for `png` instead
   of `jpg`. The PNG has an alpha channel.
6. Download it and return the image.

Remember each answer, the image or none, for the rest of the launch.

## The services

### Token

The catalog needs a developer token, a JWT. Get it from Apple Music's web player:

1. GET `https://music.apple.com/us/browse`. The HTML names one script at a path like
   `/assets/index~c10ba4a68d.js`. The hash changes with each web player release.
2. GET that script. It is several megabytes, so search it off the main queue.
3. It holds several JWTs in quotes. Decode each payload (base64url). Use the one whose `iss` claim is
   `AMPWebPlay`. Its `exp` claim is the expiry in Unix seconds, about ten weeks out. It also carries
   `root_https_origin: ["apple.com"]`.

Keep the token in `NSUserDefaults` under `spotifyglass.motion.token`. Reuse it while it is valid for
more than another hour. Callers that ask while a token is being read wait for that read. When the
catalog answers 401, read the token again and retry that request once.

Requests to `music.apple.com` send a desktop Safari User-Agent.

### Catalog search

    GET https://amp-api.music.apple.com/v1/catalog/us/search
        ?term=<term>&types=<albums|artists>&limit=10&extend=<editorialVideo|editorialArtwork>
    Authorization: Bearer <token>
    Origin: https://music.apple.com

Without the Origin header the answer is 401. The token does not work on `api.music.apple.com`
for this data.

Albums answer, trimmed:

    {"results": {"albums": {"data": [{"id": "1689131527", "attributes": {
        "name": "Midnights (The Til Dawn Edition)", "artistName": "Taylor Swift",
        "editorialVideo": {
            "motionDetailSquare":   {"video": "https://mvod.itunes.apple.com/.../xxx.m3u8", "previewFrame": {...}},
            "motionDetailTall":     {"video": "...", "previewFrame": {...}},
            "motionSquareVideo1x1": {"video": "...", "previewFrame": {...}},
            "motionTallVideo3x4":   {"video": "...", "previewFrame": {...}}}}}]}}}

Albums without an animated cover have no `editorialVideo`. A search with no albums may have no
`albums` key at all.

Artists answer, trimmed:

    {"results": {"artists": {"data": [{"id": "159260351", "attributes": {
        "name": "Taylor Swift",
        "editorialArtwork": {"musicContentColorLogoTrimmed": {
            "url": "https://is1-ssl.mzstatic.com/image/thumb/.../{w}x{h}bb.jpg",
            "width": 4826, "height": 1264, "bgColor": "000000"}}}}]}}}

Any field may be missing or of another type. Check each type before use.

### Playlists

A master playlist (abridged):

    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=2114513,BANDWIDTH=2251133,CODECS="avc1.64001f",FRAME-RATE=30.000,RESOLUTION=768x768
    P544849304_..._768x768.m3u8
    #EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1674892,BANDWIDTH=1936611,CODECS="hvc1.2.20000000.L123.B0",FRAME-RATE=30.000,RESOLUTION=768x768
    ...

Square covers run from 360x360 to 2160x2160, in both H.264 and HEVC.

A media playlist:

    #EXTM3U
    #EXT-X-TARGETDURATION:3
    #EXT-X-PLAYLIST-TYPE:VOD
    #EXT-X-MAP:URI="P544849304_Anull_video_gr240_sdr_768x768-.mp4",BYTERANGE="896@0"
    #EXTINF:2.83333,
    #EXT-X-BYTERANGE:622900@896
    P544849304_Anull_video_gr240_sdr_768x768-.mp4
    #EXTINF:2.83333,
    #EXT-X-BYTERANGE:717722@623796
    P544849304_Anull_video_gr240_sdr_768x768-.mp4

That file, downloaded whole, is a playable fragmented MP4 (about 6 MB at 768x768).

### Low Data Mode

Every request sets `allowsConstrainedNetworkAccess` to `SGFlag(SGKeyMotionLowData, NO)`.
