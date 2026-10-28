#!/usr/bin/env bash
# Runs a decrypted Spotify IPA with the tweak in the iOS Simulator (Apple silicon only).
#
#   scripts/sim-build.sh <decrypted.ipa> [--no-tweak] [--device NAME|UDID] [--no-launch]
#
# The device build of the tweak goes in as it is. Every Mach-O of the app and the tweak's dylib has its
# LC_BUILD_VERSION platform turned from iOS (2) into iOS Simulator (7), which arm64 code needs nothing
# else for, and is signed ad hoc. The extensions and the Watch app are left out. scripts/sim-shim.m goes
# in too (Substrate's MSHookMessageEx, and a phone's hw.machine). The device is a simulator of its own
# ("Vitrine" by default, an iPhone 17 on the newest iOS runtime), so the booted ones are left alone.
# SG_DRIVER=1 builds the tweak with the phone driver, on port 8086: PHONE_PORT=8086 scripts/phone.py state.
# SIM_PORT=8087 moves it, so two simulators can run their drivers at once.
#
# Needs: full Xcode with an iOS Simulator runtime, Theos in $THEOS, gmake.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${SIM_PORT:-8086}"
export THEOS="${THEOS:-$HOME/theos}"
IN="" TWEAK=1 DEVICE="Vitrine" LAUNCH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-tweak) TWEAK=0; shift ;;
    --device) DEVICE="$2"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -f "$IN" ] || { echo "usage: $0 <decrypted.ipa> [--no-tweak] [--device NAME|UDID] [--no-launch]" >&2; exit 1; }

VERSION="$(unzip -p "$IN" 'Payload/Spotify.app/Info.plist' | plutil -extract CFBundleShortVersionString raw -o - -)"
WORK="$ROOT/out/sim/$VERSION"
APP="$WORK/Payload/Spotify.app"
echo "==> Spotify $VERSION -> $WORK"
rm -rf "$WORK" && mkdir -p "$WORK"
unzip -q "$IN" -d "$WORK"
# Extensions and the Watch app would each need the same patching and only get in the way of installing.
rm -rf "$APP/PlugIns" "$APP/Watch" "$APP/_CodeSignature"
find "$APP" -name SC_Info -prune -exec rm -rf {} +

echo "==> building the simulator shim"
xcrun -sdk iphonesimulator clang -target arm64-apple-ios16.0-simulator -dynamiclib -Os -lobjc -framework Foundation \
  -DSG_DRIVER="${SG_DRIVER:-0}" \
  -install_name @executable_path/Frameworks/libvitrinesim.dylib -o "$APP/Frameworks/libvitrinesim.dylib" "$ROOT/scripts/sim-shim.m"
"$ROOT/scripts/insert-dylib.py" "$APP/Spotify" @executable_path/Frameworks/libvitrinesim.dylib

if [ "$TWEAK" = 1 ]; then
  # The flag table is generated from the IPA (gitignored), as pipeline.sh does.
  FLAG_LIST="$ROOT/tweak/Sources/Shared/Flags/SGFlagList.m"
  if ! head -1 "$FLAG_LIST" 2>/dev/null | grep -qF "from Spotify $VERSION."; then
    echo "==> extracting the flag table for Spotify $VERSION"
    "$ROOT/scripts/extract-flags.py" "$IN"
  fi
  echo "==> building tweak"
  # The driver's server moves to port $PORT (8086 unless SIM_PORT says), so an iproxy tunnel to the phone on 8085 stays the phone's.
  # Its objects go to .theos/obj-sim, so they never end up in a build for the phone (make quick builds
  # .theos/obj incrementally). Theos does not rebuild on changed flags, so a change of them cleans first.
  MAKE_FLAGS=(THEOS_OBJ_DIR_NAME=obj-sim SG_DRIVER="${SG_DRIVER:-0}" ADDITIONAL_CFLAGS=-DSG_TREE_PORT=$PORT)
  STAMP="$ROOT/tweak/.theos/obj-sim/sim-flags"
  CLEAN=""
  [ "$(cat "$STAMP" 2>/dev/null)" = "${MAKE_FLAGS[*]}" ] || CLEAN=clean
  env -u MAKELEVEL gmake -C "$ROOT/tweak" $CLEAN all "${MAKE_FLAGS[@]}" >/dev/null
  echo "${MAKE_FLAGS[*]}" > "$STAMP"
  DYLIB="$APP/Frameworks/spotifyglass.dylib"
  cp "$ROOT/tweak/.theos/obj-sim/spotifyglass.dylib" "$DYLIB"
  install_name_tool -id @rpath/spotifyglass.dylib \
    -change /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate @executable_path/Frameworks/libvitrinesim.dylib \
    "$DYLIB" 2>/dev/null
  if otool -L "$DYLIB" | grep -q CydiaSubstrate; then echo "the tweak still loads CydiaSubstrate" >&2; exit 1; fi
  "$ROOT/scripts/insert-dylib.py" "$APP/Spotify" @rpath/spotifyglass.dylib
  # The Info.plist keys pipeline.sh merges in (UIDesignRequiresCompatibility off among them), the same way.
  python3 -I - "$ROOT/plist/liquid-glass.plist" "$APP/Info.plist" <<'PY'
import plistlib, sys
overlay, app = (plistlib.load(open(p, 'rb')) for p in sys.argv[1:3])
services = list(app.get('NSBonjourServices', []))
overlay['NSBonjourServices'] = services + [s for s in overlay.get('NSBonjourServices', []) if s not in services]
if app.get('NSLocalNetworkUsageDescription'): overlay.pop('NSLocalNetworkUsageDescription', None)
app.update(overlay)
plistlib.dump(app, open(sys.argv[2], 'wb'))
PY
fi

