#!/bin/bash
# Builds Browser Router.app and installs it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Browser Router.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ARCH="$(uname -m)"   # arm64 or x86_64
swiftc -swift-version 5 -O -target "$ARCH-apple-macos14" \
    Sources/L10n.swift Sources/Model.swift Sources/Rules.swift Sources/main.swift \
    -o "$APP/Contents/MacOS/BrowserRouter"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/"Browser Router.app"
cp -R "$APP" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f ~/Applications/"Browser Router.app"

echo "Installed: ~/Applications/Browser Router.app"
