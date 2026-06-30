<#
.SYNOPSIS
  Seeds a hackathon cohort: creates 30 Entra users, assigns RBAC, issues TAPs,
  generates per-slot ingestion keys, and writes Assignments rows to Azure Table Storage.

.PARAMETER SessionId         Cohort identifier, e.g. contoso-2026-01-01
.PARAMETER StorageAccount    Name of the workshop app storage account (from azd output)
.PARAMETER IngestFunctionApp Name of the Ingestion API function app (from azd output).
                             If provided, INGEST_KEYS_JSON is updated automatically.
.PARAMETER DataRg            Data layer resource group (default workshop-data-rg).
.PARAMETER FabricWorkspaceId Fabric workspace ID for granting participant Viewer access.
                             Leave empty to skip. Get from infra/data-layer/fabric-outputs.json.
.PARAMETER SkipPeeringRole   Skip assigning the 'Workshop Hub Peering' custom role.
                             Peering is instructor-led in the hackathon; set this flag
                             to skip the assignment (avoids the custom-role dependency).
.PARAMETER SlotCount         Number of slots to provision (default 30)
.PARAMETER TapMinutes        TAP lifetime in minutes (default 480 = 8 hours)

.EXAMPLE
  # Minimal — tracking API only, no data-layer wiring
  .\seed-cohort.ps1 -SessionId contoso-2026-01-01 -StorageAccount wkstorexxxxxx

.EXAMPLE
  # Full hackathon — wires ingestion keys + Fabric Viewer access
  .\seed-cohort.ps1 -SessionId contoso-2026-01-01 -StorageAccount wkstorexxxxxx `
    -IngestFunctionApp workshop-ingest-xxxxxx `
    -FabricWorkspaceId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
    -SkipPeeringRole
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string]$SessionId,
  [Parameter(Mandatory)][string]$StorageAccount,
  [string]$TenantId          = '<YOUR_TENANT_ID>',
  [string]$TenantDomain      = 'contoso.onmicrosoft.com',
  [string]$SubscriptionId    = '',   # defaults to current Az context
  [string]$AppRg             = 'workshop-app-rg',
  [string]$HubRg             = 'hub-rg',
  [string]$IngestFunctionApp = '',   # set to update INGEST_KEYS_JSON automatically
  [string]$DataRg            = 'workshop-data-rg',
  [string]$FabricWorkspaceId = '',   # set to grant participants Fabric Viewer access
  [switch]$SkipPeeringRole,          # skip 'Workshop Hub Peering' role (peering is instructor-led)
  [int]   $SlotCount         = 30,
  [int]   $TapMinutes        = 480
)
$ErrorActionPreference = 'Stop'

# Pin to 2.38.0 explicitly — avoids assembly conflict when multiple versions are installed
Import-Module Microsoft.Graph.Authentication   -RequiredVersion 2.38.0 -Force
Import-Module Microsoft.Graph.Users            -RequiredVersion 2.38.0 -Force
Import-Module Microsoft.Graph.Identity.SignIns -RequiredVersion 2.38.0 -Force

# ── Connect ───────────────────────────────────────────────────────────────────
Write-Host '[seed-cohort] Connecting...' -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId `
  -Scopes 'User.ReadWrite.All','UserAuthenticationMethod.ReadWrite.All','RoleManagement.ReadWrite.Directory' `
  -NoWelcome

if (-not $SubscriptionId) {
  $SubscriptionId = az account show --query id -o tsv
  if (-not $SubscriptionId) { throw 'Could not determine subscription ID — run az login first.' }
  Write-Host "  Using subscription: $SubscriptionId" -ForegroundColor Gray
}

# Verify the storage account is reachable (key auth is disabled; uses --auth-mode login)
Write-Host "  Storage account: $StorageAccount (OAuth auth)" -ForegroundColor Gray

# ── Per-slot ingestion key generator ─────────────────────────────────────────────
function New-IngestKey {
    $bytes = [byte[]]::new(16)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [BitConverter]::ToString($bytes).Replace('-','').ToLower()
}

