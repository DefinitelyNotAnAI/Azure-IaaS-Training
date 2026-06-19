# Azure IaaS Fundamentals — Implementation Plan

> Companion to [website-plan.md](website-plan.md). That document defines **what** to build; this one defines **how** and **in what order**. The success condition stays the same: *participants know where to go, the instructor knows where they are, and the live workshop stays organized.*

> **App naming:** the app is intentionally generic (**Azure IaaS Fundamentals**) and reusable across audiences. The only place a customer/session name appears is the **Session Information** block on the welcome page, driven by configurable values in `config.js` (e.g. `sessionName: "Quanta Azure Workshop"`, `sessionDate: "June 25th, 10:00 am"`).

---

## 1. Decisions locked for this build

> **Module numbering follows the instructor guide** (`Quanta_Azure_IaaS_Training_Plan_Learn_Sandbox.docx`, owner: Lee Robbins), which is the live run-of-show. The three hands-on labs are **Module 1 = Networking, Module 2 = Compute, Module 3 = Storage**. **Platform & Architecture is an instructor-led demo**, not a numbered participant lab. This differs from the older [website-plan.md](website-plan.md) (which listed Platform as Module 1 and ran four modules) — see Section 11 to reconcile that document.

| Area | Decision | Rationale |
|------|----------|-----------|
| Frontend | **Plain static HTML/CSS/vanilla JS** (no framework, no build step) | Maximum reliability for a live event; easy to vibe-code and regenerate |
| Hosting | **Azure Static Web Apps (SWA)** — **Standard tier** | Global CDN, GitHub CI/CD; Standard enables a *linked* (bring-your-own) backend and carries an SLA |
| API | **Standalone Azure Functions app on Flex Consumption** (Node.js), **linked** to SWA | Prioritizes stability + scalability over the convenience of SWA managed functions: managed identity works cleanly, **always-ready instances remove cold-start latency** at the live event, fast per-instance-concurrency scaling, App Insights, and an SLA. Linking preserves same-origin `/api/*` routing (no CORS) — see §2 |
| Data store | **Azure Table Storage** | Cheap, simple key/value, scales for an uncertain participant count |
| Storage auth | **Managed identity + RBAC** (`Storage Table Data Contributor`) | No connection-string secret to store or leak — ideal for a public repo. The standalone Functions app makes managed identity straightforward (a known weak spot of SWA *managed* functions) |
| Dashboard access | **Shared access code / password** (lightweight gate, no Entra/SSO) | Per plan non-goals; just enough protection for a public URL |
| Hands-on lab environment | **Simulations baseline + optional real-Azure Compute via Learn sandbox + watch-along fallback** | Networking & Storage exercises are Microsoft **click-through simulations** (no sign-in/sandbox/MSA, zero prerequisites — safe on locked-down corporate machines); only the **Compute** VM lab needs real Azure, run in a Learn **sandbox** with a personal MSA. **Watch-along** (`watching_only`) is the universal fallback. A fully uniform lab type isn't possible — Microsoft authors these exercises differently. Avoids granting participants access to the instructor's MCAPS subscription (prohibited by policy). See [sandbox-modules.md](sandbox-modules.md) and §12.1 |
| Learn module links | **Placeholders** in a single config file, swapped in later | Real URLs not yet finalized |
| Feedback storage | **Stored on the participant record** in Table Storage | Single record per participant; no extra store |

> If any decision changes (e.g. framework frontend), revisit Section 6 before coding.

> **Why not SWA managed functions?** The built-in managed-functions API is convenient but Consumption-only (cold starts), has limited/awkward managed-identity support, and no SLA on the free tier — all of which work against the stability + scalability goals. A **standalone Flex Consumption Functions app linked to SWA** keeps the simple `/api/*` developer experience while fixing those gaps. **Fallback:** if Standard tier / a linked backend is unavailable, revert to SWA managed functions with a storage **connection string** (a secret, stored via app settings / Key Vault) — accepting cold starts and no SLA.

---

## 2. Architecture overview

