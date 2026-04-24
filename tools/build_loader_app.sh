#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/WMLShell.app"
EXECUTABLE_PATH="$BUILD_DIR/debug/WMLShell"
INFO_PLIST_SOURCE="$ROOT_DIR/macos/WMLShell-Info.plist"

cd "$ROOT_DIR"
swift build

mkdir -p "$DIST_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/WMLShell"
cp "$INFO_PLIST_SOURCE" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/WMLShell"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
