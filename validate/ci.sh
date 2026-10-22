#!/bin/bash
# Build one PHP source tarball (Linux, minimal extensions) and test it.
# usage: ci.sh <tarball in /tars> <label> [--debug] [--zts]
# --zts builds thread-safe, like the Windows TS builds (catches missing TSRMLS_CC in 5.6).
# Mounts: /tars (sources, read-only), /out (results), /tests (targeted .phpt, optional)
# Set QUICK=1 to skip PHP's own test suites.
# Results: /out/<label>.summary, .fails, .targeted, .warnings, and the build logs.
set -uo pipefail
tar=$1; label=$2; shift 2
out=/out/$label
log() { echo "[$(date +%T)] $*" | tee -a $out.summary; }

: > $out.summary
mkdir -p /build/$label && cd /build/$label && tar -xf /tars/$tar || { log "EXTRACT FAILED"; exit 1; }

cfg="--disable-all --enable-session --enable-cli --enable-cgi --disable-phpdbg --without-pear"
for opt in "$@"; do
  case $opt in
    --debug) cfg="$cfg --enable-debug" ;;
    --zts)   cfg="$cfg --enable-maintainer-zts" ;;
  esac
done

log "buildconf"
./buildconf --force > $out.buildconf.log 2>&1 || { log "BUILDCONF FAILED"; exit 1; }
log "configure $cfg"
./configure $cfg > $out.configure.log 2>&1 || { log "CONFIGURE FAILED"; tail -5 $out.configure.log >> $out.summary; exit 1; }
log "make"
make -j4 > $out.make.log 2>&1 || { log "MAKE FAILED"; tail -40 $out.make.log >> $out.summary; exit 1; }
log "build ok: $(sapi/cli/php -v | head -1)"
# Warnings in the files the backports touch: pointer/integer mix-ups here mean a
# wrong argument list, which only crashes at run time.
grep -E 'warning:' $out.make.log | grep -E '/(Zend|main|ext/session)/' | sort -u > $out.warnings
if grep -qE 'makes (pointer from integer|integer from pointer)|-Wint-conversion' $out.warnings; then
  log "WARNING: pointer/integer mix-ups in Zend, main or ext/session (see $label.warnings)"
fi

# The generated VM must match zend_vm_def.h: regenerate and compare.
cp Zend/zend_vm_execute.h /tmp/vm_execute.orig
if sapi/cli/php Zend/zend_vm_gen.php > $out.vmgen.log 2>&1; then
  if cmp -s /tmp/vm_execute.orig Zend/zend_vm_execute.h; then log "vmgen: zend_vm_execute.h identical after regeneration"
  else log "vmgen: zend_vm_execute.h DIFFERS after regeneration"; diff -u /tmp/vm_execute.orig Zend/zend_vm_execute.h > $out.vmgen.diff; fi
  cp /tmp/vm_execute.orig Zend/zend_vm_execute.h
else log "vmgen: generator failed (see $label.vmgen.log)"; fi

# Keep the binaries for later runs.
mkdir -p /out/bin/$label && cp sapi/cli/php sapi/cgi/php-cgi run-tests.php /out/bin/$label/

if [ -d /tests ]; then
  run-targeted.sh /out/bin/$label /tests > $out.targeted 2>&1
  log "targeted tests: $(grep -c '^PASS' $out.targeted) passed, $(grep -c '^FAIL' $out.targeted) failed"
fi

if [ "${QUICK:-0}" != 1 ]; then
  log "PHP test suites"
  export TEST_PHP_EXECUTABLE=$PWD/sapi/cli/php TEST_PHP_CGI_EXECUTABLE=$PWD/sapi/cgi/php-cgi NO_INTERACTION=1 REPORT_EXIT_STATUS=0
  sapi/cli/php run-tests.php -q --set-timeout 300 Zend tests ext/session ext/standard/tests > $out.tests.log 2>&1
  sed -n '/^FAILED TEST SUMMARY/,/^=====/p' $out.tests.log | grep -oE '\[[^]]+\.phpt\]' | tr -d '[]' | sort -u > $out.fails
  log "$(grep -E '^Tests (passed|failed)' $out.tests.log | tr -s ' ' | tr '\n' ' ')"
fi
log "done"
