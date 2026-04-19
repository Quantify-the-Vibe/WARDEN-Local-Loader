#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_TAG="${1:-dev}"
ARTIFACTS_DIR="$ROOT_DIR/artifacts/$VERSION_TAG"

APP_PATH="$("$ROOT_DIR/tools/build_loader_app.sh" | tail -n 1)"
BIN_PATH="$ROOT_DIR/.build/debug/LoaderShell"

rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

cp -R "$APP_PATH" "$ARTIFACTS_DIR/LoaderShell.app"
cp "$BIN_PATH" "$ARTIFACTS_DIR/LoaderShell-$VERSION_TAG-macos"
chmod +x "$ARTIFACTS_DIR/LoaderShell-$VERSION_TAG-macos"

ditto -c -k --sequesterRsrc --keepParent \
  "$ARTIFACTS_DIR/LoaderShell.app" \
  "$ARTIFACTS_DIR/LoaderShell-$VERSION_TAG-macos.app.zip"

(
  cd "$ARTIFACTS_DIR"
  shasum -a 256 "LoaderShell-$VERSION_TAG-macos.app.zip" "LoaderShell-$VERSION_TAG-macos" > SHA256SUMS.txt
)

echo "$ARTIFACTS_DIR"
