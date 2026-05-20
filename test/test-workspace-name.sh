#!/usr/bin/env bash
# Tests for bin/workspace-name.sh

set -uo pipefail
. "$(dirname "$0")/lib.sh"

echo "test-workspace-name.sh"

it "errors with no arg"
run bin/workspace-name.sh
assert_exit_code "2" "$RC"

it "https://www.example.com → www-example-com-shannon"
run bin/workspace-name.sh "https://www.example.com"
assert_eq "www-example-com-shannon" "$OUT"

it "deterministic — same URL same name"
run bin/workspace-name.sh "https://www.example.com/foo?bar=1"
a="$OUT"
run bin/workspace-name.sh "https://www.example.com/baz?qux=2"
b="$OUT"
assert_eq "$a" "$b"

it "strips path and query"
run bin/workspace-name.sh "https://api.example.com/v1/x?y=z"
assert_eq "api-example-com-shannon" "$OUT"

it "lowercases host"
run bin/workspace-name.sh "https://EXAMPLE.COM"
assert_eq "example-com-shannon" "$OUT"

it "preserves port as numeric segment"
run bin/workspace-name.sh "https://foo.com:8080"
assert_eq "foo-com-8080-shannon" "$OUT"

it "handles http://"
run bin/workspace-name.sh "http://example.com"
assert_eq "example-com-shannon" "$OUT"

it "fallback to 'target' when URL is unparseable"
run bin/workspace-name.sh "?????"
assert_eq "target-shannon" "$OUT"

it "BUG TARGET: real-world www.smyqh.com URL"
run bin/workspace-name.sh "https://www.smyqh.com"
assert_eq "www-smyqh-com-shannon" "$OUT"

summary
