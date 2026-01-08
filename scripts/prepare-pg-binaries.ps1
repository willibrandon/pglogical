# Script to download and repackage PostgreSQL binaries for CI
# Run this locally, then upload the resulting ZIPs to GitHub release "pg-binaries"

$versions = @{
    "13" = "13.20-1"
    "14" = "14.17-1"
    "15" = "15.12-1"
    "16" = "16.8-1"
    "17" = "17.4-1"
    "18" = "18.0-1"
}

$outputDir = ".\pg-binaries"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

foreach ($pgMajor in $versions.Keys) {
    $pgVersion = $versions[$pgMajor]
    $edbUrl = "https://get.enterprisedb.com/postgresql/postgresql-$pgVersion-windows-x64-binaries.zip"
    $downloadPath = "$env:TEMP\postgresql-$pgMajor-edb.zip"
    $extractPath = "$env:TEMP\pg-extract-$pgMajor"
    $outputZip = "$outputDir\postgresql-$pgMajor-windows-x64.zip"

    Write-Host "Processing PostgreSQL $pgMajor..." -ForegroundColor Cyan

    # Download from EDB
    if (-not (Test-Path $downloadPath)) {
        Write-Host "  Downloading from EDB..."
        Invoke-WebRequest -Uri $edbUrl -OutFile $downloadPath -UseBasicParsing
    } else {
        Write-Host "  Using cached download"
    }

    # Extract
    Write-Host "  Extracting..."
    Remove-Item -Recurse -Force $extractPath -ErrorAction SilentlyContinue
    Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force

    # EDB ZIP extracts to pgsql/ folder - perfect, just rezip
    Write-Host "  Creating $outputZip..."
    Remove-Item $outputZip -ErrorAction SilentlyContinue
    Compress-Archive -Path "$extractPath\pgsql" -DestinationPath $outputZip -CompressionLevel Optimal

    # Cleanup
    Remove-Item -Recurse -Force $extractPath

    $size = [math]::Round((Get-Item $outputZip).Length / 1MB, 1)
    Write-Host "  Done: $outputZip ($size MB)" -ForegroundColor Green
}

Write-Host ""
Write-Host "All binaries ready in $outputDir" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Create GitHub release 'pg-binaries' at:"
Write-Host "   https://github.com/willibrandon/pglogical/releases/new?tag=pg-binaries"
Write-Host ""
Write-Host "2. Upload all ZIP files from $outputDir"
Write-Host ""
Write-Host "3. Publish the release"
