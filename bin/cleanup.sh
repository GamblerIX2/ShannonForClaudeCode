#!/usr/bin/env bash
# cleanup.sh — stop Shannon worker. Does NOT delete the clone.
# Usage: cleanup.sh <shannon-dir>

set -euo pipefail

SHANNON_DIR="${1:-./shannon}"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

if [ ! -x "$SHANNON_DIR/shannon" ]; then
  echo "WARN: $SHANNON_DIR/shannon CLI not found. Skipping ./shannon stop." >&2
  exit 0
fi

cd "$SHANNON_DIR"
./shannon stop
echo "Shannon worker stopped (clone preserved at $SHANNON_DIR)."
