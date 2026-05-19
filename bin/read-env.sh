#!/usr/bin/env bash
# read-env.sh — report which AI provider credentials are present in <shannon-dir>/.env
# Usage: read-env.sh <shannon-dir>
# Output (one or more lines, each is KEY=present, or single line "none"):
#   ANTHROPIC_API_KEY=present
#   CLAUDE_CODE_OAUTH_TOKEN=present
#   AWS_BEDROCK=present
#   GOOGLE_VERTEX=present

set -u

SHANNON_DIR="${1:-./shannon}"
ENV_FILE="$SHANNON_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "none"
  exit 0
fi

found_any=0

check_key() {
  local key="$1"
  if grep -qE "^${key}=[^[:space:]]" "$ENV_FILE"; then
    echo "${key}=present"
    found_any=1
  fi
}

# Single-key providers
check_key ANTHROPIC_API_KEY
check_key CLAUDE_CODE_OAUTH_TOKEN

# Bedrock = needs all three of these (region optional but typical)
if grep -qE '^AWS_ACCESS_KEY_ID=[^[:space:]]' "$ENV_FILE" \
   && grep -qE '^AWS_SECRET_ACCESS_KEY=[^[:space:]]' "$ENV_FILE"; then
  echo "AWS_BEDROCK=present"
  found_any=1
fi

# Vertex = GOOGLE_APPLICATION_CREDENTIALS or VERTEX_AI_*
if grep -qE '^(GOOGLE_APPLICATION_CREDENTIALS|VERTEX_AI_PROJECT)=[^[:space:]]' "$ENV_FILE"; then
  echo "GOOGLE_VERTEX=present"
  found_any=1
fi

if [ "$found_any" -eq 0 ]; then
  echo "none"
fi
