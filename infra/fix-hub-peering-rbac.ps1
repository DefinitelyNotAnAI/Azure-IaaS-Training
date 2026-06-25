#Requires -Modules Az.Resources
<#
.SYNOPSIS
  Hotfix: creates/updates a custom role 'Workshop Hub Peering' scoped to the
  hub-vnet, then assigns it to all (or specific) workshop participant accounts
  on the hub-vnet scope.

  The role grants the minimum permissions the Azure portal's modern
  "Add peering" form needs to create BOTH sides of a spoke<->hub peering
  in a single operation:
    - Microsoft.Network/virtualNetworks/read
    - Microsoft.Network/virtualNetworks/peer/action
    - Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read
    - Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write
    - Microsoft.Network/virtualNetworks/virtualNetworkPeerings/delete
  This is far narrower than Contributor/Network Contributor on hub-vnet:
  it cannot modify the hub VNet itself (subnets, address space, etc.),
  only its peering links, and only on this one VNet.

  Run this when participants receive:
    "does not have permission to perform action(s)
     'Microsoft.Network/virtualNetworks/peer/action'
     ...or 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write'
     on ... hub-vnet"

  NOTE: If the role already exists from an earlier run with fewer actions,
  this script UPDATES it in place so the new permissions take effect.

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

# ── Ensure custom role exists (and is up to date) ─────────────────────────────
$roleName = 'Workshop Hub Peering'

# Minimum actions for the portal's combined "Add peering" form to create both
# the spoke->hub and hub->spoke links. peer/action alone is NOT enough because
# the combined form also writes the hub-side peering child resource.
$peeringActions = @(
  'Microsoft.Network/virtualNetworks/read',
  'Microsoft.Network/virtualNetworks/peer/action',
  'Microsoft.Network/virtualNetworks/virtualNetworkPeerings/read',
  'Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write',
  'Microsoft.Network/virtualNetworks/virtualNetworkPeerings/delete'
)
$roleDescription = 'Allows workshop participants to create spoke<->hub VNet peerings (both sides) from the portal. Scoped to hub-vnet peering links only; cannot modify the hub VNet itself.'

$existingRole = Get-AzRoleDefinition -Name $roleName -ErrorAction SilentlyContinue
if (-not $existingRole) {
  Write-Host "  Creating custom role '$roleName'..." -ForegroundColor Yellow
  $roleDef = [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition]::new()
  $roleDef.Name            = $roleName
  $roleDef.Description     = $roleDescription
  $roleDef.IsCustom        = $true
  $roleDef.Actions         = $peeringActions
  $roleDef.NotActions      = @()
  $roleDef.AssignableScopes = @("/subscriptions/$SubscriptionId")
  New-AzRoleDefinition -Role $roleDef | Out-Null
  Write-Host "  ✓ Custom role '$roleName' created" -ForegroundColor Green
  Write-Host "  Waiting 15s for role to propagate..." -ForegroundColor Gray
  Start-Sleep -Seconds 15
} else {
  # Update in place if an earlier run created it with fewer actions.
  $current = @($existingRole.Actions)
  $missing = $peeringActions | Where-Object { $_ -notin $current }
  if ($missing) {
    Write-Host "  Updating custom role '$roleName' (adding peering write permissions)..." -ForegroundColor Yellow
    $existingRole.Actions     = $peeringActions
    $existingRole.Description = $roleDescription
    if ($existingRole.AssignableScopes -notcontains "/subscriptions/$SubscriptionId") {
      $existingRole.AssignableScopes += "/subscriptions/$SubscriptionId"
    }
    Set-AzRoleDefinition -Role $existingRole | Out-Null
    Write-Host "  ✓ Custom role '$roleName' updated" -ForegroundColor Green
    Write-Host "  Waiting 15s for role changes to propagate..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
  } else {
    Write-Host "  ✓ Custom role '$roleName' already up to date" -ForegroundColor Green
  }
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