echo "==> iOS -> iOS Simulator"
find "$APP" -type f | while read -r f; do
  file -b "$f" | grep -q '^Mach-O' || continue
  vtool -show-build "$f" | grep -q 'platform IOS$' || continue
  read -r minos sdk < <(vtool -show-build "$f" | awk '/minos/{m=$2} / sdk /{s=$2} END{print m, s}')
  vtool -set-build-version 7 "${minos:-16.0}" "${sdk:-26.0}" -replace -output "$f" "$f" 2>/dev/null
done

# Signed ad hoc, macOS refuses to spawn a process whose signature carries entitlements like
# application-identifier (error 163). The simulator reads them from __TEXT,__entitlements instead, the
# section Xcode links into simulator builds; without keychain-access-groups every keychain call fails
# (-34018) and Spotify quits on its own a few seconds in.
ENTS="$WORK/ents.plist"
cat > "$ENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>SIMULATOR0.com.spotify.client</string>
  <key>keychain-access-groups</key><array><string>SIMULATOR0.com.spotify.client</string></array>
  <key>com.apple.security.application-groups</key><array>
    <string>group.com.spotify.client.notification</string><string>group.com.spotify.client.widget</string>
    <string>group.com.spotify.client.widget.data</string><string>group.com.spotify.client.widget.lifecycle</string>
  </array>
</dict></plist>
EOF
python3 -I - "$APP/Spotify" __entitlements "$ENTS" <<'PY'
# Adds the section __TEXT,<name> holding <file> to a thin 64-bit Mach-O, in the free space before its first section.
import struct, sys
path, sect, src = sys.argv[1:4]
blob = open(src, "rb").read()
data = bytearray(open(path, "rb").read())
magic, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
assert magic == 0xFEEDFACF, "not a thin 64-bit Mach-O"
off, text, first = 32, None, len(data)
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from("<II", data, off)
    if cmd == 0x19:  # LC_SEGMENT_64
        if data[off + 8:off + 24].rstrip(b"\0") == b"__TEXT":
            text = off
        for s in range(struct.unpack_from("<I", data, off + 64)[0]):
            so = off + 72 + s * 80
            if data[so:so + 16].rstrip(b"\0") == sect.encode():
                sys.exit(f"    {sect} already there")
            if o := struct.unpack_from("<I", data, so + 48)[0]:
                first = min(first, o)
    off += cmdsize
end = 32 + sizeofcmds
dst = (first - len(blob) - 64) & ~15
if end + 80 > dst or any(data[end:end + 80]) or any(data[dst:dst + len(blob)]):
    sys.exit(f"{path}: no room for {sect}")
data[dst:dst + len(blob)] = blob
cmdsize = struct.unpack_from("<I", data, text + 4)[0]
vmaddr, fileoff = struct.unpack_from("<QQ", data, text + 24)[0], struct.unpack_from("<Q", data, text + 40)[0]
nsects = struct.unpack_from("<I", data, text + 64)[0]
# The section header goes after __TEXT's last one; every later load command moves down 80 bytes.
at = text + cmdsize
data[at + 80:end + 80] = data[at:end]
data[at:at + 80] = sect.encode().ljust(16, b"\0") + b"__TEXT".ljust(16, b"\0") + struct.pack(
    "<QQIIIIIIII", vmaddr + dst - fileoff, len(blob), dst, 0, 0, 0, 0, 0, 0, 0)
struct.pack_into("<I", data, text + 4, cmdsize + 80)
struct.pack_into("<I", data, text + 64, nsects + 1)
struct.pack_into("<I", data, 20, sizeofcmds + 80)
open(path, "wb").write(data)
print(f"    {sect} added")
PY

# Frameworks and dylibs first, the app last, so its seal covers their new signatures.
find "$APP/Frameworks" -depth 1 \( -name '*.framework' -o -name '*.dylib' \) -exec codesign -f -s - {} \; 2>/dev/null
codesign -f -s - "$APP" 2>/dev/null

UDID="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
want = sys.argv[1]
for rt, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["isAvailable"] and want in (d["name"], d["udid"]): print(d["udid"]); sys.exit()
' "$DEVICE")"
if [ -z "$UDID" ]; then
  RUNTIME="$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
print([r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]][-1]["identifier"])')"
  UDID="$(xcrun simctl create "$DEVICE" com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$RUNTIME")"
  echo "==> created simulator $DEVICE ($UDID)"
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "==> installing on $DEVICE ($UDID)"
# An install over the last one keeps its data (a login). CLEAN_DATA=1 starts from a fresh container.
[ -z "${CLEAN_DATA:-}" ] || xcrun simctl uninstall "$UDID" com.spotify.client 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
[ "$LAUNCH" = 1 ] || exit 0
xcrun simctl terminate "$UDID" com.spotify.client 2>/dev/null || true
xcrun simctl launch "$UDID" com.spotify.client
echo "log:        xcrun simctl spawn $UDID log stream --style compact --predicate 'process == \"Spotify\"'"
echo "screenshot: xcrun simctl io $UDID screenshot shot.png"
if [ "${SG_DRIVER:-0}" = 1 ]; then
  # scripts/phone.py starts iproxy to the phone when nothing answers on its port, so wait for the app's.
  for _ in $(seq 60); do nc -z 127.0.0.1 "$PORT" 2>/dev/null && break; sleep 0.5; done
  nc -z 127.0.0.1 "$PORT" 2>/dev/null && echo "driver:     PHONE_PORT=$PORT scripts/phone.py state" || echo "the driver did not open port $PORT" >&2
fi
