# Lossless sources and automatic upgrades

Research and proposed implementation, 2026-10-08. **End-to-end support is not implemented.** The target is BitChord's
“Start instantly. Land on lossless” behavior: begin playback without waiting for a lossless lookup,
prepare a better rendition in the background, and switch at the current position when it is ready.
Keep separate Wi-Fi and cellular quality ceilings. The user's direction is to avoid downloaded
JavaScript in the app; use HTTP/JSON sources.

The [HTTP addon compatibility follow-up](lossless-addons.md) covers the user-supplied Plex/Jellyfin,
Telegram, Deezer, Unified and NullBeat candidates, Eclipse's optional ISRC contract, secret-bearing setup
links, per-provider quotas and client-access restrictions. Read it alongside this design.
The [Vitrine playback investigation](lossless-playback.md) adds binary evidence, the exact pre-Sing
integration point and measured native decoder limits. Its [harness](../harness/lossless/README.md)
proves local file decoding on one simulator runtime, not a working Spotify handoff.
The [native prototype](lossless-prototype.md) adds an inactive pre-Sing source selector and bounded
complete-file decoder. Its AudioUnit harness now checks replacement and lifecycle fallback; live
Spotify anchoring, providers and automatic upgrades remain to be implemented and verified.

## What upstream actually does

