# HTTP addon compatibility research

Follow-up to [Lossless sources and automatic upgrades](lossless-sources.md), checked 2026-10-08 against
the links and September announcements supplied by the user. **No provider is validated in Vitrine.**
These are provider candidates for the same background-upgrade coordinator, not separate player designs.
Server-side JavaScript is compatible with the decision to execute no downloaded provider code in the app.
The [playback investigation](lossless-playback.md) records Vitrine's native decoder and integration
limits. Provider range support alone does not prove progressive decoding or timestamp seeking.
The [audio prototype](lossless-prototype.md) does not yet connect to any of these providers.

## Provider candidates

| Candidate | Evidence | Implication |
| --- | --- | --- |
| [Plex/Jellyfin addon](https://github.com/rairulyle/bitchord-selfhosted-addon) | Inspected source at `2a20c3ac76327f56a4189df66c79292462e154f3`: manifest/search/stream endpoints and original-file proxy with range forwarding | Best first controlled integration target when a test library is available; each configured server is a separate source |
| [Telegram Music Addon](https://github.com/Imnotshashwat/Telegram-Music-Addon) | Inspected source at `cb336d2cce2b77676a450f11587edf42985cc17a`: JSON endpoints, ISRC resolution and range-aware audio route | Second candidate; requires the user's own channel and hosted server. WebDAV support does not require Vitrine to implement WebDAV |
| Deezer addon | User supplied `https://deezer.nom.deno.net/` and an announcement describing an account/free-pool requirement; the browser tool could not access the page | Current authentication, returned formats, availability and Vitrine access remain unverified |
| Unified addon | User supplied several setup URLs and announcements about Tidal account/pool requirements, CJK matching fixes, Atmos and client-version restrictions; the browser tool could not inspect the pages | Do not infer the current host, access requirements, matching quality or third-party-client eligibility from old announcements |
| NullBeat | User supplied an announcement naming paid TorBox access, 5 requests/minute and 60 TorBox caches/hour | Treat these as announced limits for this provider, not verified current limits or global addon defaults; operator permission for BitChord does not establish permission for Vitrine |
| [Amazon Music API](https://github.com/itsmeadarsh2008/amazon-music-api), [HiFi API](https://github.com/binimum/hifi-api) | Public repositories describe backend APIs, not proof of the BitChord manifest/search/stream contract | Backend building blocks only; need a separately maintained adapter and supported access. They are not paste-and-play addons |

The Unified locations supplied were `https://addon.unified.dpdns.org/pages/setup.html`,
`https://unified-addon.netlify.app/pages/setup.html`, `https://unified-addon.vercel.app/`, and
`https://unified.dpdns.org/`. Keep these as research leads only. Failed access through the browser tool
does not establish that a service is down. No credentials, donated accounts, stream requests or media
downloads were used in this research.

## Verified implementation details

The Plex/Jellyfin addon's
[routes](https://github.com/rairulyle/bitchord-selfhosted-addon/blob/2a20c3ac76327f56a4189df66c79292462e154f3/internal/server/server.go)
are `/{slug}/{secret}/manifest.json`, `/search`, `/stream/{id}`, `/file/{id}` and `/art/{id}`, all under
that source prefix. Its
[mapper](https://github.com/rairulyle/bitchord-selfhosted-addon/blob/2a20c3ac76327f56a4189df66c79292462e154f3/internal/server/mappers.go)
returns `/file/{id}` with codec, container, `manifest: "none"`, rate/depth and bitrate. Its
[proxy](https://github.com/rairulyle/bitchord-selfhosted-addon/blob/2a20c3ac76327f56a4189df66c79292462e154f3/internal/server/proxy.go)
forwards `Range`/`If-Range`, relevant response headers, and 200/206/416 statuses. Media-server credentials
are handled server-side; the source URL itself grants access and must be treated as a credential.
Its search/stream handlers serve the original file rather than negotiating a lower-quality transcode.
The reviewed mapper does not return ISRC, so strict metadata matching is still needed.

Telegram's pinned
[server](https://github.com/Imnotshashwat/Telegram-Music-Addon/blob/cb336d2cce2b77676a450f11587edf42985cc17a/index.js)
declares `search`, `stream`, `isrc`; search rows include direct `streamURL` values. It implements
`/resolve-isrc?isrc=…`, `/stream/{id}` and `/audio/{id}`. The audio handler parses byte ranges and emits
206/416; HEAD is handled too. Secret-prefix authentication is supported, but the server also permits
unprotected operation if no secret is configured. Do not assume a particular deployment is private.
Its stream handler reports the stored file and logs the requested quality; that does not establish
conversion to the requested tier. It also fills missing rate/depth with defaults. Decoder verification
must distinguish provider hints from measured format. These are static observations, not live playback
or a security audit of either server.

## Additions to the client design

The [Eclipse guide](https://eclipsemusic.app/docs) shares the basic JSON contract and documents optional
`isrc` capability: `/resolve-isrc?isrc=…` returns `trackId` (or `id`), then the client resolves the stream;
404 or a null ID means no match. It also describes `expiresAt` as a Unix timestamp and settings passed
as query parameters, with `perNetwork` selecting the active network's value. These extensions can fit
the Vitrine client without embedding provider code. Retain Vitrine's duration/edition validation even
after an ISRC lookup; do not inherit a provider's certainty without checking the actual media.

1. **Import the generated addon link.** A setup page, GitHub repository and JSON index are distinct
   inputs. Open setup in the external browser; the user pastes its generated root/manifest URL. Do not
   turn an HTML setup URL into a guessed API root. Preserve path secrets and server slugs, including
   case and encoding, when appending endpoints. Store secret-bearing URLs in Keychain, with a separate
   opaque source ID for preferences; redact them from diagnostics and settings exports.
2. **Identify the client honestly.** Use Vitrine's own user agent/version. A BitChord-only or
   version-restricted service needs operator-supported Vitrine access; do not masquerade as BitChord
   to pass its checks. Expose a useful unsupported-client reason and leave Spotify playing.
3. **Enforce a budget per provider.** Share manifest and lookup work; avoid automatic multi-query,
   whole-queue or playlist prefetch. A 5-request/minute service may spend several requests on one
   candidate. Budget health checks, retries and preparation too; a stream-resolution call can trigger
   backend caching before audio is requested. Represent request and cache quotas separately. If an
   announced limit's scope is uncertain, use a conservative configured budget until documented.
   Honor `Retry-After`; a cooldown leaves current playback alone. Do not probe these services at scale.
4. **Enforce ceilings locally.** Original-file providers may ignore a requested lower tier. Reject
   above-ceiling candidates before full buffering and retain Spotify. For the initial lossless-only
   upgrade, a cellular lossy ceiling can simply suppress external preparation. `atmos: "auto"` is a
   provider default in Telegram's manifest: explicitly request stereo where supported, then validate
   the response. Atmos availability does not establish lossless audio.
5. **Test seeking against the served bytes.** Add fixtures for path-secret prefixes, direct search
   URLs, exact/missing ISRC, absent `encrypted`, unknown rate/depth, ignored quality/Atmos preferences,
   valid and invalid ranges, 416, servers that ignore Range and return 200, revoked source links,
   incorrect Content-Range, expiry and cooldown. Byte-range support enables efficient fetching but
   does not itself prove time-accurate seeking or aligned playback. Do not make an unconditional HEAD
   request to a possibly single-use media URL.

Start with fixtures modeled on these source-verified contracts, then a controlled personal-library
server. Hosted-provider compatibility remains a separate check, with no bundled source credentials or
default hosted endpoint. The unresolved Spotify handoff described in the main design still applies.
