#!/usr/bin/env bash
# Run every test-*.sh in this directory. Exits non-zero on any failure.

set -uo pipefail

here="$(dirname "$0")"
failed=0
suites=0

for f in "$here"/test-*.sh; do
  suites=$((suites + 1))
  echo
  if ! bash "$f"; then
    failed=$((failed + 1))
  fi
done

echo
echo "==============================="
if [ $failed -eq 0 ]; then
  echo "ALL SUITES PASSED ($suites suites)"
  exit 0
else
  echo "FAILED: $failed/$suites suites"
  exit 1
fi
