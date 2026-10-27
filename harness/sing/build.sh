#!/bin/sh
# Builds the Sing harness for the Mac: the loader, the separator and the engine (tweak/Sources/Shared/Sing) as the
# tweak compiles them, and main.m, with shim/Core/SGLog.h printing their log lines.
#   ./build.sh            build/sing
#   ./build.sh thread     build/sing-thread, under ThreadSanitizer
set -e
cd "$(dirname "$0")"
SING=../../tweak/Sources/Shared/Sing
SANITIZE=$1
OUT=build/sing${SANITIZE:+-$SANITIZE}
mkdir -p build
xcrun clang -fobjc-arc -O2 -g -Wall -Werror -target arm64-apple-macos15.0 ${SANITIZE:+-fsanitize=$SANITIZE -O1 -fno-omit-frame-pointer} \
    -I shim -I ../../tweak/Sources main.m "$SING"/SGSingLoader.m "$SING"/SGSingSeparator.m "$SING"/SGSingEngine.m \
    ../../tweak/Sources/Shared/AudioEffects/SGDSPReverb.m \
    -framework Foundation -framework AudioToolbox -framework Accelerate -framework CoreML -o "$OUT"
echo "built $OUT"
