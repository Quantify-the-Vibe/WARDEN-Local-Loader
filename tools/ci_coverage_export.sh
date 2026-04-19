#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/artifacts/coverage"

cd "$ROOT_DIR"
swift test --parallel --enable-code-coverage

PROFDATA_PATH="$(find "$ROOT_DIR/.build" -name default.profdata | head -n 1)"
TEST_BINARY_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/debug/*.xctest/Contents/MacOS/*PackageTests" ! -path "*.dSYM*" | head -n 1)"

if [[ -z "$PROFDATA_PATH" || -z "$TEST_BINARY_PATH" ]]; then
  echo "Coverage artifacts not found. profdata='$PROFDATA_PATH' testbin='$TEST_BINARY_PATH'" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

xcrun llvm-cov report \
  "$TEST_BINARY_PATH" \
  -instr-profile "$PROFDATA_PATH" > "$OUT_DIR/coverage-summary.txt"

xcrun llvm-cov export \
  -format=lcov \
  "$TEST_BINARY_PATH" \
  -instr-profile "$PROFDATA_PATH" > "$OUT_DIR/coverage.lcov"

cp "$PROFDATA_PATH" "$OUT_DIR/default.profdata"

echo "$OUT_DIR"
