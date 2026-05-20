#!/usr/bin/env bash
# Tests for bin/run-state.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-run-state.sh"

it "errors with no args"
run bin/run-state.sh
assert_exit_code "2" "$RC"

it "errors with unknown cmd"
run bin/run-state.sh bogus "$SCRATCH"
assert_exit_code "2" "$RC"

it "init creates empty state file"
run bin/run-state.sh init "$SCRATCH"
assert_file_exists "$SCRATCH/.run-state"

it "set then get returns value"
run bin/run-state.sh set "$SCRATCH" STAGE 3
run bin/run-state.sh get "$SCRATCH" STAGE
assert_eq "3" "$OUT"

it "set overwrites existing key (no duplicates)"
run bin/run-state.sh set "$SCRATCH" STAGE 1
run bin/run-state.sh set "$SCRATCH" STAGE 5
count="$(grep -c '^STAGE=' "$SCRATCH/.run-state")"
assert_eq "1" "$count"

it "set with overwrite returns latest"
run bin/run-state.sh set "$SCRATCH" STAGE 1
run bin/run-state.sh set "$SCRATCH" STAGE 5
run bin/run-state.sh get "$SCRATCH" STAGE
assert_eq "5" "$OUT"

it "preserves other keys when overwriting one"
run bin/run-state.sh set "$SCRATCH" STAGE 1
run bin/run-state.sh set "$SCRATCH" TARGET_URL https://example.com
run bin/run-state.sh set "$SCRATCH" STAGE 2
run bin/run-state.sh get "$SCRATCH" TARGET_URL
assert_eq "https://example.com" "$OUT"

it "get on missing key returns empty"
run bin/run-state.sh init "$SCRATCH"
run bin/run-state.sh get "$SCRATCH" NOPE
assert_eq "" "$OUT"

it "show dumps state file content"
run bin/run-state.sh set "$SCRATCH" STAGE 7
run bin/run-state.sh set "$SCRATCH" TARGET_URL https://x.com
run bin/run-state.sh show "$SCRATCH"
assert_contains "$OUT" "STAGE=7"

it "clear removes state file"
run bin/run-state.sh set "$SCRATCH" STAGE 1
run bin/run-state.sh clear "$SCRATCH"
if [ -f "$SCRATCH/.run-state" ]; then
  fail "state file still present after clear"
else
  pass
fi

it "set handles value with '=' inside (preserved verbatim)"
run bin/run-state.sh set "$SCRATCH" FOO "a=b=c"
run bin/run-state.sh get "$SCRATCH" FOO
assert_eq "a=b=c" "$OUT"

it "state file is chmod 600"
run bin/run-state.sh set "$SCRATCH" STAGE 1
mode="$(stat -c '%a' "$SCRATCH/.run-state")"
assert_eq "600" "$mode"

it "init on existing state truncates"
run bin/run-state.sh set "$SCRATCH" STAGE 1
run bin/run-state.sh init "$SCRATCH"
size="$(stat -c '%s' "$SCRATCH/.run-state")"
assert_eq "0" "$size"

summary
