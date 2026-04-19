#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.local"

if [[ -f "$ENV_FILE" ]] && rg -q '^W4L_API_TOKEN=' "$ENV_FILE"; then
  echo "W4L_API_TOKEN already configured in $ENV_FILE"
  exit 0
fi

if command -v openssl >/dev/null 2>&1; then
  TOKEN="$(openssl rand -hex 32)"
else
  TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
fi

umask 077
{
  echo "W4L_API_TOKEN=$TOKEN"
  echo "W4L_OPENAI_BRIDGE_AUTOLOAD=0"
} >> "$ENV_FILE"

chmod 600 "$ENV_FILE"
echo "Configured W4L_API_TOKEN in $ENV_FILE"
echo "Restart loader with ./run-loader-app.sh to apply."
