#!/bin/bash
# Check the patches on Linux with Docker: build every release tag with and
# without its patches, run PHP's test suites and tests/*.phpt on both, and
# report what the patches change.
#
# usage: validate/validate.sh [version...]      e.g. validate/validate.sh 7.3 5.6
#        QUICK=1 validate/validate.sh           targeted tests only (minutes, not ~30 min)
# Works from Linux or Git Bash on Windows (Docker Desktop). Needs git, curl, docker.
# (docker calls set MSYS_NO_PATHCONV=1 so Git Bash leaves the container paths alone.)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
proj=$(dirname "$here")
work=${WORK:-$proj/.validate}
mkdir -p "$work/src" "$work/tars" "$work/out"

# Docker Desktop on Windows wants C:/... paths, not Git Bash's /c/...
hostpath() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

declare -A tag=([5.6]=php-5.6.40 [7.0]=php-7.0.33 [7.2]=php-7.2.34 [7.3]=php-7.3.33 [7.4]=php-7.4.33)
versions=${*:-5.6 7.0 7.2 7.3 7.4}

MSYS_NO_PATHCONV=1 docker build -q -t php-legacy-validate "$(hostpath "$here")" > /dev/null

for v in $versions; do
  t=${tag[$v]}
  s=$work/src/$v
  if [ ! -d "$s" ]; then
    if [ "$v" = 5.6 ]; then
      # The 5.6 git tree needs bison < 3.0 to regenerate its parser; the
      # release tarball ships the generated files.
      curl -fsSL -o "$work/src/$t.tar.gz" "https://www.php.net/distributions/$t.tar.gz"
      mkdir -p "$s" && tar -xzf "$work/src/$t.tar.gz" --strip-components=1 -C "$s"
    else
      git -c core.autocrlf=false -c advice.detachedHead=false clone -q --depth 1 --branch "$t" https://github.com/php/php-src.git "$s"
    fi
  fi
  tar -cf "$work/tars/base-$v.tar" -C "$s" --exclude=.git .

  rm -rf "${s:?}-patched" && cp -a "$s" "$s-patched"
  for p in "$proj/patches/$v"/*.patch; do
    # The 5.6 tarball tree is no git repository, but $work may sit inside one
    # (this project): stop git from finding it, or git apply would resolve the
    # patch paths against that repository and silently skip every file.
    (cd "$s-patched" && GIT_CEILING_DIRECTORIES="$(dirname "$s-patched")" git apply --whitespace=nowarn "$p")
  done
  last=$(ls "$proj/patches/$v"/*.patch | tail -1)
  (cd "$s-patched" && GIT_CEILING_DIRECTORIES="$(dirname "$s-patched")" git apply --check --reverse "$last") \
    || { echo "patches for $v did not apply" >&2; exit 1; }
  tar -cf "$work/tars/patched-$v.tar" -C "$s-patched" --exclude=.git .

  # base and patched: non-thread-safe builds with PHP's test suites (unless QUICK=1).
  # zts: the patched tree built thread-safe, like the Windows TS builds, targeted tests only.
  for kind in base patched zts; do
    tarball=$kind-$v.tar; quick=${QUICK:-0}; opts=
    if [ $kind = zts ]; then tarball=patched-$v.tar; quick=1; opts=--zts; fi
    docker rm -f "validate-$kind-$v" > /dev/null 2>&1 || true
    MSYS_NO_PATHCONV=1 docker run -d --name "validate-$kind-$v" -e QUICK="$quick" \
      -v "$(hostpath "$work/tars"):/tars:ro" -v "$(hostpath "$work/out"):/out" -v "$(hostpath "$proj/tests"):/tests:ro" \
      php-legacy-validate ci.sh "$tarball" "$kind-$v" $opts > /dev/null
  done
  echo "started $v (base, patched, patched thread-safe)"
done

for v in $versions; do docker wait "validate-base-$v" "validate-patched-$v" "validate-zts-$v" > /dev/null; done

echo
for v in $versions; do
  o=$work/out
  echo "===== PHP $v"
  grep -hE 'FAILED|DIFFERS|targeted|Tests' "$o/base-$v.summary" | sed 's/^/  base:    /'
  grep -hE 'FAILED|DIFFERS|targeted|Tests' "$o/patched-$v.summary" | sed 's/^/  patched: /'
  grep -hE 'FAILED|DIFFERS|targeted|WARNING' "$o/zts-$v.summary" | sed 's/^/  zts:     /'
  grep -h '^FAIL' "$o/patched-$v.targeted" "$o/zts-$v.targeted" 2>/dev/null | sed 's/^/  targeted /' || true
  if [ -f "$o/base-$v.fails" ] && [ -f "$o/patched-$v.fails" ]; then
    echo "  failing only with the patches:"
    comm -13 "$o/base-$v.fails" "$o/patched-$v.fails" | sed 's/^/    /'
  fi
  docker rm "validate-base-$v" "validate-patched-$v" "validate-zts-$v" > /dev/null
done
