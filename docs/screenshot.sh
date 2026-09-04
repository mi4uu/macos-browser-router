#!/bin/bash
# Takes a screenshot 10 seconds from now, so there is time to open the menu.
# Usage: ./docs/screenshot.sh menu
set -euo pipefail
name="${1:-menu}"
cd "$(dirname "$0")"
echo "Open the menu you want captured — shooting in 10 seconds…"
screencapture -T 10 -x "$name.png"
echo "Saved: docs/$name.png"
