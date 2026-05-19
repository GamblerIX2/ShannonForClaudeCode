#!/usr/bin/env bash
# save-report.sh — find Shannon's latest report and copy it to a saved-reports dir.
# Usage: save-report.sh <shannon-dir> <reports-dir>   (default reports dir: ./shannon-reports)
# Prints the destination path on stdout.

set -euo pipefail

SHANNON_DIR="${1:-./shannon}"
REPORTS_DIR="${2:-./shannon-reports}"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

mkdir -p "$REPORTS_DIR"

# Search locations Shannon is known to use. Newest match wins.
CANDIDATES=()
for sub in workspaces output reports apps/worker/output apps/worker/workspaces; do
  if [ -d "$SHANNON_DIR/$sub" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && CANDIDATES+=("$f")
    done < <(find "$SHANNON_DIR/$sub" -type f -name '*.md' 2>/dev/null)
  fi
done

# Last resort: anything under SHANNON_DIR that looks like a report.
if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && CANDIDATES+=("$f")
  done < <(find "$SHANNON_DIR" -maxdepth 6 -type f -name 'shannon-report*.md' 2>/dev/null)
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  echo "ERROR: no Shannon report .md found under $SHANNON_DIR. Did the run complete?" >&2
  exit 1
fi

# Pick the newest by mtime.
LATEST="$(printf '%s\n' "${CANDIDATES[@]}" | xargs -d '\n' ls -t 2>/dev/null | head -n1)"

if [ -z "$LATEST" ] || [ ! -f "$LATEST" ]; then
  echo "ERROR: failed to resolve newest report." >&2
  exit 1
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASENAME="$(basename "$LATEST" .md)"
DEST="$REPORTS_DIR/${BASENAME}-${TS}.md"

cp "$LATEST" "$DEST"
echo "$DEST"
