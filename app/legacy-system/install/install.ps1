#Requires -Version 5.1
<#
.SYNOPSIS
  Installs and starts the legacy-system Windows Service on a participant VM.

.DESCRIPTION
  Called by the VM Custom Script Extension (CSE) deployed by
  infra/install-legacy-app.ps1.  The CSE downloads this script, the app
  binary, and (optionally) scenario.json to the same directory, then runs:

    powershell -ExecutionPolicy Unrestricted -File install.ps1 `
        -SlotId user01 `
        -IngestionEndpoint https://workshop-ingest-XXXX.azurewebsites.net `
        -IngestionKey <secret>

  IngestionKey arrives via protectedSettings and is never written to logs.

.PARAMETER SlotId           Participant slot, e.g. user01
.PARAMETER IngestionEndpoint Base URL of the shared Ingestion API
.PARAMETER IngestionKey     Per-slot ingestion key (from CSE protectedSettings)
#>
param(
    [Parameter(Mandatory)][string]$SlotId,
    [Parameter(Mandatory)][string]$IngestionEndpoint,
    [Parameter(Mandatory)][string]$IngestionKey
)

$ErrorActionPreference = 'Stop'
$svcName   = 'LegacySystem'
$installDir = 'C:\legacy-system'
$scriptDir  = $PSScriptRoot  # directory of this script = CSE download directory

Write-Output "[install] Starting legacy-system install for slot $SlotId"

# ── Stop and remove existing service (idempotent) ─────────────────────────────
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Status -ne 'Stopped') {
        Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }
    & sc.exe delete $svcName | Out-Null
    Start-Sleep -Seconds 2
    Write-Output "[install] Removed existing service"
}

# ── Create install directory ───────────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# ── Copy app binary ────────────────────────────────────────────────────────────
$binSrc = Join-Path $scriptDir 'legacy-system.exe'
if (-not (Test-Path $binSrc)) {
    Write-Error "[install] Cannot find legacy-system.exe in $scriptDir — install failed"
    exit 1
}
Copy-Item -Path $binSrc -Destination "$installDir\legacy-system.exe" -Force
Write-Output "[install] Copied legacy-system.exe"

# ── Copy scenario.json if present (optional; app has defaults built in) ────────
$scenarioSrc = Join-Path $scriptDir 'scenario.json'
if (Test-Path $scenarioSrc) {
    Copy-Item -Path $scenarioSrc -Destination "$installDir\scenario.json" -Force
    Write-Output "[install] Copied scenario.json"
}

# ── Write appsettings.json (IngestionKey comes from protectedSettings — not logged) ──
@{
    SlotId            = $SlotId
    IngestionEndpoint = $IngestionEndpoint
    IngestionKey      = $IngestionKey
    Region            = 'eastus2'
} | ConvertTo-Json | Set-Content -Path "$installDir\appsettings.json" -Encoding UTF8
Write-Output "[install] Wrote appsettings.json (key redacted)"

# ── Register Windows Service ───────────────────────────────────────────────────
$exePath = "$installDir\legacy-system.exe"
New-Service `
    -Name        $svcName `
    -BinaryPathName $exePath `
    -DisplayName 'Workshop Legacy Support System' `
    -Description 'Simulated legacy support system for the Azure IaaS Hackathon. Emits telemetry and support signals to the shared data layer.' `
    -StartupType Automatic | Out-Null
Write-Output "[install] Service registered"

# ── Configure restart-on-failure recovery ─────────────────────────────────────
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# ── Start the service ──────────────────────────────────────────────────────────
Start-Service -Name $svcName
Start-Sleep -Seconds 3
$status = (Get-Service -Name $svcName).Status
Write-Output "[install] Service '$svcName' status: $status"

if ($status -ne 'Running') {
    # Try to retrieve the event log entry for diagnostics
    $evt = Get-EventLog -LogName Application -Source 'LegacySystem' -Newest 5 -ErrorAction SilentlyContinue
    $evt | ForEach-Object { Write-Output "  EventLog: $($_.Message)" }
    Write-Error "[install] Service failed to start — check Application event log on the VM"
    exit 1
}

Write-Output "[install] Legacy system installed and running for slot $SlotId"
Write-Output "[install] Signals will begin arriving in the shared data layer within ~30 seconds."
Write-Output "[install] Chaos incident will fire at +20 minutes (OrderService latency spike)."
