#Requires -Version 7.0
<#
.SYNOPSIS
  Publishes the legacy-system app as a self-contained single-file Windows exe.

.DESCRIPTION
  Run this once before an event (or after any code/scenario changes).
  Output: app/legacy-system/publish/
    legacy-system.exe   — single-file, self-contained, no .NET runtime required
    scenario.json       — copied here so it can be uploaded alongside the binary

  Upload both files to a public URL (GitHub release or Azure Blob) and set the
  AppBinaryUrl + InstallScriptUrl + ScenarioUrl parameters in install-legacy-app.ps1.

.PARAMETER Configuration  Build configuration (default Release)
#>
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$scriptDir   = $PSScriptRoot
$publishDir  = Join-Path $scriptDir 'publish'

Write-Host '[publish] Building and publishing legacy-system...' -ForegroundColor Cyan

dotnet publish "$scriptDir\LegacySystem.csproj" `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:PublishReadyToRun=true `
    --output $publishDir `
    --nologo

if ($LASTEXITCODE -ne 0) {
    Write-Error "[publish] dotnet publish failed"
    exit 1
}

# Copy scenario.json to publish output so it can be uploaded alongside the exe
$scenarioSrc = Join-Path $scriptDir 'scenario.json'
if (Test-Path $scenarioSrc) {
    Copy-Item -Path $scenarioSrc -Destination $publishDir -Force
}

# Copy install.ps1 to publish output
$installSrc = Join-Path $scriptDir 'install\install.ps1'
if (Test-Path $installSrc) {
    Copy-Item -Path $installSrc -Destination $publishDir -Force
}

Write-Host "`n[publish] Output: $publishDir" -ForegroundColor Green
Write-Host "  Files to upload:" -ForegroundColor Green
Get-ChildItem $publishDir -File | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host "    $_" }
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Upload legacy-system.exe, install.ps1, scenario.json to a public URL." -ForegroundColor Yellow
Write-Host "    2. Set AppBinaryUrl, InstallScriptUrl, ScenarioUrl in install-legacy-app.ps1." -ForegroundColor Yellow
Write-Host "    3. Set incidentGroundTruth in src/config.js to match scenario.json." -ForegroundColor Yellow
