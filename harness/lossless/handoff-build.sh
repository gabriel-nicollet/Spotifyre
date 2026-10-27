#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT="$HERE/build/handoff"
APP="$OUT/LosslessHandoff.app"
mkdir -p "$APP" "$OUT/gen"
"${THEOS:?Set THEOS}/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/SpeedPitch.x" > "$OUT/gen/SpeedPitch.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g \
  -isysroot "$SDK" -I"$SRC" -I"$SRC/Shared/Player" -Wno-deprecated-declarations \
  "$HERE/handoff.m" "$HERE/../scene.m" "$OUT/gen/SpeedPitch.m" \
  "$SRC/Shared/Lossless/SGPreparedPCM.m" "$SRC/Shared/Lossless/SGPCMReplacement.m" \
  "$SRC/Shared/Player/SGTimePitch.m" "$SRC/Core/SGRebind.m" "$SRC/Core/SGLog.m" \
  "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGFlagForce.m" \
  -framework UIKit -framework Foundation -framework AVFoundation -framework AudioToolbox -framework QuartzCore \
  -o "$APP/LosslessHandoff"
ffmpeg -v error -y -f lavfi -i 'aevalsrc=0.08*sin(2*PI*440*t)|0.06*sin(2*PI*997*t):s=44100:d=12' -c:a flac -sample_fmt s16 "$APP/fixture.flac"
ffmpeg -v error -y -i "$APP/fixture.flac" -c:a alac -sample_fmt s32p "$APP/fixture.m4a"
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib,sys
p=Path(sys.argv[1])
info={'CFBundleExecutable':'LosslessHandoff','CFBundleIdentifier':'dev.vitrine.lossless-handoff',
 'CFBundleName':'LosslessHandoff','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','UILaunchScreen':{},
 'UIApplicationSceneManifest':{'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[
 {'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SGRHarnessScene'}]}}}
(p/'Info.plist').write_bytes(plistlib.dumps(info))
PY
printf '%s\n' "$APP"
