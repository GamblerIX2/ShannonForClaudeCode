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
# Usage: save-report.sh <shannon-dir> <reports-dir>   (default reports dir: ./shannon-reports)
# Prints the destination path on stdout. Also prints the category of file
# selected (final/intermediate) on stderr for the agent's chat summary.

set -euo pipefail

SHANNON_DIR="${1:-./shannon}"
# Default REPORTS_DIR lives in $HOME, NOT inside CWD, because the agent
# is commonly invoked from inside a webroot (the same dir is also being
# scanned). A previous incident dropped a deliverable containing the
# scanned site's DB password into ./shannon-reports/ → publicly servable
# at https://<site>/shannon-reports/. Use $HOME by default; honor an
# explicit arg only after a safety check below.
DEFAULT_REPORTS_DIR="${HOME:-/root}/shannon-reports"
REPORTS_DIR="${2:-$DEFAULT_REPORTS_DIR}"

if [ ! -d "$SHANNON_DIR" ]; then
  echo "ERROR: shannon dir '$SHANNON_DIR' does not exist." >&2
  exit 1
fi

# Safety check: refuse to land reports under a common webroot. The
# deliverables contain credentials and full attack-surface intel —
# publishing them defeats the entire engagement.
case "$REPORTS_DIR" in
  /www/wwwroot/*|/var/www/*|/usr/share/nginx/*|/srv/www/*|/home/*/public_html/*|/home/wwwroot/*)
    echo "ERROR: reports dir '$REPORTS_DIR' looks like it's inside a webroot." >&2
    echo "       Shannon reports contain DB credentials, secret material, and" >&2
    echo "       full attack-surface intel — they must NOT be web-servable." >&2
    echo "       Default safe location: $DEFAULT_REPORTS_DIR" >&2
    echo "       Pass an explicit non-webroot path as arg 2 to override." >&2
    exit 1
    ;;
esac

mkdir -p "$REPORTS_DIR"
# Tighten dir perms — reports are root-readable only by convention,
# matches the SafeGuardForTypecho usr/uploads/safeguard/ pattern.
chmod 700 "$REPORTS_DIR" 2>/dev/null || true

# Helper: newest matching file across the known output roots, excluding any
# path that has a "prompts" directory component. We check workspaces/ first
# (where in-progress deliverables land) and the repo's .shannon/deliverables/
# directory (where the final report lands per Shannon's deliverablesDir()).
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

# 1. The real thing.
LATEST="$(find_newest 'comprehensive_security_assessment_report.md')"
[ -n "$LATEST" ] && CATEGORY="final"

# 2. Best-available deliverable (incomplete run).
if [ -z "$LATEST" ]; then
  LATEST="$(find_newest '*_deliverable.md')"
  [ -n "$LATEST" ] && CATEGORY="intermediate-deliverable"
fi

# 3. Exploitation evidence (a useful artifact even when reporting never ran).
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
echo "CATEGORY=$CATEGORY  SOURCE=$LATEST" >&2
echo "$DEST"
