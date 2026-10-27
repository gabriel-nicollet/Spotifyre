# Native lossless decoder probe

An isolated simulator app using generated sine waves. It does not load Spotify, contact providers,
play audible audio, or change production playback. Requires Xcode with an arm64 iOS simulator,
FFmpeg and Python 3.9+. Build products default to the ignored `build/` directory; override
`LOSSLESS_PROBE_OUT` to keep them elsewhere.

```sh
sh harness/lossless/build.sh
python3 harness/lossless/serve.py harness/lossless/build/LosslessProbe.app
```

In another terminal, with the intended simulator booted:

```sh
xcrun simctl install booted harness/lossless/build/LosslessProbe.app
SIMCTL_CHILD_LOSSLESS_HTTP_BASE=http://localhost:18764 \
  xcrun simctl launch --console booted dev.vitrine.lossless-probe > /tmp/lossless-probe.log 2>&1
python3 harness/lossless/check.py /tmp/lossless-probe.log
```

Omit `SIMCTL_CHILD_LOSSLESS_HTTP_BASE` for local tests only. The server binds loopback and serves only
four generated fixture names, supporting HEAD, byte ranges, 206 and 416. Stop it with Ctrl-C afterward.
The app exits after its probes, with a 60-second watchdog. Check the log with `check.py`: exiting
successfully only means the probe finished, not that all APIs supported the media.

## What is exercised

- 12-second stereo FLAC at 16-bit/44.1 kHz and 24-bit/96 kHz; ALAC at 24-bit/48 kHz in M4A with the
  `moov` box at the end and an otherwise identical fast-start copy with it at the beginning.
- `AudioFileStream` in 257-byte input chunks. Collected packets and the magic cookie then go through
  `AudioConverter` to Float32 PCM. This intentionally keeps all packets in memory: **it is not a
  bounded streaming implementation**, network-underflow test or proof of seeking compressed streams.
- `ExtAudioFile` whole-file decode at native rate and 44.1 kHz, exact total-frame checks, and a seek
  to file frame `floor(3.125 * sourceRate)`. The next 1,024 native-rate frames are compared to the known
  sine waves; converted seeks check successful reads, not waveform alignment or converter latency.
- `AVAssetReader` over local and loopback HTTP assets, requesting one second from 3.125 seconds.
  Native-rate timestamp/frame bounds are checked locally. HTTP behavior is reported, not required
  to fail on every OS.

## Observed on 2026-10-08

iOS 27.0 arm64 simulator, SDK 27.0, minimum deployment target 16.1. **Not run on iOS 16.1 or 26, or on
a physical phone.** The deployment target alone does not establish those runtimes' capabilities.
Raw structured output: [results/ios27-simulator.jsonl](results/ios27-simulator.jsonl).

| Fixture | Local native decode | Seek max absolute error | Incremental parser / packet decode |
| --- | --- | --- | --- |
| CD FLAC | 529,200 frames | 0.00001525 | Parser succeeds; packet path gives 528,384 frames, 816 short |
| 96 kHz FLAC | 1,152,000 frames | 0.000000119 | Parser succeeds; packet path gives 1,150,976 frames, 1,024 short |
| ALAC, tail metadata | 576,000 frames | 0.000000119 | Parser refuses with `optm` / 1869640813 (not optimized) |
| ALAC, fast start | 576,000 frames | 0.000000119 | Parser and packet decode return all 576,000 frames |

All four full-file conversions to 44.1 kHz returned 529,200 frames. All four local asset-reader seeks
completed within one sample of the requested start/duration. All four HTTP assets loaded tracks but
`startReading` returned false with `AVFoundationErrorDomain -11838`
(`AVErrorOperationNotSupportedForAsset`); the fixture server recorded successful 206 responses.

The FLAC packet-path tail deficit is unresolved; do not silently pad it or call streaming complete.
The source ASBD reported zero bits per channel for these compressed formats. That value cannot be used
as a verified bit-depth badge. Fixture bit depth is known from generation; future source validation
needs codec/container metadata and decode inspection, separate from Float32 output precision.

These results support a complete temporary-file decoder as the first controlled playback experiment.
They do not prove Spotify clock continuity, stage composition, seamless switching, network streaming,
low memory use, background playback, hi-res output, or any provider's compatibility. See
[the integration investigation](../../docs/lossless-playback.md) for those remaining steps.

## Audio handoff prototype

`handoff-build.sh` builds a second app from the worktree's production `SGPreparedPCM`,
`SGPCMReplacement` and `SpeedPitch.x`. It replaces generated native PCM before a stand-in stage,
using a real converter/mixer/RemoteIO chain. It emits quiet audio. See
[the prototype's calling contract and tests](../../docs/lossless-prototype.md).

```sh
THEOS="$HOME/theos" sh harness/lossless/handoff-build.sh
xcrun simctl install booted harness/lossless/build/handoff/LosslessHandoff.app
xcrun simctl launch --console booted dev.vitrine.lossless-handoff > /tmp/lossless-handoff.log 2>&1
```

Require a final `RESULT failures=0`, not just successful launch. The app has a 30-second watchdog.
The default decoder probe above and its `check.py` remain separate; they use a different log format.
The handoff checks do not run actual Spotify or Sing's ML/look-ahead engine. The production source
selector has no automatic registration or settings switch.
