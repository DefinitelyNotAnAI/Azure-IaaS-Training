# Workshop Ops Runbook

Azure IaaS Workshop — facilitator operational guide.

> **Reusing this repo?** Replace the placeholder tokens below with values from
> your own deployment (see the root [README](../README.md) for the full list):
> `<STORAGE_ACCOUNT_NAME>`, `<SUBSCRIPTION_ID>`, `<TENANT_ID>`, `<SWA_HOSTNAME>`,
> `<FUNCTION_APP_NAME>`, `<UAMI_CLIENT_ID>`, `<TENANT_DOMAIN>`, `<ADMIN_ACCESS_CODE>`,
> `<SESSION_CODE>`, and `<AZD_ENV>` (your azd environment name).

---

## Pre-workshop checklist (~60 min before start)

### 1. Enable storage public network access

If an Azure Policy in your tenant **resets `publicNetworkAccess` to `Disabled` nightly** on the storage account, it breaks `azd deploy api`. Re-enable it before any deployment.

```powershell
az storage account update `
  --name <STORAGE_ACCOUNT_NAME> `
  --resource-group workshop-app-rg `
  --subscription <SUBSCRIPTION_ID> `
  --public-network-access Enabled
```

Wait ~30 seconds for propagation before deploying.

**Symptoms if skipped:** `azd deploy api` fails with `403 BlobUploadFailedException`. Function App host crashes on cold start — all API endpoints return 500 "Backend call failure".

### 2. Deploy the API (if code changed since last run)

```powershell
cd <repo-root>
azd deploy api --environment <AZD_ENV>
```

Expected output: `● api  Done  ~1m 15s`

If this fails with 403, go back to step 1 — public network access is disabled again.

### 3. Rotate all TAPs (~30 min before start)

TAPs are valid for **8 hours** from issuance. Rotate close to workshop start so they don't expire mid-session.

```powershell
cd <repo-root>
.\infra\rotate-all-taps.ps1 -AdminCode "<ADMIN_ACCESS_CODE>"
```

Expected output: `OK=30  Failed=0`

TAPs expire 8 hours after the time shown in `issued at` column.

### 4. Smoke test the site

Open the workshop URL and sign in as a test participant:

- **URL:** `https://<SWA_HOSTNAME>/`
- **Admin dashboard:** `/admin.html` (code: `<ADMIN_ACCESS_CODE>`)
- Verify the participants table loads and the module progress columns show correctly (Sign In / M1 Networking / M2 Peering / M3 Compute).

---

## Recurring issues & fixes

### Function App returns 500 / "Error loading data" / "Backend call failure"

**Root cause:** Storage public network access was disabled (an Azure Policy may reset it nightly), blocking `azd deploy api`. The Function App host cannot start because it's running stale/incomplete code.

**Diagnosis steps:**

```powershell
# 1. Check public network access
az storage account show `
  --name <STORAGE_ACCOUNT_NAME> `
  --resource-group workshop-app-rg `
  --query "{publicNetworkAccess:publicNetworkAccess}" -o json

# 2. Try hitting participants endpoint
$r = Invoke-WebRequest `
  -Uri 'https://<SWA_HOSTNAME>/api/dashboard/participants' `
  -Headers @{ 'x-access-code' = '<ADMIN_ACCESS_CODE>' } -SkipHttpErrorCheck
"$($r.StatusCode): $([System.Text.Encoding]::UTF8.GetString($r.Content))"
```

**Fix:**

```powershell
# Re-enable public access
az storage account update --name <STORAGE_ACCOUNT_NAME> --resource-group workshop-app-rg `
  --subscription <SUBSCRIPTION_ID> --public-network-access Enabled

# Wait for propagation
Start-Sleep -Seconds 30

# Redeploy API
azd deploy api --environment <AZD_ENV>
```

### Module 2: participants get "does not have permission to peer" error

**Root cause:** The `Workshop Hub Peering` custom role (which grants `peer/action` plus `virtualNetworkPeerings` read/write/delete on hub-vnet) was not assigned to participants — either the role didn't exist yet when `seed-cohort.ps1` ran, or it was a cohort provisioned before `fix-hub-peering-rbac.ps1` was run.

