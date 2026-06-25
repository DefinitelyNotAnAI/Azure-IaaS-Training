# Workshop Infrastructure Runbook

Operator reference for the Azure IaaS Fundamentals workshop. Covers one-time setup, per-cohort lifecycle, and cost management.

---

## Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI (`az`) | 2.60 | `winget install Microsoft.AzureCLI` |
| Bicep CLI | 0.28 | `az bicep upgrade` |
| Azure Developer CLI (`azd`) | 1.9 | `winget install Microsoft.Azd` |
| PowerShell | 7.4 | `winget install Microsoft.PowerShell` |
| Az PowerShell module | 12.x | `Install-Module Az -Scope CurrentUser` |
| Microsoft.Graph module | 2.x | `Install-Module Microsoft.Graph -Scope CurrentUser` |

Log in to both CLIs before running any scripts:

```powershell
az login --tenant <YOUR_TENANT_ID>
Connect-AzAccount -Tenant <YOUR_TENANT_ID> `
  -Subscription "<YOUR_SUBSCRIPTION_NAME>"
```

---

## One-time setup (deploy hub + app infrastructure)

Run once per subscription. Hub and app infrastructure persist across cohorts.

### 1 — Deploy the hub VNet

```powershell
az deployment sub create `
  --location eastus2 `
  --template-file infra/hub.bicep `
  --parameters location=eastus2
```

Creates `hub-rg` with `hub-vnet` (10.0.0.0/16), three subnets:
- `GatewaySubnet` (10.0.0.0/24)
- `AzureBastionSubnet` (10.0.1.0/26)
- `shared-services` (10.0.2.0/24)

> **Note:** Azure Bastion itself is not deployed by `hub.bicep` — provision it manually in the portal (or add to `hub-resources.bicep`) before the first session that uses it.

### 2 — Deploy the app infrastructure

```powershell
azd up
# Select subscription: <YOUR_SUBSCRIPTION_NAME>
# Select location: eastus2
```

Alternatively, using Bicep directly:

```powershell
az deployment sub create `
  --location eastus2 `
  --template-file infra/app.bicep `
  --parameters location=eastus2 workshopTenantDomain=contoso.onmicrosoft.com
```

Creates `workshop-app-rg` with:
- UAMI `workshop-app-mi`
- Storage account `wkstoreXXXXXX` (Tables: `Participants`, `Assignments`)
- Flex Consumption Function App `workshop-api-XXXXXX`
- Static Web App `workshop-hub` (Standard tier)
- Application Insights `workshop-insights`

### 3 — Grant Graph API permissions to the UAMI

Run once. Fully idempotent — safe to re-run.

```powershell
.\infra\grant-graph-permissions.ps1
```

Grants `UserAuthenticationMethod.ReadWrite.All` and `User.Read.All` as application permissions on the `workshop-app-mi` service principal.

### 4 — Configure Function App settings

Update the app settings in `workshop-app-rg → workshop-api-XXXXXX → Configuration`:

| Setting | Value |
|---|---|
| `SESSION_CODE` | Shared passcode for participant check-in (rotate each delivery) |
| `ADMIN_ACCESS_CODE` | Instructor dashboard access code (keep secret) |
| `SESSION_ID` | Partition key for this cohort, e.g. `contoso-2026-01-01` |

All other settings (`AZURE_CLIENT_ID`, `STORAGE_ACCOUNT_NAME`, etc.) are set automatically by `app-resources.bicep`.

### 5 — Deploy the web app

```powershell
azd deploy web
```

Or push to the Static Web App via the GitHub Actions workflow (if configured).

---

## Per-cohort lifecycle

### A — Seed the cohort (run 1–2 days before the workshop)

```powershell
.\infra\seed-cohort.ps1 `
  -SessionId "contoso-2026-01-01" `
  -StorageAccount "wkstoreXXXXXX" `
  -SlotCount 25   # default 30
```

For each slot (user01…userXX):
1. Creates Entra ID user `userXX@contoso.onmicrosoft.com`
2. Assigns **Contributor** on `userXX-rg`, **Reader** on `hub-rg`
3. Issues an 8-hour multi-use TAP
4. Writes an `Assignments` table row (slot, RG, CIDR, UPN, TAP code)

> Update `SESSION_ID`, `SESSION_CODE`, and `ADMIN_ACCESS_CODE` in the Function App settings to match the new session before participants arrive.

### B — Deploy spoke resource groups

```powershell
az deployment sub create `
  --location eastus2 `
  --template-file infra/spokes.bicep `
  --parameters location=eastus2 sessionId="contoso-2026-01-01" slotCount=25
```

Creates `user01-rg` … `user25-rg` tagged with `cohort: contoso-2026-01-01`.

> Run this **before** `seed-cohort.ps1` so the spoke RGs exist when RBAC assignments are made.

### C — During the workshop: peer hub VNets (Module 2)

After participants have created their spoke VNets and added the spoke-side peering, run:

```powershell
# Batch all participants at once
.\infra\peer-hub.ps1 -SessionId "contoso-2026-01-01"

