#!/usr/bin/env bash
# scan-tree.sh — inspect a repo and suggest exclude paths.
#
# Output is structured key=value lines. The agent parses them and presents
# a confirmation prompt to the user before writing the final scan config.
#
# Categories:
#   STANDARD_EXCLUDE=<path>   — well-known noise (always safe to exclude).
#                               Only emitted for paths that actually exist
#                               in this repo, to avoid asking about absent dirs.
#   SUGGEST_EXCLUDE=<path>    — heuristic: top-level dir is unusually big
#                               (>50MB) or has many files (>1000). User
#                               should review before excluding.
#   REPO_SIZE_MB=<n>          — total repo size, MB (excluding .git).
#   REPO_FILE_COUNT=<n>       — total tracked-ish file count.
#
# Usage: scan-tree.sh <repo-path>

set -uo pipefail

repo="${1:-}"
if [ -z "$repo" ] || [ ! -d "$repo" ]; then
  echo "usage: $0 <repo-path>" >&2
  exit 2
fi

cd "$repo" || exit 1

# Language/framework-agnostic noise patterns. Each entry is a directory NAME
# (not a glob) that we check for at any depth via a top-level scan first
# (cheap), then a recursive scan if not found at root.
STANDARD_NAMES=(
  node_modules
  vendor
  .git
  .svn
  .hg
  .idea
  .vscode
  dist
  build
  out
  target
  .next
  .nuxt
  .cache
  __pycache__
  .pytest_cache
  .mypy_cache
  .venv
  venv
  env
  coverage
  .nyc_output
  tmp
  temp
  logs
  # Shannon's own scaffolding when the user runs this plugin from inside
  # the repo being scanned. Confirmed noise: Shannon's pre-recon agent
  # spends tokens identifying these dirs as "out-of-scope harness" before
  # ignoring them — pre-excluding saves that round-trip.
  shannon
  .shannon
  shannon-reports
)

# Glob patterns that translate cleanly to Shannon's `code_path` rule (these
# are minified/generated content that the SDK should not be asked to read).
STANDARD_GLOBS=(
  "**/*.min.js"
  "**/*.min.css"
  "**/*.map"
  "**/*.lock"
)

# 1. Always-applicable globs — emit unconditionally, they cost nothing if absent.
for g in "${STANDARD_GLOBS[@]}"; do
  echo "STANDARD_EXCLUDE=$g"
done

# 2. Named dirs — only emit if they actually exist somewhere in the repo.
#    Check root first (fast), then one level deep, to keep this cheap on big repos.
#    Skip depth-2 hits whose parent dir is already a known-noise name — e.g.,
#    .git/logs would otherwise be emitted alongside .git, even though .git is
#    already excluded wholesale. That noise confuses the user-facing scan plan
#    and would write redundant code_path rules to the YAML config.
is_standard_name() {
  printf '%s\n' "${STANDARD_NAMES[@]}" | grep -qxF "$1"
}

for name in "${STANDARD_NAMES[@]}"; do
  if [ -d "./$name" ]; then
    echo "STANDARD_EXCLUDE=$name"
    continue
  fi
  # One level deep — find -maxdepth 2 is bounded and cheap.
  hit="$(find . -mindepth 2 -maxdepth 2 -type d -name "$name" 2>/dev/null | head -n1)"
  if [ -n "$hit" ]; then
    # Extract the depth-1 parent: "./parent/name" → "parent"
    parent_name="$(printf '%s' "$hit" | awk -F/ '{print $2}')"
    # If parent dir is itself excluded, this child is already covered.
    if is_standard_name "$parent_name"; then
      continue
    fi
    # Strip leading ./
    echo "STANDARD_EXCLUDE=${hit#./}"
  fi
done

# 3. Heuristic suggestions — top-level dirs that are unusually large.
#    "Large" is repo-relative noise that an attacker is unlikely to read; even
#    if it's app code, the user gets to confirm before we exclude.
for d in */; do
  [ -d "$d" ] || continue
  name="${d%/}"
  # Skip if already flagged as standard.
  if printf '%s\n' "${STANDARD_NAMES[@]}" | grep -qxF "$name"; then
    continue
  fi

  # Size in MB (du -sm gives megabytes on most systems).
  size_mb="$(du -sm "$d" 2>/dev/null | awk '{print $1}')"
  file_count="$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')"

  if [ "${size_mb:-0}" -gt 50 ] 2>/dev/null || [ "${file_count:-0}" -gt 1000 ] 2>/dev/null; then
    echo "SUGGEST_EXCLUDE=$name  (size=${size_mb}MB files=${file_count})"
  fi
done

# 4. Summary.
total_mb="$(du -sm --exclude='.git' . 2>/dev/null | awk '{print $1}')"
total_files="$(find . -path ./.git -prune -o -type f -print 2>/dev/null | wc -l | tr -d ' ')"
echo "REPO_SIZE_MB=${total_mb:-0}"
echo "REPO_FILE_COUNT=${total_files:-0}"

exit 0
