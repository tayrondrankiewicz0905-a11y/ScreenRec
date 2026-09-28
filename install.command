#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/build.command"

TARGET="/Applications/ScreenRec.app"
rm -rf "$TARGET"
cp -R "$ROOT/ScreenRec.app" "$TARGET"

echo "✅ ScreenRec wurde nach /Applications installiert."
open "$TARGET"
