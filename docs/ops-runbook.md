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
