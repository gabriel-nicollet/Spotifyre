#!/bin/sh
# Builds the listening stats harness for the Mac: SGPlayLog.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/ListeningStats/SGPlayLog.m -o build/listening-stats