**Fix:**

```powershell
cd <repo-root>
# Connect if not already
Connect-AzAccount -TenantId <TENANT_ID>

# Fix all 30 participants (idempotent — safe to re-run):
.\infra\fix-hub-peering-rbac.ps1 -SubscriptionId <SUBSCRIPTION_ID>
```

The script creates the `Workshop Hub Peering` custom role if it doesn't exist, waits 15 seconds for propagation, then assigns it to every participant. Tell participants to press **F5** in the portal and retry the peering.

**Note for future cohorts:** `seed-cohort.ps1` now assigns this role automatically — but the custom role must already exist in the subscription. Run `fix-hub-peering-rbac.ps1` once after provisioning a fresh subscription to create the role, before running `seed-cohort.ps1`.

---

### TAP rotation script fails (all slots 500)

This is the same root cause as above — Function App is down. Fix the Function App first (see above), then re-run the rotation script.

### `azd deploy` fails with 403

Public network access is disabled. See "Enable storage public network access" above.

### TAP not visible for returning participants

Participants who close their browser lose their TAP from sessionStorage. The page auto-fetches a fresh TAP from the API on reload — this is expected behavior. If the API is down, participants won't see their TAP. Fix: restore the Function App.

### Admin dashboard shows no data / "Error loading data"

Either the Function App is down (see above) or the wrong access code is being used. The admin code is `<ADMIN_ACCESS_CODE>`.

---

## Key resource reference

> Fill this table in with the values from **your** deployment after running `azd up`
> and `seed-cohort.ps1`.

| Resource | Value |
|---|---|
| Workshop URL | `https://<SWA_HOSTNAME>/` |
| Admin code | `<ADMIN_ACCESS_CODE>` |
| Session code (participant sign-in) | `<SESSION_CODE>` |
| Session ID | `contoso-2026-01-01` |
| azd environment | `<AZD_ENV>` |
| Function App | `<FUNCTION_APP_NAME>` (eastus2, Flex Consumption) |
| Storage account | `<STORAGE_ACCOUNT_NAME>` |
| Resource group | `workshop-app-rg` |
| Subscription | `<SUBSCRIPTION_ID>` |
| Tenant domain | `<TENANT_DOMAIN>` |
| UAMI | `workshop-app-mi` (clientId: `<UAMI_CLIENT_ID>`) |
| Participant accounts | `user01`–`user30` @ `<TENANT_DOMAIN>` |
| TAP validity | 8 hours, multi-use |

---

## Mid-workshop TAP rotation (if needed)

If a participant's TAP expires mid-session, rotate just that slot:

```powershell
# Rotate a single slot via the admin dashboard UI:
# Admin dashboard → Assignments tab → click "Rotate TAP" for the slot

# Or via PowerShell:
Invoke-RestMethod `
  -Uri 'https://<SWA_HOSTNAME>/api/dashboard/assignments/user01/rotate-tap' `
  -Method POST `
  -Headers @{ 'x-access-code' = '<ADMIN_ACCESS_CODE>' }
```

The participant should reload `index.html` — the page will auto-fetch the new TAP.

---

## Deploying code changes

Always in this order:

```powershell
# 1. Ensure storage is accessible (do this first if Policy resets it nightly)
az storage account update --name <STORAGE_ACCOUNT_NAME> --resource-group workshop-app-rg `
  --subscription <SUBSCRIPTION_ID> --public-network-access Enabled
Start-Sleep -Seconds 30

# 2. Deploy what changed
azd deploy api --environment <AZD_ENV>   # API / Function App
azd deploy web --environment <AZD_ENV>   # Static Web App (src/)

# 3. Rotate TAPs if deploying on workshop day
.\infra\rotate-all-taps.ps1 -AdminCode "<ADMIN_ACCESS_CODE>"
```

**Do not** run `azd up` — it re-provisions infrastructure and can reset settings.

---

## Post-workshop teardown

```powershell
# Export participant data before teardown
.\infra\export-cohort.ps1

# Tear down cohort accounts (does NOT delete Azure resources)
.\infra\teardown-cohort.ps1
```

Disable storage public network access after the workshop is done:

