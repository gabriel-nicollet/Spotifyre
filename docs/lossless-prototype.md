# Native lossless prototype

**History.** This records the first slice (2026-10-08). The live engine no longer decodes whole files or
takes its anchor from Spotify's position: see the Lossless section of [tweaks.md](tweaks.md). `SGPreparedPCM` and
`SGPCMReplacement` remain for the handoff harness.

Implemented in `feat/lossless-native-prototype`, based on `e2677b1`, 2026-10-08.
This is the first audio-integration slice of [the playback design](lossless-playback.md).
**Normal Spotify playback does not enable it.** There is no provider client, settings switch,
track matcher, automatic-upgrade coordinator or network fetch in this slice.

## Implemented

- `Shared/Lossless/SGPreparedPCM.{h,m}`: native complete-file FLAC/ALAC decoding to stereo planar
  Float32 at the requested client rate. Checks codec, channels, rate, declared versus decoded length,
  finite samples, cancellation and allocation limits. Rejects network URLs. Encoded file limit:
  64 MiB; decoded PCM limit: caller-selected up to 32 MiB (about 95 seconds at 44.1 kHz stereo).
  This whole-file prototype deliberately rejects longer assets; production playback needs a bounded
  worker-fed buffer rather than raising this limit without measuring memory.
- `Shared/Lossless/SGPCMReplacement.{h,m}`: immutable, retained PCM snapshots, explicit output and
  generation identity, source-to-asset frame anchors, whole-span replacement and native fallback for
  stale/wrong output, rate, shape, position or EOF. Readers use atomic admission; storage is reclaimed
  off render after admitted readers leave. Publication is refused when retirement is backlogged;
  at most three snapshot owners are retained by the replacement manager. A caller can own additional
  decoder results, so this is not a process-wide memory cap.
- `Shared/Player/SpeedPitch.{h,x}`: a separate source-selector callback after successful non-silent
  music-mixer pulls and before the existing stage. It leaves `SGPlayerSetStage` with Sing. The native
  mixer is still pulled once, including when its output is replaced. Native samples determine output
  ownership; replacement audio cannot keep an obsolete output selected by being louder.
- Output restart, selection, connection, format change, stop and disposal invalidate source epochs.
  Native mixer silence/errors also invalidate: the output counter can advance without recording
  advancement, so recovery requires a new proven anchor. This conservatively includes natural silence.
  Format changes invalidate before `AudioUnitSetProperty`, since its property listener may arrive
  later. `SGSourceEvents.x` now invalidates on terminal seek/skip/stop commands, reported track,
  pause/resume, inferred position discontinuities/repeat, Sing on/off and route changes. These
  invalidations run only in driver (FLEX) builds. A future playback owner still needs its own policy and
  source cancellation, proven recording identity and seek-landing coordination.

## Calling contract

1. Decode a complete, trusted local file on a worker using `SGPreparedPCM`. Cancellation is cooperative
   between native reads; it cannot interrupt a stuck Core Audio call. This does not validate HTTP or
   progressive transport, and it does not create an offline library.
2. Call `SGPCMReplacementEnable` once off render. It registers the process-lifetime source callback;
   no constructor calls it in the tweak. The harness installs an instrumented wrapper instead.
3. With the correct music output running, capture the current epoch. Establish a **source-frame**
   anchor for the same recording/seek occurrence, then publish via `SGPCMReplacementInstall`.
   The output-local sample counter is not a track position. Reading Spotify's audible position while
   Sing has look-ahead does not establish this anchor. No production anchor has been proven yet.
4. Cancel on discontinuity. Once invalidated, callbacks leave native PCM untouched; an already
   admitted callback may finish its block. Invalidating cannot remove old audio that Sing or the
   time/pitch unit already buffered. Recovery must eventually coordinate those buffers and clocks.

The render path does no allocation, file I/O, codec work, Objective-C messaging, mutex acquisition or
waiting. It validates an immutable descriptor and copies PCM. Publication/reclamation use a control
mutex off render. Do not relax sequential consistency of reader admission and pointer exchange without
re-proving reclamation: a reader must increment before loading the active snapshot.

This is not sample-transparent output: substitution occurs after Spotify's mixer/EQ, potentially
bypassing normalization, fades and ducking. Existing Vitrine stages follow it, and the original decoder
still consumes data. Native stalling causes native fallback, not continued external playback. There is
no crossfade between sources. The prototype's whole-span fallback can itself be audible.

