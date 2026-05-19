#!/usr/bin/env bash
# sync-oauth.sh — pull the current Claude Code OAuth token into Shannon's .env.
#
# Reads accessToken from $HOME/.claude/.credentials.json (Claude Code's own
# credential store) and writes it as CLAUDE_CODE_OAUTH_TOKEN into
# <shannon-dir>/.env. Idempotent — safe to call before every scan start so a
# resumed run picks up a freshly-refreshed token instead of a stale one.
#
# Usage: sync-oauth.sh <shannon-dir>
#
# Env overrides:
#   CLAUDE_CREDENTIALS_FILE — path to credentials.json (default: ~/.claude/.credentials.json)
#
# Exit codes:
#   0  success — token written to <shannon-dir>/.env
#   1  credentials file missing/unreadable, or shannon-dir missing
#   2  bad usage
#   3  neither jq nor python3 available to parse JSON
#   4  accessToken not present in credentials file
#   5  token expired (expiresAt < now)

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

CRED="${CLAUDE_CREDENTIALS_FILE:-$HOME/.claude/.credentials.json}"
if [ ! -f "$CRED" ]; then
  echo "ERROR: Claude credentials not found at $CRED" >&2
  exit 1
fi
if [ ! -r "$CRED" ]; then
  echo "ERROR: cannot read $CRED (permissions?)" >&2
  exit 1
fi

extract() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$key // empty" "$CRED" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    CRED="$CRED" KEY="$key" python3 - <<'PY'
import json, os, sys
cred = os.environ['CRED']
key = os.environ['KEY'].lstrip('.')
try:
    with open(cred) as f:
        d = json.load(f)
except Exception as e:
    print('', end=''); sys.exit(0)
v = d
for p in key.split('.'):
    if isinstance(v, dict) and p in v:
        v = v[p]
    else:
        v = ''
        break
print(v if v not in (None, 'null') else '')
PY
  else
    return 3
  fi
}

TOKEN="$(extract '.claudeAiOauth.accessToken')"
if [ -z "$TOKEN" ]; then
  echo "ERROR: claudeAiOauth.accessToken not found in $CRED. Run 'claude /login' to authenticate." >&2
  exit 4
fi

EXPIRES_AT_MS="$(extract '.claudeAiOauth.expiresAt')"
if [ -n "$EXPIRES_AT_MS" ]; then
  NOW_MS="$(( $(date +%s) * 1000 ))"
  if [ "$EXPIRES_AT_MS" -lt "$NOW_MS" ] 2>/dev/null; then
    EXPIRED_AT="$(date -u -d "@$((EXPIRES_AT_MS/1000))" '+%FT%TZ' 2>/dev/null || echo unknown)"
    echo "ERROR: OAuth token expired at $EXPIRED_AT. Run 'claude /login' to refresh." >&2
    exit 5
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# write-env.sh handles the root → service-user re-exec and chmod 0600 itself.
# Suppress both stdout and stderr — with-shannon-user.sh logs the full exec
# argv (including the token value) to stderr, which would leak the secret to
# any caller that captures combined output. We re-emit our own safe summary
# below.
W_ERR="$(mktemp)"
if ! bash "$SCRIPT_DIR/write-env.sh" "$dir" CLAUDE_CODE_OAUTH_TOKEN "$TOKEN" >/dev/null 2>"$W_ERR"; then
  # Re-emit only sanitized stderr (strip lines containing the token).
  sed "s|$TOKEN|<redacted>|g" "$W_ERR" >&2
  rm -f "$W_ERR"
  echo "ERROR: write-env.sh failed while syncing CLAUDE_CODE_OAUTH_TOKEN" >&2
  exit 1
fi
rm -f "$W_ERR"

# Never echo the token. Just report the source + destination + a short fingerprint.
FP="$(printf '%s' "$TOKEN" | head -c 12)…$(printf '%s' "$TOKEN" | tail -c 4)"
echo "OK: synced CLAUDE_CODE_OAUTH_TOKEN ($FP) from $CRED -> $dir/.env"
exit 0
