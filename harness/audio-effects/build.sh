#!/bin/sh
# Builds the audio effects harness for the Mac: the engine (tweak/Sources/Shared/AudioEffects) as the tweak
# compiles it, the third-party C it uses (vendor/audio, made here first) and main.m.
#   ./build.sh            build/audio-effects
#   ./build.sh thread     build/audio-effects-thread, under ThreadSanitizer
#   ./build.sh address    build/audio-effects-address, under AddressSanitizer
#   ./build.sh route      build/route-check, the corrections remembered per output (route.m)
set -e
cd "$(dirname "$0")"
if [ "$1" = route ]; then
    SRC=../../tweak/Sources
    FX=$SRC/Shared/AudioEffects
    mkdir -p build
    xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 -I ../autoeq/shim -I "$SRC" -I "$FX" \
        route.m "$FX"/AudioEffectsPresets.m "$FX"/AutoEq.m "$FX"/AudioEffectsSettings.m "$SRC"/Core/SGPrefs.m \
        -framework Foundation -o build/route-check
    echo "built build/route-check"
    exit
fi
VENDOR=../../vendor/audio
ENGINE=../../tweak/Sources/Shared/AudioEffects
SANITIZE=$1
make -s -C "$VENDOR" PLATFORM=mac ${SANITIZE:+SANITIZE=$SANITIZE} -j8
OUT=build/audio-effects${SANITIZE:+-$SANITIZE}
mkdir -p build
xcrun clang -fobjc-arc -O2 -g -Wall -Werror -target arm64-apple-macos13.0 ${SANITIZE:+-fsanitize=$SANITIZE -O1 -fno-omit-frame-pointer} \
    -I ../../tweak/Sources -isystem "$VENDOR/libbs2b" -isystem "$VENDOR/eel2-parser" -isystem "$VENDOR/wdl/eel2" \
    main.m "$ENGINE"/SGDSPEngine.m "$ENGINE"/SGDSPFilters.m "$ENGINE"/SGDSPConvolver.m "$ENGINE"/SGDSPTone.m "$ENGINE"/SGDSPDynamics.m \
    "$ENGINE"/SGDSPCrossfeed.m "$ENGINE"/SGDSPReverb.m "$ENGINE"/SGDSPLiveprog.m "$VENDOR/build/mac${SANITIZE:+-$SANITIZE}/libsgaudio.a" \
    -framework Foundation -framework AudioToolbox -framework Accelerate -o "$OUT"
echo "built $OUT"