# Or a single straggler
.\infra\peer-hub.ps1 -SessionId "contoso-2026-01-01" -Slot user07
```

Idempotent — skips slots where peering is already `Connected` or where the spoke VNet doesn't exist yet.

### D — Export attendance (optional, before teardown)

```powershell
.\infra\export-cohort.ps1 `
  -SessionId "contoso-2026-01-01" `
  -StorageAccount "wkstoreXXXXXX" `
  -OutputPath ".\exports\contoso-2026-01-01.csv"
```

Exports: email, displayName, slot, RG, CIDR, all module statuses, portalSignedInAt, lastUpdated.

---

## Teardown options

### Soft exit (between cohorts — keep hub + app infrastructure)

Removes participant resources but leaves the app running for the next cohort.

```powershell
.\infra\teardown-cohort.ps1 `
  -SessionId "contoso-2026-01-01" `
  -StorageAccount "wkstoreXXXXXX"
```

What this does:
1. Removes all hub-side VNet peerings for the cohort
2. Deletes spoke RGs `user01-rg` … `user30-rg` (async, in parallel)
3. Deletes 30 Entra ID user accounts
4. Purges the `Participants` and `Assignments` table partitions for the session

What it **leaves intact**: `hub-rg`, `workshop-app-rg`, Function App, Static Web App, Table Storage (other partitions), UAMI, App Insights.

**Cost impact after soft exit:** hub-rg and workshop-app-rg continue to accrue charges (Static Web App Standard ~$9/mo, Flex Consumption near-zero at idle, storage negligible). No spoke VM or VNet charges.

Use `-WhatIf` to preview without making changes:
```powershell
.\infra\teardown-cohort.ps1 -SessionId "contoso-2026-01-01" -StorageAccount "wkstoreXXXXXX" -WhatIf
```

### Hard exit (end of programme — full teardown)

Run soft exit first, then:

```powershell
# Delete app infrastructure
azd down --purge --force

# Delete hub
az group delete --name hub-rg --yes --no-wait
```

This removes all resources and incurs no further costs.

---

## Cost model (East US, approximate)

| Resource | Tier | Always-on cost | Notes |
|---|---|---|---|
| Static Web App | Standard | ~$9/mo | Required for Functions backend link |
| Function App | Flex Consumption | ~$0 idle | Billed per execution during workshops |
| Storage account | Standard LRS | <$1/mo | Tables + Blob (deployment package) |
| Log Analytics | Pay-as-you-go | <$1/mo | 30-day retention, minimal ingestion |
| App Insights | Pay-as-you-go | <$1/mo | Sampled telemetry |
| hub-vnet | Free | $0 | VNet itself has no hourly charge |
| Azure Bastion | Basic/Standard | $0.19–$0.49/hr | **Stop or delete after each session** |
| **Spoke VMs (per participant)** | Standard_B2s | ~$0.04/hr | Delete spoke RGs immediately after teardown |

**Estimated workshop day cost (25 participants, 8 hours):**
- 25x Standard_B2s VMs × 8h × $0.038/hr ≈ **$7.60**
- Azure Bastion (Basic) × 8h × $0.19/hr ≈ **$1.52**
- Spoke VNets, NICs, disks ≈ **$2–3**
- **Total ≈ $11–13 per session** (excluding SWA/Functions standing cost)

> To minimize cost: run soft exit the same evening as the workshop. The biggest per-session cost driver is participant VMs left running overnight.

---

## Table Storage schema reference

### `Participants` table

| Property | Type | Notes |
|---|---|---|
| PartitionKey | string | `SESSION_ID` value |
| RowKey | string | Participant email (lowercase) |
| displayName | string | |
| participantId | string | UUID |
| assignedSlot | string | `user01`…`user30` |
| assignedRg | string | `user01-rg` |
| assignedCidr | string | `10.10.1.0/24` |
| assignedUpn | string | Full UPN |
| tapIssuedAt | string | ISO 8601 |
| portalRgUrl | string | Portal deep-link |
| moduleStatuses | string | JSON: `{"onboarding":"complete","module1":"started",...}` |
| currentModule | string | Last updated module key |
| currentStatus | string | Last updated status |
| portalSignedInAt | string | ISO 8601; set when onboarding=complete |
| feedback | string | Max 1000 chars |
| lastUpdated | string | ISO 8601 |

### `Assignments` table

| Property | Type | Notes |
|---|---|---|
| PartitionKey | string | `SESSION_ID` value |
| RowKey | string | `user01`…`user30` |
| assignedRg | string | |
| assignedCidr | string | |
| assignedUpn | string | |
| assignedUserObjectId | string | Entra ID object ID (needed for TAP rotation) |
| tempCredential | string | Current TAP code |
| currentTapId | string | TAP method ID (needed for revocation) |
| tapIssuedAt | string | ISO 8601 |
| claimedByEmail | string | Empty string = unclaimed |
| claimedAt | string | ISO 8601 or empty |
