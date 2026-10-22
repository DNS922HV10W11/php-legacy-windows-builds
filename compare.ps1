<#
.SYNOPSIS
    Tests a patched build from build.ps1 against the official php.net build of the
    same release.

.DESCRIPTION
    For each requested version:
      1. Downloads the official zip and test pack from windows.php.net's archives,
         and finds the patched zip in <Root>\dist.
      2. Loads every extension DLL of both builds, one at a time, and enables the ones
         that load cleanly in both: the same php.ini is written next to both php.exe.
      3. Runs the targeted tests in tests\ against both builds. The patched build must
         pass all of them; the official one fails the three that check the fix.
      4. Unless -TargetedOnly: runs the official test pack against both builds and
         reports the tests that fail on one side only. Failures shared by both builds
         (network, locale, missing database servers, ...) are left out.

    Results go to <Root>\compare\<version>-<flavor>\report.txt.

    The full test pack is 13,000-17,000 tests: count 1-2 hours per build for 5.6-7.3,
    which run tests one at a time. 7.4 can run them in parallel with -Jobs.

.EXAMPLE
    .\compare.ps1 -Version 7.3 -TargetedOnly
.EXAMPLE
    .\compare.ps1 -Version 7.3
.EXAMPLE
    .\compare.ps1 -Version 7.4 -Jobs 8 -TestDirs Zend,tests,ext\standard
