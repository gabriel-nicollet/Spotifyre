#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${LOSSLESS_PROBE_OUT:-"$HERE/build"}
APP="$OUT/LosslessProbe.app"
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios16.1-simulator -fobjc-arc -O1 \
    -isysroot "$SDK" -Wno-deprecated-declarations "$HERE/main.m" "$HERE/../scene.m" \
    -framework UIKit -framework Foundation -framework AVFoundation -framework AudioToolbox \
    -framework CoreMedia -o "$APP/LosslessProbe"
for NAME in cd hires alac; do
    case "$NAME" in
        cd) RATE=44100; CODEC=flac; FORMAT=s16; EXT=flac ;;
        hires) RATE=96000; CODEC=flac; FORMAT=s32; EXT=flac ;;
        alac) RATE=48000; CODEC=alac; FORMAT=s32p; EXT=m4a ;;
    esac
    ffmpeg -v error -y -f lavfi \
        -i "aevalsrc=0.08*sin(2*PI*440*t)|0.06*sin(2*PI*997*t):s=$RATE:d=12" \
        -c:a "$CODEC" -sample_fmt "$FORMAT" "$APP/$NAME.$EXT"
done
ffmpeg -v error -y -i "$APP/alac.m4a" -c:a copy -movflags +faststart "$APP/alac-fast.m4a"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LosslessProbe</string>
<key>CFBundleIdentifier</key><string>dev.vitrine.lossless-probe</string>
<key>CFBundleName</key><string>LosslessProbe</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>UIApplicationSceneManifest</key><dict>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "$APP"
