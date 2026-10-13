#!/bin/bash
# Builds Coreplay for macOS and the iOS Simulator, then runs the package tests.
# Full logs go to build/ (ignored by git); build/summary.txt has one line per step.
#
#   bash Tools/build-check.sh
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
summary=build/summary.txt
: > "$summary"

step() {
    # step <name> <xcodebuild arguments...>
    local name=$1
    shift
    local started
    started=$(date +%s)
    if xcodebuild -project Coreplay.xcodeproj -scheme Coreplay "$@" > "build/$name.log" 2>&1; then
        echo "$name: ok ($(( $(date +%s) - started ))s)" >> "$summary"
        return 0
    fi
    local errors
    errors=$(grep -c ' error: ' "build/$name.log")
    echo "$name: FAILED, $errors error lines ($(( $(date +%s) - started ))s)" >> "$summary"
    return 1
}

step mac build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
mac=$?
step ios build -destination 'generic/platform=iOS Simulator' ARCHS=arm64
if [ "$mac" -eq 0 ]; then
    step test test -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO
else
    echo "test: skipped because the macOS build failed" >> "$summary"
fi
cat "$summary"
