<#
.SYNOPSIS
  Idempotent: grants workshop-app-mi the Graph app permissions needed to issue/revoke TAPs.
  Run once after every azd up (safe to re-run — skips already-granted roles).

.EXAMPLE
  .\grant-graph-permissions.ps1 -TenantId 3d50d380-fed3-48c7-b967-3fd8026cc60b
#>
[CmdletBinding()]
param(
  [string]$TenantId    = '3d50d380-fed3-48c7-b967-3fd8026cc60b',
  [string]$UamiName    = 'workshop-app-mi',
  [string[]]$GraphRoles = @('UserAuthenticationMethod.ReadWrite.All', 'User.Read.All')
)
$ErrorActionPreference = 'Stop'

# Pin to 2.38.0 explicitly — avoids assembly conflict when multiple versions are installed
Import-Module Microsoft.Graph.Authentication -RequiredVersion 2.38.0 -Force
Import-Module Microsoft.Graph.Applications   -RequiredVersion 2.38.0 -Force

Write-Host '[grant-graph-permissions] Connecting to Microsoft Graph...' -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId `
  -Scopes 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All' `
  -UseDeviceCode `
  -NoWelcome

# Find the UAMI service principal
$uamiSp = Get-MgServicePrincipal -Filter "displayName eq '$UamiName'" -ErrorAction Stop
if (-not $uamiSp) {
  throw "UAMI service principal '$UamiName' not found. Deploy infra/app.bicep first."
}
Write-Host "  UAMI SP: $($uamiSp.Id)" -ForegroundColor Green

# Find the Microsoft Graph service principal (appId is constant across all tenants)
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
Write-Host "  Graph SP: $($graphSp.Id)" -ForegroundColor Green

$existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $uamiSp.Id

foreach ($roleName in $GraphRoles) {
  $appRole = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName -and $_.AllowedMemberTypes -contains 'Application' }
  if (-not $appRole) { Write-Warning "  Role '$roleName' not found on Graph SP — skipping"; continue }

  if ($existing | Where-Object { $_.AppRoleId -eq $appRole.Id }) {
    Write-Host "  ✓ '$roleName' already granted (skipping)" -ForegroundColor Green
    continue
  }

  Write-Host "  Granting '$roleName'..." -ForegroundColor Yellow
  $null = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $uamiSp.Id -BodyParameter @{
    principalId = $uamiSp.Id
    resourceId  = $graphSp.Id
    appRoleId   = $appRole.Id
  }
  Write-Host "  ✓ '$roleName' granted" -ForegroundColor Green
}

Write-Host "`n[grant-graph-permissions] Done." -ForegroundColor Green
Write-Host "  Verify: Entra portal → Enterprise applications → $UamiName → Permissions → Admin consent" -ForegroundColor Gray
