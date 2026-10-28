#!/bin/sh
# Builds the album credits check for the Mac: Redesigned/Album/AlbumCredits.m as the tweak compiles it.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
mkdir -p build
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 \
    check.m "$SRC"/Redesigned/Album/AlbumCredits.m -framework Foundation -o build/album-credits-check
echo "built build/album-credits-check"