## Validation

[harness/lossless/handoff.m](../harness/lossless/handoff.m) compiles the production decoder, replacement
manager and Logos `SpeedPitch.x` with a real converter -> mixer -> RemoteIO chain. Generated test audio
only, with a stand-in processing stage; it does not run Spotify or Sing's ML engine.

```sh
THEOS="$HOME/theos" sh harness/lossless/handoff-build.sh
xcrun simctl install booted harness/lossless/build/handoff/LosslessHandoff.app
xcrun simctl launch --console booted dev.vitrine.lossless-handoff > /tmp/lossless-handoff.log 2>&1
```

Require `RESULT failures=0` and no `FAIL` lines. A 30-second watchdog catches an incomplete run. The
harness emits quiet audio through the simulator. The direct checks cover complete decode, waveform,
rate conversion, exact/insufficient budget, cancelled preparation, remote-URL rejection, frame anchors,
invalid source guards, storage retention/release and concurrent publication/cancellation. The live
chain covers no-stage and existing-stage paths, native advancement, speed, cancellation, pause/resume,
native silence and recovery without reusing its old anchor, format invalidation and mixer disposal.

Run the existing `harness/speed` `two` scenario as a regression with the selector unregistered. That
checks multiple outputs and rate/ownership behavior, not simultaneous active lossless substitution on
two outputs. The new direct test separately rejects a wrong output identity.

Full tweak package build (does not install):

```sh
THEOS="$HOME/theos" CLANG_MODULE_CACHE_PATH=/tmp/vitrine-lossless-module-cache \
  env -u MAKELEVEL gmake -C tweak package -j4 \
  'ADDITIONAL_SWIFTFLAGS=-module-cache-path /tmp/vitrine-lossless-module-cache'
```

A fresh worktree also needs its ignored `SGFlagList.m` generated from the target IPA with
`scripts/extract-flags.py`. The decoder/handoff harness needs no IPA or provider account.

On 2026-10-08, the iOS 27.0 arm64 simulator handoff run completed with zero failures (59 checks,
including AudioUnit setup checks). The full arm64 tweak package builds. The existing `two` regression
checks 12 multi-output scenarios with the selector inactive. Recorded results are in
[the harness results](../harness/lossless/results/). No device installation,
physical-device handoff, actual Sing look-ahead, recording match, provider compatibility, seamless
switch, end-to-end latency or network bandwidth improvement is established by these simulator checks.

## Next dependency

Prove the source-frame anchor and validate the new application-level discontinuity observation on
a phone, including actual Sing look-ahead and buffering. Separately add the HTTP fixture client and
bounded media preparation. Keep the prototype inactive in normal playback until those paths pass;
do not infer production readiness from the source selector or the simulator waveform checks.

## Source-frame anchor diagnostic

Phase 1 adds measurement only. It neither registers the selector nor replaces any audio, and it has
no provider client or network fetch. The capture code and ring storage compile only with `SG_DRIVER=1`,
the flag `scripts/pipeline.sh` sets for FLEX builds. Logging additionally requires `FLEXManager` at
runtime, like Sing's dev-model slot (currently in `SGSingModel.m`, not `SGSingLoader.m`). Do not install
this branch merely to enable lossless: replacement remains inactive.

Build the diagnostic package without installing:

```sh
THEOS="$HOME/theos" CLANG_MODULE_CACHE_PATH=/private/tmp/vitrine-anchor-module-cache \
  env -u MAKELEVEL gmake -C tweak package -j4 SG_DRIVER=1 \
  'ADDITIONAL_SWIFTFLAGS=-module-cache-path /private/tmp/vitrine-anchor-module-cache'
```

The package must be used with a FLEX-carrying app for the runtime check to pass. A non-FLEX package
omits the sampler, diagnostic getters and logger. Keep one canonical spelling of the module cache
path: reusing a cache through both `/tmp` and `/private/tmp` can make Swift report duplicate Darwin
modules. The original package command above was attempted; a fresh canonical cache resolved that
local build failure.

