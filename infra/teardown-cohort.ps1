#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users
<#
.SYNOPSIS
  Tears down a cohort: deletes 30 user accounts, 30 spoke RGs, hub-side peerings,
  and purges the cohort partition from Participants + Assignments tables.
  Hub-rg and workshop-app-rg are untouched.

.EXAMPLE
  .\teardown-cohort.ps1 -SessionId contoso-2026-01-01 -StorageAccount wkstorexxxxxx
  .\teardown-cohort.ps1 -SessionId contoso-2026-01-01 -StorageAccount wkstorexxxxxx -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
  [Parameter(Mandatory)][string]$SessionId,
  [Parameter(Mandatory)][string]$StorageAccount,
  [string]$TenantId       = '<YOUR_TENANT_ID>',
  [string]$TenantDomain   = 'contoso.onmicrosoft.com',
  [string]$AppRg          = 'workshop-app-rg',
  [string]$HubRg          = 'hub-rg',
  [string]$HubVnetName    = 'hub-vnet',
  [int]   $SlotCount      = 30
)
$ErrorActionPreference = 'Stop'

if (-not $PSCmdlet.ShouldProcess($SessionId, 'Tear down cohort (delete users, RGs, peerings, table rows)')) { return }

Write-Host "[teardown-cohort] Starting teardown of session '$SessionId'" -ForegroundColor Red

# ── Connect ───────────────────────────────────────────────────────────────────
Connect-MgGraph -TenantId $TenantId -Scopes 'User.ReadWrite.All' -NoWelcome

$storageKey = (az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $AppRg `
  --query '[0].value' -o tsv)

$slots = 1..$SlotCount | ForEach-Object { 'user{0:D2}' -f $_ }

# ── Delete hub-side peerings ──────────────────────────────────────────────────
Write-Host "`n[teardown] Removing hub-side peerings..." -ForegroundColor Yellow
try {
  $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $HubRg -Name $HubVnetName -ErrorAction SilentlyContinue
  if ($hubVnet) {
    foreach ($slot in $slots) {
      $peeringName = "hub-to-$slot"
      $p = $hubVnet.VirtualNetworkPeerings | Where-Object { $_.Name -eq $peeringName }
      if ($p) {
        Remove-AzVirtualNetworkPeering -VirtualNetworkName $HubVnetName -ResourceGroupName $HubRg -Name $peeringName -Force -Confirm:$false
        Write-Host "  ✓ Removed $peeringName" -ForegroundColor Green
      }
    }
  }
} catch { Write-Warning "  Could not remove hub peerings: $_" }

# ── Delete spoke RGs ──────────────────────────────────────────────────────────
Write-Host "`n[teardown] Deleting spoke resource groups..." -ForegroundColor Yellow
foreach ($slot in $slots) {
  $rg = "$slot-rg"
  $exists = az group exists --name $rg --output tsv 2>$null
  if ($exists -eq 'true') {
    Write-Host "  Deleting $rg..." -ForegroundColor Yellow
    az group delete --name $rg --yes --no-wait --output none
    Write-Host "  ✓ Delete initiated for $rg (async)" -ForegroundColor Green
  } else {
    Write-Host "  $rg not found — skipping" -ForegroundColor Gray
  }
}

# ── Delete Entra user accounts ────────────────────────────────────────────────
Write-Host "`n[teardown] Deleting Entra user accounts..." -ForegroundColor Yellow
foreach ($slot in $slots) {
  $upn = "$slot@$TenantDomain"
  $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
  if ($user) {
    Remove-MgUser -UserId $user.Id -Confirm:$false
    Write-Host "  ✓ Deleted $upn" -ForegroundColor Green
  } else {
    Write-Host "  $upn not found — skipping" -ForegroundColor Gray
  }
}

# ── Purge table rows ──────────────────────────────────────────────────────────
Write-Host "`n[teardown] Purging table rows for session '$SessionId'..." -ForegroundColor Yellow
foreach ($tableName in @('Participants', 'Assignments')) {
  $entities = az storage entity query `
    --account-name $StorageAccount `
    --account-key $storageKey `
    --table-name $tableName `
    --filter "PartitionKey eq '$SessionId'" `
    --select RowKey `
    --output json 2>$null | ConvertFrom-Json

  if ($entities -and $entities.items) {
    foreach ($e in $entities.items) {
      az storage entity delete `
        --account-name $StorageAccount `
        --account-key $storageKey `
        --table-name $tableName `
        --partition-key $SessionId `
        --row-key $e.RowKey `
        --output none 2>$null
    }
    Write-Host "  ✓ Purged $($entities.items.Count) rows from $tableName" -ForegroundColor Green
  }
}

Write-Host "`n[teardown-cohort] Done. Hub-rg and workshop-app-rg are untouched." -ForegroundColor Green
Write-Host "  Note: RG deletions run async — allow a few minutes for full completion." -ForegroundColor Gray
