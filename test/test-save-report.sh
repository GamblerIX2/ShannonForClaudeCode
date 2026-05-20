#!/usr/bin/env bash
# Tests for bin/save-report.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-save-report.sh"

# Helper: create a shannon-shaped dir under $SCRATCH with given files.
# Each arg is "relative/path/file:content".
make_shannon() {
  local shannon="$SCRATCH/shannon"
  mkdir -p "$shannon"
  for spec in "$@"; do
    local path="${spec%%:*}"
    local body="${spec#*:}"
    mkdir -p "$shannon/$(dirname "$path")"
    printf '%s\n' "$body" > "$shannon/$path"
  done
  echo "$shannon"
}

# ── argument handling ───────────────────────────────────────────────────
it "errors when shannon dir is missing"
run bin/save-report.sh "$SCRATCH/nope"
assert_exit_code "1" "$RC"

it "errors when shannon dir has no usable output"
shannon="$(make_shannon)"
mkdir -p "$shannon/workspaces"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_exit_code "1" "$RC"

# ── selection precedence ────────────────────────────────────────────────
it "picks comprehensive_security_assessment_report.md (final)"
shannon="$(make_shannon \
  "workspaces/run1/comprehensive_security_assessment_report.md:FINAL CONTENT" \
  "workspaces/run1/pre_recon_deliverable.md:OLDER" \
  "workspaces/run1/exploit_evidence.md:OLDEST")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "CATEGORY=final"

it "final-report copy contains the source content"
shannon="$(make_shannon "workspaces/run1/comprehensive_security_assessment_report.md:FINAL CONTENT")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
dest="$OUT"
assert_contains "$(cat "$dest")" "FINAL CONTENT"

it "falls back to *_deliverable.md when no final"
shannon="$(make_shannon \
  "workspaces/run1/pre_recon_deliverable.md:DELIV" \
  "workspaces/run1/exploit_evidence.md:EVID")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "CATEGORY=intermediate-deliverable"

it "falls back to *_evidence.md when no final / no deliverable"
shannon="$(make_shannon "workspaces/run1/foo_evidence.md:EVID-ONLY")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "CATEGORY=intermediate-evidence"

# ── prompts/ exclusion ──────────────────────────────────────────────────
it "ignores comprehensive report inside prompts/ dir"
shannon="$(make_shannon \
  "workspaces/run1/prompts/comprehensive_security_assessment_report.md:PROMPT TEMPLATE" \
  "workspaces/run1/pre_recon_deliverable.md:REAL CONTENT")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "CATEGORY=intermediate-deliverable"

it "ignores deliverable inside prompts/ dir"
shannon="$(make_shannon "workspaces/run1/prompts/foo_deliverable.md:JUST A PROMPT")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_exit_code "1" "$RC"

# ── newest wins ─────────────────────────────────────────────────────────
it "picks newest deliverable when multiple"
shannon="$(make_shannon \
  "workspaces/run1/a_deliverable.md:OLDER" \
  "workspaces/run1/b_deliverable.md:NEWER")"
# Force mtimes so test is deterministic.
touch -d '2020-01-01' "$shannon/workspaces/run1/a_deliverable.md"
touch -d '2025-01-01' "$shannon/workspaces/run1/b_deliverable.md"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
dest="$OUT"
assert_contains "$(cat "$dest")" "NEWER"