`Shared/Player/SpeedPitch.x` samples each music mixer pull before source selection and Sing. Each
output has its own 256-entry single-producer/single-consumer ring, with release/acquire publication
and compile-time checks for lock-free atomics. Sampling uses
`N = max(1, round(rate * speed / (10 * frames)))`, plus every changed epoch. This is roughly ten
samples per wall second during steady playback; Sing's refill can burst. Silent and failed pulls
are included and invalidate the diagnostic epoch even with no selector installed. A full ring drops
new entries rather than waiting; `dropped` is cumulative. The render additions do no allocation,
locking, logging, Objective-C messaging or waiting. Rings are never reset when output slots are reused.

One main-thread timer drains all rings once a second. Application events also drain and log immediately
on main; events received on another thread invalidate immediately and dispatch the log asynchronously.
`event_host`/`event_epoch` retain the event's origin, while `control_host` describes when state was read.
Every line begins `lossless-anchor:` and carries `v=1`, a process `session` and a monotonic `seq`.
Track URIs are percent-escaped. There is no inference that a command succeeded: `evidence=command`
(or `next_command`/`previous_command`) is a request, `reported` is observed state, and `inferred` is
clock-based evidence. The all-report observer sees position-only reports that the original
`playerStateDidChange:` deliberately filters out.

The fields come from:

| Fields | Source and meaning |
| --- | --- |
| `source_frame`, `frames`, `rate`, `host`, `silent`, `status`, `sample_epoch`, `output` | The native pull's starting output-local frame, span, client rate, `mach_absolute_time()` immediately before `AudioUnitRender`, its silence/error result, epoch captured before the pull and output identity. This counter is not a recording position. |
| `epoch`, `event_epoch` | Current source epoch and the epoch after an application invalidation. They can differ from the latest render sample. |
| `position_ms`, `uri`, `playing`, `paused` | `SGPlayerState()` from the existing player-state observer. Position uses `positionAsOfTimestamp` while paused and `position` otherwise. Sing's existing correction applies. |
| `raw_ms` | `SGSingSourcePosition`, a wrapper around Sing's existing thread-local `rawPosition` path, bypassing only Sing's correction. SpeedPitch's playback-speed hook still applies. |
| `karaoke_ms`, `karaoke_uri` | `SGKaraokePositionMs()` and `SGKaraokePlayingTrack()`, through KaraokeSource's captured player's state. The id may differ from the observer while reports arrive. No lyrics-delay preference is applied. |
| `speed`, `pitch`, `follows` | `SGPlayerSpeed()`, `SGPlayerPitch()` and `SGPlayerPitchFollowsSpeed()`. Their changes are labeled `speed_pitch` on the next timer tick. |
| `tp_engaged`, `tp_latency_ms` | SpeedPitch's engagement flag and `SGTimePitchLatency()` for the selected pull/in-place unit, read off render under its build lock. Zero when disengaged; this is the unit's reported latency, not a measurement of the whole output route or Varispeed. |
| `sing_on`, `sing_active`, `sing_state` | The requested mic setting, whether the last stage call entered the compatible Sing engine, and `SGSingCurrentState()`. A stopped output can leave the last-call flag set; consult sample age. Engine entry does not mean the ML worker is separating. |
| `sing_lead_ms`, `sing_correction_ms` | `SGSingHeldLead()` and `SGSingLeadOf(state)`. The latter is the correction for that state's clock line, and need not equal current held lead. |
| `age_ms`, `read_ms`, `dropped` | Age of the latest render sample, duration of the control reads, and total ring drops. Control reads and render samples are not an atomic snapshot. |

No unique Spotify recording-occurrence id or sample-exact seek-landing marker was found in the
exposed state. A same-URI backwards clock jump near the prior end, with repeat-one enabled, logs
`repeat` with `evidence=inferred`; other clock changes over 500 ms log `position_jump`. A seek to zero
near the end can also look like repeat. Commands and the later observed transition are separate
boundaries. Small remote seeks or repeats that never produce distinguishable state reports can be
missed. A callback for a route notification has the route reason, not proof of an acoustic change.
No independent fixed Sing end-to-end latency is exposed; its held lead and correction are available.

### Phone capture and procedure

After the maintainer reviews, builds and installs a FLEX app, capture its syslog with the locally
available `pymobiledevice3 syslog live` command. That CLI was not installed in this sandbox; no phone
capture or installation was attempted here. The exact filter is:

