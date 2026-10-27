#!/bin/sh
# Builds the moving artwork harness for the Mac: SGMotionClip.m as the tweak compiles it, with the
# protobuf reader it uses, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics \
    main.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o build/motion
