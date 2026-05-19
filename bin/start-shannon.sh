#!/usr/bin/env bash
# start-shannon.sh — start a Shannon pentest run.
# Usage: start-shannon.sh <shannon-dir> <target-url> <repo-path>
# Designed to be invoked from the agent with Bash run_in_background: true.
#
# Behavior contract (for the parent agent):
#   * Pre-validates that <repo-path>/.git exists. Shannon's own preflight
#     requires this; failing here gives a clearer message earlier.
#   * Runs ./shannon start and CAPTURES its exit code (no exec).
#   * On any failure (non-zero exit OR "Workflow FAILED" found in workflow.log)
#     emits the last 80 lines of the newest workflow.log to stdout.
#   * Always emits a single terminal marker line as its very last line of
#     stdout — one of:
#         SHANNON_RUN_RESULT: success
#         SHANNON_RUN_RESULT: failed (exit=<code>) reason=<short>
#     The agent's Monitor / TaskOutput consumer should grep for this prefix.

set -uo pipefail

SHANNON_DIR="${1:-}"
TARGET_URL="${2:-}"
REPO_PATH="${3:-}"

if [ -z "$SHANNON_DIR" ] || [ -z "$TARGET_URL" ] || [ -z "$REPO_PATH" ]; then
  echo "Usage: $0 <shannon-dir> <target-url> <repo-path>" >&2
  echo "SHANNON_RUN_RESULT: failed (exit=2) reason=usage" >&2
  exit 2
fi

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  echo "SHANNON_RUN_RESULT: failed (exit=1) reason=shannon-dir-missing" >&2
  exit 1
fi

if [ ! -x "$SHANNON_DIR/shannon" ]; then
  echo "ERROR: $SHANNON_DIR/shannon CLI not found or not executable. Did pnpm build complete?" >&2
  echo "SHANNON_RUN_RESULT: failed (exit=1) reason=shannon-cli-missing" >&2
  exit 1
fi

# Resolve repo path against the user's original cwd, not shannon dir.
case "$REPO_PATH" in
  /*) ABS_REPO="$REPO_PATH" ;;
  *)  ABS_REPO="$(cd "$REPO_PATH" 2>/dev/null && pwd)" ;;
esac

if [ -z "${ABS_REPO:-}" ] || [ ! -d "$ABS_REPO" ]; then
  echo "ERROR: repo path '$REPO_PATH' does not resolve to a directory." >&2
  echo "SHANNON_RUN_RESULT: failed (exit=1) reason=repo-path-invalid" >&2
  exit 1
fi

# Shannon requires the target repo to be a git checkout — its preflight does
# `git -C <repo> rev-parse` and aborts with "Not a git repository" otherwise.
# Catch that here so the agent gets a clear, early signal instead of a buried
# workflow.log error.
if [ ! -d "$ABS_REPO/.git" ] && [ ! -f "$ABS_REPO/.git" ]; then
  cat >&2 <<EOF
ERROR: Shannon requires the target repo to be a git repository, but
       '$ABS_REPO' has no .git directory.

       To fix, run (as the repo owner):
           cd '$ABS_REPO'
           git init
           git add -A
           git -c user.email=shannon@local -c user.name=shannon \\
               commit -m 'shannon baseline' --allow-empty

       Then re-run /shannon-run.
EOF
  echo "SHANNON_RUN_RESULT: failed (exit=1) reason=repo-not-git" >&2
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

# IMPORTANT: do NOT exec — we need to inspect the exit code and workflow.log
# after the CLI returns, so the parent agent always gets a structured result.
"$SCRIPT_DIR/with-shannon-user.sh" "$SHANNON_DIR" "$ABS_REPO" -- \
  ./shannon start -u "$TARGET_URL" -r "$ABS_REPO"
EC=$?

# Find the newest workflow.log so we can inspect / surface it on failure.
# Shannon writes them to workspaces/<host>_<id>/workflow.log.
LATEST_LOG=""
if [ -d "$SHANNON_DIR/workspaces" ]; then
  LATEST_LOG="$(find "$SHANNON_DIR/workspaces" -maxdepth 3 -name workflow.log -printf '%T@ %p\n' 2>/dev/null \
                  | sort -nr | head -n1 | cut -d' ' -f2-)"
fi

# Detect logical failure even when the CLI returns 0 — Shannon sometimes
# logs "Workflow FAILED" yet returns success to the shell.
LOG_FAILED=0
LOG_REASON=""
if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
  if grep -qE 'Workflow FAILED|Status:[[:space:]]+failed|ConfigurationError|preflight failed' "$LATEST_LOG"; then
    LOG_FAILED=1
    LOG_REASON="$(grep -E 'Error:|ConfigurationError|preflight failed' "$LATEST_LOG" \
                    | head -n1 | sed 's/^[[:space:]]*//' | cut -c1-160)"
  fi
fi

if [ "$EC" -ne 0 ] || [ "$LOG_FAILED" -eq 1 ]; then
  echo
  echo "================================================================================"
  echo "Shannon run did NOT complete cleanly."
  echo "  exit code:     $EC"
  echo "  log signaled:  $LOG_FAILED"
  if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
    echo "  workflow.log:  $LATEST_LOG"
    echo "--- workflow.log (tail, last 80 lines) ---"
    tail -n 80 "$LATEST_LOG"
    echo "--- end workflow.log ---"
  else
    echo "  workflow.log:  (not found — Shannon may have aborted before workspace creation)"
  fi
  echo "================================================================================"

  # Propagate a useful exit code: prefer the CLI's, else 1.
  if [ "$EC" -eq 0 ] && [ "$LOG_FAILED" -eq 1 ]; then
    EC=1
  fi

  REASON_TAG="run-failed"
  if [ -n "$LOG_REASON" ]; then
    # Sanitize: keep ASCII printable, collapse whitespace, swap commas.
    SAFE_REASON="$(printf '%s' "$LOG_REASON" | tr -d '\r' | tr '\t' ' ' | tr -s ' ' | tr ',' ';' )"
    REASON_TAG="run-failed; $SAFE_REASON"
  fi
  echo "SHANNON_RUN_RESULT: failed (exit=$EC) reason=$REASON_TAG"
  exit "$EC"
fi

echo "SHANNON_RUN_RESULT: success"
exit 0
