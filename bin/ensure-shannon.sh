#!/usr/bin/env bash
# ensure-shannon.sh — clone or pull Shannon, then build it.
# Usage: ensure-shannon.sh <dest-dir>     (default: ./shannon)

set -euo pipefail

DEST="${1:-./shannon}"
REPO_URL="https://github.com/KeygraphHQ/shannon.git"
EXPECTED_REMOTE_FRAGMENT="KeygraphHQ/shannon"

if [ -d "$DEST/.git" ]; then
  REMOTE_URL="$(git -C "$DEST" remote get-url origin 2>/dev/null || true)"
  if [[ "$REMOTE_URL" == *"$EXPECTED_REMOTE_FRAGMENT"* ]]; then
    echo "Shannon clone exists at $DEST (remote: $REMOTE_URL). Pulling..."
    git -C "$DEST" pull --ff-only
  else
    echo "ERROR: $DEST exists and is a git repo but origin '$REMOTE_URL' is not Shannon's upstream ($EXPECTED_REMOTE_FRAGMENT)." >&2
    echo "Move or rename $DEST and re-run." >&2
    exit 1
  fi
elif [ -e "$DEST" ]; then
  echo "ERROR: $DEST exists but is not a git checkout. Move or rename it and re-run." >&2
  exit 1
else
  echo "Cloning Shannon into $DEST ..."
  git clone --depth 1 "$REPO_URL" "$DEST"
fi

cd "$DEST"

echo "Installing dependencies (pnpm install)..."
pnpm install --prefer-frozen-lockfile

echo "Building Shannon (pnpm build)..."
pnpm build

echo "Shannon is ready at $DEST"
