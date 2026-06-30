# Deployment Runbook — Azure IaaS Hackathon

Complete first-time deployment guide. Run this **once per subscription** before the first event.  
Subsequent events only need the [pre-flight checklist](preflight-checklist.md).

> **Estimated time:** 45–90 minutes (most waits are Azure provisioning).

---

## Prerequisites

Verify before starting:

| Prerequisite | Command | Expected |
|---|---|---|
| Azure CLI ≥ 2.60 | `az --version` | `azure-cli 2.60+` |
| Azure Developer CLI ≥ 1.10 | `azd version` | `azd version 1.10+` |
| Node.js ≥ 20 | `node --version` | `v20.x.x` |
| .NET 8 SDK | `dotnet --version` | `8.0.x` |
| PowerShell 7 | `pwsh --version` | `7.x.x` |
| Git | `git --version` | any |
| Fabric capacity **F2+** | Azure portal | Status = Active |
| Entra tenant with admin consent ability | — | Tenant admin or App Admin role |
| Azure subscription with Owner role | `az account show` | Owner |

### One-time permissions setup

```powershell
# Log in to Azure and set subscription
az login
az account set --subscription '<SUBSCRIPTION_ID>'

# Install required PowerShell modules (once per machine)
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns `
  -RequiredVersion 2.38.0 -Scope CurrentUser -Force

# Install Azure PowerShell (for hub peering scripts)
Install-Module Az.Network -Scope CurrentUser -Force
```

---

## Step 1 — Deploy app + data infrastructure (`azd up`)

This deploys `workshop-app-rg` (SWA, Functions, Table Storage, App Insights) and `workshop-data-rg` (Event Hub, Ingestion API, Ingestion App Insights), then runs the Fabric postprovision hook automatically.

```powershell
cd <repo-root>

# First run: initialise azd environment
azd env new <AZD_ENV>           # e.g. workshop-contoso
azd env set AZURE_SUBSCRIPTION_ID '<SUBSCRIPTION_ID>'
azd env set AZURE_LOCATION 'eastus2'

# Deploy (creates RGs, runs Bicep, deploys Functions, runs setup-fabric.ps1)
azd up
```

**Expected output (abridged):**
```
(✓) Done: Resource group: workshop-app-rg
(✓) Done: Resource group: workshop-data-rg
(✓) Done: Deploying service api
(✓) Done: Deploying service ingest-api
(✓) Done: Deploying service web
Running postprovision hook...
[setup-fabric] Workspace: https://app.fabric.microsoft.com/groups/XXXX
[setup-fabric] KQL URI: https://...kusto.windows.net
[setup-fabric] Fabric setup complete!
```

⏱ **~20–30 minutes** (first run). Subsequent `azd up` runs are ~5 minutes.

Capture from output or `azd env get-values`:

```powershell
azd env get-values | Select-String 'AZURE_INGEST|AZURE_FUNCTION|AZURE_STATIC'
```

Note: `AZURE_INGEST_FUNCTION_APP_URL`, `AZURE_FUNCTION_APP_NAME`, `AZURE_STATIC_WEB_APP_URL`.

- [ ] All three services show `(✓) Done`
- [ ] Fabric postprovision hook shows **Fabric setup complete!**
- [ ] `infra/data-layer/fabric-outputs.json` exists

---

## Step 2 — Grant Graph API permissions to UAMI

The participant-tracking API needs Graph permissions (create users, issue TAPs). This is a **one-time step per subscription** that requires a Global Admin or Privileged Role Administrator to consent.

```powershell
# Get the UAMI principal ID from azd output
$uamiPrincipalId = azd env get-values | Select-String 'UAMI_PRINCIPAL_ID' | ForEach-Object { $_ -split '=' | Select-Object -Last 1 }

.\infra\grant-graph-permissions.ps1 -UamiObjectId $uamiPrincipalId
```

Expected: `✓ UserAuthenticationMethod.ReadWrite.All granted`, `✓ User.Read.All granted`.

- [ ] Graph permissions granted (verify in Azure portal → Enterprise apps → workshop-app-mi → Permissions)

---

## Step 3 — Deploy hub networking

```powershell
az deployment sub create `
  --location eastus2 `
  --template-file infra/hub.bicep `
  --parameters location=eastus2
```

Expected: `"provisioningState": "Succeeded"`. Creates `hub-rg` with `hub-vnet` (10.0.0.0/16).

⏱ **~3 minutes**.

- [ ] `hub-rg` resource group exists with `hub-vnet`

### Optional: deploy Azure Bastion

If participants will use Bastion for optional VM access:

```powershell
# Bastion is not deployed by Bicep — create it manually in the portal
# hub-rg → hub-vnet → Bastion → Standard tier, AzureBastionSubnet (10.0.1.0/26)
```

- [ ] (Optional) Bastion provisioned in hub-rg

---

## Step 4 — Deploy spoke resource groups

```powershell
az deployment sub create `
  --location eastus2 `
  --template-file infra/spokes.bicep `
  --parameters sessionId='<SESSION_ID>' slotCount=30
```

Expected: `"provisioningState": "Succeeded"`. Creates `user01-rg` through `user30-rg`.

⏱ **~3 minutes**.

- [ ] 30 resource groups created: `az group list --query "[?tags.purpose=='workshop-spoke'].name" -o tsv | Measure-Object | Select-Object -ExpandProperty Count` → `30`

---

## Step 5 — Build and publish the legacy app

```powershell
cd app/legacy-system
.\publish.ps1
```

Expected output: `publish/` directory containing `legacy-system.exe`, `scenario.json`, `install.ps1`.

- [ ] `app/legacy-system/publish/legacy-system.exe` exists (~60–80 MB self-contained)

### Upload to a public URL

Upload all three files from `app/legacy-system/publish/` to a URL accessible from participant VMs (Azure Blob public container or GitHub release):

```powershell
# Option A: Azure Blob (create a public container in the workshop storage account)
az storage container create --name releases --account-name <STORAGE_ACCOUNT_NAME> `
  --public-access blob --auth-mode login

az storage blob upload-batch --source app/legacy-system/publish/ `
  --destination releases --account-name <STORAGE_ACCOUNT_NAME> --auth-mode login