```powershell
az storage account update --name <STORAGE_ACCOUNT_NAME> --resource-group workshop-app-rg `
  --subscription <SUBSCRIPTION_ID> --public-network-access Disabled
```

---

## Hackathon-specific failure modes (Parts 2 & 3)

### Ingestion API returns 401 for all VM emitters

**Symptom:** `part1-validate.html` shows "No signals found yet" for all slots. Ingestion API App Insights shows 401s.

**Root cause:** `INGEST_KEYS_JSON` is empty (`{}`) on the Ingestion API — seed-cohort ran without `-IngestFunctionApp` or the step was skipped.

**Fix:**

```powershell
$keys = Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json | ConvertTo-Json -Compress
az functionapp config appsettings set `
  --name <INGEST_FUNCTION_APP_NAME> `
  --resource-group workshop-data-rg `
  --settings "INGEST_KEYS_JSON=$keys"
```

Participants should see signals within 30 seconds of their VM emitter next polling cycle.

---

### Eventhouse shows no rows / zero telemetry

**Symptom:** `SlotTelemetry_userXX()` returns empty in Fabric. Ingestion API shows 202 responses.

**Diagnosis:** The Eventstream is either not configured or has lost its Event Hub connection.

```powershell
# Check if events are landing in Event Hub
az eventhubs eventhub show `
  --namespace-name <EH_NAMESPACE> `
  --resource-group workshop-data-rg `
  --name telemetry `
  --query "messageRetentionInDays"  # confirms hub exists

# Check Eventstream in Fabric portal:
# Fabric workspace → Eventstreams → workshop-eventstream-telemetry → Live view
# Should show events flowing through the pipeline
```

**Fix options:**
1. If Eventstream shows errors on the Event Hub source: re-enter the Event Hub connection string in the Eventstream source settings.
2. If Eventstream source is healthy but destination (Eventhouse) shows errors: delete and re-add the Eventhouse destination in the Eventstream editor.
3. If Eventstream was never configured (preview API failed during setup): create it manually in Fabric portal → New Eventstream → Source: Event Hub `telemetry` (consumer group: `eventstream`) → Destination: Eventhouse → `workshop-db` → `Telemetry` table.

---

### Lakehouse (Tickets) shows no rows

Same diagnosis path as Eventhouse above, but for the `support` Event Hub and `workshop-eventstream-support`.

---

### Fabric Data Agent returns "grounding failed" or "no data available"

**Symptom:** Participant's Data Agent answers "I couldn't retrieve data from the data source."

**Root cause:** The Data Agent's grounding is pointing at the wrong database or the KQL functions don't exist yet.

**Diagnosis:**

1. In the Data Agent editor, check that the grounding shows `workshop-eventhouse → workshop-db`.
2. In the Eventhouse KQL editor, confirm the slot functions exist:

```kql
.show functions | where Name startswith 'SlotTelemetry_user'
```

If no functions appear, re-run `setup-fabric.ps1` (safe to re-run — idempotent):

```powershell
.\infra\data-layer\setup-fabric.ps1
```

**Per-participant fix:** If the grounding looks correct but answers are wrong, have the participant re-open the Data Agent, click the grounding item, and click **Refresh schema**. Then re-test.

---

### Foundry agent does not call the Fabric tool

**Symptom:** Foundry agent answers "I don't have access to data" or gives generic answers without citing specific metrics.

**Root cause:** The Microsoft Fabric tool is not connected to the participant's Data Agent, or the Fabric workspace connection is not added to the Foundry hub.

**Facilitator fix (workspace connection):**
1. Azure AI Foundry → your hub → Settings → Connected resources
2. Add connection → Microsoft Fabric → select the workshop workspace
3. Participants may need to refresh their agent after the connection is added

**Participant fix (tool not configured):**
1. In the Foundry agent editor, go to Tools
2. Click **+ Add tool** → Microsoft Fabric → select their `workshop-agent-userXX` Data Agent
3. Save and re-test

---

### VM Custom Script Extension shows "Failed"

**Symptom:** Participant's VM blade → Extensions shows `InstallLegacyApp` with status **Failed**.

**Diagnosis:**
```powershell
# Check extension detailed status
az vm extension show `
  --resource-group user01-rg `
  --vm-name vm-user01 `
  --name InstallLegacyApp `
  --query "instanceView" -o json
```

