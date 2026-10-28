#!/bin/sh
# Builds the phone driver harness for the simulator: Diagnostics.x's tree server and Driver.m, as a FLEX build
# compiles them (SG_DRIVER=1), on a mock app (main.m). It serves on 127.0.0.1:8095 (PORT=), not the phone's
# 8085, so an iproxy to the phone keeps its port.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/DriverHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Diagnostics/Diagnostics.x" > "$OUT/gen/Diagnostics.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.4-simulator -fobjc-arc -g -O0 -DSG_DRIVER=1 -DSG_TREE_PORT=${PORT:-8095} \
    -I"$SRC" -I"$SRC/Diagnostics" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" "$OUT"/gen/*.m "$SRC"/Diagnostics/Driver.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGViewTree.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/DriverHarness.app/DriverHarness"

cat > "$OUT/DriverHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DriverHarness</string>
<key>CFBundleIdentifier</key><string>com.vitrine.driverharness</string>
<key>CFBundleName</key><string>DriverHarness</string>
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
echo "built $OUT/DriverHarness.app"
