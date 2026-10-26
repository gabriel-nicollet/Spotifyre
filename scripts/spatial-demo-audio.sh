#!/usr/bin/env bash
# Add the supplied two-stem Spatial Voice demo to the built Spotify app.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$1"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
APP_DIR="$(unzip -Z1 "$OUT" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_DIR" ] || { echo "no Payload/*.app in $OUT" >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BUNDLE="${APP_DIR}SpotifyreDemo.bundle"
mkdir -p "$WORK/$BUNDLE"
cp "$ROOT/assets/spatial-demo/Vocals.m4a" "$WORK/$BUNDLE/Vocals.m4a"
cp "$ROOT/assets/spatial-demo/Soundtrack.m4a" "$WORK/$BUNDLE/Soundtrack.m4a"
(cd "$WORK" && zip -q "$OUT_ABS" "$BUNDLE/Vocals.m4a" "$BUNDLE/Soundtrack.m4a")
echo "    demo stems included"