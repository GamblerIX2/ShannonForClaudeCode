#!/usr/bin/env bash
# Tests for bin/build-scan-config.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-build-scan-config.sh"

it "errors with no args"
run bin/build-scan-config.sh
assert_exit_code "2" "$RC"

it "errors with invalid exploit flag"
run bin/build-scan-config.sh "$SCRATCH/out.yaml" maybe < /dev/null
assert_exit_code "2" "$RC"

it "accepts exploit=true with no excludes"
out="$SCRATCH/out.yaml"
echo "" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
[ -f "$out" ] && pass || fail "out missing"

it "accepts exploit=false"
out="$SCRATCH/out.yaml"
echo "" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" false >/dev/null
content="$(cat "$out")"
assert_contains "$content" "exploit: 'false'"

it "emits exploit as quoted string (schema requirement)"
out="$SCRATCH/out.yaml"
echo "" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
assert_contains "$content" "exploit: 'true'"

it "writes excludes as code_path entries"
out="$SCRATCH/out.yaml"
printf 'node_modules\nvendor\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
assert_contains "$content" "type: code_path"

it "each exclude has type, value, description"
out="$SCRATCH/out.yaml"
printf 'node_modules\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
type_count="$(printf '%s\n' "$content" | grep -c 'type: code_path')"
val_count="$(printf '%s\n' "$content" | grep -c 'value:')"
desc_count="$(printf '%s\n' "$content" | grep -c 'description:')"
if [ "$type_count" = "1" ] && [ "$val_count" = "1" ] && [ "$desc_count" = "1" ]; then
  pass
else
  fail "type=$type_count value=$val_count description=$desc_count (expected 1 each)"
fi

it "skips blank lines"
out="$SCRATCH/out.yaml"
printf '\n\nnode_modules\n\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
val_count="$(printf '%s\n' "$content" | grep -c 'value:')"
assert_eq "1" "$val_count"

it "skips comment lines"
out="$SCRATCH/out.yaml"
printf '# header comment\nnode_modules\n# trailing comment\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
val_count="$(printf '%s\n' "$content" | grep -c 'value:')"
assert_eq "1" "$val_count"

it "dedupes identical excludes"
out="$SCRATCH/out.yaml"
printf 'node_modules\nnode_modules\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
val_count="$(printf '%s\n' "$content" | grep -c 'value:')"
assert_eq "1" "$val_count"

it "trims whitespace from excludes"
out="$SCRATCH/out.yaml"
printf '   node_modules   \n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
assert_contains "$content" "value: 'node_modules'"

it "single-quotes glob patterns"
out="$SCRATCH/out.yaml"
printf '**/*.min.js\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
assert_contains "$content" "value: '**/*.min.js'"

it "escapes single quotes inside exclude values"
out="$SCRATCH/out.yaml"
printf "foo's-dir\n" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
content="$(cat "$out")"
# YAML single-quoted strings escape ' as ''
assert_contains "$content" "foo''s-dir"

it "writes file with mode 644 (not secret)"
out="$SCRATCH/out.yaml"
echo "node_modules" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
mode="$(stat -c '%a' "$out")"
assert_eq "644" "$mode"

it "creates parent dir if missing"
out="$SCRATCH/nested/deep/out.yaml"
echo "" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
[ -f "$out" ] && pass || fail "nested out missing"

it "prints OK line on stdout"
out="$SCRATCH/out.yaml"
OUT="$(printf 'a\nb\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true)"
assert_contains "$OUT" "OK: wrote"

it "OK line reports correct count and exploit flag"
out="$SCRATCH/out.yaml"
OUT="$(printf 'a\nb\nc\n' | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" false)"
assert_contains "$OUT" "excludes=3, exploit=false"

# Schema sanity — pipe through python yaml to ensure valid YAML.
it "output is valid YAML"
out="$SCRATCH/out.yaml"
printf "node_modules\n**/*.min.js\nfoo's-dir\n" | bash "$PLUGIN_ROOT/bin/build-scan-config.sh" "$out" true >/dev/null
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$out" 2>/dev/null; then
    pass
  else
    fail "python yaml.safe_load rejected output: $(cat "$out")"
  fi
else
  # No python — skip but pass
  pass
fi

summary