Look for the error message in `statuses[].message`.

**Common causes and fixes:**

| Message | Cause | Fix |
|---|---|---|
| `Cannot find legacy-system.exe in ...` | AppBinaryUrl was unreachable when CSE ran | Re-run `install-legacy-app.ps1` for the affected slot with a verified URL |
| `Service failed to start` | App configuration error | RDP into VM (via Bastion if peered), check `C:\legacy-system\appsettings.json` for correct values, check Windows Event Log for `LegacySystem` errors |
| `Exit code: 1` (generic) | Script execution failed | Check CSE extension stdout/stderr in `az vm extension show` `instanceView` |

**Re-run extension for a single slot:**
```powershell
.\infra\install-legacy-app.ps1 `
  -SubscriptionId    '<SUBSCRIPTION_ID>' `
  -IngestionEndpoint '<INGEST_URL>' `
  -AppBinaryUrl      '<APP_BINARY_URL>' `
  -InstallScriptUrl  '<INSTALL_SCRIPT_URL>' `
  -IngestionKeysJson (Get-Content '.\infra\cohort-keys.json' -Raw) `
  -SlotCount         1    # won't help — script iterates all slots
```

For a single slot, use az CLI directly:
```powershell
$slot = 'user01'
$key  = (Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json).$slot
$cmd  = "powershell -ExecutionPolicy Unrestricted -File install.ps1 -SlotId '$slot' -IngestionEndpoint '<INGEST_URL>' -IngestionKey '$key'"
az vm extension set --resource-group "$slot-rg" --vm-name "vm-$slot" `
  --name CustomScriptExtension --publisher Microsoft.Compute `
  --settings "{\"fileUris\":[\"<INSTALL_SCRIPT_URL>\",\"<APP_BINARY_URL>\"]}" `
  --protected-settings "{\"commandToExecute\": \"$cmd\"}"
```

---

### Legacy app installed but not emitting (LegacySystem service Running, no Eventhouse rows)

**Symptom:** Extension shows Provisioned. Service is Running. But `SlotTelemetry_userXX()` stays empty.

**Diagnosis:**
1. Confirm `IngestionEndpoint` in `C:\legacy-system\appsettings.json` is correct (RDP via Bastion or re-check install parameters).
2. Check if the Ingestion API is returning errors for this slot: Ingestion API App Insights → Failures → filter by `x-team-key` header.
3. Check the Windows Application event log on the VM for `LegacySystem` warnings.

**Fix:** If `IngestionEndpoint` is wrong (blank or old URL), update `appsettings.json` on the VM and restart the service:

```powershell
# Via Bastion on the VM:
$cfg = Get-Content 'C:\legacy-system\appsettings.json' | ConvertFrom-Json
$cfg.IngestionEndpoint = '<CORRECT_INGEST_URL>'
$cfg | ConvertTo-Json | Set-Content 'C:\legacy-system\appsettings.json'
Restart-Service LegacySystem
```

---

### Mid-event recovery: re-rotate ingestion keys for a slot

If a participant somehow obtains another slot's ingestion key (e.g. from browser network tab), regenerate the key:

```powershell
# Generate a new key for user01
function New-IngestKey { $b=[byte[]]::new(16); [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [BitConverter]::ToString($b).Replace('-','').ToLower() }
$newKey = New-IngestKey

# Update cohort-keys.json locally
$keys = Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json
$keys.user01 = $newKey
$keys | ConvertTo-Json | Set-Content '.\infra\cohort-keys.json'

# Push to Ingestion API
az functionapp config appsettings set `
  --name <INGEST_FUNCTION_APP_NAME> --resource-group workshop-data-rg `
  --settings "INGEST_KEYS_JSON=$($keys | ConvertTo-Json -Compress)"

# Update Assignments table
az storage entity merge --account-name <STORAGE_ACCOUNT_NAME> --auth-mode login `
  --table-name Assignments --partition-key '<SESSION_ID>' --row-key user01 `
  --entity "ingestKey=$newKey"

# Re-run extension on the VM with the new key
# (use single-slot az vm extension set command from above)
```
