# Lossless playback inside Vitrine

Investigation and native decoder experiment, 2026-10-08. **No production playback integration yet.**
Read with the [provider design](lossless-sources.md) and [addon compatibility notes](lossless-addons.md).
Implementation follow-up: [the inactive native prototype](lossless-prototype.md) now includes a
complete-file decoder and pre-Sing source selector with a real AudioUnit handoff harness. The remaining
production integration and streaming limits below still apply.

## Recommendation

Use HTTP addons, with a user-configured Plex/Jellyfin addon as the first real integration. Keep Spotify
as queue/control owner and investigate replacing its decoded audio **before Sing**. First prove that
handoff with a completely prepared, generated file. Native file decoding now has a reproducible
simulator baseline; live progressive decoding and Spotify synchronization do not.

Spotify can start immediately while a matched alternative prepares in the background. Waiting for a
bounded temporary file is acceptable for the first experiment because Spotify continues playing. It
is not a promise of a quick upgrade on every connection. Check expected size, allowed network, remaining
track duration and buffering permissions before fetching. Keep a bounded investigation of Spotify's
native external-source route alongside this work: a working native handoff could avoid the PCM
approach's continuing Spotify download and decoder, but static evidence does not prove it works.

## Native decoding: measured evidence

Added [harness/lossless](../harness/lossless/README.md), an isolated arm64 simulator app using four
generated 12-second stereo assets. No third-party media, account, Spotify instance or phone is used.

| Question | Observed on iOS 27.0 simulator | Consequence |
| --- | --- | --- |
| Native FLAC/ALAC files? | Complete frames and waveform-checked seeks for 16/44.1 FLAC, 24/96 FLAC and 24/48 ALAC | `ExtAudioFile` is a usable first decoder experiment; no JavaScript or FFmpeg runtime required |
| Convert to Spotify's client rate? | All four assets convert to 44.1 kHz with the expected frame count | Decode into the negotiated client format; conversion does not preserve original hi-res rate |
| Remote PCM via `AVAssetReader`? | Metadata loads over successful HTTP 206 requests; decoding refuses all four with -11838 | Do not assume local decoding generalizes to HTTP URLs |
| Incremental FLAC? | Parser succeeds and native packet conversion yields correct samples, but is 816/1,024 frames short at EOF | Promising, incomplete; investigate EOF before a streaming claim |
| Incremental ALAC? | Fast-start M4A succeeds; tail-metadata M4A returns `optm` | Container layout matters; not every `.m4a` is progressively streamable |
| Bit depth from compressed ASBD? | `mBitsPerChannel` is zero for these assets | Validate codec/container metadata separately; Float32 output does not prove source depth |

Raw output and reproduction commands are in the harness. Its packet test collects all input before
converting, so it does not establish bounded buffering, underflow recovery or progressive seek. This
ran on one simulator runtime, not iOS 16.1/26 or a phone. Local decode timings are not playback-startup
or device-throughput measurements. The deployment target alone does not prove older runtime support.