```
Browser (participant + instructor)
        │  HTTPS
        ▼
Azure Static Web Apps (Standard) — static HTML/CSS/JS, global CDN
        │  /api/*  (same-origin; SWA proxies to the linked backend — no CORS)
        ▼
Azure Functions (Node.js) — standalone app on Flex Consumption
        │  • managed identity + Azure Tables SDK
        │  • always-ready instances (no cold start) + App Insights
        ▼
Azure Table Storage  ── table: Participants
```

- **Linked backend (no CORS):** the Functions app is a *separate, independently-scaled* resource, but SWA links it so the browser calls relative `/api/*` paths on the **same origin**. SWA reverse-proxies to the Functions app, so there is no cross-origin request and no CORS configuration to misfire mid-event.
- **PartitionKey:** the **session identifier** (`sessionId` from `config.js`, e.g. `quanta-2026-06-25`). Each delivery writes to its own partition, so reusing the same deployed instance for a new cohort starts clean — the dashboard queries only the current session's partition and never shows stale rows from a prior delivery. All of one session's rows are still a single-partition scan for the dashboard.
- **RowKey:** the participant's **normalized email** (trimmed + lowercased). Email is the deterministic identity, so re-entering it from any browser, InPrivate window, or device resolves to the same row — recovery needs no remembered code, URL, or preserved tab. `localStorage` only caches it for the happy-path refresh.
- **Identity vs. label:** **email = identity** (the key); **name = display label** shown on the admin dashboard. Both are required at check-in. Name is never part of the key, so a differently typed name on recovery (`Mike` vs `Michael`) still finds the right row — the server just refreshes `displayName` to the latest value (last-write-wins).
- **Instance reuse:** because the partition is the session, no reset/purge step or destructive "clear" button is needed between deliveries — set a new `sessionId` in `config.js` and prior cohorts' data stays isolated (and available as history).

---

## 3. Data model

Single table `Participants`. One row per participant.

```json
{
  "PartitionKey": "quanta-2026-06-25",
  "RowKey": "lee.robbins@contoso.com",
  "displayName": "Lee Robbins",
  "moduleStatuses": "{\"welcome\":\"complete\",\"module1\":\"complete\",\"module2\":\"started\",\"module3\":\"not_started\",\"wrapup\":\"not_started\"}",
  "currentModule": "module2",
  "currentStatus": "started",
  "feedback": "",
  "lastUpdated": "2026-06-19T10:42:00-04:00"
}
```

- `PartitionKey` is the **session identifier** (`sessionId` from `config.js`), so each delivery is isolated and instance reuse needs no purge step.
- `RowKey` is the participant's **normalized email** (trimmed + lowercased) — the unique identity. `displayName` (the entered name) is a **required** label used only on the admin dashboard.
- `moduleStatuses` stored as a JSON string (Table Storage has no nested objects).
- **Tracked keys:** `welcome`, `module1` (Networking), `module2` (Compute), `module3` (Storage), `wrapup`. The **Platform & Architecture framing** page and the **Governance overlay** are instructor-led and carry no participant status.
- **Status values (constrained):** `not_started`, `started`, `complete`, `need_help`, `watching_only`.
- `RowKey` (normalized email) is the true key; `displayName` is a required label and may duplicate across participants.

---

## 4. API surface (Azure Functions)

| Method | Route | Purpose | Body / Query |
|--------|-------|---------|--------------|
| POST | `/api/participants` | Check-in / resume — **upsert** by normalized email; returns the participant's state | `{ email, displayName }`, header: `x-session-code` |
| GET | `/api/participants/{email}` | Resume — fetch one participant's state by normalized email | header: `x-session-code` |
| PATCH | `/api/participants/{email}` | Update a module status / current module / feedback | `{ module, status }` or `{ feedback }`, header: `x-session-code` |
| GET | `/api/admin/participants` | Dashboard — list all participants | header: `x-access-code` |

