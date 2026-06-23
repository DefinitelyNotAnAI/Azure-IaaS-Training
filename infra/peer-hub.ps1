#Requires -Modules Az.Network
<#
.SYNOPSIS
  Idempotent: creates hub-side VNet peerings for all (or specific) spokes.
  Run this during Module 2 after participants have created their spoke VNets.

.EXAMPLE
  .\peer-hub.ps1 -SessionId quanta-2026-07-15
  .\peer-hub.ps1 -SessionId quanta-2026-07-15 -Slot user07  # single stragglers
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$SessionId,
  [string]$SubscriptionId = '',
  [string]$HubRg          = 'hub-rg',
  [string]$HubVnetName    = 'hub-vnet',
  [string]$Slot           = '',       # blank = all slots
  [int]   $SlotCount      = 30
)
$ErrorActionPreference = 'Stop'

if (-not $SubscriptionId) { $SubscriptionId = (Get-AzContext).Subscription.Id }

$hubVnet = Get-AzVirtualNetwork -ResourceGroupName $HubRg -Name $HubVnetName
if (-not $hubVnet) { throw "hub-vnet not found in $HubRg" }

$slots = if ($Slot) { @($Slot) } else { 1..$SlotCount | ForEach-Object { 'user{0:D2}' -f $_ } }

foreach ($s in $slots) {
  $spokeRg     = "$s-rg"
  $spokeVnet   = "vnet-$s"
  $peeringName = "hub-to-$s"

  # Check if peering already exists
  $existing = $hubVnet.VirtualNetworkPeerings | Where-Object { $_.Name -eq $peeringName }
  if ($existing -and $existing.PeeringState -eq 'Connected') {
    Write-Host "[$s] ✓ Peering '$peeringName' already Connected — skipping" -ForegroundColor Green
    continue
  }

  # Check if spoke VNet exists (participant may not have created it yet)
  $spoke = Get-AzVirtualNetwork -ResourceGroupName $spokeRg -Name $spokeVnet -ErrorAction SilentlyContinue
  if (-not $spoke) {
    Write-Warning "[$s] Spoke VNet '$spokeVnet' not found in '$spokeRg' — skipping (participant not ready)"
    continue
  }

  Write-Host "[$s] Creating hub-side peering '$peeringName'..." -ForegroundColor Yellow
  $peeringConfig = @{
    Name                  = $peeringName
    RemoteVirtualNetworkId = $spoke.Id
    AllowForwardedTraffic = $true
    AllowGatewayTransit   = $false
    UseRemoteGateways     = $false
  }

  # Add or update peering on hub-vnet
  $hubVnet = Get-AzVirtualNetwork -ResourceGroupName $HubRg -Name $HubVnetName
  Add-AzVirtualNetworkPeering @peeringConfig -VirtualNetwork $hubVnet | Out-Null

  Write-Host "[$s] ✓ Hub-side peering created" -ForegroundColor Green
}

Write-Host "`n[peer-hub] Done. Re-run with -Slot userXX for any stragglers." -ForegroundColor Green