The installed Apple SDK's `AVPlayerItemSampleBufferOutput.h` marks that API available from iOS 27
and currently supports HLS items only. Apple's
[API documentation](https://developer.apple.com/documentation/avfoundation/avplayeritemsamplebufferoutput)
also limits it to decoded PCM from HLS. It cannot be the iOS 16.1/26 direct-FLAC baseline.

## Exact PCM integration point

Inspect [SpeedPitch.x](../tweak/Sources/Shared/Player/SpeedPitch.x): `pullSource`, `pullMixer`,
`pullChain`, `feed`; and [Sing.x](../tweak/Sources/Shared/Sing/Sing.x): `stage`, `musicOutputChanged`,
`SGSingLeadOf`.

Flow exercised by the inactive prototype; normal Spotify playback does not enable source selection:

```text
Spotify mixer -> original PCM + source advancement
                            |
prepared external PCM -> source selector -> Sing -> speed/pitch -> RemoteIO
                                                        -> render-notify effects/haptics
```

`SGPlayerSetStage` is one atomic function pointer, already registered by Sing even when its engine is
inactive. Do not register lossless as another stage. The prototype adds a distinct source selector
inside Shared/Player's `pullSource`, reached both with no stage and through the `pullMixer` callback
passed to the existing stage. The decoder lives in Shared/Lossless; its future coordinator will
publish prepared buffers through that seam.

The first prototype should still pull the original mixer for each source span, retain its valid/silent
frame information, and choose external frames only for a validated corresponding span. This is a
hypothesis for preserving Spotify's advancement, **not proof of its clock contract**. It continues
Spotify's traffic and decoding. Never replace frames beyond a native stall, pending seek, unknown
track transition or EOF just because external data exists. Never wait for a worker during render.

Constraints from the current code:

- `pullSource` advances a per-output sample counter. It is not track position and cannot identify
  repeat, seek or crossfade. Bind the external cursor to a verified track/seek occurrence and source
  frame anchor; carry that generation through every decoded buffer.
- Sing pulls seconds ahead and corrects the public position for that lead. Feeding its input from the
  *audible* position would replay old audio. Commit at the aligned next **source** frame; change the
  source badge when new audio actually emerges. Do not discard buffered audio to hurry a badge update.
- Speed/pitch consumes input at a different rate from wall time. Advance by frames actually pulled,
  not a main-thread timer. Sing's seek/landing behavior needs a shared discontinuity signal; the track
  observer does not report every seek.
- The seam accepts Float32, noninterleaved, at most two channels with matching mixer/output client
  rates. Sing further requires stereo 44.1 kHz. The harness tested interleaved decoder output; planar
  conversion and actual stage composition still need tests. A 96 kHz source converted to 44.1 kHz is
  a lossless source with resampled output, not preserved hi-res output.
- Selection is after Spotify's mixer/EQ. Overwriting its samples can bypass upstream gain,
  normalization, fade and duck behavior. Measure and reproduce necessary gains explicitly; exclude
  crossfade/Automix initially. Vitrine's downstream processing is a separate stage.
- Follow `SGPlayerWatchMusicOutput`, disposal and format changes. Keep buffers alive through render.
  Preserve native sound information used to choose the music output; replacement sound must not keep
  an obsolete output selected.
- Network, file I/O, codec work, allocation, Objective-C messages and waits stay on workers. Render
  reads preallocated PCM and an immutable generation descriptor. Recovery must account for frames
  Sing already holds rather than abruptly mixing clock generations.

An independent `AVPlayer` would need another design for Spotify's queue, lyrics, lock-screen commands,
sleep timer, interruptions and Connect. It is not the preferred production shortcut. Phone-side PCM
replacement cannot improve a remote Connect renderer; keep that mode with Spotify.

## Spotify binary: a real lead, not a proven hook

Inspected the available decrypted **9.1.78** executable, SHA-256
`2d78c32e16c941776c1de2d38f06a61fbc0aac6a865c6a68ce4180cf1001d671`.
Used symbols, string cross-references and bounded ARM64 disassembly; did not modify or run the binary.

- `SPTEsperantoPlayer` exposes `playContext:options:loggingParams:origin:` and context preparation.
  `SPTPlayerContext`, `SPTPlayerContextPage` and `SPTPlayerTrack` have dictionary construction and
  serialization. These are investigation entry points, not a demonstrated stream-replacement API.
- `media.external_url` has code references including `0x1095ce8ec` and `0x1095ce97c`. This establishes
  a metadata-key code path, not that overriding `-[SPTPlayerTrack metadata]` changes the decoder.
- The binary contains `ResolveAudioURL` and `rurl`; timeline-conductor code has separate branches
  logging external URIs (`0x1096a1da4`) and HLS audio URLs (`0x1096a1e34`), checked in disassembly.
  This supports investigating native external media, but establishes neither music-track eligibility
  nor required fields, authorization behavior, codecs or handoff.

Addresses are unslid evidence for that exact executable, not offsets to ship. Verify 9.1.88 separately.
AVPlayer symbols in Canvas/video do not establish the main music player's implementation.

The next native-source experiment should use a diagnostic build and generated audio: trace the context
representation to the selected source, identify necessary fields, and test whether changing the
rendition retains recording identity, queue, position and local controls. Starting a separate context
or episode does not solve in-place music upgrades. Do not invent selectors or rewrite entitlements.

## Concrete implementation slices

1. **Controlled PCM handoff harness.** Extend the real AudioUnit chain from `harness/speed`, with a
   known original signal and a native-decoded alternate. Prove source selection before a stand-in
   stage, original decoder advancement, seek/skip/format cancellation, underflow/fallback, pause,
   two outputs and disposal during render. Then test actual Sing. This is the highest-risk unresolved
   dependency; prove it before shipping a settings switch.
2. **Provider configuration and diagnostics.** Native HTTP/JSON models, isolated session, Keychain,
   source ordering, per-network ceilings and “Test source.” Use fixtures first, then a user's own
   Plex/Jellyfin source. No bundled credential pools or playlist-sized searches. Distinguish a
   successful recording match and media validation from mere connectivity.
3. **Opt-in prepared-file upgrade on device.** A bounded transient file, native worker decode to
   the client format, generation-tagged PCM and one playback owner. Prepare while Spotify plays;
   switch only when recording, position, format, policy and transition checks agree. No offline
   library management in this slice. If buffering permissions/budgets rule out a complete file, keep
   Spotify playing until a supported streaming path exists.
4. **Progressive media.** Resolve the FLAC EOF deficit; test a bounded URLSession/parser/converter
   pipeline, cancellation, truncation, seek tables/range reopens and resets. ALAC needs a compatible
   container or a separately tested random-access reader. Range support alone does not map time to
   compressed byte offsets. Local-file decoding does not prove reading a file still being downloaded.
5. **Automatic upgrades and both looks.** Add coordinator and source/output status after the seam
   passes. Test rapid A/B/A, repeat, pause/seek during preparation, network/route changes, recovery,
   background, lyrics/Live Activity, speed/pitch, Sing and haptics. Measure audible discontinuity,
   drift, total bytes for both sources, CPU, memory and recovery time.

The follow-up prototype adds a tested audio seam and native decoder, not an addon client, lossless
settings, active Spotify replacement or production streaming engine. Synchronized playback ownership
remains the main uncertainty; progressive transport is another unresolved part.