```sh
grep -F 'lossless-anchor:' phone-syslog.log > lossless-anchor.log
uv run harness/lossless/anchor.py lossless-anchor.log
uv run harness/lossless/anchor.py --selftest
```

Do not filter on process name: signing can change it. The prefix is inside SGLog's public text, so a
full syslog capture works too. Keep the full capture for comparison with Sing's own logs.

1. Start with a local phone output, one music track, Sing off, normal speed/pitch, crossfade/Automix and
   other effects off. Record at least 30 seconds of steady playback before each change, and 30 seconds
   after it settles. Confirm `sample=1`, a fresh `age_ms`, and matching sample/current epochs.
2. Seek forward, then backward, including a seek while paused. Pause for five seconds and resume.
   Check `seek`, reported `pause`/`resume`, any observed `position_jump`, and fresh epochs afterward.
3. Skip next, skip previous, then let repeat-one wrap naturally on the same track. A skip request and
   track report are distinct lines; a same-track repeat is an inferred boundary, not proven identity.
4. Turn Sing on with an already available model and vocals below As sung. Wait for active processing
   and a settled lead; record it, then turn Sing off and record the retained lead draining. Do not
   download a model as part of this measurement-only phase.
5. Set speed to 1.5x and back to 1x. Record the Pitch follows speed setting; repeat with it off if
   comparing the time-stretch unit. Repeat the seek/pause checks with Sing and 1.5x together.
6. Connect AirPods, record, disconnect them, and resume if Spotify pauses. Repeat with Sing on. Check
   `route` and pause/resume epochs and note the route externally; the unit latency is not Bluetooth's
   acoustic latency. Include a foreground/background interval to expose delayed control sampling.

### Reading the analysis

The stdlib-only script splits at every event, URI, epoch, output, rate, speed or dropped-count change,
including empty event segments. It rejects paused, silent, failed, missing, stale (>250 ms), slow
control-read (>20 ms), reused and mismatched-epoch samples. The default settling exclusion is one
second after a boundary (`--settle` changes it); Sing may need much longer. Karaoke fits additionally
require a matching track id. Fewer than three usable samples or no frame span reports `insufficient`.

For each of the corrected observer, uncorrected observer and Karaoke clocks, it projects the control
position back to render time using the recorded speed, then fits the fixed-slope model
`position = a + source_frame / rate`. `a_ms` is the mean offset; `jitter_ms` is RMS residual about that
fixed offset. A regression of that residual against source seconds gives `drift_ppm`; `detrended_ms`
shows scatter after removing that linear trend. The reference for `a` is each segment's mean frame,
so drift affects comparisons between segments. Short spans are not a reliable ppm estimate.

`jump_ms` compares offsets with the last fitted segment in the same process. `across` lists all
intervening event kinds, including events without enough data to fit. A cluster such as seek, pause
and route cannot be attributed to just one cause. Frame-counter resets change the numerical offset;
a jump is not necessarily a jump in audible audio. Different tracks need separate recording anchors.
The script reports each event transition rather than averaging unlike recordings by event kind.

These are asynchronously paired block-level observations. They can reject a stable-anchor hypothesis
or motivate a tighter probe, but even low jitter does not prove a source-frame anchor, acoustic
alignment, seamless replacement, HTTP decoding, hi-res output or Sing buffer continuity. No measured
phone result exists in this change.

### Checks for this phase

Both non-FLEX and FLEX arm64 tweak packages built on 2026-10-08, and the non-FLEX dylib holds none of the
diagnostic's strings or classes. On the iOS 27.0 arm64 simulator, the lossless handoff run passed 59 checks
with `RESULT failures=0`, and the speed harness `two` scenario reported 0 failures. Both runs are recorded in
[the harness results](../harness/lossless/results/).

The analyzer self-check passes known offsets, 100 ppm drift, jumps, all named event boundaries,
stale/silent/error/paused samples, epoch/output changes, duplicate capture lines and missing lyrics.
The actual ring implementation also passed wraparound, full-ring drops and a 200,000-entry concurrent
producer/consumer check on the Mac:

```sh
clang -std=c11 -Wall -Wextra -Werror -Wno-unused-parameter -O2 -pthread \
  harness/lossless/anchor-ring.c -o /tmp/vitrine-anchor-ring
/tmp/vitrine-anchor-ring
```

Layer and whitespace checks pass. No commit, push, phone installation or main-checkout edit was made.
