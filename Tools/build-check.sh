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
# Which libVLC modules the VLCKit binary carries, and its headers, for
# checking network and casting support without guessing.
vlckit=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*VLCKit.xcframework/macos*" -name VLCKit -type f 2>/dev/null | head -1)
if [ -n "$vlckit" ]; then
    {
        echo "$vlckit"
        strings -a "$vlckit" | grep -iE "smb|sftp|libssh|nfs|upnp|dlna|ftp|microdns|chromecast|bonjour|netbios|rtsp|rtmp|mms:|srt|webdav|--enable-|--disable-" | sort -u
    } > build/vlckit-modules.txt
    mkdir -p build/vlckit-headers && cp -R "$(dirname "$vlckit")/Headers/." build/vlckit-headers/ 2>/dev/null
fi
cat "$summary"
