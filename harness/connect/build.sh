#!/bin/sh
# Builds the Connect discovery harness for the Mac: SGMDNS.m and SGConnectRelay.m as the tweak compiles
# them, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/Connect/SGMDNS.m ../../tweak/Sources/Shared/Connect/SGConnectRelay.m -o build/connect
echo "built build/connect"
