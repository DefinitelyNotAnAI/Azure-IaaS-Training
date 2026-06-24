<#
.SYNOPSIS
  Rotates TAPs for all workshop slots via the admin API.
  Run this ~30 minutes before the workshop to ensure fresh credentials.

.PARAMETER SwaUrl
  Base URL of the Static Web App (default: the deployed instance).

.PARAMETER AdminCode
  Value of ADMIN_ACCESS_CODE (default: reads from azd env or prompts).

.PARAMETER SessionSlots
  Number of slots to rotate (default: 30).

.EXAMPLE
  .\infra\rotate-all-taps.ps1
  .\infra\rotate-all-taps.ps1 -AdminCode "Facilitator2026"
#>
param(
  [string] $SwaUrl       = 'https://agreeable-wave-045e1a40f.7.azurestaticapps.net',
  [string] $AdminCode    = '',
  [int]    $SessionSlots = 30
)

if (-not $AdminCode) {
  # Try azd env first
  $AdminCode = (azd env get-value ADMIN_ACCESS_CODE --environment 0625-quanta 2>$null).Trim()
}
if (-not $AdminCode) {
  $AdminCode = Read-Host "Enter ADMIN_ACCESS_CODE"
}

Write-Host "`n[rotate-all-taps] Rotating TAPs for $SessionSlots slots against $SwaUrl`n" -ForegroundColor Cyan

$ok      = 0
$failed  = 0
$results = @()

1..$SessionSlots | ForEach-Object {
  $slot = 'user{0:D2}' -f $_
  try {
    $r = Invoke-RestMethod `
      -Uri     "$SwaUrl/api/dashboard/assignments/$slot/rotate-tap" `
      -Method  POST `
      -Headers @{ 'x-access-code' = $AdminCode } `
      -TimeoutSec 30 `
      -ErrorAction Stop
    Write-Host "  ✓ $slot  issued at $($r.tapIssuedAt)" -ForegroundColor Green
    $results += [pscustomobject]@{ Slot = $slot; Status = 'OK'; IssuedAt = $r.tapIssuedAt }
    $ok++
  } catch {
    $msg = $_.Exception.Message
    Write-Host "  ✗ $slot  FAILED: $msg" -ForegroundColor Red
    $results += [pscustomobject]@{ Slot = $slot; Status = 'FAILED'; IssuedAt = '' }
    $failed++
  }
  Start-Sleep -Milliseconds 300   # avoid Graph API throttling
}

Write-Host "`n[rotate-all-taps] Done.  OK=$ok  Failed=$failed" -ForegroundColor Cyan

if ($failed -gt 0) {
  Write-Host "`nFailed slots:" -ForegroundColor Yellow
  $results | Where-Object { $_.Status -eq 'FAILED' } | Format-Table -AutoSize
}

Write-Host "`nTo verify, sign in to portal.azure.com as userXX@MngEnvMCAP475636.onmicrosoft.com" -ForegroundColor Gray
Write-Host "using the TAP shown on each participant's workshop page after they (re-)load index.html.`n" -ForegroundColor Gray
