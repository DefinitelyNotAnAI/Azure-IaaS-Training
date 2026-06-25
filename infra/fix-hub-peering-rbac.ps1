#Requires -Modules Az.Resources
<#
.SYNOPSIS
  Hotfix: creates a custom role 'Workshop Hub Peering' with only the
  Microsoft.Network/virtualNetworks/peer/action permission, then assigns it
  to all (or specific) workshop participant accounts on the hub-vnet scope.

  Run this when participants receive:
    "does not have permission to perform action(s)
     'Microsoft.Network/virtualNetworks/peer/action'
     on ... hub-vnet"

.EXAMPLE
  .\fix-hub-peering-rbac.ps1
  .\fix-hub-peering-rbac.ps1 -Slot user01   # single participant
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$SubscriptionId = '',
  [string]$TenantDomain   = 'contoso.onmicrosoft.com',
  [string]$HubRg          = 'hub-rg',
  [string]$HubVnetName    = 'hub-vnet',
  [string]$Slot           = '',   # blank = all 30 slots
  [int]   $SlotCount      = 30
)
$ErrorActionPreference = 'Stop'

if (-not $SubscriptionId) { $SubscriptionId = (Get-AzContext).Subscription.Id }
Write-Host "[fix-hub-peering-rbac] Subscription: $SubscriptionId" -ForegroundColor Cyan

$hubVnetScope = "/subscriptions/$SubscriptionId/resourceGroups/$HubRg/providers/Microsoft.Network/virtualNetworks/$HubVnetName"

# ── Ensure custom role exists ─────────────────────────────────────────────────
$roleName = 'Workshop Hub Peering'
$existingRole = Get-AzRoleDefinition -Name $roleName -ErrorAction SilentlyContinue
if (-not $existingRole) {
  Write-Host "  Creating custom role '$roleName'..." -ForegroundColor Yellow
  $roleDef = [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]::new()
  $roleDef.Name            = $roleName
  $roleDef.Description     = 'Allows workshop participants to peer their spoke VNet to the hub. Scoped to hub-vnet only.'
  $roleDef.IsCustom        = $true
  $roleDef.Actions         = @('Microsoft.Network/virtualNetworks/peer/action')
  $roleDef.NotActions      = @()
  $roleDef.AssignableScopes = @("/subscriptions/$SubscriptionId")
  New-AzRoleDefinition -Role $roleDef | Out-Null
  Write-Host "  ✓ Custom role '$roleName' created" -ForegroundColor Green
  Write-Host "  Waiting 15s for role to propagate..." -ForegroundColor Gray
  Start-Sleep -Seconds 15
} else {
  Write-Host "  ✓ Custom role '$roleName' already exists" -ForegroundColor Green
}

# ── Assign to participants ─────────────────────────────────────────────────────
$slots = if ($Slot) { @($Slot) } else { 1..$SlotCount | ForEach-Object { 'user{0:D2}' -f $_ } }

foreach ($s in $slots) {
  $upn = "$s@$TenantDomain"
  Write-Host "[$s] Checking $upn..." -ForegroundColor Cyan

  $user = Get-AzADUser -UserPrincipalName $upn -ErrorAction SilentlyContinue
  if (-not $user) {
    Write-Warning "[$s] User '$upn' not found — skipping"
    continue
  }

  $existing = Get-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName $roleName -Scope $hubVnetScope -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Host "  ✓ Already assigned — skipping" -ForegroundColor Green
    continue
  }

  Write-Host "  Assigning '$roleName' on $HubVnetName..." -ForegroundColor Yellow
  New-AzRoleAssignment -ObjectId $user.Id -RoleDefinitionName $roleName -Scope $hubVnetScope | Out-Null
  Write-Host "  ✓ Assigned" -ForegroundColor Green
}

Write-Host "`n[fix-hub-peering-rbac] Done. Participants can now create VNet peerings to hub-vnet." -ForegroundColor Green
Write-Host "  They may need to refresh the portal (F5) for the permission to take effect." -ForegroundColor Gray
