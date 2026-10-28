#!/bin/sh
# Builds the palette check for the Mac (Mac Catalyst, for UIKit): Redesigned/Kit/SGRPalette.m as the tweak compiles it.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
SDK=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p build
xcrun clang -fobjc-arc -O0 -g -target arm64-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -isystem "$SDK/System/iOSSupport/usr/include" \
    -I"$SRC" check.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m \
    -framework UIKit -framework CoreImage -framework CoreGraphics -framework QuartzCore -o build/palette-check
echo "built build/palette-check"
