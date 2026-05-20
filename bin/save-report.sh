#!/usr/bin/env bash
# save-report.sh — find Shannon's final report (or best available deliverable)
# and copy it into a saved-reports dir.
#
# Selection order (first match wins):
#   1. comprehensive_security_assessment_report.md anywhere under SHANNON_DIR
#      EXCEPT inside any "prompts/" directory. This is the final report from
#      the `report` agent (per apps/worker/src/session-manager.ts).
#   2. Newest *_deliverable.md under SHANNON_DIR (excluding prompts/). This
#      handles incomplete runs — e.g., pre_recon_deliverable.md when the
#      workflow died before reporting.
#   3. Newest *_evidence.md under SHANNON_DIR (excluding prompts/). Exploit
#      agents save their evidence under this suffix.
#
# `prompts/` directories contain the agent's INPUT prompt snapshot, not the
# analysis output. Selecting from there (as a previous version did) shipped
# the user the prompt template instead of the report — exactly the wrong file.
#
# Usage: save-report.sh <shannon-dir> [reports-dir]
#
# Default location resolution (when reports-dir not passed):
#   1. $SHANNONFORCLAUDE_FILES_HOME env var (one-shot override)
#   2. ~/.config/shannon-for-claude-code/files-home file contents (persistent)
#   3. ./shannon-reports inside cwd (legacy default)
#
# Values "1", "true", "yes", "on" resolve to "$HOME/shannon-reports".
# Absolute paths are used verbatim.
#
# Regardless of where reports land, web-server deny templates are dropped
# in the dest dir as defense-in-depth (see web-deny-templates.sh).
#
# Prints the destination path on stdout. Prints CATEGORY (final/intermediate)
# on stderr for the agent's chat summary.

set -euo pipefail

SHANNON_DIR="${1:-./shannon}"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

# ── Resolve default reports dir ───────────────────────────────────────────
pref=""
if [ -n "${SHANNONFORCLAUDE_FILES_HOME:-}" ]; then
  pref="$SHANNONFORCLAUDE_FILES_HOME"
elif [ -f "${HOME:-/root}/.config/shannon-for-claude-code/files-home" ]; then
  pref="$(head -n1 "${HOME:-/root}/.config/shannon-for-claude-code/files-home" 2>/dev/null | tr -d '[:space:]')"
fi

case "$pref" in
  1|true|yes|TRUE|YES|on|ON)
    DEFAULT_REPORTS_DIR="${HOME:-/root}/shannon-reports" ;;
  /*)
    DEFAULT_REPORTS_DIR="$pref" ;;
  *)
    DEFAULT_REPORTS_DIR="./shannon-reports" ;;
esac

REPORTS_DIR="${2:-$DEFAULT_REPORTS_DIR}"

# ── Warn (do not refuse) on webroot path ──────────────────────────────────
# The agent is supposed to have asked the user before getting here. We just
# leave a loud trace on stderr so an unattended invocation flags the risk.
case "$REPORTS_DIR" in
  /www/wwwroot/*|/var/www/*|/usr/share/nginx/*|/srv/www/*|/home/*/public_html/*|/home/wwwroot/*)
    echo "WARN: reports dir '$REPORTS_DIR' is under a common webroot path." >&2
    echo "      Deny templates will be dropped alongside the report — verify" >&2
    echo "      HTTP access is blocked (curl -sI) before closing the engagement." >&2
    ;;
esac

mkdir -p "$REPORTS_DIR"
# Tighten dir perms — even when templates are inert, root-owned 700 makes
# the dir unreadable to the web-server user (www/www-data/nginx).
chmod 700 "$REPORTS_DIR" 2>/dev/null || true

# ── Pick the best available output ────────────────────────────────────────
find_newest() {
  local pattern="$1"
  local roots=(
    "$SHANNON_DIR/workspaces"
    "$SHANNON_DIR/repos"
    "$SHANNON_DIR/output"
    "$SHANNON_DIR/reports"
    "$SHANNON_DIR/apps/worker/output"
    "$SHANNON_DIR/apps/worker/workspaces"
  )
  for r in "${roots[@]}"; do
    [ -d "$r" ] || continue
    find "$r" -type f -name "$pattern" \
      -not -path '*/prompts/*' \
      -printf '%T@ %p\n' 2>/dev/null
  done | sort -nr | head -n1 | cut -d' ' -f2-
}

CATEGORY=""
LATEST=""

LATEST="$(find_newest 'comprehensive_security_assessment_report.md')"
[ -n "$LATEST" ] && CATEGORY="final"

if [ -z "$LATEST" ]; then
  LATEST="$(find_newest '*_deliverable.md')"
  [ -n "$LATEST" ] && CATEGORY="intermediate-deliverable"
fi

if [ -z "$LATEST" ]; then
  LATEST="$(find_newest '*_evidence.md')"
  [ -n "$LATEST" ] && CATEGORY="intermediate-evidence"
fi

if [ -z "$LATEST" ] || [ ! -f "$LATEST" ]; then
  echo "ERROR: no usable Shannon output found under $SHANNON_DIR." >&2
  echo "       Checked patterns: comprehensive_security_assessment_report.md," >&2
  echo "       *_deliverable.md, *_evidence.md (excluding prompts/ dirs)." >&2
  exit 1
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASENAME="$(basename "$LATEST" .md)"
DEST="$REPORTS_DIR/${BASENAME}-${TS}.md"

cp "$LATEST" "$DEST"

# ── Always drop deny templates (defense-in-depth) ─────────────────────────
# Harmless outside a docroot; critical inside one.
bash "$(dirname "$0")/web-deny-templates.sh" "$REPORTS_DIR" 2>/dev/null || true

echo "CATEGORY=$CATEGORY  SOURCE=$LATEST" >&2
echo "$DEST"
