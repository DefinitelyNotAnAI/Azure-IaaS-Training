# Pre-Flight Checklist — Azure IaaS Hackathon

Run this checklist **before each delivery** (not before publishing — that's the UAT plan).  
Aim to complete this 60 minutes before participants arrive.

> **Tokens to replace:** `<STORAGE_ACCOUNT_NAME>`, `<INGEST_FUNCTION_APP_NAME>`, `<INGEST_URL>`, `<SWA_HOSTNAME>`, `<AZD_ENV>`, `<ADMIN_ACCESS_CODE>`, `<SESSION_CODE>`, `<FABRIC_WORKSPACE_ID>`, `<FABRIC_CAPACITY_NAME>`, `<SUBSCRIPTION_ID>`, `<TENANT_DOMAIN>`

---

## T-60 min — Infrastructure checks

### 1. Resume Fabric capacity (if suspended from previous event)

```powershell
$subId = az account show --query id -o tsv
az rest --method post `
  --url "https://management.azure.com/subscriptions/$subId/resourceGroups/workshop-data-rg/providers/Microsoft.Fabric/capacities/<FABRIC_CAPACITY_NAME>/resume?api-version=2023-11-01"
```

Expected: `200 OK`. Capacity takes 1–3 minutes to reach **Active** — verify in the Azure portal.

- [ ] Fabric capacity status = **Active**

### 2. Check storage public network access

```powershell
az storage account show --name <STORAGE_ACCOUNT_NAME> --resource-group workshop-app-rg `
  --query "{publicNetworkAccess:publicNetworkAccess}" -o json
```

If output is `"Disabled"`:

```powershell
az storage account update --name <STORAGE_ACCOUNT_NAME> --resource-group workshop-app-rg `
  --subscription <SUBSCRIPTION_ID> --public-network-access Enabled
Start-Sleep -Seconds 30
```

- [ ] `publicNetworkAccess = Enabled`

### 3. Smoke-test the participant tracking API

```powershell
$r = Invoke-WebRequest -Uri 'https://<SWA_HOSTNAME>/api/dashboard/participants' `
  -Headers @{ 'x-access-code' = '<ADMIN_ACCESS_CODE>' } -SkipHttpErrorCheck
"Status: $($r.StatusCode)"
```

- [ ] Returns `200` (even if `[]` — no participants yet)
- [ ] If `500`: redeploy API → `azd deploy api --environment <AZD_ENV>`

### 4. Smoke-test the Ingestion API

```powershell
$r = Invoke-WebRequest -Uri '<INGEST_URL>/api/health' -SkipHttpErrorCheck
"Status: $($r.StatusCode)"
```

- [ ] Returns `200` (or any non-5xx)
- [ ] If `500`: redeploy → `azd deploy ingest-api --environment <AZD_ENV>`

### 5. Verify Fabric workspace accessible

Open `https://app.fabric.microsoft.com/groups/<FABRIC_WORKSPACE_ID>` in your browser.

- [ ] Workspace loads; Eventhouse `workshop-eventhouse` and Lakehouse `workshop-lakehouse` are visible
- [ ] Reference Data Agent `workshop-agent-reference` is visible and can be opened

---

## T-45 min — Cohort provisioning

### 6. Seed the cohort

```powershell
.\infra\seed-cohort.ps1 `
  -SessionId        '<SESSION_ID>' `
  -StorageAccount   '<STORAGE_ACCOUNT_NAME>' `
  -IngestFunctionApp '<INGEST_FUNCTION_APP_NAME>' `
  -FabricWorkspaceId '<FABRIC_WORKSPACE_ID>' `
  -SkipPeeringRole `
  -TenantDomain     '<TENANT_DOMAIN>' `
  -TenantId         '<TENANT_ID>'
```

Expected: `30 slots seeded`, `cohort-keys.json` written, `INGEST_KEYS_JSON` updated.

- [ ] Seeding completes with 0 errors
- [ ] `infra/cohort-keys.json` created (back this up securely; needed for install-legacy-app.ps1)

### 7. Update `src/config.js` for this delivery

Edit [src/config.js](../src/config.js) — update the per-delivery fields:

```javascript
sessionId:   '<SESSION_ID>',    // e.g. 'contoso-2026-07-01'
sessionName: '<SESSION_NAME>',  // e.g. 'Contoso Azure Hackathon'
sessionDate: '<DATE>',
sessionCode: '<SESSION_CODE>',
```

Verify `ingestionEndpoint`, `fabricWorkspaceUrl`, `foundryProjectUrl`, and `incidentGroundTruth` are already set from UAT / previous deployment.

- [ ] config.js saved and deployed (`azd deploy web --environment <AZD_ENV>`)

### 8. Rotate all TAPs

```powershell
.\infra\rotate-all-taps.ps1 -AdminCode "<ADMIN_ACCESS_CODE>"
```

- [ ] `OK=30  Failed=0`

---

## T-30 min — Data layer + signals

### 9. Verify Ingestion API has the new cohort keys

```powershell
az functionapp config appsettings list `
  --name <INGEST_FUNCTION_APP_NAME> `
  --resource-group workshop-data-rg `
  --query "[?name=='INGEST_KEYS_JSON'].value" -o tsv | Select-String 'user01'
```

- [ ] `INGEST_KEYS_JSON` contains `user01` key

### 10. Spot-check one emitter (optional if legacy app binary unchanged)

If you want to confirm the emitter works before the event:

```powershell
$keys = Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json
$tmpDir = "$env:TEMP\preflight-user01"
New-Item -ItemType Directory -Force $tmpDir | Out-Null
@{ SlotId='user01'; IngestionEndpoint='<INGEST_URL>'; IngestionKey=$keys.user01; Region='eastus2' } |
  ConvertTo-Json | Set-Content "$tmpDir\appsettings.json"
Copy-Item '.\app\legacy-system\scenario.json' "$tmpDir\" -Force
# Run for 30 seconds; Ctrl+C to stop
.\app\legacy-system\publish\legacy-system.exe
```

- [ ] App starts and logs `Legacy system started. slot=user01`
- [ ] After ~15 seconds: rows appear in Eventhouse `SlotTelemetry_user01() | take 3`

### 11. Confirm reference Data Agent answers a test question

Open the Fabric workspace → `workshop-agent-reference`. Ask:

> "Were there any issues in the last hour for slot user01?"

- [ ] Agent responds (even if "no data yet") without errors
- [ ] Agent does NOT return a 500 or "grounding failed" message

---

## T-15 min — Final smoke test

### 12. Open the admin dashboard

`https://<SWA_HOSTNAME>/admin.html` — enter `<ADMIN_ACCESS_CODE>`.

- [ ] Dashboard loads, shows session name from config.js
- [ ] Regroup summary shows 3 part cards (Part 1 / Part 2 / Part 3) — all "Not started"
- [ ] Slot Pool tab shows 30 unclaimed slots with TAP issued timestamps

### 13. Test participant check-in

Open `https://<SWA_HOSTNAME>/` in a private/incognito window. Enter a test email and name; use session code `<SESSION_CODE>`.

- [ ] Credentials screen appears with slot, TAP, and resource group
- [ ] Admin dashboard immediately shows the test participant (may need a manual refresh)
- [ ] Click "Change" → returns to check-in form (no stale localStorage issue)

### 14. Confirm `part1-validate.html` unconfigured state (optional)

Navigate to `https://<SWA_HOSTNAME>/part1-validate.html`. If `ingestionEndpoint` is set in config.js and working:

- [ ] Page shows "checking" state or a "data layer not configured" callout (if endpoint is blank — expected)

---

## T-0 — Go / No-Go

| Check | Status |
|---|---|
| Fabric capacity **Active** | ☐ |
| Storage public access **Enabled** | ☐ |
| Tracking API returns 200 | ☐ |
| Ingestion API returns 200 | ☐ |
| Fabric workspace loads | ☐ |
| 30 slots seeded, keys updated | ☐ |
| config.js updated + deployed | ☐ |
| All TAPs rotated (OK=30) | ☐ |
| Admin dashboard loads + shows 30 slots | ☐ |
| Test check-in succeeds | ☐ |

**All 10 green = GO.** Any red item = resolve before opening the workshop URL to participants.

---

## Post-event cleanup

After the event ends:

```powershell
# Teardown with full cleanup
.\infra\teardown-cohort.ps1 `
  -SessionId        '<SESSION_ID>' `
  -StorageAccount   '<STORAGE_ACCOUNT_NAME>' `
  -IngestFunctionApp '<INGEST_FUNCTION_APP_NAME>' `
  -PauseFabricCapacity `
  -FabricCapacityName '<FABRIC_CAPACITY_NAME>' `
  -FabricCapacityRg  'workshop-data-rg'
```

- [ ] `teardown-cohort.ps1` completes (VMs deleted, RGs deleting, users deleted, INGEST_KEYS_JSON reset)
- [ ] Fabric capacity shows **Paused** in the portal (~2–3 minutes)
- [ ] Delete `infra/cohort-keys.json` from local disk (contains secrets)
