#!/usr/bin/env bash
# run-state.sh — persist Shannon-run checkpoint across agent sessions.
#
# A tiny key=value store at <shannon-dir>/.run-state. Lets a fresh agent
# invocation skip stages that already completed instead of re-running
# preflight/clone/config and re-reading credentials.
#
# Usage:
#   run-state.sh init  <shannon-dir>
#   run-state.sh set   <shannon-dir> KEY VALUE
#   run-state.sh get   <shannon-dir> KEY
#   run-state.sh show  <shannon-dir>
#   run-state.sh clear <shannon-dir>

set -uo pipefail

cmd="${1:-}"
dir="${2:-}"

if [ -z "$cmd" ] || [ -z "$dir" ]; then
  echo "usage: $0 <init|set|get|show|clear> <shannon-dir> [args]" >&2
  exit 2
fi

file="$dir/.run-state"

case "$cmd" in
  init)
    mkdir -p "$dir"
    : > "$file"
    chmod 600 "$file" 2>/dev/null || true
    ;;
  set)
    key="${3:-}"
    val="${4:-}"
    if [ -z "$key" ]; then
      echo "set requires KEY VALUE" >&2
      exit 2
    fi
    mkdir -p "$dir"
    touch "$file"
    tmp="$(mktemp)"
    grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$val" >> "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file" 2>/dev/null || true
    ;;
  get)
    key="${3:-}"
    [ -z "$key" ] && exit 2
    [ -f "$file" ] || exit 0
    grep "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2-
    ;;
  show)
    [ -f "$file" ] || exit 0
    cat "$file"
    ;;
  clear)
    rm -f "$file"
    ;;
  *)
    echo "unknown cmd: $cmd" >&2
    exit 2
    ;;
esac
