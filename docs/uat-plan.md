# UAT Plan — Azure IaaS Hackathon

**Purpose:** One-time end-to-end validation before the repository is published.  
**Scope:** Full Part 1 → 2 → 3 participant journey on a 2–3 slot test cohort, plus a 30-emitter load sanity check.  
**Gate:** All pass criteria must be met before the repo is made public or shared with customers.

> **Who runs this:** One facilitator (or pair) with Owner access to the test subscription and Fabric workspace.

---

## Prerequisites

| Item | Check |
|---|---|
| Azure subscription deployed (`azd up` ran cleanly) | ☐ |
| Fabric capacity running, workspace created by `setup-fabric.ps1` | ☐ |
| `infra/data-layer/fabric-outputs.json` exists with valid workspace ID | ☐ |
| Legacy app published (`app/legacy-system/publish.ps1`) and uploaded to a URL | ☐ |
| `src/config.js` updated: `ingestionEndpoint`, `fabricWorkspaceUrl`, `foundryProjectUrl`, `incidentGroundTruth` | ☐ |
| 3 test slots seeded (`.\infra\seed-cohort.ps1 -SlotCount 3 ...`) | ☐ |
| Azure AI Foundry project accessible with a shared GPT-4o deployment | ☐ |
| Test browser open on the workshop URL | ☐ |

---

## UAT Cohort Setup

Provision a minimal 3-slot cohort (user01, user02, user03) so the full journey can be walked without seeding all 30 slots.

```powershell
# Seed 3 test slots
.\infra\seed-cohort.ps1 `
  -SessionId       'uat-test-2026' `
  -StorageAccount  '<STORAGE_ACCOUNT_NAME>' `
  -IngestFunctionApp '<INGEST_FUNCTION_APP_NAME>' `
  -FabricWorkspaceId '<FABRIC_WORKSPACE_ID>' `
  -SkipPeeringRole `
  -SlotCount       3 `
  -TenantDomain    '<TENANT_DOMAIN>' `
  -TenantId        '<TENANT_ID>'
```

Expected: `3 slots seeded`, `cohort-keys.json` written, `INGEST_KEYS_JSON` updated on the Ingestion API, Fabric Viewer access granted to user01–03.

---

## Part 1 — Infrastructure

### 1.1 Participant check-in

- [ ] Open the workshop URL, enter email + display name for user01
- [ ] Credentials screen shows slot `user01`, TAP, resource group `user01-rg`
- [ ] Mark onboarding Complete → admin dashboard updates

### 1.2 Module 1 — Networking

- [ ] Follow Module 1 steps: create VNet `vnet-user01` (10.10.1.0/24) + `workload` subnet
- [ ] Mark module1 Complete → admin dashboard updates Part 1 — In Progress

### 1.3 Module 2 (instructor-led peering demo)

- [ ] Run `.\infra\peer-hub.ps1` for slot user01 → peering status reaches **Connected**
- [ ] Module 2 page shows instructor-demo callout; progress is optional (not a blocker)

### 1.4 Module 3 — Compute + app install

- [ ] Create VM `vm-user01` (Standard_D2ads_v5, Windows Server 2022, workload subnet, no public IP)
- [ ] Mark module3 Complete
- [ ] Run `.\infra\install-legacy-app.ps1` for user01 only
- [ ] Wait 2–3 minutes; verify `InstallLegacyApp` extension shows **Provisioning succeeded**

### 1.5 Part 1 Validation page

- [ ] Open `part1-validate.html` → signals check calls `GET /api/signals/check?slot=user01`
- [ ] Both `telemetryCount > 0` and `ticketCount > 0`; page shows **Signals confirmed**
- [ ] `part1_validate` auto-marks Complete → Part 1 segment turns green in progress bar

**Part 1 pass criteria:**
- All module statuses reflected on admin dashboard within 10 seconds of marking
- Signals arrive in Eventhouse and Lakehouse (verify in Fabric portal) within 60 seconds of app start
- No 500 errors from participant or admin API endpoints

---

## Part 2 — Data Layer

### 2.1 Confirm signals in Eventhouse

Open the Fabric workspace → Eventhouse → workshop-db. Run:

```kql
SlotTelemetry_user01()
| take 5
| project Timestamp, Service, LatencyMs, IsAnomaly
```

- [ ] Returns rows with `IsAnomaly = false` (normal operation, app started < 20 min ago)
- [ ] `SlotTickets_user01()` also returns rows in the Lakehouse

### 2.2 KQL correlation query

Wait until T+23 minutes (or adjust `scenario.json` `offsetMinutes` for UAT speed). Run:

```kql
let spikeWindows =
    SlotTelemetry_user01()
    | summarize AvgLatencyMs = avg(LatencyMs) by bin(Timestamp, 5m)
    | where AvgLatencyMs > 300;
let ticketBursts =
    SlotTickets_user01()
    | summarize TicketCount = count() by bin(Timestamp, 5m)
    | where TicketCount > 1;
spikeWindows
| join kind=inner (ticketBursts) on Timestamp
| project Timestamp, AvgLatencyMs, TicketCount
```

- [ ] Returns at least one row with correlated spike + burst
- [ ] The correlated window's `IncidentId` matches `INC-BADDEPLOYMENT-01`

### 2.3 Correlation function

