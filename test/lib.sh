#!/usr/bin/env bash
# Minimal bash test harness for shannon-for-claude-code plugin.
# Usage from a test file:
#   . "$(dirname "$0")/lib.sh"
#   it "does the thing" && {
#     out="$(run_script ...)"
#     assert_eq "expected" "$out"
#   }
#   summary

set -uo pipefail

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_RUN=0
CURRENT_TEST=""
FAILED_TESTS=()

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PLUGIN_ROOT

# Per-test scratch dir, recreated each it().
SCRATCH=""

it() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  SCRATCH="$(mktemp -d)"
  # mktemp creates 700; loosen to 755 so a non-root re-exec'd service user
  # (e.g. 'shannon' via with-shannon-user.sh) can traverse our scratch dirs.
  chmod 755 "$SCRATCH" 2>/dev/null || true
  export SCRATCH
  return 0
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf '  ok   %s\n' "$CURRENT_TEST"
  [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"
}

fail() {
  local msg="${1:-}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_TESTS+=("$CURRENT_TEST")
  printf '  FAIL %s\n' "$CURRENT_TEST"
  [ -n "$msg" ] && printf '       %s\n' "$msg"
  [ -n "$SCRATCH" ] && printf '       scratch kept: %s\n' "$SCRATCH"
  SCRATCH=""  # don't auto-delete on fail
}

assert_eq() {
  local want="$1" got="$2" label="${3:-}"
  if [ "$want" = "$got" ]; then
    pass
  else
    fail "${label:+$label: }want=[$want] got=[$got]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass
  else
    fail "${label:+$label: }expected to contain [$needle] in: $(printf '%s' "$haystack" | head -c 200)"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    fail "${label:+$label: }expected NOT to contain [$needle]"
  else
    pass
  fi
}

assert_file_exists() {
  local path="$1" label="${2:-}"
  if [ -f "$path" ]; then
    pass
  else
    fail "${label:+$label: }file missing: $path"
  fi
}

assert_exit_code() {
  local want="$1" got="$2" label="${3:-}"
  assert_eq "$want" "$got" "$label exit code"
}

# Run a plugin script. Captures stdout, stderr, and exit code into vars:
#   OUT, ERR, RC
# Usage: run bin/detect-webroot.sh /some/path
run() {
  local script="$1"; shift
  local stdout_f stderr_f
  stdout_f="$(mktemp)"; stderr_f="$(mktemp)"
  set +e
  bash "$PLUGIN_ROOT/$script" "$@" >"$stdout_f" 2>"$stderr_f"
  RC=$?
  set -e
  OUT="$(cat "$stdout_f")"
  ERR="$(cat "$stderr_f")"
  rm -f "$stdout_f" "$stderr_f"
}

# Same as run, but with env vars prefixed.
# Usage: run_env "FOO=bar BAZ=qux" bin/save-report.sh ...
run_env() {
  local envs="$1"; shift
  local script="$1"; shift
  local stdout_f stderr_f
  stdout_f="$(mktemp)"; stderr_f="$(mktemp)"
  set +e
  env -i HOME="${HOME:-/root}" PATH="$PATH" $envs bash "$PLUGIN_ROOT/$script" "$@" >"$stdout_f" 2>"$stderr_f"
  RC=$?
  set -e
  OUT="$(cat "$stdout_f")"
  ERR="$(cat "$stderr_f")"
  rm -f "$stdout_f" "$stderr_f"
}

summary() {
  echo
  echo "ran $TESTS_RUN  pass $TESTS_PASSED  fail $TESTS_FAILED"
  if [ $TESTS_FAILED -gt 0 ]; then
    echo "failed:"
    for t in "${FAILED_TESTS[@]}"; do echo "  - $t"; done
    exit 1
  fi
  exit 0
}
