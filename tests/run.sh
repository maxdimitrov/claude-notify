#!/bin/sh
# Runs all sh tests. Exit non-zero if any fails.
here=$(cd "$(dirname "$0")" && pwd)
rc=0
for t in "$here"/test_*.sh; do
  echo "== $(basename "$t")"
  sh "$t" || rc=1
done
if [ "$rc" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit $rc
