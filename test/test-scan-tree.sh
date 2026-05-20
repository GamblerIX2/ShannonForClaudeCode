#!/usr/bin/env bash
# Tests for bin/scan-tree.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-scan-tree.sh"

it "errors with no arg"
run bin/scan-tree.sh
assert_exit_code "2" "$RC"

it "errors with non-existent path"
run bin/scan-tree.sh "/nope/here"
assert_exit_code "2" "$RC"

it "always emits the standard globs"
mkdir -p "$SCRATCH/repo"
run bin/scan-tree.sh "$SCRATCH/repo"
for g in "**/*.min.js" "**/*.min.css" "**/*.map" "**/*.lock"; do
  if ! printf '%s' "$OUT" | grep -qF "STANDARD_EXCLUDE=$g"; then
    fail "missing standard glob: $g"
    continue 2
  fi
done
pass

it "emits node_modules when present at root"
mkdir -p "$SCRATCH/repo/node_modules/foo"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "STANDARD_EXCLUDE=node_modules"

it "emits .git when present at root"
mkdir -p "$SCRATCH/repo/.git/objects"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "STANDARD_EXCLUDE=.git"

it "BUG REGRESSION: does not emit .git/logs alongside .git"
mkdir -p "$SCRATCH/repo/.git/logs"
mkdir -p "$SCRATCH/repo/.git/refs"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_not_contains "$OUT" "STANDARD_EXCLUDE=.git/logs"

it "BUG REGRESSION: does not emit node_modules/<dep>/.git"
mkdir -p "$SCRATCH/repo/node_modules"
mkdir -p "$SCRATCH/repo/node_modules/dep/.git"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_not_contains "$OUT" "STANDARD_EXCLUDE=node_modules/dep/.git"

it "emits depth-2 hit when parent is NOT a noise dir"
mkdir -p "$SCRATCH/repo/apps/dist"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "STANDARD_EXCLUDE=apps/dist"

it "emits REPO_SIZE_MB and REPO_FILE_COUNT"
mkdir -p "$SCRATCH/repo"
echo "hi" > "$SCRATCH/repo/file.txt"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "REPO_SIZE_MB="

it "REPO_FILE_COUNT present"
mkdir -p "$SCRATCH/repo"
echo "hi" > "$SCRATCH/repo/file.txt"
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "REPO_FILE_COUNT="

it "SUGGEST_EXCLUDE fires for large top-level dir"
mkdir -p "$SCRATCH/repo/bigdir"
# Create >1000 small files to trip the file-count heuristic
for i in $(seq 1 1001); do echo x > "$SCRATCH/repo/bigdir/f$i"; done
run bin/scan-tree.sh "$SCRATCH/repo"
assert_contains "$OUT" "SUGGEST_EXCLUDE=bigdir"

it "skips empty repo cleanly"
mkdir -p "$SCRATCH/empty"
run bin/scan-tree.sh "$SCRATCH/empty"
assert_exit_code "0" "$RC"

summary
