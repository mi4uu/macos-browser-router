#!/bin/bash
# Browser Router installer — downloads the latest release into ~/Applications.
#   curl -fsSL https://raw.githubusercontent.com/mi4uu/macos-browser-router/main/install.sh | bash
set -euo pipefail

REPO="mi4uu/macos-browser-router"
APP_NAME="Browser Router.app"
DEST="$HOME/Applications"

[ "$(uname -s)" = "Darwin" ] || { echo "Browser Router is macOS only."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || { echo "macOS 14 or newer required (found $(sw_vers -productVersion))."; exit 1; }

echo "Looking up the latest release…"
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"browser_download_url"' | grep '\.zip"' | head -1 | cut -d'"' -f4)
[ -n "$url" ] || { echo "No release asset found — build from source: https://github.com/$REPO"; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $(basename "$url")…"
curl -fsSL "$url" -o "$tmp/app.zip"
ditto -x -k "$tmp/app.zip" "$tmp/unpacked"

mkdir -p "$DEST"
rm -rf "${DEST:?}/$APP_NAME"
ditto "$tmp/unpacked/$APP_NAME" "$DEST/$APP_NAME"

# The build is signed ad-hoc rather than notarized by Apple, so macOS would refuse to open
# a downloaded copy. Clearing the quarantine flag is the point of running this installer.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST/$APP_NAME"
open -a "$DEST/$APP_NAME"

cat <<EOF

Installed: $DEST/$APP_NAME

Next, in the menubar menu:
  1. "Set Browser Router as default browser…", confirm the macOS dialog
  2. Pick the browser your links should open in
EOF
