---
name: clean-room-describer
description: >
  Learn what upstream spoti.pw (github.com/skopevoj/spoti.pw) changed or what its users report, without
  anyone on Vitrine seeing upstream code. Use when the user asks about an upstream issue, pull request,
  release or feature, or wants to know whether Vitrine needs something upstream did.
---

# Clean-room describer

Upstream is under a license that does not allow reuse, so Vitrine is written clean room. Whoever implements
must never see upstream code. One agent, the describer, reads upstream and hands back behavior only.

## The rule

- Implementers, including you, never read upstream code, diffs, the clone at
  `/Users/r/GitRepositories/spoti.pw-beta` or anything in `/Users/r/temp`, and never decompile an upstream
  build.
- The describer reads issues, pull requests, release notes, screenshots and videos, and diffs only to
  understand behavior. It writes what a user sees and under which conditions, never code, upstream's own
  names for functions, variables, files or constants, or a paraphrase close enough to rebuild the code.
- Spotify's classes and selectors and Apple's API names are facts about Spotify and iOS. The describer may
  name them.

## Dispatch

Start a `general-purpose` agent with the Agent tool. It needs `gh` with the sandbox off; inside it, `gh`
fails on TLS. Give it:

1. The rule above, word for word.
2. The exact items: issue or PR numbers, a release tag, or "open issues and those closed in the last N
   weeks".
3. What to report for each:
   - The symptom, steps to reproduce, and conditions (device, iOS, Spotify version, redesign or native look).
   - Expected against actual, and any timing measured from a video.
   - Status, and any cause the maintainer stated, in behavior terms.
   - For a PR: what changes for the user, which Spotify classes or system mechanisms are involved, and the
     caveats.
   - For a PR with several commits, how the behavior changed from commit to commit, above all a limit, a
     guard or a cleanup added and later removed, and the reason given, if any. The connect relay was built
     from what merged, and the merged version had dropped the earlier limit of one round per second. Nobody
     noticed until the phone showed about fifty answers a second.
   - The numbers in the behavior, with their units: rates, intervals, timeouts, caps, sizes, retry counts and
     backoff.
   - What the behavior costs while it runs: how often it does work (timers, polling, a round per event),
     network traffic, CPU, background work, and the logging it does. State plainly when the source gives no
     limit on any of these.
   - Defaults and controls: whether it is on by default, whether a setting turns it off, and what a user
     loses with it off.
4. Where to write: a file in the session's scratchpad, also returned as its final answer, under a word
   limit (about 900 for a survey, 1200 for detail).
5. That it writes nothing into the repo, and keeps raw dumps out of the report. Issue bodies can carry
   tokens or keys; raw dumps stay in the scratchpad and are never passed on or committed.

To follow up on the same items, send the describer another message with SendMessage instead of starting a
new agent, so it keeps what it already read.

## After the report

- Read only the report, never the raw dumps beside it.
- Check each item against Vitrine yourself: grep `git log` for the fix by its behavior, then read our code.
  Many upstream bugs are already fixed here under our own commit.
- A spec built from the report keeps its numbers, its costs and the limits upstream removed, each as a point
  for the implementer to decide, never dropped silently.
- What Vitrine still needs becomes a behavior spec in `notes/` (gitignored, so it stays on this Mac, as
  `notes/cleanroom-specs/` and `notes/beta-gaps/` do), which the implementer reads instead of the upstream
  thread.
