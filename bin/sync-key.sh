#!/usr/bin/env bash
# sync-key.sh — sync a standalone ANTHROPIC_API_KEY into Shannon's .env.
#
# Lets users avoid sharing the Claude Code OAuth rate-limit pool with the
# main session. If they drop a plaintext key at one of the standard search
# paths, Shannon will use it instead of the OAuth token.
#
# Search order (first hit wins):
#   $SHANNON_API_KEY_FILE                 (env override)
#   $HOME/.claude/keys/shannon.key
#   $HOME/.claude/keys/anthropic.key
#
# Usage: sync-key.sh <shannon-dir>
#
# Exit codes:
#   0  success — key synced to <shannon-dir>/.env
#   1  fs error
#   2  bad usage
#   4  no key file found at any search path (caller should fall back)

set -uo pipefail

dir="${1:-}"
if [ -z "$dir" ]; then
  echo "usage: $0 <shannon-dir>" >&2
  exit 2
fi
if [ ! -d "$dir" ]; then
  echo "ERROR: shannon dir '$dir' does not exist." >&2
  exit 1
fi

# Build search list. Honor env override first, then standard locations.
candidates=()
[ -n "${SHANNON_API_KEY_FILE:-}" ] && candidates+=("$SHANNON_API_KEY_FILE")
candidates+=("$HOME/.claude/keys/shannon.key")
candidates+=("$HOME/.claude/keys/anthropic.key")

key_file=""
for c in "${candidates[@]}"; do
  if [ -f "$c" ] && [ -r "$c" ]; then
    key_file="$c"
    break
  fi
done

if [ -z "$key_file" ]; then
  # Quiet exit — caller decides whether to surface this. No key file is the
  # common case for new users; we don't want to spam stderr.
  exit 4
fi

# Read first non-empty, non-comment line as the key. Strip whitespace.
KEY="$(grep -vE '^[[:space:]]*(#|$)' "$key_file" | head -n1 | tr -d '\r\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

if [ -z "$KEY" ]; then
  echo "ERROR: $key_file is empty or only contains comments." >&2
  exit 4
fi

# Sanity check — Anthropic keys start with sk-ant-. Don't enforce, just warn.
case "$KEY" in
  sk-ant-*) ;;
  *) echo "WARNING: key at $key_file does not start with 'sk-ant-'; using it anyway." >&2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Same stderr-capture trick as sync-oauth.sh — with-shannon-user.sh logs argv
# to stderr, which would leak the key. Sanitize before re-emit.
W_ERR="$(mktemp)"
if ! bash "$SCRIPT_DIR/write-env.sh" "$dir" ANTHROPIC_API_KEY "$KEY" >/dev/null 2>"$W_ERR"; then
  sed "s|$KEY|<redacted>|g" "$W_ERR" >&2
  rm -f "$W_ERR"
  echo "ERROR: write-env.sh failed while syncing ANTHROPIC_API_KEY" >&2
  exit 1
fi
rm -f "$W_ERR"

FP="$(printf '%s' "$KEY" | head -c 12)…$(printf '%s' "$KEY" | tail -c 4)"
echo "OK: synced ANTHROPIC_API_KEY ($FP) from $key_file -> $dir/.env"
exit 0
