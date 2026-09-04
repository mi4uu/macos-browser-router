#!/bin/bash
# Builds a universal (arm64 + x86_64) Browser Router.app and zips it for a release.
# Usage: ./release.sh [version]
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-0.0.0-dev}"
VERSION="${VERSION#v}"
APP="dist/Browser Router.app"
SOURCES=(Sources/L10n.swift Sources/Model.swift Sources/Rules.swift Sources/main.swift)

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/thin

for arch in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$arch-apple-macos14" "${SOURCES[@]}" -o "dist/thin/$arch"
done
lipo -create dist/thin/arm64 dist/thin/x86_64 -output "$APP/Contents/MacOS/BrowserRouter"
rm -rf dist/thin

cp Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

ditto -c -k --keepParent "$APP" "dist/BrowserRouter-$VERSION.zip"
echo "dist/BrowserRouter-$VERSION.zip"
