#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_TAG="${1:-dev}"
ARTIFACTS_DIR="$ROOT_DIR/artifacts/$VERSION_TAG"

APP_PATH="$("$ROOT_DIR/tools/build_loader_app.sh" | tail -n 1)"
BIN_PATH="$ROOT_DIR/.build/debug/WMLShell"

rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

cp -R "$APP_PATH" "$ARTIFACTS_DIR/WMLShell.app"
cp "$BIN_PATH" "$ARTIFACTS_DIR/WMLShell-$VERSION_TAG-macos"
chmod +x "$ARTIFACTS_DIR/WMLShell-$VERSION_TAG-macos"

ditto -c -k --sequesterRsrc --keepParent \
  "$ARTIFACTS_DIR/WMLShell.app" \
  "$ARTIFACTS_DIR/WMLShell-$VERSION_TAG-macos.app.zip"

(
  cd "$ARTIFACTS_DIR"
  shasum -a 256 "WMLShell-$VERSION_TAG-macos.app.zip" "WMLShell-$VERSION_TAG-macos" > SHA256SUMS.txt
)

echo "$ARTIFACTS_DIR"
