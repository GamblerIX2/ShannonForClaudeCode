#!/usr/bin/env bash
# start-shannon.sh — start a Shannon pentest run.
# Usage: start-shannon.sh <shannon-dir> <target-url> <repo-path>
# Designed to be invoked from the agent with Bash run_in_background: true.

set -euo pipefail

SHANNON_DIR="$1"
TARGET_URL="$2"
REPO_PATH="$3"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

if [ ! -x "$SHANNON_DIR/shannon" ]; then
  echo "ERROR: $SHANNON_DIR/shannon CLI not found or not executable. Did pnpm build complete?" >&2
  exit 1
fi

# Resolve repo path against the user's original cwd, not shannon dir.
case "$REPO_PATH" in
  /*) ABS_REPO="$REPO_PATH" ;;
  *)  ABS_REPO="$(cd "$REPO_PATH" 2>/dev/null && pwd)" ;;
esac

if [ -z "${ABS_REPO:-}" ] || [ ! -d "$ABS_REPO" ]; then
  echo "ERROR: repo path '$REPO_PATH' does not resolve to a directory." >&2
  exit 1
fi

echo "Shannon start"
echo "  target: $TARGET_URL"
echo "  repo:   $ABS_REPO"
echo "  cwd:    $SHANNON_DIR"
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Shannon refuses to run as root. with-shannon-user.sh ensures a service user
# exists (when EUID=0), owns the shannon dir, and has read access to the repo,
# then re-execs the command under that user. If non-root, it just execs.
cd "$SHANNON_DIR"
exec "$SCRIPT_DIR/with-shannon-user.sh" "$SHANNON_DIR" "$ABS_REPO" -- \
  ./shannon start -u "$TARGET_URL" -r "$ABS_REPO"
