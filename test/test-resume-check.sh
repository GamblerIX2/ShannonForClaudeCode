#!/usr/bin/env bash
# Tests for bin/resume-check.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-resume-check.sh"

# ── usage / smoke ───────────────────────────────────────────────────────
it "errors with no arg"
run bin/resume-check.sh
assert_exit_code "2" "$RC"

it "always emits RESUME_STATE on empty dir"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "RESUME_STATE=none"

it "always emits WORKER_RUNNING"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "WORKER_RUNNING="

it "always emits REPORT_READY"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_READY="

it "always emits RATE_LIMITED"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "RATE_LIMITED="

# ── state file is surfaced ───────────────────────────────────────────────
it "RESUME_STATE=present when .run-state exists"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
cat > "$shannon/.run-state" <<EOF
STAGE=3
TARGET_URL=https://example.com
WORKSPACE_ID=example.com_abc123
EOF
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "RESUME_STATE=present"

it "state-file contents passed through"
shannon="$SCRATCH/shannon"; mkdir -p "$shannon"
cat > "$shannon/.run-state" <<EOF
STAGE=4
EOF
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "STAGE=4"

# ── BUG REGRESSION: REPORT_READY/PATH for actual Shannon output ─────────
it "REPORT_READY=true when comprehensive_security_assessment_report.md present"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/example.com_abc"
mkdir -p "$ws"
echo "stub final report" > "$ws/comprehensive_security_assessment_report.md"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_READY=true"

it "REPORT_PATH points at the final report"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/example.com_abc"
mkdir -p "$ws"
echo "stub" > "$ws/comprehensive_security_assessment_report.md"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_PATH=$ws/comprehensive_security_assessment_report.md"

it "REPORT_READY=false when only deliverable.md (intermediate)"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/example.com_abc"
mkdir -p "$ws"
echo "incomplete" > "$ws/pre_recon_deliverable.md"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_READY=false"

it "ignores comprehensive report inside prompts/ dir"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/example.com_abc"
mkdir -p "$ws/prompts"
echo "PROMPT TEMPLATE" > "$ws/prompts/comprehensive_security_assessment_report.md"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_READY=false"

it "scoped by WORKSPACE_ID when present in .run-state"
shannon="$SCRATCH/shannon"
mkdir -p "$shannon/workspaces/other_ws"
echo "wrong ws" > "$shannon/workspaces/other_ws/comprehensive_security_assessment_report.md"
mkdir -p "$shannon/workspaces/correct_ws"
echo "right ws" > "$shannon/workspaces/correct_ws/comprehensive_security_assessment_report.md"
cat > "$shannon/.run-state" <<EOF
WORKSPACE_ID=correct_ws
EOF
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "REPORT_PATH=$shannon/workspaces/correct_ws/comprehensive_security_assessment_report.md"

# ── workflow status from log ─────────────────────────────────────────────
it "WORKFLOW_STATUS=succeeded for 'Workflow COMPLETED' log"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/x"
mkdir -p "$ws"
printf 'Workflow COMPLETED\n' > "$ws/workflow.log"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "WORKFLOW_STATUS=succeeded"

it "WORKFLOW_STATUS=failed for 'Workflow FAILED' log"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/x"
mkdir -p "$ws"
printf 'Workflow FAILED\nError: something broke\n' > "$ws/workflow.log"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "WORKFLOW_STATUS=failed"

it "WORKFLOW_REASON extracted from log"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/x"
mkdir -p "$ws"
printf 'Workflow FAILED\nError: ConfigurationError: bad config\n' > "$ws/workflow.log"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "WORKFLOW_REASON="

# ── rate-limit parsing ───────────────────────────────────────────────────
it "RATE_LIMITED=true when log contains rate-limit phrase"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/x"
mkdir -p "$ws"
printf 'Workflow FAILED\nError: 429 rate limit exceeded\n' > "$ws/workflow.log"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "RATE_LIMITED=true"

it "RATE_LIMIT_RESET_RAW parsed from 'resets 6:30am (UTC)' format"
shannon="$SCRATCH/shannon"
ws="$shannon/workspaces/x"
mkdir -p "$ws"
printf "Workflow FAILED\nrate limit hit — resets 6:30am (UTC)\n" > "$ws/workflow.log"
run bin/resume-check.sh "$shannon"
assert_contains "$OUT" "RATE_LIMIT_RESET_RAW="

summary
