#!/bin/sh
# Builds the clean shared links check for the Mac: Shared/Privacy/CleanLinks.m as the tweak compiles it, shim/
# standing in for Privacy.h's UIKit.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
mkdir -p build
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 -I shim -I "$SRC" -I "$SRC/Shared/Privacy" \
    check.m "$SRC"/Shared/Privacy/CleanLinks.m -framework Foundation -o build/clean-links-check
echo "built build/clean-links-check"