Source inspected at BitChord [`2c599a6`](https://github.com/kushagrasinghx/BitChord/tree/2c599a6cd7a195227a11dab5769f88da8fd08194)
and Monochrome [`eb602ad`](https://github.com/monochrome-music/monochrome/tree/eb602ad4f8f74e0307f29906fc78a32f08a34f87).
These are source observations, not measurements of a running app or proof that a provider serves Vitrine.

| Mechanism | What runs on the client | Relevance to Vitrine |
| --- | --- | --- |
| BitChord JavaScript modules | Fetch a JSON index, download JavaScript, execute it in QuickJS | Do not embed this mechanism |
| BitChord HTTP addons | Read JSON from manifest, search and stream endpoints | Recommended provider contract |
| BitChord automatic upgrade | Match another recording, prepare its audio, replace the current rendition while preserving position | Desired playback behavior, independent of the provider contract |
| Monochrome | Web client with its own catalogue/stream APIs and browser playback | Backend-adapter reference; not a BitChord module protocol |

BitChord's [module host](https://github.com/kushagrasinghx/BitChord/tree/2c599a6cd7a195227a11dab5769f88da8fd08194/app/src/main/java/com/music/bitchord/data/sources/module)
reads arbitrary `category:*` arrays, excluding artwork/testing, and deduplicates module IDs. A descriptor
supplies `id`, `name`, `download`, and capability tags (`tags` or `labels`). Relative downloads resolve
against the index location. The downloaded code exports `searchTracks(query, limit, context)` and
`getTrackStreamUrl(id, quality, context)`; settings use `context.settings.<key>.value`. Search returns
`tracks`; resolution returns `streamUrl` plus track format metadata. QuickJS receives fetch and timer
bridges and polyfills. This executes third-party code, including initialization code, rather than
merely reading configuration. The current registry removes its retired built-in module but preserves
user-added module sources. A known working module index was not supplied or tested here.

BitChord's [HTTP addon guide](https://bitchord.kushagrasingh.in/docs) describes a separate JSON protocol.
Its [implementation](https://github.com/kushagrasinghx/BitChord/tree/2c599a6cd7a195227a11dab5769f88da8fd08194/app/src/main/java/com/music/bitchord/data/sources/addon)
confirms that downloaded JavaScript is unnecessary for search, resolution, quality selection or upgrades.

The [resolver](https://github.com/kushagrasinghx/BitChord/blob/2c599a6cd7a195227a11dab5769f88da8fd08194/app/src/main/java/com/music/bitchord/data/sources/SourceResolver.kt)
uses the current connection's quality ceiling. The
[matcher](https://github.com/kushagrasinghx/BitChord/blob/2c599a6cd7a195227a11dab5769f88da8fd08194/shared/src/jvmSharedMain/kotlin/com/music/bitchord/data/sources/TrackMatcher.kt)
compares title, recording/version markers, credited artists, duration and edition metadata. A search
result is a candidate, not sufficient reason to replace the playing recording.

[QualityUpgrade](https://github.com/kushagrasinghx/BitChord/blob/2c599a6cd7a195227a11dab5769f88da8fd08194/app/src/main/java/com/music/bitchord/playback/QualityUpgrade.kt)
tracks background candidates. In
[PlaybackService](https://github.com/kushagrasinghx/BitChord/blob/2c599a6cd7a195227a11dab5769f88da8fd08194/app/src/main/java/com/music/bitchord/playback/PlaybackService.kt),
`swapIn` first auditions/buffers the replacement, rechecks the current item and remaining duration,
avoids an active crossfade, then replaces the media item with a distinct rendition URI, seeks to the
freshly read position, prepares playback and watches for failure. This is possible because BitChord
owns its player. Its source comments acknowledge a playback break: the marketing description is not
evidence of a gapless or sample-aligned transition, and its latency claims are not Vitrine measurements.

Monochrome's current [`getStreamUrl`](https://github.com/monochrome-music/monochrome/blob/eb602ad4f8f74e0307f29906fc78a32f08a34f87/js/api.js)
uses [`tracks-api.js`](https://github.com/monochrome-music/monochrome/blob/eb602ad4f8f74e0307f29906fc78a32f08a34f87/js/tracks-api.js)
outside developer mode. That client searches `/search/tracks?q=…&limit=…`, matches external catalogue
metadata, and constructs `/track/{id}` on its configured service. It labels that path FLAC; its `quality`
argument is recorded as requested quality but is not sent by that URL builder. Do not treat this as
proof of decoded quality or enforcement of a cellular ceiling. Developer mode uses a configured HiFi
endpoint and `/trackManifests/`; other code handles base64 manifests, direct URLs and DASH/HLS through
browser playback. Do not assume all those older/alternate paths are today's default resolver.

Monochrome's [README](https://github.com/monochrome-music/monochrome/blob/eb602ad4f8f74e0307f29906fc78a32f08a34f87/README.md)
also warns about restrictions on its hosted API. Its frontend being public does not establish a stable
third-party service contract. Prefer a user-configured addon or separately hosted adapter with supported
backend access. No provider addresses, service credentials or executable modules should ship as defaults.
BitChord's root license is GPL-3.0 and Monochrome's is Apache-2.0; preserve applicable notices if code is
later reused. This research change copies neither implementation into Vitrine.

## Proposed HTTP compatibility scope

The following is a proposed Vitrine subset, not a claim of complete BitChord compatibility:

| Request | Response and handling |
| --- | --- |
| `GET /manifest.json` | Require a nonempty `id`; read name, version, resources, settings defaults/options and policy switches. Preserve any base-path prefix. Reject a module index with an explanation; never follow its JavaScript downloads. |
| `GET /search?q=…&quality=…` | Read `tracks` with provider IDs, title, artist, album, duration in seconds and format hints. Ignore unknown fields. Validate types, sizes and finite positive durations. |
| `GET /stream/{encoded-id}?quality=…` | Read `url`, codec, container, manifest transport, encryption and audio-format hints. A `404` is a miss; an empty URL or JSON error is not playable. |
| `GET /resolve-isrc?isrc=…` (optional) | For a source declaring `isrc`, accept `trackId` or `id`, then resolve and validate the media; 404/null means no match. This is an Eclipse extension also implemented by the inspected Telegram addon. |

Quality tiers are `LOSSLESS`, `HIGH`, `LOW`, mapped to a manifest's declared option values when present.
Search rows can carry `streamURL`, allowing resolution to skip `/stream`. Support that optimization only
through the same URL, policy and media validation as a resolved stream. BitChord accepts aliases such as
`fileCodec`, `containerFormat`, `mediaType`, and `format: "dash"`; normalize these explicitly and reject
conflicting transport declarations. `atmos` is separate from lossless quality; immersive playback is
outside the first implementation, so decline immersive renditions and request a supported stereo copy.

Persist `allowDownloads` (default allowed) and `checkValidLossless` (default off). Downloads are outside
the first implementation regardless of that permission. The output gate is learned on the first
manifest request; afterward apply it before health checks, searches, resolution and media requests,
including requests for previously queued results. Unknown routes do not qualify. Define and device-test
an iOS route policy; do not copy Android's Bluetooth codec list. BitChord deliberately includes some
lossy Bluetooth codecs in this gate, so its meaning is not proof of bit-perfect output.

Start with direct, unencrypted FLAC/ALAC assets whose exact container and seeking behavior pass the
iOS harness. HLS is a later compatibility test; DASH is unsupported until a separate transport path or
server-side remux is implemented and tested. Do not send an MPD to a direct-file decoder, silently
transcode lossless to AAC, accept DRM payloads, or claim support from a filename extension. A hosted
adapter can translate a Monochrome/backend API or run a module outside the phone and expose the JSON
contract; operating and trusting that adapter remains a separate concern.

Use asynchronous asset inspection and audio format descriptions to establish what the native decoder
can read; Apple's [loading-media guidance](https://developer.apple.com/documentation/avfoundation/loading-media-data-asynchronously)
documents that inspection. Actual decode, seek and handoff tests remain necessary for each container,
transport and supported iOS version.

## What Vitrine already has, and what is missing

| Existing code | Can reuse | Does not establish |
| --- | --- | --- |
| `Shared/Player/PlayerState.{h,x}` | Main-thread track/state observation, current state | Observers do not report every position change; no external stream setter |
| `Headers/SPTPlayer.h` | Pause, resume, seek, queue commands and position/duration | A verified API to load a provider URL into Spotify's player |
| `Shared/Haptics/SystemMusicHaptics.x`, `SGHapticTrack.h` | `SGSpotifyISRC` recording lookup | Provider access or permission to send Spotify's request headers elsewhere |
| `Shared/Player/SpeedPitch.{h,x}` | Music-output tracking and a PCM stage seam | Encoded FLAC decoding, sample-rate preservation or a complete replacement clock |
| `Shared/Sing/Sing.x` | Existing consumer of `SGPlayerSetStage` | A second independent stage slot; registering another would replace Sing's stage |
| `Shared/Lyrics/KaraokeSource.x` | Lyrics use Spotify's position and seek commands | Automatic synchronization with an independent player |
| `Shared/LocalFiles/` | Metadata/cover edits and lyrics for files Spotify already plays | Importing an arbitrary URL as a playable Spotify track |
| `Redesigned/Kit/SGRDownload.m` | Mirrors Spotify's download controls/state | An external-audio cache or downloader |
| `Shared/AdBlock/Premium.m` | Existing product-state behavior | Lossless/offline server entitlement; an external source is a separate audio path |

The resolver and shared settings belong under a proposed `Shared/Lossless/`, with keys beginning
`spotifyglass.lossless.` and no look gate. `App/Pages.m` composes the settings entry. Each look owns any
player badge/menu presentation. Preserve `Core <- Settings <- Shared <- Native | Redesigned <- App`.
Reuse the state observer instead of adding another feature-specific player-state hook. If recording
identity helpers move out of Haptics, preserve existing lyrics and haptics callers.

## Playback design to prove

There is no verified Spotify URL-substitution hook in the reviewed code. Do not invent one or patch
Spotify's entitlement/quality responses to pretend this feature exists. Investigate three paths:

1. **Spotify source handoff:** best integration if a real stream-source boundary can be demonstrated
   against the supported binary and on device. It is presently unproven.
2. **Decoded PCM substitution:** use a worker-fed bounded buffer before the existing processing chain.
   This offers reuse of speed/pitch, effects and haptics, but requires a composable stage with Sing,
   explicit sample-rate conversion, render-safe ownership, and synchronized seek/clock/EOF handling.
   Continuing to pull Spotify to advance its clock would still consume Spotify's stream and bandwidth.
3. **Independent native player:** useful for proving provider decoding first; production use requires
   routing all controls, queue progression, lock screen, interruptions and clocks through one playback
   owner. Merely pausing Spotify and starting another player leaves Spotify's state and lyrics behind.

Prove the playback seam using a known recording and a controlled alternate file before implementing
automatic replacement. Keep the feature off until one path passes the device checks below. Do not label
any of these paths implemented based on a parser test or successful URL lookup.
Standalone native file decoding now has a simulator baseline; see the playback investigation. The next
experiment is a prepared-file PCM source selector before Sing, alongside bounded investigation of
Spotify's external-source path. Preserve Sing's stage slot. An independent production player has the
largest control/state scope. Remote `AVAssetReader` and complete local files are not interchangeable:
the former refused the tested HTTP media, and incremental paths have separate container/EOF limits.

The automatic-upgrade coordinator should have explicit states:

`Spotify playing + resolving -> candidate matched -> preparing -> ready -> switching -> external playing`

Before switching, any miss, timeout, rejection or cancellation leaves Spotify playing. After switching,
a media failure enters recovery: prepare Spotify at the current audible position, transfer ownership
once ready, and clear external state. If recovery cannot play, surface the actual error. Never leave a
permanent mute or two audible players. A skip or source removal invalidates all prior work.

- Start Spotify immediately. Provider lookup must never delay its normal start. A validated cached
  rendition can participate in an eventual startup race, once the playback seam supports it; a quick
  metadata response alone is not ready audio. Keep one owner of playback commands and one audible path.
- Match the recording before buffering. Prefer matching ISRCs when both sides provide them, then verify
  duration and edition; reject conflicting ISRCs. The baseline addon contract does not promise ISRCs.
  Otherwise require strong title, artists, album/version and duration agreement. Unknown or ambiguous
  matches keep Spotify. Matching length does not prove sample alignment between masters.
- Give each playback occurrence a generation, even when repeat plays the same URI. Carry it with source
  configuration revision, seek revision and network policy through every lookup, decode and callback.
  Recheck immediately before committing. A paused track must stay paused; a seek invalidates prepared
  audio for the old position. Drop stale publication and cancel obsolete network/decode work explicitly.
- Prepare silently while Spotify continues. Validate decoded format, duration, seek accuracy and buffered
  headroom around the moving playback position. Read that position again at commit. Avoid late-song,
  crossfade and Automix transitions; defer or skip when their state cannot be established reliably.
  No claim of an inaudible transition until measured on device with aligned and differently mastered files.
- Separate Wi-Fi/cellular ceilings apply to lookup, prefetch and media requests, including retries and
  redirects. Recheck on path changes and before handoff. Cancel disallowed network work immediately;
  already buffered audio can finish without new requests while recovery is prepared. Unknown network
  types use the stricter policy. These settings govern Vitrine's extra traffic; Spotify's own data-use
  controls still govern its stream. Account for both streams when measuring usage.
- A returned FLAC above a lossy ceiling is refused, not accepted because the source ignored `quality`.
  Do not compare unlike lossy codecs by bitrate alone or replace known native lossless with an unproven
  alternative. Initially restrict upgrades to verified lossless candidates from a known lossy baseline.
- Keep network, decoding, allocations, locks and Objective-C messaging out of the audio render callback.
  Output disposal and route changes must not free buffers still in use. Output gates and policy changes
  invalidate pending upgrades as well as new requests.

## Network and quality boundaries

Use a dedicated network session with no Spotify cookies, authorization headers or shared authentication
state. Store provider credentials separately in Keychain; redact complete signed/token-bearing URLs,
including paths, query strings and provider error text. Show users that a configured source receives
track metadata. Require HTTPS, validate every redirect, and reject non-network schemes and unexpected
local/private destinations by default. A user-configured LAN provider needs an explicit scoped policy.
Validate manifests and media URLs as untrusted data; JSON removes code execution, not network risks.

Bound response sizes, nesting, candidate count, concurrent requests, decode memory, total wall-clock
time and retries. Honor `429`/`Retry-After`, distinguish auth/configuration errors from misses, and use
backoff rather than retry loops per player-state event. Source removal, reset and disable must stop its
requests and clear its credentials, pending work and cached answers. Do not rely only on stale-result
checks to stop bandwidth use. Apply limits to artwork and media manifests/segments as well as API calls.

BitChord caches manifests/searches for ten minutes and stream answers for five, with shared in-flight
calls. For Vitrine, key by source identity/configuration, recording, rendition, requested quality and
policy; respect a provider's earlier expiry and single-use URLs. A signed URL is not a permanent
track identity. Keep transport errors out of successful caches and evict expired/failed stream entries.
Transient playback buffering must be bounded and must not become offline storage for a streaming-only
provider. Offline downloads need a separate design and permission enforcement.

Display source codec/rate/depth separately from output route/rate and active processing. A FLAC label
does not establish an unaltered source master; decoder verification establishes the delivered format.
DSP, speed, pitch, Sing, normalization and resampling can change the output. Apple's
[audio-session guidance](https://developer.apple.com/library/archive/qa/qa1631/_index.html) says preferred
sample rates are requests: inspect the actual active rate. Never promise bit-perfect output from the
source label, a cable, or a settings switch alone.

## Implementation sequence and acceptance evidence

1. Build `Shared/Lossless` provider models, HTTP client, matcher and shared settings against a local
   fixture service. Test root/manifest URLs with prefixes, encoded IDs, optional fields, malformed and
   oversized JSON, wrong editions, duplicate IDs across providers, expiry, redirects, auth, rate limits,
   cancellation, source reset/removal and quality ceilings. A JS index must be rejected without fetching
   or executing its code. Fixture audio should be owned or generated test material.
2. Add a decoder/playback harness for direct FLAC/ALAC. Measure startup, seeking, buffer size, cancellation
   and actual formats. Separately investigate the Spotify handoff seam; do not publish a working-feature
   claim from standalone playback. Prove one audible owner and recovery before enabling automation.
3. Add the coordinator and per-network policy. Exercise rapid A/B/A skips, repeat of one URI, seek/pause
   during preparation and handoff, late completions, EOF, 403 after resolution, stalls after handoff,
   network/route changes, background/lock screen, calls and Connect transfer. Remote Connect playback
   stays with Spotify initially; phone-side substitution cannot upgrade a remote renderer.
4. Validate both looks on supported Spotify versions and iOS targets. Exercise lyrics, Live Activity,
   lock-screen controls, sleep timer, speed/pitch, effects, Sing and haptics together. Run the layer check
   and relevant harnesses; measure time to first sound, time to upgrade, audible gap, drift, total bytes,
   CPU/memory and recovery time. Report measured results separately from targets.

The worktree now includes documentation, decoder and AudioUnit harnesses, and an inactive source selector
in Shared/Player. No provider client, JavaScript runtime or network settings were added. No Spotify/device
handoff was validated. The HTTP contract is sufficiently documented for a fixture-backed client; the
next major prerequisite is proven Spotify recording/frame anchoring, followed by bounded streaming.
