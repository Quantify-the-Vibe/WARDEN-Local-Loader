#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="${1:-$ROOT_DIR/.build/debug/LoaderShell}"
STATUS_URL="http://127.0.0.1:8787/status"
LOG_PATH="$ROOT_DIR/artifacts/ci-smoke-loader.log"

mkdir -p "$(dirname "$LOG_PATH")"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Smoke test binary missing or not executable: $BIN_PATH" >&2
  exit 1
fi

"$BIN_PATH" >"$LOG_PATH" 2>&1 &
LOADER_PID=$!

cleanup() {
  if kill -0 "$LOADER_PID" >/dev/null 2>&1; then
    kill "$LOADER_PID" >/dev/null 2>&1 || true
    wait "$LOADER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for _ in {1..30}; do
  if RESPONSE="$(curl -fsS "$STATUS_URL" 2>/dev/null)"; then
    if [[ "$RESPONSE" == *"runtime_state"* ]]; then
      echo "Smoke status probe passed: $STATUS_URL"
      exit 0
    fi
  fi
  sleep 1
done

echo "Smoke status probe failed: $STATUS_URL" >&2
echo "Loader log tail:" >&2
tail -n 60 "$LOG_PATH" >&2 || true
exit 1
