#!/bin/bash
# Builds a Release Coreplay.app for the Mac and packs it into build/Coreplay.dmg,
# with an Applications shortcut to drag it onto. The app is signed with the
# project's team (a free Personal Team), so it isn't notarized: it's for Macs
# you build on, not for sharing. The archive log goes to build/dmg-archive.log.
#
#   bash Tools/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
archive=build/Coreplay.xcarchive
staging=build/dmg-staging
dmg=build/Coreplay.dmg
rm -rf "$archive" "$staging" "$dmg"

if ! xcodebuild -project Coreplay.xcodeproj -scheme Coreplay -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -allowProvisioningUpdates archive > build/dmg-archive.log 2>&1; then
    grep ' error: ' build/dmg-archive.log | head -20 || tail -20 build/dmg-archive.log
    exit 1
fi

app="$archive/Products/Applications/Coreplay.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")

mkdir -p "$staging"
ditto "$app" "$staging/Coreplay.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Coreplay $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" > /dev/null
rm -rf "$staging"
hdiutil verify "$dmg" > /dev/null 2>&1
echo "$dmg (Coreplay $version)"
