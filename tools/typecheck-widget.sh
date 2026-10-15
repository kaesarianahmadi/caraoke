#!/bin/bash
# Verifies the two things this machine CAN verify before a push.
#
# There is no iOS SDK here — Command Line Tools only — so `xcodebuild` cannot
# run and the real gate is CI's `ios-app-compile`. Build 68 was rejected there
# for an arity error (`swiftc -parse` catches syntax, not types; a private
# method gained a parameter and one call site was not updated).
#
# An attempt to type-check the widget target against the macOS SDK was
# abandoned: SwiftUI's AppIntents overlay and the iOS-only API surface produce
# cross-import errors that would need a growing pile of hand-written stubs.
# The honest local ceiling is:
#
#   1. `swiftc -parse` over every iOS source — syntax only.
#   2. The Core suite, compiled and run for real — its types ARE checked.
#
# Run both with the CI compile job understood as the real check. If you add a
# parameter to a shared method, grep its call sites by hand.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
FAIL=0

echo "== iOS parse sweep =="
for f in CaraokePOC/iOS/*.swift; do
  out=$(swiftc -parse "$f" 2>&1)
  if [ -n "$out" ]; then
    echo "PARSE FAIL: $f"
    echo "$out" | head -5
    FAIL=1
  fi
done
[ "$FAIL" -eq 0 ] && echo "  all $(ls CaraokePOC/iOS/*.swift | wc -l | tr -d ' ') files parse clean"

echo "== Core suite (types checked) =="
# The suite resolves fixtures relative to the project dir, so run it from there.
( cd CaraokePOC || exit 1
  mkdir -p .build
  if swiftc -Onone -module-cache-path .build/modulecache \
       Sources/CaraokeCore/*.swift Tests/main.swift -o .build/testrunner 2>&1 | head -5; then
    .build/testrunner | tail -2
  else
    echo "core build FAILED"; exit 1
  fi
) || FAIL=1

echo "== call-site arity reminder =="
echo "  CI ios-app-compile is the only true type check. Re-grep call sites after"
echo "  changing any shared signature."

exit $FAIL
