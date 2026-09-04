#!/bin/bash
# Points the Homebrew cask at a released version.
# Usage: ./scripts/bump-cask.sh 0.2.0 [path-to-tap-checkout]
set -euo pipefail

VERSION="${1:?usage: bump-cask.sh <version> [tap-dir]}"
VERSION="${VERSION#v}"
TAP="${2:-$(brew --repository)/Library/Taps/mi4uu/homebrew-tap}"
CASK="$TAP/Casks/browser-router.rb"
URL="https://github.com/mi4uu/macos-browser-router/releases/download/v$VERSION/BrowserRouter-$VERSION.zip"

[ -f "$CASK" ] || { echo "Cask not found: $CASK"; exit 1; }

echo "Hashing $URL"
SHA=$(curl -fsSL "$URL" | shasum -a 256 | cut -d' ' -f1)

/usr/bin/sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
                   -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

git -C "$TAP" commit -qam "browser-router $VERSION" && git -C "$TAP" push -q
echo "Cask updated to $VERSION ($SHA)"
