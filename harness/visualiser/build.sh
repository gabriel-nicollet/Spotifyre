#!/bin/sh
# Builds the Visualizer's spectrum check for the Mac: SGRSpectrum.m as the tweak compiles it, under main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation -framework Accelerate \
    main.m ../../tweak/Sources/Redesigned/Player/SGRSpectrum.m -o build/spectrum
echo "built build/spectrum"
