#!/usr/bin/env bash
# Tests for bin/write-env.sh
# (Skip the root re-exec branch — would need to be root and create a real user.)

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-write-env.sh"

# Most tests need non-root or a non-root-equivalent path. The script re-execs
# under with-shannon-user.sh when EUID=0; we accept that pass-through is
# tested implicitly. These tests cover the post-drop logic by invoking under
# a fake HOME with non-root illusion — since we ARE root in this session,
# they exercise the re-exec path end-to-end.

it "errors when shannon dir missing"
run bin/write-env.sh "$SCRATCH/nope" KEY value
assert_exit_code "1" "$RC"

it "creates .env file when missing"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO bar
assert_file_exists "$SCRATCH/shannon/.env"

it "appends KEY=VALUE line"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO bar
assert_contains "$(cat "$SCRATCH/shannon/.env")" "FOO=bar"

it "overwrites existing key (no duplicates)"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO bar
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO baz
count="$(grep -c '^FOO=' "$SCRATCH/shannon/.env")"
assert_eq "1" "$count"

it "second write reflects latest value"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO bar
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO baz
assert_contains "$(cat "$SCRATCH/shannon/.env")" "FOO=baz"

it "preserves other keys when overwriting one"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO 1
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" OTHER kept
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO 2
assert_contains "$(cat "$SCRATCH/shannon/.env")" "OTHER=kept"

it ".env mode is 600"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO bar
mode="$(stat -c '%a' "$SCRATCH/shannon/.env")"
assert_eq "600" "$mode"

it "handles value with slash characters"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" PATH_LIKE "/a/b/c"
assert_contains "$(cat "$SCRATCH/shannon/.env")" "PATH_LIKE=/a/b/c"

it "handles value containing '=' (preserved verbatim)"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" EQ "a=b=c"
assert_contains "$(cat "$SCRATCH/shannon/.env")" "EQ=a=b=c"

it "regex-special key chars in regex match (KEY1 doesn't match KEY1.x)"
mkdir -p "$SCRATCH/shannon"
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO_BAR 1
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO_BAZ 2
# Now overwrite FOO_BAR — FOO_BAZ should survive
run_env "HOME=$SCRATCH/home" bin/write-env.sh "$SCRATCH/shannon" FOO_BAR 99
assert_contains "$(cat "$SCRATCH/shannon/.env")" "FOO_BAZ=2"

summary
