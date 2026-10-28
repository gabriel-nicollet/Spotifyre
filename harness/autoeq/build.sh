#!/bin/sh
# Builds the presets and AutoEq check for the Mac: AudioEffectsPresets.m, AutoEq.m, AudioEffectsSettings.m and
# Core/SGPrefs.m as the tweak compiles them, shim/ standing in for SGCore.h's UIKit half.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
FX=$SRC/Shared/AudioEffects
mkdir -p build
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 -I shim -I "$SRC" -I "$FX" \
    check.m "$FX"/AudioEffectsPresets.m "$FX"/AutoEq.m "$FX"/AudioEffectsSettings.m "$SRC"/Core/SGPrefs.m \
    -framework Foundation -o build/autoeq-check
echo "built build/autoeq-check"
