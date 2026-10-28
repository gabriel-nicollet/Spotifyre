---
name: spotify-version-check
description: >
  Check Vitrine against a new Spotify version: sweep every class, selector and ivar the tweak hooks or calls
  against the new build's class dump, and read a Spotify method's body from the binary when a selector is gone.
  Use when Vitrine moves to or adds a Spotify version, when a feature works on one version and not another, or
  when a selector or class the tweak needs has disappeared.
---

# Checking a new Spotify version

Spotify renames and removes Objective-C classes and selectors between versions. A hook on a missing class
fails at launch in `SGRequireClasses`, so it is easy to see. A selector the tweak *calls* is different: the
call sits behind `respondsToSelector:`, so a missing one does nothing and logs nothing. Sweep both.

## What 9.1.88 and later broke

| Feature | Cause | How it showed |
|---|---|---|
| Player morph from the now playing bar | `SPTBarOverlayPresentationTransition` gone; the player now opens through `MainUI_TabBarUIImpl.CompactOverlayTransition` | No morph; the hook sweep caught it |
| Tabs of the mod's own (`SGOpenSpotifyURI`) | `-[SPTLinkDispatcherImplementation navigateToURI:options:interactionID:]` gone | A tap did nothing; the sweep missed it, since the selector is called, not hooked |
| Redesigned player header blurred | iOS 26's scroll edge effect over a header inside the player's list | Not a Spotify change; found on the phone |

The second row is the reason this skill exists. Read the third as a reminder that the phone check
(`phone-check`) still runs after a clean sweep.

## The sweep

Class dumps of a version live in `notes/spotify-<ver>/data/` (gitignored): `di-objc-<ver>.txt` holds
`-[Class selector]` lines, `classes-<ver>.txt` every class name. `notes/spotify-9.1.90/tools/hook-sweep.py`
compares the tweak's `%hook` classes and methods, and its `NSClassFromString` and `SGRequireClasses` names,
against two versions. Copy the tools folder to the new version's notes and change the two version strings.

The hook sweep does not check what the tweak calls. Check these by hand, or extend the script:

    grep -rhoE 'respondsToSelector:@selector\(([^)]+)\)|NSSelectorFromString\(@"[^"]+"\)|@selector\([^)]+\)' tweak/Sources | sort -u
    grep -rhoE 'class_getInstanceVariable\([^,]+, "[^"]+"\)' tweak/Sources | sort -u

For each selector, find which class it is sent to in the code, then grep the new dump:

    grep -c '\[SPTLinkDispatcherImplementation navigateToURI:options:interactionID:\]' notes/spotify-<ver>/data/di-objc-<ver>.txt

A count of 0 on a selector that the old version had is a silent break. A Swift ivar (`class_getInstanceVariable`)
is not in the dump. Check it on the phone, or read the class's ivar list with `otool -ov` (below).

## Reading a method in the binary

When a selector is gone, read what the old version's method did. It is often a thin wrapper around one the new
version still has. Use Vitrine's own decrypted base IPAs in `ipa/` only. Never open upstream builds or the
Eevee+Chroma IPAs; the clean-room rule (`clean-room-describer`) still holds.

1. Unzip the binary outside the repo (`$CLAUDE_JOB_DIR/tmp` in a background job, else `$TMPDIR`). The
   later steps run in that folder:

       repo=$PWD; mkdir -p "$TMPDIR/s78" && cd "$TMPDIR/s78"
       unzip -o -q "$repo/ipa/Spotify-9.1.78.ipa" 'Payload/Spotify.app/Spotify'

2. Dump the Objective-C metadata once (about 170 MB, a minute) and find the class's method list:

       otool -arch arm64 -ov Payload/Spotify.app/Spotify > ov.txt
       grep -n 'name .* SPTLinkDispatcherImplementation$' ov.txt

   Under `baseMethods`, each entry has `name` (a selector reference), `types` and `imp`, and the address in
   parentheses is the absolute one. The list is relative, so the names are not printed. Match by `types`: a
   method of `v40@0:8@16q24@32` takes an object, a long and an object. A wrapper's `imp` is a few
   instructions before the next one's.

3. Disassemble the range. `dis.py` uses Xcode's `llvm-objdump` and names every `objc_msgSend$` stub:

       python3 -I "$repo/notes/spotify-9.1.90/tools/dis.py" Payload/Spotify.app/Spotify 0x109776338 0x109776350

   `/usr/bin/objdump` ignores `--start-address` on this binary and prints from the top. Use the Xcode one.
   `stubs.py` resolves single stub addresses (`adrp x1` + `ldr x1, [x1, #off]` to a selector reference; the
   pointer's low 36 bits under chained fixups, base `0x100000000`).

4. Read the arguments: `x0` self, `x1` the selector, `x2` onward the arguments in order. A class reference
   loaded before an `init…` stub gives the class. Search `ov.txt` for the reference's address to name it.

## What 9.1.78's link dispatcher did

The worked example behind the tabs fix (`Shared/Navigation/Links.x`):

    navigateToURI:options:interactionID:
      -> navigateToURI:sourceApplication:nil options: interactionID: completionHandler:nil resultHandler:nil
         -> reason = [[SPTUBINavigationReason alloc] initWithSourceApplication:nil interactionID:]
         -> navigateToURI:options:reason:completionHandler:resultHandler:

A nil reason crashes 9.1.90 (`swift_getEnumCaseMultiPayload`): a Swift reason is not optional just because the
selector takes an object. Build the argument the old wrapper built.

## After the sweep

- A fix for one version keeps the old version's path first where it still exists, so a supported version runs
  the code it ran before (`AGENTS.md`: 9.1.78 is the version Vitrine is made for).
- Check each fix on the phone with `phone-check`, and say which versions were run and which were not.
