#!/bin/sh
# Builds the download check (main.m) for the Mac, through Mac Catalyst since Sing.h imports UIKit: SGSingModel.m
# as the tweak compiles it, with shim/Core/SGCore.h standing in for the mod's core.
#   ./build.sh && CFFIXED_USER_HOME="$(mktemp -d)" ../build/download 0.2
set -e
cd "$(dirname "$0")"
SRC=../../../tweak/Sources
mkdir -p ../build
xcrun clang -fobjc-arc -O1 -g -Wall -Werror -target arm64-apple-ios18.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -I shim -I "$SRC" main.m "$SRC/Shared/Sing/SGSingModel.m" \
    -framework Foundation -o ../build/download
echo "built ../build/download"