#>
[CmdletBinding()]
param(
    # 5.6, 7.0, 7.2, 7.3 or 7.4; several as 7.3,7.2 (run one after the other).
    [Parameter(Mandatory)]
    [string[]] $Version,

    # Same Root as build.ps1: patched zips are read from <Root>\dist. Must not contain spaces.
    [string] $Root = 'C:\php-sdk',

    [ValidateSet('x64', 'x86')]
    [string] $Arch = 'x64',

    # TS or NTS: which of the two builds to compare.
    [ValidateSet('TS', 'NTS')]
    [string] $Flavor = 'TS',

    # The suffix given to build.ps1.
    [string] $VersionSuffix = '-cve2026',

    # Test pack directories to run, e.g. Zend,tests,ext\standard. Default: all.
    [string[]] $TestDirs = @(),

    # 7.4 only: parallel test workers (run-tests -j).
    [int] $Jobs = 0,

    # Only run the targeted tests (about a minute).
    [switch] $TargetedOnly
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Official = 'https://windows.php.net/downloads/releases/archives'
$Releases = [ordered]@{
    '5.6' = @{ Full = '5.6.40'; Crt = 'VC11' }
    '7.0' = @{ Full = '7.0.33'; Crt = 'VC14' }
    '7.2' = @{ Full = '7.2.34'; Crt = 'VC15' }
    '7.3' = @{ Full = '7.3.33'; Crt = 'VC15' }
    '7.4' = @{ Full = '7.4.33'; Crt = 'vc15' }
}

# Tests the fix is known to change (see README): every patched version fails these.
$ExpectedChanges = @(
    'ext/session/tests/rfc1867.phpt'
    'ext/session/tests/rfc1867_inter.phpt'
    'ext/session/tests/rfc1867_sid_cookie.phpt'
    'ext/session/tests/rfc1867_sid_get.phpt'
    'ext/session/tests/rfc1867_sid_get_2.phpt'
    'ext/session/tests/rfc1867_sid_invalid.phpt'
    'ext/session/tests/rfc1867_sid_only_cookie.phpt'
    'ext/session/tests/rfc1867_sid_post.phpt'
    'tests/lang/bug45392.phpt'
)

function Split-List([string[]] $Values) {
    @($Values | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
}

function Get-File([string] $Url, [string] $Path) {
    if (-not (Test-Path $Path)) {
        Write-Host "Downloading $Url"
        Invoke-WebRequest -Uri $Url -OutFile "$Path.part" -UseBasicParsing
        Move-Item "$Path.part" $Path
    }
}

function Expand-Fresh([string] $Zip, [string] $Dir) {
    if (Test-Path $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $sevenZip = Join-Path $Root 'bin\7za.exe'
    if (Test-Path $sevenZip) {
        & $sevenZip x -y "-o$Dir" $Zip | Out-Null
        if ($LASTEXITCODE) { throw "7za failed to extract $Zip" }
    } else {
        Expand-Archive -Path $Zip -DestinationPath $Dir -Force
    }
}

# Runs cmd.exe so that PHP's stderr doesn't become PowerShell errors; returns the output.
function Invoke-Cmd([string] $CommandLine) {
    $ErrorActionPreference = 'Continue'
    $out = & cmd.exe /c "$CommandLine 2>&1"
    ($out | Out-String).Trim()
}

function Get-FailedTests([string] $Log, [string] $TestsDir) {
    if (-not (Test-Path $Log)) { return @() }
    $inSummary = $false
    $prefix = ($TestsDir.TrimEnd('\') + '\').ToLowerInvariant()
    foreach ($line in [IO.File]::ReadAllLines($Log)) {
        if ($line -match '^(FAILED|BORKED) TEST SUMMARY') { $inSummary = $true; continue }
        if ($inSummary -and $line -match '^=+$') { $inSummary = $false; continue }
        if ($inSummary -and $line -match '\[([^\]]+\.phpt)\]') {
            $path = $Matches[1]
            if ($path.ToLowerInvariant().StartsWith($prefix)) { $path = $path.Substring($prefix.Length) }
            $path.Replace('\', '/')
        }
    }
}

function Invoke-TestRun([string] $PhpDir, [string] $Runner, [string] $WorkDir, [string[]] $Targets, [string] $Log, [string[]] $Extra) {
    $env:TEST_PHP_EXECUTABLE     = Join-Path $PhpDir 'php.exe'
    $env:TEST_PHP_CGI_EXECUTABLE = Join-Path $PhpDir 'php-cgi.exe'
    $env:NO_INTERACTION          = '1'
    $env:REPORT_EXIT_STATUS      = '0'
    $env:SKIP_ONLINE_TESTS       = '1'
    Push-Location $WorkDir
    try {
        $cmd = "$($env:TEST_PHP_EXECUTABLE) $Runner -q --offline --set-timeout 300 $($Extra -join ' ') $($Targets -join ' ') > $Log"
        Invoke-Cmd $cmd | Out-Null
    } finally {
        Pop-Location
    }
}

# --- Preflight -------------------------------------------------------------

if ($Root -match '\s') { throw "Root must not contain spaces: $Root" }
$Version = Split-List $Version
$unknown = @($Version | Where-Object { -not $Releases.Contains($_) })
if ($unknown) { throw "Unknown version(s): $($unknown -join ', '). Use 5.6, 7.0, 7.2, 7.3 or 7.4." }
$TestDirs = Split-List $TestDirs

$dist = Join-Path $Root 'dist'
$officialDir = Join-Path $Root 'official'
New-Item -ItemType Directory -Force -Path $officialDir | Out-Null

foreach ($ver in $Version) {
    $rel  = $Releases[$ver]
    $full = $rel.Full
    $nts  = if ($Flavor -eq 'NTS') { '-nts' } else { '' }
    $work = Join-Path $Root "compare\$ver-$Flavor"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $report = Join-Path $work 'report.txt'
    $lines = New-Object System.Collections.Generic.List[string]
    function Out-Report([string] $Text = '') { $lines.Add($Text); Write-Host $Text }

    Write-Host ''
    Write-Host "===== PHP $ver ${Flavor}: official $full vs patched $full$VersionSuffix =====" -ForegroundColor Cyan

    # Builds and test pack.
    $pattern = '^php-' + [regex]::Escape("$full$VersionSuffix$nts") + '-Win32-.+-' + $Arch + '\.zip$'
    $patchedZip = Get-ChildItem $dist -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pattern } |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $patchedZip) { throw "No patched $Flavor zip for $ver in $dist (looked for $pattern). Run build.ps1 first." }

    $officialZip = Join-Path $officialDir "php-$full$nts-Win32-$($rel.Crt)-$Arch.zip"
    Get-File "$Official/$(Split-Path $officialZip -Leaf)" $officialZip
    $testPack = Join-Path $officialDir "php-test-pack-$full.zip"
    Get-File "$Official/$(Split-Path $testPack -Leaf)" $testPack

    Write-Host "Unpacking $($patchedZip.Name) and $(Split-Path $officialZip -Leaf)"
    $builds = [ordered]@{ official = (Join-Path $work 'official'); patched = (Join-Path $work 'patched') }
    Expand-Fresh $officialZip $builds.official
    Expand-Fresh $patchedZip.FullName $builds.patched

    # Extensions that load cleanly in both builds.
    $probe = Join-Path $work 'probe.php'
    [IO.File]::WriteAllText($probe, '<?php echo "ok";')
    function Test-Extension([string] $PhpDir, [string] $Dll, [string[]] $Preload) {
        $ini = "-n -d extension_dir=$PhpDir\ext -d date.timezone=UTC"
        foreach ($p in $Preload) { $ini += " -d extension=$p" }
        (Invoke-Cmd "$PhpDir\php.exe $ini -d extension=$Dll $probe") -eq 'ok'
    }
    $dlls = @(Get-ChildItem (Join-Path $builds.official 'ext') -Filter 'php_*.dll' | ForEach-Object { $_.Name }) |
            Where-Object { Test-Path (Join-Path $builds.patched "ext\$_") } |
            Where-Object { $_ -notin 'php_opcache.dll', 'php_phpdbg_webhelper.dll' } | Sort-Object
    # exif needs mbstring loaded first.
    $preload = @()
    if ($dlls -contains 'php_mbstring.dll' -and (Test-Extension $builds.official 'php_mbstring.dll' @()) -and (Test-Extension $builds.patched 'php_mbstring.dll' @())) {
        $preload = @('php_mbstring.dll')
    }
    $enabled = @($preload); $skipped = @()
    foreach ($dll in $dlls | Where-Object { $_ -notin $preload }) {
        if ((Test-Extension $builds.official $dll $preload) -and (Test-Extension $builds.patched $dll $preload)) { $enabled += $dll } else { $skipped += $dll }
    }
    foreach ($dir in $builds.Values) {
        $ini = @("extension_dir = `"$dir\ext`"", 'date.timezone = UTC') + ($enabled | ForEach-Object { "extension=$_" })
        [IO.File]::WriteAllLines((Join-Path $dir 'php.ini'), $ini)
    }

    Out-Report "PHP $ver $Flavor $Arch"
    Out-Report "  official: $(Split-Path $officialZip -Leaf)"
    Out-Report "  patched:  $($patchedZip.Name)"
    Out-Report "  extensions enabled in both ($($enabled.Count)): $(($enabled | ForEach-Object { $_ -replace '^php_|\.dll$' }) -join ' ')"
    if ($skipped) { Out-Report "  not loadable in both, left out: $(($skipped | ForEach-Object { $_ -replace '^php_|\.dll$' }) -join ' ')" }
    foreach ($kind in $builds.Keys) {
        Out-Report "  $kind php -v: $((Invoke-Cmd "$($builds[$kind])\php.exe -v") -split "`r?`n" | Select-Object -First 1)"
    }

    # The official test pack, once per build: run-tests writes its results next to the tests.
    $packs = [ordered]@{}
    foreach ($kind in $builds.Keys) {
        $packs[$kind] = Join-Path $work "tests-$kind"
        Expand-Fresh $testPack $packs[$kind]
    }
    $runnerName = @('run-test.php', 'run-tests.php') | Where-Object { Test-Path (Join-Path $packs.official $_) } | Select-Object -First 1
    if (-not $runnerName) { throw "No run-test.php in $testPack" }

    # Targeted tests.
    Out-Report ''
    Out-Report 'Targeted tests (tests\*.phpt):'
    foreach ($kind in $builds.Keys) {
        $dir = Join-Path $work "targeted-$kind"
        if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Copy-Item (Join-Path $PSScriptRoot 'tests\*.phpt') $dir
        $log = Join-Path $work "targeted-$kind.log"
        Invoke-TestRun $builds[$kind] (Join-Path $packs[$kind] $runnerName) $packs[$kind] @($dir) $log @()
        $failed = @(Get-FailedTests $log $dir)
        $total = @(Get-ChildItem $dir -Filter *.phpt).Count
        Out-Report ("  {0,-8} {1} of {2} passed{3}" -f $kind, ($total - $failed.Count), $total, $(if ($failed) { '; failed: ' + ($failed -join ', ') } else { '' }))
    }

    if (-not $TargetedOnly) {
        $targets = if ($TestDirs) { $TestDirs } else {
            Get-ChildItem $packs.official -Directory | Where-Object { $_.Name -in 'Zend', 'tests', 'ext', 'sapi' } | ForEach-Object { $_.Name }
        }
        $extra = @()
        if ($Jobs -gt 0) {
            if ($ver -eq '7.4') { $extra += "-j$Jobs" } else { Write-Warning "-Jobs needs 7.4's run-tests; $ver runs tests one at a time." }
        }
        $failed = @{}
        foreach ($kind in $builds.Keys) {
            $log = Join-Path $work "suite-$kind.log"
            Write-Host "Running the test pack against the $kind build ($($targets -join ', ')); log: $log"
            $started = Get-Date
            Invoke-TestRun $builds[$kind] $runnerName $packs[$kind] $targets $log $extra
            $failed[$kind] = @(Get-FailedTests $log $packs[$kind])
            Write-Host ("  {0}: {1} failed tests, {2:N0} minutes" -f $kind, $failed[$kind].Count, ((Get-Date) - $started).TotalMinutes)
        }

        $onlyPatched  = @($failed.patched | Where-Object { $_ -notin $failed.official } | Sort-Object)
        $onlyOfficial = @($failed.official | Where-Object { $_ -notin $failed.patched } | Sort-Object)
        $expected     = @($onlyPatched | Where-Object { $_ -in $ExpectedChanges })
        $unexpected   = @($onlyPatched | Where-Object { $_ -notin $ExpectedChanges })

        Out-Report ''
        Out-Report "Test pack ($($targets -join ', ')):"
        foreach ($kind in $builds.Keys) {
            $summary = (Select-String -Path (Join-Path $work "suite-$kind.log") -Pattern '^Tests (passed|failed|skipped) ' | ForEach-Object { ($_.Line -replace '\s+', ' ').Trim() }) -join '; '
            Out-Report "  $kind`: $summary"
        }
        Out-Report "  failing in both builds: $(@($failed.patched | Where-Object { $_ -in $failed.official }).Count) (not a difference)"
        Out-Report ''
        Out-Report "Failing only with the patches, expected ($($expected.Count) of $($ExpectedChanges.Count)):"
        $expected | ForEach-Object { Out-Report "  $_" }
        Out-Report ''
        Out-Report "Failing only with the patches, NOT expected ($($unexpected.Count)) - look at the .diff next to each test in $($packs.patched):"
        $unexpected | ForEach-Object { Out-Report "  $_" }
        Out-Report ''
        Out-Report "Failing only on the official build ($($onlyOfficial.Count)):"
        $onlyOfficial | ForEach-Object { Out-Report "  $_" }
    }

    [IO.File]::WriteAllLines($report, $lines)
    Write-Host "Report: $report" -ForegroundColor Green
}
