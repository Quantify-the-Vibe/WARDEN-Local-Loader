#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$("$ROOT_DIR/tools/build_loader_app.sh" | tail -n 1)"

open "$APP_PATH"
