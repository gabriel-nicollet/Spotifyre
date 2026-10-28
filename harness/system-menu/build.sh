#!/bin/sh
# Builds the system menu harness for the simulator: ContextMenu.x's hooks and PlayerMenu.m run for real
# on a mock of Spotify's context menu sheet.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/SystemMenuHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Redesigned/ContextMenu/ContextMenu.x" > "$OUT/gen/ContextMenu.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.4-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/ContextMenu" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" "$(dirname "$0")/../tabbar/touch.m" "$OUT"/gen/*.m "$SRC"/Redesigned/Player/PlayerMenu.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework IOKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/SystemMenuHarness.app/SystemMenuHarness"

cat > "$OUT/SystemMenuHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SystemMenuHarness</string>
<key>CFBundleIdentifier</key><string>com.vitrine.systemmenuharness</string>
<key>CFBundleName</key><string>SystemMenuHarness</string>
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
echo "built $OUT/SystemMenuHarness.app"
