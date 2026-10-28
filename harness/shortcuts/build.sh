#!/bin/sh
# Builds the shortcuts harness for the simulator, LiveActivityShared.swift as the tweak compiles it with
# main.swift and observer.m, and runs it on the simulator named by SIM (a UDID), which must be booted.
set -e
cd "$(dirname "$0")"
mkdir -p build
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios18.0-simulator -isysroot "$SDK" -fobjc-arc -Wall -Werror \
    -c observer.m -o build/observer.o
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios18.0-simulator -sdk "$SDK" -parse-as-library \
    -import-objc-header observer.h main.swift ../../tweak/Sources/Shared/LiveActivity/LiveActivityShared.swift \
    build/observer.o -o build/shortcuts
echo "built build/shortcuts"
if [ -n "$SIM" ]; then xcrun simctl spawn "$SIM" "$PWD/build/shortcuts"; fi
