#!/usr/bin/env bash
# workspace-name.sh — derive a deterministic Shannon workspace name from a URL.
#
# Same target URL → same name, so Shannon's built-in resume (-w <name>) picks
# up where a prior run left off instead of creating a new workspace and
# re-running already-completed agents.
#
# Usage: workspace-name.sh <target-url>

set -uo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "usage: $0 <target-url>" >&2
  exit 2
fi

# Strip protocol + path/query, lowercase, replace non-alnum with '-', trim edges.
slug="$(printf '%s' "$url" \
  | sed -E 's|^[a-zA-Z]+://||; s|/.*$||; s|[?#].*$||' \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed 's/^-//; s/-$//')"

[ -z "$slug" ] && slug="target"

echo "${slug}-shannon"
