# Legacy PHP Windows builds: CVE-2026-109618 / CVE-2026-109619

Patches and scripts to build **PHP 5.6, 7.0, 7.2, 7.3 and 7.4 for Windows** with the
fixes for the two critical remote code execution bugs announced on
[21 October 2026](https://www.php.net/archive/2026.php#2026-10-21-5):

- [CVE-2026-109618](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w): RCE via OOM corruption
- [CVE-2026-109619](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp): RCE via stale global state

php.net only released fixed builds for 8.2 and later, and Windows binaries for
nothing older. These versions are end of life: this is a stopgap to keep legacy
applications running while they are migrated, not a supported PHP.

## What is in the patches

| Version | Base tag | Patches | Source of the CVE fix |
|---|---|---|---|
| 7.4 | `php-7.4.33` | 1 | The PHP security team's backport, [`712e60f`](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2), applied to the 7.4.33 tag |
| 7.3 | `php-7.3.33` | 3 | Freexian ELTS backport (Debian `php7.3 7.3.31-1~deb10u16`), context adjusted for upstream 7.3.33 |
| 7.2 | `php-7.2.34` | 4 | Ported here from the 7.4 fix, using the 7.3 and 7.0 ELTS backports as references (patch 0004 only makes the packaging script run on the SDK's PHP 8) |
| 7.0 | `php-7.0.33` | 3 | Freexian ELTS backport (Debian `php7.0 7.0.33-0+deb9u26`), context adjusted for upstream 7.0.33 |
| 5.6 | `php-5.6.40` | 3 | Ported here from the 7.4 fix, following the 7.0 backport where the engines are alike; C89 for VS2012 (patch 0003 only fixes packaging of in-tree x64 builds) |

5.6 through 7.3 also get two prerequisites from the Freexian ELTS packages:
`max_multipart_body_parts` (CVE-2023-0662, which these versions never received
upstream and which the fix relies on), and, for 7.x, the `ZSTR_MAX_LEN` macro.
Each patch's commit message lists its origin and every deviation from the 7.4 fix.

## Behaviour changes to know before deploying

These come from the upstream fix itself and are the same on every version:

- **Hitting `memory_limit` ends the process.** "Allowed memory size exhausted", out of
  memory and allocation overflow errors are written to stderr and the process exits
  with code 1. Shutdown functions, destructors and output buffer flushing no longer
  run after such an error, and the client gets no response body.
  - **Apache `mod_php` on Windows** (`mpm_winnt`) runs every request in one child
    process, so one request hitting the memory limit takes down every request in
    flight while Apache restarts the child. Prefer FastCGI (IIS, or Apache with
    `mod_fcgid`) with the NTS build, where only one `php-cgi` process dies.
- **Session upload progress is disabled**, whatever `session.upload_progress.enabled` says.
- **`max_multipart_body_parts`** (new INI setting, default `-1` =
  `max_input_vars + max_file_uploads`) limits the parts of a multipart request.
- Multipart parts keep only their `Content-Disposition` and `Content-Type` headers,
  and the first of each; nothing in PHP used the others.

The advisory's mitigations are still worth applying, in `php.ini` or the server
config (not `.user.ini`): `session.upload_progress.enabled=0`, a modest
`post_max_size`, and request size limits at the web server or proxy.

## Building on Windows

Requirements per version (they can all live on one machine):

| Version | Compiler | Install |
|---|---|---|
| 7.2, 7.3, 7.4 | VC15 | Visual Studio 2017 with *Desktop development with C++* |
| 7.0 | VC14 | Visual Studio 2015, or VS2017's *VC++ 2015.3 v14.00 (v140) toolset for desktop* component |
| 5.6 | VC11 | Visual Studio 2012, Update 5 (Express for Windows Desktop is enough) |

Plus Git and internet access (github.com, windows.php.net, downloads.php.net).

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version all
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 7.3,7.2 -Flavors TS
powershell -ExecutionPolicy Bypass -File .\build.ps1 -Version 7.0 -Vc14WithVs2017
```

For each version the script clones the release tag, applies `patches\<version>`,
sets the version to e.g. `7.3.33-cve2026`, fetches the official dependency
libraries, and runs `configure --enable-snapshot-build` (every extension the
dependencies support, shared where possible), `nmake` and `nmake snap` for each
flavor. Packages land in `C:\php-sdk\dist`:

- `php-<version>-Win32-<vc>-x64.zip`: thread-safe, for Apache `mod_php`
- `php-<version>-nts-Win32-<vc>-x64.zip`: non-thread-safe, for IIS/FastCGI and `php-cgi`

`-Vc14WithVs2017` builds 7.0 with the VS2017 compiler when the VC14 toolset is
missing. The output links the same `vcruntime140`, but PHP 7.0 labels the compiler
"untested" and its API ID differs from official VC14 builds, which only matters for
loading separately built PECL DLLs.

Then check `php -v` shows the `-cve2026` suffix and compare `php -m` with the server
you are replacing.

> `build.ps1` has not yet been run end to end on Windows: the patches were validated
> on Linux (below). Expect the first run of each toolchain, 5.6 and 7.0 especially,
> to need small fixes.

### Comparing a build with the official one

`compare.ps1` checks a build from `build.ps1` against php.net's official build of the
same release, with php.net's own test pack:

```powershell
powershell -ExecutionPolicy Bypass -File .\compare.ps1 -Version 7.3 -TargetedOnly   # about a minute
powershell -ExecutionPolicy Bypass -File .\compare.ps1 -Version all -TargetedOnly   # every version built so far
powershell -ExecutionPolicy Bypass -File .\compare.ps1 -Version 7.3                 # full test pack, hours
powershell -ExecutionPolicy Bypass -File .\compare.ps1 -Version 7.4 -Jobs 8 -Flavor NTS
```

It downloads the official zip and test pack, enables in both builds the extensions that
load cleanly in both (the same `php.ini` for each), runs the targeted tests (the official
build fails the 3 that check the fix, the patched one must pass all 5), then the test pack
against each build. The report, `C:\php-sdk\compare\<version>-<flavor>\report.txt`, lists
the tests failing on one side only. Expect exactly the 9 tests the fix changes (the 8
`ext/session/tests/rfc1867*` tests and `tests/lang/bug45392.phpt`); anything else is worth
a look at its `.diff`. `-TestDirs Zend,tests,ext\standard` runs a subset.

### OpenSSL and other bundled libraries

The official dependency sets are as old as these PHP versions:

| Version | OpenSSL | DLLs |
|---|---|---|
| 7.4 / 7.3 / 7.2 | 1.1.1s / 1.1.1l / 1.1.1g | `libcrypto-1_1-x64.dll`, `libssl-1_1-x64.dll` |
| 7.0, 5.6 | 1.0.2q | `libeay32.dll`, `ssleay32.dll` |

For 7.2-7.4 the two OpenSSL DLLs can be replaced next to `php.exe` with any
OpenSSL 1.1.1 build, e.g. FireDaemon's signed 1.1.1w (the last public 1.1.1).
With Apache `mod_php`, the copy Apache loads first wins: update `Apache24\bin` too
if it ships `*-1_1-x64.dll`. `php -i` then shows the new *OpenSSL Library Version*.
5.6 and 7.0 would need a 1.0.2 build (1.0.2u was the last public one).

## Validation

`validate/` builds each release tag with and without its patches on Linux
(Docker, Debian 9 toolchain, minimal extensions), then runs PHP's own test suites
(`Zend`, `tests`, `ext/session`, `ext/standard`) and the targeted tests in `tests/`.

```bash
validate/validate.sh                 # all versions, ~30 minutes
QUICK=1 validate/validate.sh 7.3     # targeted tests only
```

Results when the patches were written (21 October 2026):

- All patched builds compile; regenerating `zend_vm_execute.h` from `zend_vm_def.h`
  gives back the patched file.
- PHP's test suites (5,700-7,000 tests per version): every patched version fails the
  same 9 tests more than its base tag, all expected:
  the 8 `ext/session/tests/rfc1867*` upload progress tests, and `tests/lang/bug45392.phpt`
  (output buffered before a memory limit error is no longer flushed).
- 5.6 and 7.2, the ports done here, were also run as debug builds (internal assertions
  and hash table consistency checks): no additional failures.
- `tests/`: every base tag fails the 3 tests of the fix (memory limit exit, session
  upload progress, multipart part limit) and passes the 2 behaviour tests (multipart
  headers, nested input arrays); every patched build passes all 5.

## Not covered

- **Other vulnerabilities fixed after these versions' end of life.** The Debian ELTS
  packages carry many more (e.g. CVE-2026-7258, out-of-bounds read in `urldecode()`);
  their `debian/patches` are a good source for further backports.
- The bundled libraries (OpenSSL, curl, libxml2, ...) beyond the DLL swap above.
- PHP 7.1 (no patches here; it sits between the 7.0 and 7.2 ports).

## Layout

```
build.ps1           Windows build for all versions
compare.ps1         patched build vs official build, with the official test pack
patches/<version>/  git format-patch series, applied in name order
tests/              targeted .phpt tests for the fix
validate/           Linux validation (Dockerfile, ci.sh, validate.sh, run-targeted.sh)
```

## Credits

The fix is by Arnaud Le Blanc and Ilija Tovilo (PHP security team). The 7.3 and 7.0
backports and the CVE-2023-0662 and `ZSTR_MAX_LEN` patches are by Guilhem Moulin
and Markus Koschany for Debian ELTS / Freexian. The patches are derived from PHP and
are under the [PHP License 3.01](https://www.php.net/license/3_01.txt).
