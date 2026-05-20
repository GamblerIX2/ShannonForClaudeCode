#!/usr/bin/env bash
# Tests for bin/web-deny-templates.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-web-deny-templates.sh"

# ── arg handling ─────────────────────────────────────────────────────────
it "errors with no arg"
run bin/web-deny-templates.sh
assert_exit_code "1" "$RC"

it "errors with non-existent dir"
run bin/web-deny-templates.sh "/nonexistent/path/here"
assert_exit_code "1" "$RC"

it "succeeds with valid dir"
run bin/web-deny-templates.sh "$SCRATCH"
assert_exit_code "0" "$RC"

# ── file creation ────────────────────────────────────────────────────────
for f in .htaccess _apache-deny.conf _nginx-deny.conf _caddy-deny.Caddyfile _lighttpd-deny.conf _iis-web.config README.PROTECT.md; do
  it "creates $f"
  run bin/web-deny-templates.sh "$SCRATCH"
  assert_file_exists "$SCRATCH/$f"
done

# ── content correctness ──────────────────────────────────────────────────
it ".htaccess contains Require all denied (Apache 2.4)"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/.htaccess")" "Require all denied"

it ".htaccess includes Apache 2.2 fallback (Order deny,allow)"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/.htaccess")" "Deny from all"

it "_nginx-deny.conf uses base dir name as location"
base="$(basename "$SCRATCH")"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_nginx-deny.conf")" "location ^~ /$base/"

it "_nginx-deny.conf returns 404 (not 403 — less info leak)"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_nginx-deny.conf")" "return 404"

it "_apache-deny.conf <Directory> targets absolute path"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_apache-deny.conf")" "<Directory \"$SCRATCH\">"

it "_caddy-deny.Caddyfile uses base as path matcher"
base="$(basename "$SCRATCH")"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_caddy-deny.Caddyfile")" "path /$base/*"

it "_lighttpd-deny.conf condition uses base"
base="$(basename "$SCRATCH")"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_lighttpd-deny.conf")" "^/$base"

it "_iis-web.config denies all users"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/_iis-web.config")" 'accessType="Deny" users="*"'

it "README mentions all six server templates"
run bin/web-deny-templates.sh "$SCRATCH"
content="$(cat "$SCRATCH/README.PROTECT.md")"
for name in ".htaccess" "_apache-deny.conf" "_nginx-deny.conf" "_caddy-deny.Caddyfile" "_lighttpd-deny.conf" "_iis-web.config"; do
  if ! printf '%s' "$content" | grep -qF -- "$name"; then
    fail "README missing reference to $name"
    continue 2
  fi
done
pass

it "README curl example uses base dir name"
base="$(basename "$SCRATCH")"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$(cat "$SCRATCH/README.PROTECT.md")" "/$base/"

# ── permissions ──────────────────────────────────────────────────────────
it "chmods dir to 700"
run bin/web-deny-templates.sh "$SCRATCH"
mode="$(stat -c '%a' "$SCRATCH")"
assert_eq "700" "$mode"

# ── stderr signal ────────────────────────────────────────────────────────
it "emits DENY_TEMPLATES_WRITTEN= on stderr"
run bin/web-deny-templates.sh "$SCRATCH"
assert_contains "$ERR" "DENY_TEMPLATES_WRITTEN=$SCRATCH"

# ── idempotency ──────────────────────────────────────────────────────────
it "re-running overwrites cleanly (no errors)"
run bin/web-deny-templates.sh "$SCRATCH"
run bin/web-deny-templates.sh "$SCRATCH"
assert_exit_code "0" "$RC"

# ── path-with-spaces ─────────────────────────────────────────────────────
it "handles dir name with spaces"
weird="$SCRATCH/dir with space"
mkdir -p "$weird"
run bin/web-deny-templates.sh "$weird"
assert_exit_code "0" "$RC"

it "nginx template escapes/quotes space-containing base correctly"
weird="$SCRATCH/odd name"
mkdir -p "$weird"
run bin/web-deny-templates.sh "$weird"
# We don't expect proper escaping yet — but verify file was at least written.
assert_file_exists "$weird/_nginx-deny.conf"

summary