**Validation / security (boundaries only):**
- **Email is the identity (upsert):** `POST /api/participants` normalizes `email` (trim + lowercase) and **upserts** — creates the row on first check-in, returns the existing row (with saved `moduleStatuses`) on re-entry. This is the recovery path: a participant who loses their window/tab/InPrivate session just reopens the link and re-enters email + name to resume. `displayName` is refreshed to the latest value on every check-in (last-write-wins).
- **Both fields required:** reject check-in unless `email` passes a basic format check **and** `displayName` is non-empty. Normalize the email before it is used as the key in any route ({email} path segment is normalized server-side too).
- **Shared session code on writes:** `POST` and `PATCH` require a matching `x-session-code` header (compared to the session's `sessionCode`); reject with 401 otherwise. The code is **shared with participants alongside the workshop link** (it lives in `config.js` and the client sends it automatically). This blocks drive-by writes from a leaked/guessed URL without per-user sign-in. It is a low-value deterrent, not a real secret — it ships in the browser bundle; rotate `sessionCode` (and `sessionId`) per delivery.
- Server validates `status` is in the allowed set and `module` is one of the tracked keys (`welcome`, `module1`, `module2`, `module3`, `wrapup`) — reject otherwise.
- `displayName` trimmed, length-capped, stored as-is (treated as label; output HTML-escaped client-side); `feedback` length-capped.
- Admin endpoint requires matching `x-access-code` header (compared to an app setting); returns 401 otherwise. `x-access-code` is the real secret (app setting), distinct from the public `sessionCode`. Compare it in **constant time** (e.g. `crypto.timingSafeEqual`) and require a **long random value** (not a memorable word) so the unlisted dashboard URL can't be brute-forced for participant PII — see §12.5.
- `GET /api/participants/{id}` stays open: `participantId` is an unguessable UUID handle used for resume.

---

## 5. Page inventory

Static pages, consistent shell, one primary action each.

Each lab page uses the three content blocks the instructor guide specifies: **what you are about to do**, **how it fits into enterprise Azure**, and **the exact links for that module**.

| # | Page | File | Key elements |
|---|------|------|--------------|
| 1 | Welcome / Check-in | `index.html` | Title (**Azure IaaS Fundamentals**), expectations, **Session Information** block (configurable session name + date), **required email + name inputs**, **Start Workshop** |
| — | Platform & Architecture (instructor demo) | `framing.html` | ALZ/CAF framing, optional diagram link, *no status row*, **Continue** |
| 2 | Module 1 — Networking | `module1.html` | 3 framing blocks + links + status row + return cue |
| 3 | Module 2 — Compute | `module2.html` | Same pattern, VM focus |
| 4 | Module 3 — Storage | `module3.html` | Same pattern, storage account focus |
| 5 | Governance & Operations Overlay | `governance.html` | Contrast statements, *no status row*, **Continue to Wrap-up** |
| 6 | Wrap-up / Completion | `wrapup.html` | Recap, final status, optional feedback box |
| — | Admin dashboard | `admin.html` | Access-code gate, participant table, filters, auto-refresh, **regroup summary** (per-module counts: started / complete / need-help, so the instructor knows when it's safe to regroup) |

> The Platform & Architecture page is a landing/framing page participants read while the instructor runs the live ALZ demo — it advances with **Continue**, not a status button.

**Shared assets**
- `styles.css` — one stylesheet (cards, progress bar, status buttons, callout box).
- `app.js` — participant state (email-keyed identity; `localStorage` caches it for happy-path refresh only), API calls, status-row rendering, progress bar.
- `config.js` — module definitions + Learn/portal links **and session metadata**. Session fields drive the welcome-page Session Information block: `sessionName` (e.g. `"Quanta Azure Workshop"`) and `sessionDate` (e.g. `"June 25th, 10:00 am"`) — the only customer-specific values in the app, edited per delivery. A third field, `sessionId` (e.g. `"quanta-2026-06-25"`), is the Table Storage **PartitionKey** that isolates each cohort on instance reuse (see §2/§3), and a fourth, `sessionCode`, is the shared join code the client sends on participant writes (see §4). Because this is the one file changed per delivery, it must be served `no-cache` so late edits aren't masked by the CDN — see the cache-busting note under §9 Deployment. Source the real module URLs from [sandbox-modules.md](sandbox-modules.md): **Module 1** Networking → *Configure virtual networks* **simulation** unit, **Module 2** Compute → create a Windows VM lab (real Azure, Learn sandbox), **Module 3** Storage → *Configure blob storage* **simulation** unit, plus the optional/reference links.
- `admin.js` — dashboard fetch, render, filters, auto-refresh.

---

## 6. Shared UI behavior

- **State persistence:** on check-in, store `participantId` + `displayName` in `localStorage`; restore on every page load; "Change participant name" link to reset.
- **Status row:** rendered from a shared function — buttons for Started / Complete / Need help / Watching only; selected state highlighted; click → PATCH API + update local progress bar.
- **Progress bar:** derived from `moduleStatuses`; shown on every module page.
- **Return cue:** standard callout on each module page: *"After completing the exercise, return here and click **Mark complete**."*
- **Checkpoint cue:** the guide runs explicit regroup/debrief checkpoints after each lab with a "do not continue until regroup" pause. Each lab page shows a subtle hold-for-regroup callout so participants wait for the instructor after marking status.
- **Regroup readout (instructor side):** the dashboard shows a per-module completion summary (e.g. *"8 of 12 complete on Module 1"* plus need-help count), derived from the `Participants` data already stored. This is the instructor's signal for when to regroup. Module ordering stays a **social convention** (welcome copy: *"work through modules in order; pause at each checkpoint"*) — the hub does not gate or lock modules (out of scope per the "not a custom LMS" non-goal).
- **Two-tab / refresh safety:** server is source of truth on load; last-write-wins on status updates (acceptable for this scale).

---

## 7. Build milestones

### Milestone 1 — MVP shell (static, no backend)
- Page shell + `styles.css` + navigation across all 7 participant pages (welcome, framing, 3 labs, governance, wrap-up).
- Name capture → generate UUID → store in localStorage.
- `config.js` with placeholder links; lab pages render the three framing blocks + link cards.
- **Exit check:** a participant can walk all 7 pages with correct links and copy.

### Milestone 2 — Status tracking + dashboard
- Provision Table Storage + Functions; implement the 4 API routes.
- Wire status buttons → PATCH; create record on check-in; resume on load.
- `admin.html` table (Participant | M1 Networking | M2 Compute | M3 Storage | Current status | Last update) behind access code, plus a **per-module regroup summary** (started / complete / need-help counts) so the instructor knows when to regroup.
- **Exit check:** status updates persist and appear on the dashboard in near real time.

### Milestone 3 — Polish
- Progress bar, status filters, "show only Need help" toggle, dashboard auto-refresh.
- Feedback box on wrap-up → PATCH `feedback`.
- Framing/styling cleanup, callout boxes, "do not continue until regroup" cues.

### Milestone 4 — Optional hardening
- CSV export from dashboard.
- Extra dashboard summaries beyond the core regroup readout (e.g. checked-in total, overall completion %).
- Visual refinement.

---

## 8. Edge cases handled

| Case | Handling |
|------|----------|
| Duplicate display names | Allowed; unique `participantId`. Dashboard shows `Name (a1b2)` only if ambiguous |
| Browser refresh | State restored from localStorage + server fetch |
| Two tabs | Last-write-wins; server authoritative on load |
| Forgot to mark complete | Instructor sees stale status + last-updated time |
| Late joiner | Can check in any time; appears immediately on dashboard |
| Watching only | Dedicated status value, distinct on dashboard |

---

## 9. Deployment

- **Topology:** **SWA (Standard)** serves the static site and links to a **standalone Azure Functions app (Flex Consumption)** as its backend. The Functions app uses **managed identity** for Table Storage, has **App Insights** enabled, and is configured with **always-ready instances** so the first check-in of the event pays no cold-start penalty.
- **Provision-time validation (linked backend):** capacity is a non-issue at classroom scale (SWA is a CDN; the Functions app + Table Storage absorb a class's trickle of writes easily). The only real risk is **configuration**: a *linked* backend **requires Standard tier** and a **region that supports SWA linked backends**. Before deploy, confirm linked-backend support in the target region (`eastus2`) and that the Functions app links successfully; if it doesn't, fall back to SWA managed functions (below). Treat this as a go/no-go provisioning check, not a capacity concern.
- **Repo layout:** `/src` (static site) + `/api` (Functions app). The Functions app deploys as its own resource and is attached to SWA via the linked-backend configuration.
- **CI/CD:** SWA GitHub Action on push to main (static + linked backend); preview environments on PRs.
- **Cache-busting (`config.js` freshness):** SWA serves static assets through a CDN that caches aggressively, so a late edit to `config.js` (e.g. fixing `sessionDate` an hour before the event) can be masked by a stale cached copy. Add a `staticwebapp.config.json` route rule that sets `Cache-Control: no-cache` (revalidate) on **`/config.js`** and the **entry HTML** (`/`, `/index.html`), while leaving the rest of the site on normal long-lived caching for performance. This keeps the "edit one file and redeploy" reuse flow reliable without a per-delivery versioning step.
- **App settings (on the Functions app):** `STORAGE_ACCOUNT_NAME` (or table endpoint) + `ADMIN_ACCESS_CODE`. Storage access uses the app's **managed identity** (no connection string). `ADMIN_ACCESS_CODE` is the only true secret and lives only in app settings, never in source.
- **Fallback (if Standard tier / linked backend is unavailable):** deploy the API as SWA **managed functions** and authenticate to storage with a **connection string** stored in app settings (ideally a Key Vault reference). This reintroduces one secret and accepts cold starts / no SLA — see the note under §1.
- **Secrets handling:**
  - Keep all secrets out of the repo. `ADMIN_ACCESS_CODE` lives only in the SWA/Function **app settings** (set via the Azure portal or `az`/CLI), not in any committed file.
  - Storage uses **managed identity + RBAC**, so there is **no `TABLE_CONNECTION_STRING` secret** in production. (A connection string is only used locally against Azurite.)
  - For local dev, put values in a **git-ignored** `local.settings.json` (and/or `.env`); confirm `.gitignore` excludes them before the first commit. Use throwaway values locally (Azurite connection string + a dummy access code).
  - Use a long random string for `ADMIN_ACCESS_CODE`, and **rotate (or retire) it after the event** since it was shared verbally/over chat with instructors.
- **Local dev:** SWA CLI + Azurite (local Table Storage emulator) for offline testing.

### 9.1 Repo reuse & config hygiene (public repo)

This repo is intended to be **published publicly and reused** by colleagues. Treat `config.js` as public (it's served to the browser) and keep all secrets server-side.

- **Public vs. secret boundary:**
  - *Public, committed* — `config.js`: `sessionId`, `sessionName`, `sessionDate`, `sessionCode`, module definitions, Learn/portal links, UI labels. None of these are sensitive (`sessionCode` is a low-value deterrent shared with the link, **not** a secret — the real secret is `ADMIN_ACCESS_CODE`).
  - *Secret, never committed* — `ADMIN_ACCESS_CODE` (app setting). Storage needs no secret thanks to managed identity.
- **Templates over real values:**
  - Commit `api/local.settings.sample.json` with empty/dummy values; **git-ignore** the real `api/local.settings.json`.
  - `config.js` may be committed directly (non-sensitive); document the four per-delivery fields (`sessionId`, `sessionName`, `sessionDate`, `sessionCode`) in the README so reusers know what to edit.
- **`.gitignore` + scanning (defense in depth):**
  - Ignore `api/local.settings.json`, `.env`, `*.local.*`.
  - Enable **GitHub secret scanning + push protection** (free on public repos).
  - Optional: a **gitleaks** pre-commit/CI check to catch custom secrets before push.
- **Reuse flow for a colleague:** fork → edit `sessionId`/`sessionName`/`sessionDate`/`sessionCode` in `config.js` → deploy their own SWA (Standard) + linked Functions app + storage → grant the Functions app's managed identity `Storage Table Data Contributor` → set their own `ADMIN_ACCESS_CODE` in app settings. No secret-hygiene burden beyond that one code.

---

## 10. Acceptance criteria (from website-plan)

1. A participant can enter a name and proceed through all modules. ✅ M1
2. Each module page clearly states the next action. ✅ M1
3. Each page shows only its relevant links. ✅ M1
4. Status updates persist. ✅ M2
5. Dashboard shows progress in near real time. ✅ M2/M3
6. The site reduces link confusion and pacing ambiguity in a dry run. ✅ M3

---

## 11. Open items to confirm before launch

- [x] **Reconciled [website-plan.md](website-plan.md)** to the instructor guide's numbering: Platform & Architecture is now an instructor-led framing page (no status), and Networking/Compute/Storage = Modules 1/2/3 (IA, dashboard table, data model, and progression all updated).
- [x] Real Microsoft Learn module URLs captured in [sandbox-modules.md](sandbox-modules.md) → wire into `config.js`. **Lab type is mixed by module** (locked, see §12.1): Networking (*Configure virtual networks*) and Storage (*Configure blob storage*) link directly to **click-through simulation** units (no sandbox/MSA); Compute (*Create a Windows VM*) is the only **real-Azure sandbox** lab, with watch-along as the fallback.
- [x] Architecture diagram / reference link for the Platform & Architecture framing page: the official **Azure landing zone conceptual architecture** ([CAF — What is an Azure landing zone?](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)), captured in [sandbox-modules.md](sandbox-modules.md). Swap for a custom/Quanta-branded slide later if desired.
- [x] `ADMIN_ACCESS_CODE`: keep as an **app-setting placeholder** — instructor sets a long random value directly in Azure app settings at deploy time (never committed), and rotates/retires it after the event. See **Secrets handling** under §9 Deployment.
- [x] **App name is generic** (**Azure IaaS Fundamentals**) and reused across deliveries. Customer/session identity shows only in the welcome-page **Session Information** block, driven by `config.js` (`sessionName: "Quanta Azure Workshop"`, `sessionDate: "June 25th, 10:00 am"`). Detailed welcome body copy left to the build/vibe-code stage.
- [x] **Azure target locked.** Resource group `rg-azure-iaas-fundamentals`, region `eastus2` (Functions + storage are regional; SWA static content is global via CDN). **Subscription ID is intentionally kept out of this public repo** per §9.1 — store it in the deployment environment instead (azd env var `AZURE_SUBSCRIPTION_ID`, or a GitHub Actions secret), not in committed files. The owner holds the subscription ID separately.

---

## 12. Risks & pre-event checks

These are delivery/environment risks (not app code) that can break the live workshop if unaddressed. The app hub itself never authenticates against Microsoft Learn — these only affect participants' ability to run the hands-on sandbox labs.

### 12.1 Hands-on lab environment — **decided: simulations baseline + Learn sandbox (personal MSA) only for Compute + watch-along fallback**

**Lab type is mixed by module** because Microsoft authors these exercises differently, so a fully uniform lab type isn't possible:

- **Module 1 (Networking)** and **Module 3 (Storage)** are **click-through simulations** — no Azure sign-in, no sandbox, no MSA, zero prerequisites. They run on any locked-down corporate machine and are the **baseline**.
- **Module 2 (Compute)** is a **real Azure lab** (creating a VM). Participants run it in a **Microsoft Learn sandbox** signed in with a **personal Microsoft account (MSA)** — this is the **only** module that needs sign-in/sandbox. A Learn sandbox spins up a free temporary Azure subscription in Microsoft's Learn-managed directory; it never touches the instructor's MCAPS subscription (granting customers access to that subscription is prohibited by policy, which rules out instructor-provisioned options).
- **Watch-along is the universal fallback:** if a participant can't activate a sandbox, the instructor performs the exercise live while they follow using the app's `watching_only` status (see §12.3).
- **Azure free trial was considered and rejected** for participant labs: it requires a credit card + phone verification, is one-per-person for life, and risks real charges — too much friction and liability for a one-off customer workshop. The Learn sandbox (no card, repeatable, auto-expiring) is the better participant-owned option.

- **MSA over corporate ID (Compute only):** for the sandbox, participants sign in to Learn with a **personal MSA**, not their Quanta corporate ID. This avoids the corporate tenant blocking sandbox activation via policy (conditional access / "no sandbox") — a blocker we couldn't see or control. (Pre-created accounts in an M365 dev/test tenant were considered and rejected as unrealistic — seat caps and first-login MFA friction.)
- **Pre-event ask:** tell participants in the invite to **create and/or activate their MSA before the session**, and not to pre-burn Learn sandbox activations the day before (Learn caps activations per account over a rolling period).
- **Day-of buffer:** if someone arrives without a working account, the **opening lecture section (welcome + Platform & Architecture framing)** is used as a setup window to get their MSA sorted **before Module 1** begins. No participant status is tracked on those pages, so this slots in naturally.

### 12.2 Residual prerequisites (call out in invite + welcome copy)

> These prerequisites apply **only to the Module 2 (Compute) sandbox lab**. The Networking and Storage simulations need none of them — no sign-in, no account, no sandbox.

- **Personal MS account ready** — have one (or create it) before arriving (for the Compute sandbox lab).
- **Network egress** — identity-independent: a locked-down corporate network/VPN/proxy can still block the Azure portal or Cloud Shell used by the Compute lab. The pre-event pilot test (below) should run from a representative machine/network. (The simulations are unaffected — they run entirely in the Learn page.)
- **Browser profile** — sign in to the **Learn sandbox** using an **InPrivate/incognito window** (or a separate browser profile) with the personal MSA, to avoid conflicts with a corporate account already signed in. This does **not** risk the workshop hub: identity there is the participant's **email**, so if the workshop window or an InPrivate session closes, they just reopen the link and re-enter email + name to resume — no remembered code, URL, or preserved tab required.
- **Activation timing** — don't activate the sandbox prematurely; it has a limited lifetime and a per-account activation cap.

### 12.2a Participant data is PII — purge after the event

The `Participants` table stores **email + name** (personal data). For a disposable classroom table this is low-stakes, but treat it with light hygiene: the table is runtime-only (never committed to the repo), and **after each delivery delete the session partition** (all rows for that `sessionId`) — or the storage account if the instance is being retired. This pairs with rotating `sessionId`/`sessionCode` per delivery.

### 12.3 Pre-event pilot test (go/no-go)

Before the event, have one person on a **representative corporate machine/network** activate a Learn sandbox for the **Compute** lab using a **personal MSA in an InPrivate window**. This validates network egress, sign-in, and the activation flow in one shot — and it's the only lab with these prerequisites (the Networking/Storage simulations need no validation beyond the page loading). Fallback if it fails: run **watch-along mode** — the instructor performs the exercise live while participants follow using the app's existing `watching_only` status.

### 12.4 Lockstep is a social convention, not enforced

The page model assumes participants move roughly in lockstep with the instructor, but nothing technically enforces module order — every module link is reachable, so fast finishers can race ahead and stragglers can fall behind. **Decision:** keep ordering as a **social convention** (welcome-page copy + per-lab hold-for-regroup cue) rather than building soft/hard gating, which would over-engineer against the "not a custom LMS" non-goal. **Mitigation:** the instructor relies on the dashboard's **per-module regroup summary** (§6, Milestone 2) to decide when to regroup, instead of assuming everyone is on the same page.

### 12.5 No brute-force protection on the admin access code

The dashboard is gated only by the shared `ADMIN_ACCESS_CODE` (`x-access-code` header), with no rate limiting or lockout. Because the dashboard exposes participant **PII (names + emails)**, anyone who discovers the unlisted URL could script-guess the code against `/api/admin/participants` as fast as the Function responds. **Decision (accepted):** rely on **code strength + short exposure**, not runtime throttling. Specifically: (1) `ADMIN_ACCESS_CODE` must be a **long random string** (not a memorable word), making online guessing infeasible; (2) compare it in **constant time** to avoid timing leaks; (3) **rotate/retire it per delivery** alongside `sessionCode`/`sessionId`; (4) the existing **post-event PII purge** (§12.2a) bounds the exposure window to a single session. **Rejected:** in-Function throttling/lockout (per-instance in-memory state is unreliable across Flex Consumption scale events and adds fragile live-event code) and a real auth gate (Entra/SWA roles/APIM) as contrary to the lightweight, no-SSO non-goal. Lightweight throttling stays noted as a future option only if the hub ever hosts higher-sensitivity data.
