#!/bin/sh
# Builds CleanLinks.x's hooks with the check in sim/ for the iOS simulator and runs it in the booted one, or in the
# simulator named by SIM (a UDID): logos.pl's internal generator, so no substrate is needed.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
mkdir -p build/gen
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/Privacy/CleanLinks.x" > build/gen/CleanLinks.m
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O0 -g -isysroot "$SDK" \
    -I "$SRC" -I "$SRC/Shared/Privacy" \
    sim/main.m build/gen/CleanLinks.m "$SRC"/Shared/Privacy/CleanLinks.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLog.m \
    -framework UIKit -framework Foundation -o build/clean-links-sim
xcrun simctl spawn "${SIM:-booted}" "$PWD/build/clean-links-sim"
