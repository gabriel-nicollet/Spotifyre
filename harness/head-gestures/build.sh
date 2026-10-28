#!/bin/sh
# Builds the AirPods gestures harness for the Mac: SGHeadDetector.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/HeadGestures/SGHeadDetector.m -o build/head-gestures
echo "built build/head-gestures"