```kql
.create-or-alter function SlotCorrelation_user01() {
    let spikeWindows = SlotTelemetry_user01()
        | summarize AvgLatencyMs = avg(LatencyMs) by bin(Timestamp, 5m)
        | where AvgLatencyMs > 300;
    let ticketBursts = SlotTickets_user01()
        | summarize TicketCount = count() by bin(Timestamp, 5m)
        | where TicketCount > 1;
    spikeWindows | join kind=inner (ticketBursts) on Timestamp
}
```

- [ ] Function created; `SlotCorrelation_user01()` returns expected rows

### 2.4 Fabric Data Agent

- [ ] Create Data Agent `workshop-agent-uat` grounded on Eventhouse + workshop-db
- [ ] Test: "Were there any latency spikes in the last 2 hours?" → agent returns specific timestamps and service name
- [ ] Test: "Which customer tenants filed tickets during the spike?" → agent returns at least one tenant name
- [ ] Test: "What was the IncidentId of the main spike?" → agent returns `INC-BADDEPLOYMENT-01`

**Part 2 pass criteria:**
- KQL correlation query returns at least one correlated window within 5 min of the incident firing
- Data Agent correctly identifies the incident service and IncidentId without prompting

---

## Part 3 — AI Agent

### 3.1 Foundry agent scaffold

- [ ] Create Foundry agent in the test project, connected to the `workshop-agent-uat` Data Agent via the Microsoft Fabric tool
- [ ] Test connection: "What was the average latency in the last hour?" → returns a number

### 3.2 Five use cases

Send each question; record the agent's answer:

| Use case | Test prompt | Pass |
|---|---|---|
| Root cause | "What system event caused the recent ticket spike?" | Agent names OrderService + timestamps |
| Noise vs signal | "Are the recent tickets all about the same problem?" | Agent clusters around the incident |
| Customer impact | "Which tenants were affected?" | Agent lists at least one tenant name |
| Change impact | "What deployment or change correlates with the issue?" | Agent names INC-BADDEPLOYMENT-01 |
| Blind spot | "Were there any ticket bursts with no telemetry anomaly?" | Agent identifies T+50 BlindSpot event |

- [ ] All 5 answers grounded in data (agent does not hallucinate service names or tenants)
- [ ] Agent uses the Fabric tool on at least 3 out of 5 questions (check Foundry trace)

### 3.3 Self-validation

- [ ] Open `part3-validate.html` → ground-truth card shows `INC-BADDEPLOYMENT-01`, `OrderService`, `eastus2`
- [ ] All `incidentGroundTruth` fields in `src/config.js` match `scenario.json`

**Part 3 pass criteria:**
- Foundry agent correctly identifies the planted root cause (`INC-BADDEPLOYMENT-01` + `OrderService`) in use case 4
- Agent names at least one affected customer tenant
- Agent identifies the blind-spot window in use case 5

---

## Load Sanity Check (~30 emitters)

To validate the shared infrastructure handles 30 simultaneous emitters without degradation:

```powershell
# Run the legacy app binary locally 30 times in parallel,
# each with a different slot ID, pointing at the real ingestion endpoint.
# Use the cohort-keys.json from a UAT seed of 30 slots.

$keys = Get-Content '.\infra\cohort-keys.json' | ConvertFrom-Json

1..30 | ForEach-Object -Parallel {
    $slot   = 'user{0:D2}' -f $_
    $key    = $using:keys.$slot
    $tmpDir = "$env:TEMP\legacy-load-$slot"
    New-Item -ItemType Directory -Force $tmpDir | Out-Null
    @{ SlotId = $slot; IngestionEndpoint = '<INGEST_URL>'; IngestionKey = $key; Region = 'eastus2' } |
        ConvertTo-Json | Set-Content "$tmpDir\appsettings.json"
    Copy-Item '.\app\legacy-system\scenario.json' "$tmpDir\" -Force
    Start-Process -FilePath '.\app\legacy-system\publish\legacy-system.exe' -WorkingDirectory $tmpDir -NoNewWindow
} -ThrottleLimit 30

# Wait 2 minutes, then check Ingestion API App Insights for error rate
# Expected: < 2% 4xx/5xx across all 30 slots
Start-Sleep -Seconds 120
Write-Host "Check App Insights for workshop-ingest-* — error rate should be < 2%"
```

- [ ] All 30 "slots" emit telemetry + tickets without 429 (throttle) or 500 errors
- [ ] Ingestion API App Insights shows request duration < 3s at p95
- [ ] Event Hub namespace metrics show no throttling (zero throttled requests)
- [ ] Eventhouse ingestion lag < 60 seconds end-to-end

---

## Pass / Fail Summary

Complete this before publishing the repo:

| Area | Result | Notes |
|---|---|---|
| Part 1 end-to-end (1 slot) | ☐ Pass ☐ Fail | |
| Signals in Eventhouse + Lakehouse | ☐ Pass ☐ Fail | |
| KQL correlation query | ☐ Pass ☐ Fail | |
| Fabric Data Agent — root cause | ☐ Pass ☐ Fail | |
| Foundry agent — all 5 use cases | ☐ Pass ☐ Fail | |
| Self-validation page | ☐ Pass ☐ Fail | |
| Load sanity (30 emitters) | ☐ Pass ☐ Fail | |
| Admin dashboard — 3-part progress | ☐ Pass ☐ Fail | |

**Sign-off:** All 8 rows must show **Pass** before publishing.

Signed off by: _________________________ Date: _____________
