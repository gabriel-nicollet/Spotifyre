#!/bin/sh
# build-sim.sh: builds the Edit info harness for the simulator (EditInfoMenu.x and LocalFiles.m as the
# tweak compiles them) and, given a booted simulator's UDID, installs it, runs it and saves a screenshot
# at each SHOT into ../build/sim/shots/. `large` as a second argument runs it once at the largest accessibility
# text size and sets the size back after.
#
#     THEOS=$HOME/theos ./build-sim.sh [<udid> [large]]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../../tweak/Sources" && pwd)
OUT="$HERE/../build/sim"   # harness/*/build/ is ignored
rm -rf "$OUT/gen" "$OUT/EditInfoHarness.app"; mkdir -p "$OUT/gen" "$OUT/EditInfoHarness.app" "$OUT/shots"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/LocalFiles/EditInfoMenu.x" > "$OUT/gen/EditInfoMenu.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 -Wall \
    -I"$SRC" -I"$SRC/Shared/LocalFiles" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../../scene.m" "$OUT/gen/EditInfoMenu.m" "$SRC/Shared/LocalFiles/LocalFiles.m" "$SRC/Core/SGLog.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework UniformTypeIdentifiers -framework Foundation \
    -o "$OUT/EditInfoHarness.app/EditInfoHarness"
cat > "$OUT/EditInfoHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EditInfoHarness</string>
<key>CFBundleIdentifier</key><string>com.vitrine.editinfoharness</string>
<key>CFBundleName</key><string>EditInfoHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "built $OUT/EditInfoHarness.app"
[ -n "$1" ] || exit 0
UDID=$1
xcrun simctl install "$UDID" "$OUT/EditInfoHarness.app"
[ "$2" = large ] && xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
xcrun simctl launch --console-pty "$UDID" com.vitrine.editinfoharness $2 2>&1 | tr -ud '\r' | while IFS= read -r line; do
    echo "$line"
    case "$line" in *"[harness] SHOT "*) xcrun simctl io "$UDID" screenshot "$OUT/shots/${line##*SHOT }.png" >/dev/null 2>&1 & ;; esac
done
[ "$2" = large ] && xcrun simctl ui "$UDID" content_size large
exit 0
