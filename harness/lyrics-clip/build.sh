#!/bin/sh
# Builds the lyrics clip harness for the Mac: SGLyricsClip.m as the tweak compiles it, and main.m. motion.m
# times the words over moving artwork against SGMotionClip.m's cut, which needs Protobuf.m to link.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -I ../../tweak/Sources \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreImage \
    -framework CoreText -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate \
    main.m motion.m ../../tweak/Sources/Shared/LockScreenLyrics/SGLyricsClip.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o build/lyrics-clip
