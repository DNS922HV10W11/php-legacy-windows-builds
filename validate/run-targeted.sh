#!/bin/bash
# Run the targeted CVE tests in tests/ against one PHP build.
# usage: run-targeted.sh <dir containing php, php-cgi and run-tests.php> <tests dir>
# Prints one PASS/FAIL/SKIP/BORK line per test, then the diffs of failed tests.
# Exits non-zero when a test fails.
set -u
work=$(mktemp -d)
cp -r "$1" "$work/bin" && cp "$2"/*.phpt "$work"/
bin=$work/bin
export TEST_PHP_EXECUTABLE=$bin/php TEST_PHP_CGI_EXECUTABLE=$bin/php-cgi NO_INTERACTION=1 REPORT_EXIT_STATUS=1
"$bin/php" "$bin/run-tests.php" "$work" > "$work/run.log" 2>&1
rc=$?
# Results look like "PASS <title> [<file>]", sometimes after a "TEST n/m [file]" progress prefix.
tr '\r' '\n' < "$work/run.log" | grep -oE '(PASS|FAIL|SKIP|BORK) .*\[[^]]*\.phpt\]' \
  | sed -E 's/ \[[^]]*\]$//' | sort -u
for f in "$work"/*.diff; do [ -e "$f" ] || continue; echo "--- $(basename "$f")"; head -12 "$f"; echo; done
exit $rc
