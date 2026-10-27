#!/bin/sh
# Builds the sleep timer harness for the Mac: SleepTimer.m as the tweak compiles it, the UIKit headers it
# imports stood in for by stub/, SpotifySleepTimer.m (Spotify's own timer followed) and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I stub -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/Player/SleepTimer.m ../../tweak/Sources/Shared/Player/SpotifySleepTimer.m \
    -o build/sleep-timer
echo "built build/sleep-timer"
