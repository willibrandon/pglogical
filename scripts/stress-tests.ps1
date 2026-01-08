<#
.SYNOPSIS
    Stress test pglogical by running regression tests multiple times.

.DESCRIPTION
    This script runs the regression tests multiple times and tracks which tests
    fail across runs. Useful for identifying intermittent/flaky test failures.

.PARAMETER Runs
    Number of times to run the test suite. Default is 10.

.PARAMETER StopOnFailure
    Stop running after the first failure. Default is false (continue all runs).

.PARAMETER TestFilter
    Run only specific tests (comma-separated). If not specified, runs all tests.

.EXAMPLE
    .\stress-tests.ps1 -Runs 5

.EXAMPLE
    .\stress-tests.ps1 -Runs 10 -StopOnFailure

.EXAMPLE
    .\stress-tests.ps1 -TestFilter "init,basic,interfaces"
#>

param(
    [int]$Runs = 10,
    [switch]$StopOnFailure,
    [string]$TestFilter = ""
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$buildDir = Join-Path $projectRoot "build"
$resultsDir = Join-Path $projectRoot "test-results"

# Create results directory
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

# Track results
$runResults = @()
$failedTests = @{}
$startTime = Get-Date

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "pglogical Stress Test Runner" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Runs planned: $Runs"
Write-Host "Stop on failure: $StopOnFailure"
Write-Host "Results dir: $resultsDir"
Write-Host "Started at: $startTime"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

for ($i = 1; $i -le $Runs; $i++) {
    $runStart = Get-Date
    Write-Host "Run $i of $Runs starting at $runStart..." -ForegroundColor Yellow

    # Clean previous results
    $diffFile = Join-Path $projectRoot "regression.diffs"
    $outFile = Join-Path $projectRoot "regression.out"
    if (Test-Path $diffFile) { Remove-Item $diffFile -Force }
    if (Test-Path $outFile) { Remove-Item $outFile -Force }

    # Run tests
    $testOutput = & cmake --build $buildDir --target check 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $runEnd = Get-Date
    $duration = $runEnd - $runStart

    # Parse results
    $passed = @()
    $failed = @()

    foreach ($line in $testOutput -split "`n") {
        if ($line -match "^  ok \d+\s+-\s+(\S+)") {
            $passed += $matches[1]
        }
        elseif ($line -match "^  not ok \d+\s+-\s+(\S+)") {
            $testName = $matches[1]
            $failed += $testName
            if (-not $failedTests.ContainsKey($testName)) {
                $failedTests[$testName] = @()
            }
            $failedTests[$testName] += $i
        }
    }

    $result = @{
        Run = $i
        Passed = $passed.Count
        Failed = $failed.Count
        FailedTests = $failed
        Duration = $duration.TotalSeconds
        ExitCode = $exitCode
    }
    $runResults += $result

    # Save artifacts for failed runs
    if ($failed.Count -gt 0) {
        $runDir = Join-Path $resultsDir "run-$i"
        New-Item -ItemType Directory -Path $runDir -Force | Out-Null

        if (Test-Path $diffFile) {
            Copy-Item $diffFile (Join-Path $runDir "regression.diffs")
        }
        if (Test-Path $outFile) {
            Copy-Item $outFile (Join-Path $runDir "regression.out")
        }

        # Copy individual result files
        $resultsPath = Join-Path $projectRoot "results"
        if (Test-Path $resultsPath) {
            Copy-Item -Path $resultsPath -Destination (Join-Path $runDir "results") -Recurse -Force
        }

        $testOutput | Out-File (Join-Path $runDir "output.txt")
    }

    # Report
    if ($failed.Count -eq 0) {
        Write-Host "  Run $i PASSED ($($passed.Count) tests in $([math]::Round($duration.TotalSeconds, 1))s)" -ForegroundColor Green
    } else {
        Write-Host "  Run $i FAILED ($($failed.Count) failures: $($failed -join ', '))" -ForegroundColor Red
        Write-Host "  Artifacts saved to: $runDir" -ForegroundColor DarkGray

        if ($StopOnFailure) {
            Write-Host ""
            Write-Host "Stopping due to -StopOnFailure flag." -ForegroundColor Yellow
            break
        }
    }
}

$endTime = Get-Date
$totalDuration = $endTime - $startTime

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total runs: $($runResults.Count)"
Write-Host "Total time: $([math]::Round($totalDuration.TotalMinutes, 1)) minutes"
Write-Host ""

$passedRuns = ($runResults | Where-Object { $_.Failed -eq 0 }).Count
$failedRuns = ($runResults | Where-Object { $_.Failed -gt 0 }).Count

Write-Host "Passed runs: $passedRuns" -ForegroundColor Green
Write-Host "Failed runs: $failedRuns" -ForegroundColor $(if ($failedRuns -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($failedTests.Count -gt 0) {
    Write-Host "Flaky tests detected:" -ForegroundColor Yellow
    foreach ($test in $failedTests.Keys | Sort-Object) {
        $runs = $failedTests[$test] -join ", "
        $failRate = [math]::Round(($failedTests[$test].Count / $runResults.Count) * 100, 1)
        Write-Host "  $test - failed in runs: $runs ($failRate% failure rate)" -ForegroundColor Red
    }
} else {
    Write-Host "No flaky tests detected across $($runResults.Count) runs!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Results saved to: $resultsDir" -ForegroundColor DarkGray

# Return exit code based on whether any tests failed
if ($failedRuns -gt 0) {
    exit 1
} else {
    exit 0
}
