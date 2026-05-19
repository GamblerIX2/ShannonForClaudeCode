#!/usr/bin/env bash
# write-env.sh — set KEY=VALUE in <shannon-dir>/.env (idempotent, replaces existing).
# Usage: write-env.sh <shannon-dir> <KEY> <VALUE>

set -euo pipefail

SHANNON_DIR="$1"
KEY="$2"
VALUE="$3"

ENV_FILE="$SHANNON_DIR/.env"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

# When root, drop to the service user so the file ends up readable by the
# user that later runs Shannon (mode 0600 + root-owned would lock them out).
if [ "$(id -u)" -eq 0 ]; then
  exec "$SCRIPT_DIR/with-shannon-user.sh" "$SHANNON_DIR" "" -- "$0" "$SHANNON_DIR" "$KEY" "$VALUE"
fi

touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Remove any existing line for this key, then append.
# Using awk avoids sed-quoting headaches for values containing slashes etc.
TMP="$(mktemp)"
awk -v k="$KEY" 'BEGIN{re="^"k"="} $0 !~ re {print}' "$ENV_FILE" > "$TMP"
mv "$TMP" "$ENV_FILE"
chmod 600 "$ENV_FILE"

# Append the new value. Quote the value to handle spaces.
printf '%s=%s\n' "$KEY" "$VALUE" >> "$ENV_FILE"

echo "Set $KEY in $ENV_FILE"