# Get URLs
$base = "https://<STORAGE_ACCOUNT_NAME>.blob.core.windows.net/releases"
Write-Host "AppBinaryUrl:    $base/legacy-system.exe"
Write-Host "InstallScriptUrl: $base/install.ps1"
Write-Host "ScenarioUrl:      $base/scenario.json"
```

Note all three URLs — you'll need them for `install-legacy-app.ps1`.

- [ ] All three files publicly accessible (test `Invoke-WebRequest -Uri <URL> -Method HEAD`)

---

## Step 6 — Update `src/config.js`

Open [src/config.js](../src/config.js) and set the deployment-specific fields:

```javascript
// Per-delivery fields
sessionId:   '<SESSION_ID>',
sessionName: '<SESSION_NAME>',
sessionDate: '<DATE_STRING>',
sessionCode: '<SESSION_CODE>',   // rotate per delivery

// Data layer (from infra/data-layer/fabric-outputs.json + azd env)
ingestionEndpoint:  'https://<INGEST_FUNCTION_APP_NAME>.azurewebsites.net',
fabricWorkspaceUrl: 'https://app.fabric.microsoft.com/groups/<FABRIC_WORKSPACE_ID>',
foundryProjectUrl:  'https://ai.azure.com/build/<FOUNDRY_PROJECT_ID>',

// Planted incident (must match app/legacy-system/scenario.json)
incidentGroundTruth: {
  incidentId:      'INC-BADDEPLOYMENT-01',
  injectedAt:      '',          // set on event day after app starts
  affectedService: 'OrderService',
  affectedRegion:  'eastus2',
  failureType:     'LatencySpike',
  description:     'A simulated bad config deploy increased OrderService ...',
},
```

Deploy the static web app:

```powershell
azd deploy web --environment <AZD_ENV>
```

- [ ] Workshop URL shows the updated session name and date

---

## Step 7 — Seed the cohort

```powershell
.\infra\seed-cohort.ps1 `
  -SessionId         '<SESSION_ID>' `
  -StorageAccount    '<STORAGE_ACCOUNT_NAME>' `
  -IngestFunctionApp '<INGEST_FUNCTION_APP_NAME>' `
  -FabricWorkspaceId '<FABRIC_WORKSPACE_ID>' `
  -SkipPeeringRole `
  -TenantDomain      '<TENANT_DOMAIN>' `
  -TenantId          '<TENANT_ID>'
```

Expected: `30 slots seeded. INGEST_KEYS_JSON updated. Fabric Viewer access granted to 30 participants.`

- [ ] `infra/cohort-keys.json` written (back this up — needed for install-legacy-app.ps1)
- [ ] Admin dashboard Slot Pool shows 30 unclaimed slots

---

## Step 8 — Final smoke test

```powershell
# 1. Check admin dashboard
$r = Invoke-WebRequest -Uri 'https://<SWA_HOSTNAME>/admin.html' -SkipHttpErrorCheck
"Dashboard: $($r.StatusCode)"   # expect 200

# 2. Check participant check-in
$r = Invoke-WebRequest -Uri 'https://<SWA_HOSTNAME>/api/participants' -Method POST `
  -ContentType 'application/json' `
  -Headers @{ 'x-session-code' = '<SESSION_CODE>' } `
  -Body '{"email":"smoke@test.com","displayName":"Smoke Test"}' `
  -SkipHttpErrorCheck
"Check-in: $($r.StatusCode)"    # expect 201

# 3. Spot-check ingestion
$key = (Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json).user01
$r = Invoke-WebRequest -Uri '<INGEST_URL>/api/ingest/telemetry' -Method POST `
  -ContentType 'application/json' `
  -Headers @{ 'x-team-key' = $key } `
  -Body '{"service":"OrderService","operation":"ProcessOrder","region":"eastus2","latencyMs":100}' `
  -SkipHttpErrorCheck
"Ingest: $($r.StatusCode)"      # expect 202

# Clean up smoke test participant
az storage entity delete --account-name <STORAGE_ACCOUNT_NAME> --auth-mode login `
  --table-name Participants --partition-key '<SESSION_ID>' --row-key 'smoke@test.com'
```

- [ ] All three return expected status codes
- [ ] Fabric Eventhouse shows one row in `Telemetry | where SlotId == 'user01' | take 1`

---

## Reference: resource names after deployment

| Resource | Name |
|---|---|
| Workshop URL | `https://<SWA_HOSTNAME>/` |
| Admin code | `<ADMIN_ACCESS_CODE>` |
| Session code | `<SESSION_CODE>` |
| Tracking Functions app | `<FUNCTION_APP_NAME>` |
| Ingestion Functions app | `<INGEST_FUNCTION_APP_NAME>` |
| Tracking storage | `<STORAGE_ACCOUNT_NAME>` (workshop-app-rg) |
| Ingestion storage | `<INGEST_STORAGE_ACCOUNT_NAME>` (workshop-data-rg) |
| Event Hub namespace | `workshop-eh-<suffix>` (workshop-data-rg) |
| Fabric workspace URL | `https://app.fabric.microsoft.com/groups/<FABRIC_WORKSPACE_ID>` |
| Fabric capacity | `<FABRIC_CAPACITY_NAME>` |
| azd environment | `<AZD_ENV>` |