# ── explicit reports-dir wins ───────────────────────────────────────────
it "explicit 2nd arg wins over env var"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
explicit="$SCRATCH/explicit-dest"
run_env "HOME=$SCRATCH/home SHANNONFORCLAUDE_FILES_HOME=$SCRATCH/from-env" bin/save-report.sh "$shannon" "$explicit"
dest="$OUT"
case "$dest" in
  "$explicit"/*) pass ;;
  *) fail "dest=[$dest] not under explicit=[$explicit]" ;;
esac

# ── env-var resolution ──────────────────────────────────────────────────
it "SHANNONFORCLAUDE_FILES_HOME=1 → \$HOME/shannon-reports"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
fake_home="$SCRATCH/home"
mkdir -p "$fake_home"
run_env "HOME=$fake_home SHANNONFORCLAUDE_FILES_HOME=1" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$fake_home/shannon-reports/"*) pass ;;
  *) fail "dest=[$dest] not under $fake_home/shannon-reports/" ;;
esac

it "SHANNONFORCLAUDE_FILES_HOME=yes → \$HOME/shannon-reports"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
fake_home="$SCRATCH/home"
mkdir -p "$fake_home"
run_env "HOME=$fake_home SHANNONFORCLAUDE_FILES_HOME=yes" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$fake_home/shannon-reports/"*) pass ;;
  *) fail "dest=[$dest] not under $fake_home/shannon-reports/" ;;
esac

it "SHANNONFORCLAUDE_FILES_HOME=/abs/path → /abs/path"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
abs="$SCRATCH/custom-dest"
run_env "HOME=$SCRATCH/home SHANNONFORCLAUDE_FILES_HOME=$abs" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$abs/"*) pass ;;
  *) fail "dest=[$dest] not under $abs/" ;;
esac

it "SHANNONFORCLAUDE_FILES_HOME=relative → fallback to ./shannon-reports"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
prev_pwd="$PWD"; cd "$SCRATCH"
run_env "HOME=$SCRATCH/home SHANNONFORCLAUDE_FILES_HOME=somerel/path" bin/save-report.sh "$shannon"
cd "$prev_pwd"
dest="$OUT"
case "$dest" in
  "$SCRATCH/shannon-reports/"*|"./shannon-reports/"*) pass ;;
  *) fail "expected ./shannon-reports/ fallback, got=[$dest]" ;;
esac

# ── config-file resolution ──────────────────────────────────────────────
it "config file with '1' resolves to \$HOME/shannon-reports"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
fake_home="$SCRATCH/home"
mkdir -p "$fake_home/.config/shannon-for-claude-code"
echo "1" > "$fake_home/.config/shannon-for-claude-code/files-home"
run_env "HOME=$fake_home" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$fake_home/shannon-reports/"*) pass ;;
  *) fail "dest=[$dest] not under $fake_home/shannon-reports/" ;;
esac

it "config file with absolute path is used verbatim"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
fake_home="$SCRATCH/home"
custom="$SCRATCH/configured-dest"
mkdir -p "$fake_home/.config/shannon-for-claude-code"
echo "$custom" > "$fake_home/.config/shannon-for-claude-code/files-home"
run_env "HOME=$fake_home" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$custom/"*) pass ;;
  *) fail "dest=[$dest] not under $custom/" ;;
esac

it "env var beats config file"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
fake_home="$SCRATCH/home"
from_config="$SCRATCH/from-config"
from_env="$SCRATCH/from-env"
mkdir -p "$fake_home/.config/shannon-for-claude-code"
echo "$from_config" > "$fake_home/.config/shannon-for-claude-code/files-home"
run_env "HOME=$fake_home SHANNONFORCLAUDE_FILES_HOME=$from_env" bin/save-report.sh "$shannon"
dest="$OUT"
case "$dest" in
  "$from_env/"*) pass ;;
  *) fail "dest=[$dest] not under env-var $from_env/, got=[$dest]" ;;
esac

# ── webroot WARN ────────────────────────────────────────────────────────
it "WARN on /www/wwwroot destination"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
webroot="/www/wwwroot/__test_save_report_$$"
mkdir -p "$webroot"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$webroot"
rc=$RC; err="$ERR"
rm -rf "$webroot"
RC=$rc; ERR="$err"
assert_contains "$ERR" "WARN: reports dir"

it "no WARN on safe path"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
safe="$SCRATCH/totally-safe-place"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$safe"
assert_not_contains "$ERR" "WARN: reports dir"

# ── deny-templates side effect ──────────────────────────────────────────
it "drops .htaccess into reports dir"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_file_exists "$SCRATCH/reports/.htaccess"

it "drops _nginx-deny.conf into reports dir"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_file_exists "$SCRATCH/reports/_nginx-deny.conf"

# ── permissions ─────────────────────────────────────────────────────────
it "reports dir chmod 700"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
mode="$(stat -c '%a' "$SCRATCH/reports")"
assert_eq "700" "$mode"

# ── output schema ───────────────────────────────────────────────────────
it "stdout is exactly the dest path"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
case "$OUT" in
  "$SCRATCH/reports/"*-*Z.md) pass ;;
  *) fail "stdout=[$OUT] not a timestamped report path" ;;
esac

it "stderr includes SOURCE= line"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "SOURCE="

it "stderr includes DENY_TEMPLATES_WRITTEN= line"
shannon="$(make_shannon "workspaces/run1/x_deliverable.md:X")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/reports"
assert_contains "$ERR" "DENY_TEMPLATES_WRITTEN="

# ── searches multiple root dirs ─────────────────────────────────────────
it "finds report under reports/ subdir"
shannon="$(make_shannon "reports/foo_deliverable.md:R")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/dest"
assert_contains "$ERR" "CATEGORY=intermediate-deliverable"

it "finds report under apps/worker/output/"
shannon="$(make_shannon "apps/worker/output/x_deliverable.md:Y")"
run_env "HOME=$SCRATCH/home" bin/save-report.sh "$shannon" "$SCRATCH/dest"
assert_contains "$ERR" "CATEGORY=intermediate-deliverable"

summary
