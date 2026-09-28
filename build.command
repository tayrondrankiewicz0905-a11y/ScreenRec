#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "🔨 Building ScreenRec…"
swift build -c release

APP="$ROOT/ScreenRec.app"
rm -rf "$APP"

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp ".build/release/ScreenRec" "$APP/Contents/MacOS/ScreenRec"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

chmod +x "$APP/Contents/MacOS/ScreenRec"

codesign --force --deep --sign - "$APP"

echo "✅ Created: $APP"