$keysMap = @{} # slot -> ingest key; written to cohort-keys.json at the end

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
    $allChars   = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    $pwdParts   = @(
      [char]'abcdefghijklmnopqrstuvwxyz'[(Get-Random -Max 26)]
      [char]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[(Get-Random -Max 26)]
      [char]'0123456789'[(Get-Random -Max 10)]
      [char]'!@#$%^&*'[(Get-Random -Max 8)]
    ) + (1..12 | ForEach-Object { [char]$allChars[(Get-Random -Max $allChars.Length)] })
    $genPassword = ($pwdParts | Get-Random -Count $pwdParts.Count) -join ''
    $user = New-MgUser -DisplayName "Workshop $slot" `
      -UserPrincipalName $upn `
      -MailNickname $slot `
      -AccountEnabled `
      -PasswordProfile @{
        Password                      = $genPassword
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

  # ── RBAC: Workshop Hub Peering on hub-vnet ────────────────────────────────
  # Allows participants to create both sides of a spoke<->hub VNet peering
  # from the portal's "Add peering" form without Contributor on hub-vnet.
  # Custom role must exist first (created/updated by fix-hub-peering-rbac.ps1).
  # The role grants peer/action + virtualNetworkPeerings read/write/delete on
  # hub-vnet only — it cannot modify the hub VNet itself.
  $hubVnetScope = "/subscriptions/$SubscriptionId/resourceGroups/$HubRg/providers/Microsoft.Network/virtualNetworks/hub-vnet"
  $existingPeer = az role assignment list --assignee $user.Id --role 'Workshop Hub Peering' --scope $hubVnetScope --query '[0].id' -o tsv 2>$null
  if (-not $existingPeer) {
    Write-Host "  Assigning 'Workshop Hub Peering' on hub-vnet" -ForegroundColor Yellow
    az role assignment create --assignee-object-id $user.Id --assignee-principal-type User `
      --role 'Workshop Hub Peering' --scope $hubVnetScope --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "  Could not assign 'Workshop Hub Peering' — run fix-hub-peering-rbac.ps1 first to create the custom role"
    } else {
      Write-Host "  ✓ Workshop Hub Peering assigned" -ForegroundColor Green
    }
  } else {
    Write-Host "  ✓ Workshop Hub Peering already assigned" -ForegroundColor Green
  }
  } else {
    Write-Host "  [SkipPeeringRole] Skipping 'Workshop Hub Peering' role assignment (peering is instructor-led)" -ForegroundColor Gray
  }

  # ── Generate per-slot ingestion key ─────────────────────────────────────────────────
  $ingestKey = New-IngestKey
  $keysMap[$slot] = $ingestKey
  Write-Host "  Generated ingest key for $slot" -ForegroundColor Gray

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
    --auth-mode login `
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
      "ingestKey=$ingestKey" `
      "claimedByEmail=" `
      "claimedAt=" `
    --if-exists replace `
    --output none
  Write-Host "  ✓ Assignments row written" -ForegroundColor Green
}

# ── Post-loop: write keys file + update Ingestion API + Fabric access ───────────────────────

# Always write cohort-keys.json (gitignored — contains secrets)
$outputPath = Join-Path $PSScriptRoot 'cohort-keys.json'
$keysMap | ConvertTo-Json | Set-Content $outputPath
Write-Host "`n[seed-cohort] Ingestion keys written to $outputPath (gitignored — contains secrets)" -ForegroundColor Cyan

# Optionally push keys to the Ingestion API app settings
if ($IngestFunctionApp) {
    Write-Host "[seed-cohort] Updating INGEST_KEYS_JSON on $IngestFunctionApp..." -ForegroundColor Cyan
    $keysJson = ($keysMap | ConvertTo-Json -Compress)
    az functionapp config appsettings set `
        --name $IngestFunctionApp `
        --resource-group $DataRg `
        --settings "INGEST_KEYS_JSON=$keysJson" `
        --output none
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ INGEST_KEYS_JSON updated" -ForegroundColor Green
    } else {
        Write-Warning "  Failed to update INGEST_KEYS_JSON — set it manually from cohort-keys.json"
    }
}

# Optionally grant Fabric Viewer access to all participant users
if ($FabricWorkspaceId) {
    Write-Host "`n[seed-cohort] Granting Fabric Viewer access to $SlotCount participants..." -ForegroundColor Cyan
    $fabricToken  = (az account get-access-token --resource 'https://api.fabric.microsoft.com' --output json | ConvertFrom-Json).accessToken
    $fabricHeaders = @{ Authorization = "Bearer $fabricToken"; 'Content-Type' = 'application/json' }
    foreach ($slot in $slots) {
        $upn  = "$slot@$TenantDomain"
        $user = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue
        if (-not $user) { continue }
        try {
            $body = @{ principal = @{ id = $user.Id; type = 'User' }; role = 'Viewer' } | ConvertTo-Json -Compress
            Invoke-RestMethod -Method POST `
                -Uri "https://api.fabric.microsoft.com/v1/workspaces/$FabricWorkspaceId/roleAssignments" `
                -Headers $fabricHeaders -Body $body -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Viewer granted to $slot" -ForegroundColor Green
        } catch {
            $sc = $_.Exception.Response?.StatusCode?.value__
            if ($sc -eq 409) { Write-Host "  ✓ $slot already has Viewer access" -ForegroundColor Gray }
            else { Write-Warning "  Failed to grant Viewer to $slot: $($_.ErrorDetails.Message)" }
        }
    }
}
Write-Host "  Run TAP smoke test: sign in to portal.azure.com as user01@$TenantDomain with their TAP." -ForegroundColor Gray
Write-Host "  Next steps:" -ForegroundColor Gray
Write-Host "    1. Deploy spokes.bicep if not already done." -ForegroundColor Gray
Write-Host "    2. If data layer deployed: run install-legacy-app.ps1 after Module 3." -ForegroundColor Gray
if (-not $IngestFunctionApp) {
    Write-Host "    3. Update INGEST_KEYS_JSON on the Ingestion API (use cohort-keys.json)." -ForegroundColor Yellow
}
