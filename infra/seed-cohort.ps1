#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns
<#
.SYNOPSIS
  Seeds a workshop cohort: creates 30 Entra users, assigns RBAC, issues TAPs,
  writes Assignments rows to Azure Table Storage.

.PARAMETER SessionId       Cohort identifier, e.g. quanta-2026-07-15
.PARAMETER StorageAccount  Name of the workshop app storage account (from azd output)
.PARAMETER SlotCount       Number of slots to provision (default 30)
.PARAMETER TapMinutes      TAP lifetime in minutes (default 480 = 8 hours)

.EXAMPLE
  .\seed-cohort.ps1 -SessionId quanta-2026-07-15 -StorageAccount wkstore4a2f1b
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$SessionId,
  [Parameter(Mandatory)][string]$StorageAccount,
  [string]$TenantId          = '3d50d380-fed3-48c7-b967-3fd8026cc60b',
  [string]$TenantDomain      = 'MngEnvMCAP475636.onmicrosoft.com',
  [string]$SubscriptionId    = '',   # defaults to current Az context
  [string]$AppRg             = 'workshop-app-rg',
  [string]$HubRg             = 'hub-rg',
  [int]   $SlotCount         = 30,
  [int]   $TapMinutes        = 480
)
$ErrorActionPreference = 'Stop'

# ── Connect ───────────────────────────────────────────────────────────────────
Write-Host '[seed-cohort] Connecting...' -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId `
  -Scopes 'User.ReadWrite.All','UserAuthenticationMethod.ReadWrite.All','RoleManagement.ReadWrite.Directory' `
  -NoWelcome

if (-not $SubscriptionId) {
  $SubscriptionId = (Get-AzContext).Subscription.Id
  Write-Host "  Using subscription: $SubscriptionId" -ForegroundColor Gray
}

# Get storage key for table writes
$storageKey = (az storage account keys list `
  --account-name $StorageAccount `
  --resource-group $AppRg `
  --query '[0].value' -o tsv)

if (-not $storageKey) { throw "Could not retrieve storage key for $StorageAccount" }

$slots = 1..$SlotCount | ForEach-Object { 'user{0:D2}' -f $_ }

foreach ($slot in $slots) {
  $n    = [int]$slot.Substring(4)
  $rg   = "$slot-rg"
  $cidr = "10.10.$n.0/24"
  $upn  = "$slot@$TenantDomain"

  Write-Host "`n[$slot] Processing..." -ForegroundColor Cyan

  # ── Create or retrieve Entra user ─────────────────────────────────────────
  $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
  if (-not $user) {
    Write-Host "  Creating user $upn" -ForegroundColor Yellow
    $user = New-MgUser -DisplayName "Workshop $slot" `
      -UserPrincipalName $upn `
      -MailNickname $slot `
      -AccountEnabled `
      -PasswordProfile @{
        Password                      = [System.Web.Security.Membership]::GeneratePassword(16, 3)
        ForceChangePasswordNextSignIn = $false
      }
    Write-Host "  ✓ Created user OID: $($user.Id)" -ForegroundColor Green
  } else {
    Write-Host "  ✓ User exists OID: $($user.Id)" -ForegroundColor Green
  }

  # ── RBAC: Contributor on userXX-rg ────────────────────────────────────────
  $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$rg"
  $existingContrib = az role assignment list --assignee $user.Id --role Contributor --scope $rgScope --query '[0].id' -o tsv 2>$null
  if (-not $existingContrib) {
    Write-Host "  Assigning Contributor on $rg" -ForegroundColor Yellow
    az role assignment create --assignee-object-id $user.Id --assignee-principal-type User `
      --role Contributor --scope $rgScope --output none
    Write-Host "  ✓ Contributor assigned" -ForegroundColor Green
  } else {
    Write-Host "  ✓ Contributor already assigned" -ForegroundColor Green
  }

  # ── RBAC: Reader on hub-rg ────────────────────────────────────────────────
  $hubRgScope = "/subscriptions/$SubscriptionId/resourceGroups/$HubRg"
  $existingReader = az role assignment list --assignee $user.Id --role Reader --scope $hubRgScope --query '[0].id' -o tsv 2>$null
  if (-not $existingReader) {
    Write-Host "  Assigning Reader on hub-rg" -ForegroundColor Yellow
    az role assignment create --assignee-object-id $user.Id --assignee-principal-type User `
      --role Reader --scope $hubRgScope --output none
    Write-Host "  ✓ Reader assigned" -ForegroundColor Green
  } else {
    Write-Host "  ✓ Reader already assigned" -ForegroundColor Green
  }

  # ── Issue TAP ─────────────────────────────────────────────────────────────
  # Revoke any existing TAP first (idempotent)
  $existingTaps = Get-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user.Id -ErrorAction SilentlyContinue
  foreach ($tap in $existingTaps) {
    Write-Host "  Revoking old TAP $($tap.Id)" -ForegroundColor Gray
    Remove-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user.Id -TemporaryAccessPassAuthenticationMethodId $tap.Id
  }

  Write-Host "  Issuing new TAP ($TapMinutes min, multi-use)" -ForegroundColor Yellow
  $newTap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $user.Id -BodyParameter @{
    lifetimeInMinutes = $TapMinutes
    isUsableOnce      = $false
  }
  $tapCode      = $newTap.TemporaryAccessPass
  $tapId        = $newTap.Id
  $tapIssuedAt  = (Get-Date).ToUniversalTime().ToString('o')
  Write-Host "  ✓ TAP issued (ID: $tapId)" -ForegroundColor Green

  # ── Write Assignments table row ───────────────────────────────────────────
  Write-Host "  Writing Assignments table row" -ForegroundColor Yellow
  az storage entity insert `
    --account-name $StorageAccount `
    --account-key $storageKey `
    --table-name Assignments `
    --entity `
      "PartitionKey=$SessionId" `
      "RowKey=$slot" `
      "assignedRg=$rg" `
      "assignedCidr=$cidr" `
      "assignedUpn=$upn" `
      "assignedUserObjectId=$($user.Id)" `
      "tempCredential=$tapCode" `
      "currentTapId=$tapId" `
      "tapIssuedAt=$tapIssuedAt" `
      "claimedByEmail=" `
      "claimedAt=" `
    --if-exists replace `
    --output none
  Write-Host "  ✓ Assignments row written" -ForegroundColor Green
}

Write-Host "`n[seed-cohort] Complete. $SlotCount slots seeded for session '$SessionId'." -ForegroundColor Green
Write-Host "  Run TAP smoke test: sign in to portal.azure.com as user01@$TenantDomain with their TAP." -ForegroundColor Gray
Write-Host "  Next step: deploy spokes.bicep if not already done." -ForegroundColor Gray
