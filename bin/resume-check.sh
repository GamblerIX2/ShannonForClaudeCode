#!/usr/bin/env bash
# resume-check.sh — inspect prior Shannon-run state for cross-session resume.
#
# Prints structured key=value lines so the agent can decide whether to skip
# stages or pick up mid-pipeline without re-running expensive work.
#
# Output keys (always emit RESUME_STATE, WORKER_RUNNING, REPORT_READY):
#   RESUME_STATE=present|none
#   STAGE=<n>                   (from state file)
#   TARGET_URL=...              (from state file)
#   TARGET_REPO=...             (from state file)
#   WORKSPACE_ID=...            (from state file)
#   TASK_OUTPUT=...             (from state file)
#   STARTED_AT=...              (from state file)
#   LAST_RESULT=...             (from state file: success|failed|<reason>)
#   WORKER_RUNNING=true|false
#   WORKFLOW_STATUS=succeeded|failed|running|unknown  (from latest workflow.log)
#   WORKFLOW_REASON=<short>     (when WORKFLOW_STATUS=failed)
#   RATE_LIMITED=true|false     (true when failure reason mentions rate limit)
#   RATE_LIMIT_RESET_RAW=...    (raw string Shannon logged, e.g. "6:30am (UTC)")
#   RATE_LIMIT_RESET_EPOCH=<n>  (epoch seconds, only when parseable)
#   REPORT_READY=true|false
#   REPORT_PATH=...             (when REPORT_READY=true)
#
# Usage: resume-check.sh <shannon-dir>

set -uo pipefail

dir="${1:-}"
if [ -z "$dir" ]; then
  echo "usage: $0 <shannon-dir>" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
state_file="$dir/.run-state"

if [ -f "$state_file" ]; then
  echo "RESUME_STATE=present"
  cat "$state_file"
else
  echo "RESUME_STATE=none"
fi

# Docker probe — worker is a container; `docker ps` is enough.
worker_running=false
if command -v docker >/dev/null 2>&1; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE '^shannon-worker-'; then
    worker_running=true
  fi
fi
echo "WORKER_RUNNING=$worker_running"

# Inspect the newest workflow.log to determine outcome of the most recent run.
ws_id=""
if [ -f "$state_file" ]; then
  ws_id="$(grep '^WORKSPACE_ID=' "$state_file" 2>/dev/null | tail -n1 | cut -d= -f2-)"
fi

latest_log=""
if [ -n "$ws_id" ] && [ -f "$dir/workspaces/$ws_id/workflow.log" ]; then
  latest_log="$dir/workspaces/$ws_id/workflow.log"
elif [ -d "$dir/workspaces" ]; then
  latest_log="$(find "$dir/workspaces" -maxdepth 3 -name workflow.log -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
fi

workflow_status="unknown"
workflow_reason=""
if [ -n "$latest_log" ] && [ -f "$latest_log" ]; then
  if grep -qE 'Workflow COMPLETED|Status:[[:space:]]+succeeded' "$latest_log"; then
    workflow_status="succeeded"
  elif grep -qE 'Workflow FAILED|Status:[[:space:]]+failed' "$latest_log"; then
    workflow_status="failed"
    workflow_reason="$(grep -E 'Error:|ConfigurationError|preflight failed|Authentication failed|Rate limit' "$latest_log" \
                        | tail -n1 | sed 's/^[[:space:]]*//' | cut -c1-200 | tr ',' ';')"
  elif [ "$worker_running" = "true" ]; then
    workflow_status="running"
  fi
fi
echo "WORKFLOW_STATUS=$workflow_status"
[ -n "$workflow_reason" ] && echo "WORKFLOW_REASON=$workflow_reason"

# Rate-limit detection — Anthropic surfaces strings like:
#   "You've hit your limit · resets 6:30am (UTC)"
#   "rate limit exceeded; retry after 2025-04-12T14:00:00Z"
# We extract the reset clue so the agent can schedule a wakeup instead of
# making the user manually retry. We try only well-bounded formats; if none
# match, RATE_LIMIT_RESET_EPOCH is omitted and the agent should ask the user.
rate_limited=false
reset_raw=""
reset_epoch=""
if [ -n "$latest_log" ] && [ -f "$latest_log" ] && [ "$workflow_status" = "failed" ]; then
  if grep -qE -i 'rate.limit|hit your limit|429|too many requests' "$latest_log"; then
    rate_limited=true
    # Format A: "resets <H[:MM][am|pm]> (UTC|<TZ>)" — Anthropic console style.
    reset_raw="$(grep -oE "resets [0-9]{1,2}(:[0-9]{2})?(am|pm|AM|PM)?[[:space:]]*\\([A-Za-z]+\\)" "$latest_log" \
                  | tail -n1 | sed -E 's/^resets[[:space:]]+//')"
    # Format B: ISO timestamp "retry after <ISO8601>".
    if [ -z "$reset_raw" ]; then
      reset_raw="$(grep -oE "retry after [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+(\\.[0-9]+)?Z?" "$latest_log" \
                    | tail -n1 | sed -E 's/^retry after[[:space:]]+//')"
    fi

    if [ -n "$reset_raw" ]; then
      # Try to convert to epoch via GNU `date -d`. If it fails we just leave
      # RESET_EPOCH unset — the raw string still informs the user.
      reset_epoch="$(date -d "$reset_raw" +%s 2>/dev/null || true)"
      # If GNU date parsed "6:30am (UTC)" as today and that time is in the
      # past, roll forward 24h — the actual reset is the next occurrence.
      if [ -n "$reset_epoch" ]; then
        now_epoch="$(date +%s)"
        if [ "$reset_epoch" -lt "$now_epoch" ]; then
          reset_epoch=$((reset_epoch + 86400))
        fi
      fi
    fi
  fi
fi
echo "RATE_LIMITED=$rate_limited"
[ -n "$reset_raw" ] && echo "RATE_LIMIT_RESET_RAW=$reset_raw"
[ -n "$reset_epoch" ] && echo "RATE_LIMIT_RESET_EPOCH=$reset_epoch"

# Final report probe under the saved workspace, if any.
report_ready=false
report_path=""
search_root="$dir/workspaces"
[ -n "$ws_id" ] && [ -d "$dir/workspaces/$ws_id" ] && search_root="$dir/workspaces/$ws_id"
if [ -d "$search_root" ]; then
  report_path="$(find "$search_root" -maxdepth 3 -type f -name 'shannon-report*.md' -printf '%T@ %p\n' 2>/dev/null \
                  | sort -nr | head -n1 | cut -d' ' -f2-)"
  if [ -n "$report_path" ]; then
    report_ready=true
  fi
fi
echo "REPORT_READY=$report_ready"
[ -n "$report_path" ] && echo "REPORT_PATH=$report_path"

exit 0
