#!/usr/bin/env bash
# Rebuilds the tweak alone and installs it in the app the last full build made: seconds of compiling and
# signing instead of minutes of unpacking, injecting and zipping.
#
#   scripts/quick.sh            (make quick)
#
# The last out/*.ipa from scripts/pipeline.sh is kept unpacked in out/quick/, and unpacked again when a
# newer one is built. Only spotifyglass.dylib changes: a change to the extension, the App Group shim, a
# plist or an icon needs the full pipeline (make install).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/out/quick"
IPA="$(ls -t "$ROOT"/out/*.ipa 2>/dev/null | grep -v -- '-signed\.ipa$' | head -1 || true)"
REF="$IPA"
# With the IPA moved away, the app already unpacked from it still serves.
if [ -z "$IPA" ]; then
  [ -f "$CACHE/.from" ] || { echo "no IPA in out/: run the full build once (make install)" >&2; exit 1; }
  IPA="$(cat "$CACHE/.from")"
  REF="$CACHE/.from"
fi

# What only the full pipeline builds: the Live Activity widget (its Swift, some of it beside the tweak's
# sources), the App Group shim, the plist overlay and the icons. Changed since that build, it is stale here.
stale="$(find "$ROOT/extension" "$ROOT/plist" "$ROOT/icons" "$ROOT/tweak/Sources" \( -name '*.swift' -o -path "$ROOT/extension/*" -o -path "$ROOT/plist/*" -o -path "$ROOT/icons/*" \) -type f -newer "$REF" 2>/dev/null | head -3)"
if [ -n "$stale" ]; then
  printf 'changed since the last full build, which make quick does not rebuild:\n%s\nrun make install once\n' "$stale" >&2
  exit 1
fi

if [ ! -f "$CACHE/.from" ] || [ "$IPA" -nt "$CACHE/.from" ] || [ "$(cat "$CACHE/.from")" != "$IPA" ]; then
  echo "==> unpacking $IPA"
  rm -rf "$CACHE"
  mkdir -p "$CACHE"
  unzip -q "$IPA" -d "$CACHE"
  # The App Store's DRM records, which a decrypted app does not need, and which make the phone refuse the
  # patch install devicectl does for a folder ("did not supply a new SINF").
  find "$CACHE/Payload" -type d -name SC_Info -prune -exec rm -rf {} +
  printf '%s' "$IPA" > "$CACHE/.from"
fi
APP="$(ls -d "$CACHE"/Payload/*.app | head -1)"

# A build with FLEX carries the phone driver (tweak/Makefile, SG_DRIVER). Theos rebuilds by file times
# alone, so a change of the flag cleans first.
DRIVER=0
[ -f "$APP/Frameworks/autoflex.dylib" ] && DRIVER=1
STAMP="$ROOT/tweak/.theos/quick-driver"
if [ "$(cat "$STAMP" 2>/dev/null)" != "$DRIVER" ]; then
  echo "==> SG_DRIVER is now $DRIVER: building from clean"
  env -u MAKELEVEL gmake -C "$ROOT/tweak" clean >/dev/null
fi

# The linked dylib is taken from Theos's objects, with no .deb packed around it.
echo "==> building tweak"
env -u MAKELEVEL gmake -C "$ROOT/tweak" SG_DRIVER="$DRIVER" >/dev/null
mkdir -p "$(dirname "$STAMP")"
printf '%s' "$DRIVER" > "$STAMP"

# The dylib as cyan puts it in the app: Substrate found through the app's Frameworks.
DYLIB="$APP/Frameworks/spotifyglass.dylib"
cp "$ROOT/tweak/.theos/obj/spotifyglass.dylib" "$DYLIB"
install_name_tool -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate \
  @rpath/CydiaSubstrate.framework/CydiaSubstrate "$DYLIB" 2>/dev/null

exec "$ROOT/scripts/install.sh" "$APP"
