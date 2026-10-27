#!/usr/bin/env bash
# Signs an IPA, or an app folder, with your own certificate and installs it on the paired iPhone, over USB
# or the network, through Xcode's devicectl.
#
#   scripts/install.sh out/<name>.ipa
#   scripts/install.sh out/quick/Payload/Spotify.app    # signed in place; scripts/quick.sh does this
#
# Put the certificate details in .signing.env (gitignored):
#   SIGN_P12=/path/to/cert.p12
#   SIGN_PROFILE=/path/to/profile.mobileprovision
#   SIGN_P12_PASSWORD=...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.signing.env" ] && . "$ROOT/.signing.env"
cd "$ROOT"
: "${SIGN_P12:?set SIGN_P12 in .signing.env}" "${SIGN_PROFILE:?set SIGN_PROFILE in .signing.env}" "${SIGN_P12_PASSWORD:?set SIGN_P12_PASSWORD in .signing.env}"

IN="${1:?usage: $0 <ipa or .app folder>}"
# A folder is signed where it is, and zsign then re-signs only what changed since its last signing.
if [ -d "$IN" ]; then SIGNED="$IN"; else SIGNED="${IN%.ipa}-signed.ipa"; fi

command -v zsign >/dev/null || { echo "missing zsign -> brew install zsign" >&2; exit 1; }

# The bundle id has to equal the App ID of the profile. iOS may well install a mismatched pair, but
# MediaRemote launches the now playing app by its application-identifier entitlement rather than by
# CFBundleIdentifier, so tapping the lock screen card then asks for a bundle that does not exist and
# nothing opens. A wildcard App ID needs no rewrite: the entitlement takes the IPA's own bundle id.
PROFILE_PLIST="$(mktemp)"
security cms -D -i "$SIGN_PROFILE" > "$PROFILE_PLIST" 2>/dev/null
APP_ID="$(plutil -extract Entitlements.application-identifier raw -o - "$PROFILE_PLIST" 2>/dev/null || true)"
rm -f "$PROFILE_PLIST"
APP_ID="${APP_ID#*.}"

sign() {  # sign [bundle id]
  echo "==> signing${1:+ as $1}"
  if [ -d "$IN" ]; then
    zsign -k "$SIGN_P12" -p "$SIGN_P12_PASSWORD" -m "$SIGN_PROFILE" ${1:+-b "$1"} "$IN" >/dev/null
  else
    zsign -k "$SIGN_P12" -p "$SIGN_P12_PASSWORD" -m "$SIGN_PROFILE" ${1:+-b "$1"} -z 1 -o "$SIGNED" "$IN" >/dev/null
  fi
}

if [ -n "$APP_ID" ] && [ "$APP_ID" != "*" ]; then sign "$APP_ID"; else sign; fi
# The paired iPhone's UDID; its state reads "connected" over USB and "available (paired)" over Wi-Fi.
phone() { xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && (/connected/ || /available/) { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]+-[0-9A-F]+$/) { print $i; exit } }'; }

# An install waits on the app while it runs, so a copy already on the phone is quit first.
quit_app() {
  [ -n "$APP_ID" ] && [ "$APP_ID" != "*" ] || return 0
  local udid="$UDID" apps procs pid
  apps="$(mktemp)"; procs="$(mktemp)"
  xcrun devicectl device info apps --device "$udid" --bundle-id "$APP_ID" --json-output "$apps" >/dev/null 2>&1 || true
  xcrun devicectl device info processes --device "$udid" --json-output "$procs" >/dev/null 2>&1 || true
  pid="$(python3 - "$apps" "$procs" <<'PY' 2>/dev/null || true
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
if apps:
    for p in json.load(open(sys.argv[2]))["result"]["runningProcesses"]:
        if p.get("executable", "").startswith(apps[0]["url"]):
            print(p["processIdentifier"])
            break
PY
)"
  rm -f "$apps" "$procs"
  [ -n "$pid" ] || return 0
  echo "==> quitting the running app ($pid)"
  xcrun devicectl device process terminate --device "$udid" --pid "$pid" >/dev/null 2>&1 || true
}

UDID="$(phone)"
[ -n "$UDID" ] || { echo "no paired iPhone over USB or the network" >&2; exit 1; }
quit_app
echo "==> installing $SIGNED to $UDID"
out="$(xcrun devicectl device install app --device "$UDID" "$SIGNED" 2>&1)" || { printf '%s\n' "$out" | grep -iE "error|reason|description" | head -5 >&2; exit 1; }
printf '%s\n' "$out" | grep -E "installationURL" | tail -1
