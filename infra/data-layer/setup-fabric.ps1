#Requires -Version 7.0
<#
.SYNOPSIS
  Provisions the shared Microsoft Fabric data layer for the hackathon.

.DESCRIPTION
  Called automatically as an azd postprovision hook after `azd provision`.
  Idempotent — safe to re-run at any time.

  Creates or updates in the Fabric workspace:
    1. Workspace
    2. Eventhouse + KQL database
    3. Telemetry table schema + per-slot KQL functions (user01..user30)
    4. Lakehouse
    5. Eventstreams (telemetry + support) — preview API, falls back to manual guidance
    6. OneLake shortcut: Tickets (Lakehouse) → Eventhouse for cross-plane KQL joins
    7. Reference Data Agent grounded on Eventhouse + Lakehouse

  Uses az login credentials — no extra CLI required.
  Reads event hub namespace from the AZURE_INGEST_EVENT_HUB_NAMESPACE env var
  (set automatically by azd from Bicep output).

.OUTPUTS
  Writes infra/data-layer/fabric-outputs.json (gitignored).
#>
[CmdletBinding()]
param (
    [int]   $SlotCount     = 30,
    [string]$WorkspaceName = 'workshop-hackathon'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$FabricBaseUrl = 'https://api.fabric.microsoft.com/v1'
$scriptDir     = $PSScriptRoot

# ── Acquire tokens ─────────────────────────────────────────────────────────────
Write-Host '[setup-fabric] Acquiring Fabric token...' -ForegroundColor Cyan
$fabricTokenResult = az account get-access-token --resource 'https://api.fabric.microsoft.com' --output json | ConvertFrom-Json
if (-not $fabricTokenResult.accessToken) { throw 'Could not acquire Fabric token. Ensure az login is complete.' }
$fabricHeaders = @{ Authorization = "Bearer $($fabricTokenResult.accessToken)"; 'Content-Type' = 'application/json' }

Write-Host '[setup-fabric] Acquiring Kusto token...' -ForegroundColor Cyan
$kustoTokenResult = az account get-access-token --resource 'https://kusto.kusto.windows.net' --output json | ConvertFrom-Json
$kustoToken = $kustoTokenResult.accessToken

# ── Helpers ────────────────────────────────────────────────────────────────────
function Invoke-Fabric {
    param([string]$Method, [string]$Path, [object]$Body = $null)
    $uri    = "$FabricBaseUrl$Path"
    $params = @{ Method = $Method; Uri = $uri; Headers = $fabricHeaders; ErrorAction = 'Stop' }
    if ($Body -and $Method -in 'POST','PATCH','PUT') {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }
    try   { Invoke-RestMethod @params }
    catch {
        $status = $_.Exception.Response?.StatusCode?.value__
        $detail = $_.ErrorDetails?.Message
        throw "Fabric $Method $Path failed ($status): $detail"
    }
}

function Get-OrCreate-Item {
    param([string]$ListPath, [string]$CreatePath, [string]$DisplayName, [object]$CreateBody)
    $list     = Invoke-Fabric -Method GET -Path $ListPath
    $existing = $list.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($existing) { return $existing }
    Write-Host "  Creating '$DisplayName'..."
    $item = Invoke-Fabric -Method POST -Path $CreatePath -Body $CreateBody
    Start-Sleep -Seconds 3
    return $item
}

# ── 1. Workspace ───────────────────────────────────────────────────────────────
Write-Host "[setup-fabric] 1/7  Workspace '$WorkspaceName'..." -ForegroundColor Yellow
$workspace = Get-OrCreate-Item `
    -ListPath   '/workspaces' `
    -CreatePath '/workspaces' `
    -DisplayName $WorkspaceName `
    -CreateBody  @{ displayName = $WorkspaceName }
$workspaceId = $workspace.id
Write-Host "  Workspace: $workspaceId" -ForegroundColor Green

# ── 2. Eventhouse ──────────────────────────────────────────────────────────────
Write-Host '[setup-fabric] 2/7  Eventhouse...' -ForegroundColor Yellow
$eventhouse = Get-OrCreate-Item `
    -ListPath   "/workspaces/$workspaceId/eventhouses" `
    -CreatePath "/workspaces/$workspaceId/eventhouses" `
    -DisplayName 'workshop-eventhouse' `
    -CreateBody  @{ displayName = 'workshop-eventhouse' }

# Poll until provisioned
$maxWait = 90; $waited = 0
while ($eventhouse.properties?.status -eq 'Provisioning' -and $waited -lt $maxWait) {
    Start-Sleep -Seconds 5; $waited += 5
    $eventhouse = Invoke-Fabric -Method GET -Path "/workspaces/$workspaceId/eventhouses/$($eventhouse.id)"
}
$eventhouseId      = $eventhouse.id
$kustoQueryUri     = $eventhouse.properties.queryServiceUri
Write-Host "  Eventhouse: $eventhouseId | KQL URI: $kustoQueryUri" -ForegroundColor Green

# ── 3. KQL database ────────────────────────────────────────────────────────────
Write-Host '[setup-fabric] 3/7  KQL database + schema...' -ForegroundColor Yellow
$databases = Invoke-Fabric -Method GET -Path "/workspaces/$workspaceId/eventhouses/$eventhouseId/databases"
$kqlDb     = $databases.value | Where-Object { $_.displayName -eq 'workshop-db' } | Select-Object -First 1
if (-not $kqlDb) {
    $kqlDb = Invoke-Fabric -Method POST `
        -Path "/workspaces/$workspaceId/eventhouses/$eventhouseId/databases" `
        -Body @{ displayName = 'workshop-db'; databaseType = 'ReadWrite' }
    Start-Sleep -Seconds 5
}
$kqlDbName = $kqlDb.displayName
Write-Host "  Database: $kqlDbName" -ForegroundColor Green

# Apply table schema (DDL lines from telemetry.kql)
$schemaFile   = Join-Path $scriptDir 'schema/telemetry.kql'
$schemaScript = Get-Content $schemaFile -Raw
$ddl = ($schemaScript -split "`n" | Where-Object { $_ -match '^\.(create-merge|alter)\s' }) -join "`n"
if ($ddl) {
    $kustoHeaders = @{ Authorization = "Bearer $kustoToken"; 'Content-Type' = 'application/json' }
    $body         = @{ db = $kqlDbName; csl = $ddl } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method POST -Uri "$kustoQueryUri/v1/rest/mgmt" -Headers $kustoHeaders -Body $body | Out-Null
    Write-Host '  Telemetry table created/merged' -ForegroundColor Green
}

# Per-slot KQL functions (SlotTelemetry_userNN, SlotTickets_userNN)
$funcs = @()
1..$SlotCount | ForEach-Object {
    $s = 'user{0:D2}' -f $_
    $funcs += ".create-or-alter function with (docstring='Telemetry for $s') SlotTelemetry_$s() { Telemetry | where SlotId == '$s' }"
    $funcs += ".create-or-alter function with (docstring='Tickets for $s') SlotTickets_$s() { Tickets | where SlotId == '$s' }"
}
$kustoHeaders = @{ Authorization = "Bearer $kustoToken"; 'Content-Type' = 'application/json' }
$funcBody     = @{ db = $kqlDbName; csl = $funcs -join "`n" } | ConvertTo-Json -Compress
Invoke-RestMethod -Method POST -Uri "$kustoQueryUri/v1/rest/mgmt" -Headers $kustoHeaders -Body $funcBody | Out-Null
Write-Host "  Per-slot KQL functions created for $SlotCount slots" -ForegroundColor Green

# ── 4. Lakehouse ───────────────────────────────────────────────────────────────
Write-Host '[setup-fabric] 4/7  Lakehouse...' -ForegroundColor Yellow
$lakehouse = Get-OrCreate-Item `
    -ListPath   "/workspaces/$workspaceId/lakehouses" `
    -CreatePath "/workspaces/$workspaceId/lakehouses" `
    -DisplayName 'workshop-lakehouse' `
    -CreateBody  @{ displayName = 'workshop-lakehouse' }
$lakehouseId = $lakehouse.id
Write-Host "  Lakehouse: $lakehouseId" -ForegroundColor Green

# ── 5. Eventstreams (telemetry + support) ──────────────────────────────────────
Write-Host '[setup-fabric] 5/7  Eventstreams (preview API)...' -ForegroundColor Yellow
$ehNamespace = $env:AZURE_INGEST_EVENT_HUB_NAMESPACE

$eventstreams = Invoke-Fabric -Method GET -Path "/workspaces/$workspaceId/eventstreams"
foreach ($hub in @('telemetry','support')) {
    $esName   = "workshop-eventstream-$hub"
    $existing = $eventstreams.value | Where-Object { $_.displayName -eq $esName } | Select-Object -First 1
    if (-not $existing) {
        try {
            Invoke-Fabric -Method POST -Path "/workspaces/$workspaceId/eventstreams" `
                -Body @{ displayName = $esName } | Out-Null
            Write-Host "  Eventstream '$esName' created (configure source/dest in Fabric portal)" -ForegroundColor Yellow
        } catch {
            Write-Warning "  Eventstream REST creation not yet GA for '$esName'. Create manually:"
            Write-Warning "    Source: Event Hub '$hub' in namespace $ehNamespace (consumer group: eventstream)"
            $dest = if ($hub -eq 'telemetry') { "Eventhouse > workshop-db > Telemetry table" } else { "Lakehouse > workshop-lakehouse > Tickets table" }
            Write-Warning "    Destination: $dest"
        }
    } else {
        Write-Host "  Eventstream '$esName' exists" -ForegroundColor Green
    }
}

# ── 6. OneLake shortcut: Tickets (Lakehouse) → Eventhouse ─────────────────────
Write-Host '[setup-fabric] 6/7  OneLake shortcut for Tickets...' -ForegroundColor Yellow
try {
    $shortcuts = Invoke-Fabric -Method GET -Path "/workspaces/$workspaceId/eventhouses/$eventhouseId/shortcuts" 2>$null
    $existing  = $shortcuts?.value | Where-Object { $_.displayName -eq 'Tickets' } | Select-Object -First 1
    if (-not $existing) {
        Invoke-Fabric -Method POST `
            -Path "/workspaces/$workspaceId/eventhouses/$eventhouseId/shortcuts" `
            -Body @{
                displayName = 'Tickets'
                type        = 'OneLake'
                target      = @{ workspaceId = $workspaceId; itemId = $lakehouseId; path = 'Tables/Tickets' }
            } | Out-Null
        Write-Host '  Tickets shortcut created' -ForegroundColor Green
    } else {
        Write-Host '  Tickets shortcut exists' -ForegroundColor Green
    }
} catch {
    Write-Warning '  Tickets shortcut creation failed. Create manually in Fabric portal:'
    Write-Warning '    In the Eventhouse, Add shortcut > OneLake > workshop-lakehouse > Tables/Tickets'
}

# ── 7. Reference Data Agent ────────────────────────────────────────────────────
Write-Host '[setup-fabric] 7/7  Reference Data Agent...' -ForegroundColor Yellow
$refAgentName = 'workshop-agent-reference'
try {
    $agents   = Invoke-Fabric -Method GET -Path "/workspaces/$workspaceId/dataAgents"
    $existing = $agents?.value | Where-Object { $_.displayName -eq $refAgentName } | Select-Object -First 1
    if (-not $existing) {
        Invoke-Fabric -Method POST -Path "/workspaces/$workspaceId/dataAgents" -Body @{
            displayName  = $refAgentName
            description  = 'Reference grounding. Participants copy this as their Part 2 starting point.'
            instructions = "You are an analysis agent for the Azure IaaS Hackathon. Always filter by the participant's SlotId. Use Telemetry for system metrics (latency, errors, throughput) and Tickets for support signals. Correlate spikes with ticket bursts to find root causes."
            groundings   = @(@{ type = 'Eventhouse'; itemId = $eventhouseId; database = $kqlDbName })
        } | Out-Null
        Write-Host "  Reference Data Agent '$refAgentName' created" -ForegroundColor Green
    } else {
        Write-Host "  Reference Data Agent exists" -ForegroundColor Green
    }
} catch {
    Write-Warning "  Data Agent REST creation not yet GA. Create manually in Fabric portal:"
    Write-Warning "    Name: $refAgentName"
    Write-Warning "    Ground on: Eventhouse > workshop-db (Telemetry + Tickets tables)"
    Write-Warning "    Add instructions: Always filter by SlotId. Use Telemetry for metrics, Tickets for support signals."
}

# ── Write outputs ──────────────────────────────────────────────────────────────
$outputPath = Join-Path $scriptDir 'fabric-outputs.json'
@{
    workspaceId       = $workspaceId
    workspaceUrl      = "https://app.fabric.microsoft.com/groups/$workspaceId"
    eventhouseId      = $eventhouseId
    kustoQueryUri     = $kustoQueryUri
    kqlDatabaseName   = $kqlDbName
    lakehouseId       = $lakehouseId
} | ConvertTo-Json | Set-Content $outputPath

Write-Host ''
Write-Host '══════════════════════════════════════════════════════' -ForegroundColor Green
Write-Host ' Fabric setup complete!' -ForegroundColor Green
Write-Host "  Workspace: https://app.fabric.microsoft.com/groups/$workspaceId" -ForegroundColor Green
Write-Host "  KQL URI:   $kustoQueryUri" -ForegroundColor Green
Write-Host "  Outputs:   $outputPath" -ForegroundColor Green
Write-Host '' -ForegroundColor Green
Write-Host ' If any steps needed manual fallback (see warnings above),' -ForegroundColor Yellow
Write-Host ' complete them in the Fabric portal and re-run this script to verify.' -ForegroundColor Yellow
Write-Host '══════════════════════════════════════════════════════' -ForegroundColor Green
