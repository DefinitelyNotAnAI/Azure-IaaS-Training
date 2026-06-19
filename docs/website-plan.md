# Azure IaaS Fundamentals - Website Plan

## Purpose
Build a lightweight, **reusable** workshop hub that supports a Microsoft Learn sandbox delivery model for an instructor-led Azure IaaS session. The app name is generic (**Azure IaaS Fundamentals**); the specific customer/session is identified only via a configurable **Session Information** block on the welcome page. The site is **not** a custom LMS or lab platform. It should act as a centralized workshop shell that:

1. gives participants one place to start,
2. captures participant name for simple status tracking,
3. presents curated links and framing content for each module,
4. provides explicit checkpoints between exercises, and
5. gives the facilitator a simple dashboard to see workshop progress in real time.

---

## Non-goals
Do **not** build the following:

- Entra ID / SSO authentication
- Microsoft Learn content duplication
- Embedded lab environments
- Automated sandbox provisioning
- Deep analytics or BI reporting
- Complex role-based access control
- A different experience for every participant type

This should be simple, reliable, and fast to build.

---

## Workshop delivery assumptions
The course uses Microsoft Learn content (instructor-hosted lecture + individual labs) instead of a lab in our Azure subscription. **Lab type is mixed by module** (locked decision — see [implementation-plan.md](implementation-plan.md) §1 and §12.1): Networking and Storage are **click-through simulations** (no sign-in, no sandbox, no account), Compute is the only **real-Azure** lab (Learn sandbox + personal MSA), and **watch-along** is the universal fallback.

### Key implications
- Participants open official Learn units: **simulations** for Networking/Storage (zero prerequisites) and a **Microsoft-managed sandbox subscription** only for the Compute VM lab.
- The site should provide **context and navigation**, not full exercise instructions.
- The workshop is run live by an instructor with explicit regroup checkpoints.
- Participant count is uncertain, so the website must scale without manual provisioning.

---

## Primary user experience

### Participant flow
1. Open workshop hub link
2. Enter name
3. Read welcome / expectations
4. Start Module 1
5. Open the linked Learn exercise
6. Return to the hub at checkpoint and click a status button
7. Repeat through all modules
8. Finish on wrap-up page

### Instructor flow
1. Open admin dashboard
2. Monitor participant names, current module, status, and last update time
3. Use dashboard to determine when to pause, proceed, or intervene

---

## Information architecture

### Public participant pages

#### 1. Welcome / Check-in
Purpose:
- capture participant **name and email**
- establish expectations
- explain how the workshop will run

Content:
- workshop title (**Azure IaaS Fundamentals** — generic, reused across deliveries)
- **Session Information** block (configurable, per delivery):
  - session name (e.g. `Quanta Azure Workshop`)
  - session date/time (e.g. `June 25th, 10:00 am`)
  - these are the only customer-specific values in the app, set in `config.js`
- short description
- what to keep open (hub, Learn, Azure portal)
- note that sandboxes are temporary and simplified
- **required name and email inputs** (email is the identity; re-entering it on any device/window resumes the same session — see data model)
- “Start Workshop” button

#### 2. Platform & Architecture (instructor-led framing)
Purpose:
- front-load enterprise framing before hands-on work
- this page is read while the instructor runs the live ALZ demo; it is **not** a numbered hands-on module and has no status controls

Content:
- short explanation of ALZ and CAF
- what participants should pay attention to during demo
- optional link to architecture diagram / reference slide
- “Continue to Networking Module” button

#### 3. Module 1 - Networking
Purpose:
- prepare participants for the networking Learn exercise

Content blocks:
- what you are about to do
- why it matters in enterprise Azure
- how the sandbox simplifies the real pattern
- links:
  - networking Learn module
  - Azure portal
  - any quick reference links
- status controls:
  - Started
  - Complete
  - Need help
  - Watching only

#### 4. Module 2 - Compute
Same pattern as Networking, but focused on VM deployment.

#### 5. Module 3 - Storage
Same pattern as Networking, but focused on storage account creation.

#### 6. Governance & Operations Overlay
Purpose:
- reinforce what the sandbox did **not** represent well

Content:
- short explanation of policy, RBAC, tagging, budgets, monitoring, management groups
- key contrast statements like “in the sandbox, you created X; in enterprise ALZ, this would usually be inherited or governed automatically”
- “Continue to Wrap-up” button

#### 7. Wrap-up / Completion
Purpose:
- mark final completion
- optionally collect quick feedback

Content:
- short recap
- final status button
- optional short text box for “What was most useful?”

---

## Admin dashboard requirements
The dashboard should be simple.

### Required fields per participant
- display name
- participant ID
- current module
- current status
- last updated timestamp
- per-module status summary

### Recommended table view
| Participant | M1 Networking | M2 Compute | M3 Storage | Current status | Last update |
|-------------|---------------|------------|------------|----------------|-------------|
| Lee Robbins | Complete | Started | Not started | Started | 10:42 AM |

### Recommended dashboard controls
- refresh
- filter by status
- filter by module
- “show only need help” toggle

### Nice-to-have (optional)
- total participants checked in
- count by current status
- count by module progress

---

## Data model
Use a lightweight backend with one primary participant record.

### Participant record
```json
{
  "email": "lee.robbins@contoso.com",
  "displayName": "Lee Robbins",
  "moduleStatuses": {
    "welcome": "complete",
    "module1": "complete",
    "module2": "started",
    "module3": "not_started",
    "wrapup": "not_started"
  },
  "currentModule": "module2",
  "currentStatus": "started",
  "lastUpdated": "2026-06-12T10:42:00-04:00"
}
```

### Status values
Use a constrained set:
- `not_started`
- `started`
- `complete`
- `need_help`
- `watching_only`

### Important design note
The **normalized email** (trimmed + lowercased) is the true system key — it makes check-in idempotent and lets a participant resume from any browser, InPrivate window, or device by re-entering it.
`displayName` (the entered name) is a **required** label shown on the admin dashboard, not a unique identifier. The email + name table is **PII** — keep it out of the repo and purge the session's rows after each delivery (see implementation-plan.md §12).

---

## Suggested technical architecture
Keep the stack simple.

### Option A - Fastest practical stack
- **Frontend:** Next.js or plain static HTML/CSS/JS
- **Hosting:** GitHub Pages, Vercel, or Azure Static Web Apps
- **Backend/API:** Azure Functions or a lightweight serverless API
- **Storage:** Azure Table Storage, Supabase, Airtable, or a simple database where writes are easy

### Option B - Lowest complexity prototype
- **Frontend:** static site
- **Backend:** Google Sheets / Airtable as a data store
- **API layer:** lightweight script or service wrapper

### Recommendation
Use the stack you can ship quickly and trust during a live event.
Prioritize reliability over elegance.

> **Locked decision (see [implementation-plan.md](implementation-plan.md) §1–§2 for the authoritative detail):** plain static HTML/CSS/JS on **Azure Static Web Apps (Standard)**, with the API as a **standalone Azure Functions app (Flex Consumption) linked to SWA** and data in **Azure Table Storage**. The Functions app uses **managed identity** for storage (no connection string), **always-ready instances** to avoid cold starts during the event, and App Insights. Linking the backend keeps same-origin `/api/*` routing, so there is **no CORS** to configure. This choice favors stability and scalability over the convenience of SWA's built-in managed functions.

---

## Page-by-page content requirements
Each module page should use the same content pattern.

### 1. Short framing text
Keep this to 2–4 short paragraphs max.

Recommended headings:
- What you are about to do
- Why it matters in real Azure environments
- What the sandbox simplifies

### 2. Link list
Provide only the links users need **right now**.
Examples:
- Microsoft Learn module
- Azure portal
- quick reference doc
- optional troubleshooting tips

### 3. Checkpoint actions
Every module page should include status buttons.
Recommended:
- Start this module
- Mark complete
- Need help
- Watching only

### 4. Return cue
Explicitly tell participants to return to the workshop hub after the Learn exercise.

Example copy:
> After completing the exercise, return to this page and click **Mark complete** so the instructor can track progress.

---

## UX guidelines

### Keep the site calm and simple
The participant is already juggling Learn, Azure portal, and instructor guidance.
The hub should reduce mental load, not add to it.

### Design principles
- one clear action per page
- prominent module progress
- consistent page structure
- concise text
- obvious next step
- avoid dense walls of instructions

### Recommended visual elements
- module progress bar
- clear cards for links
- callout box for enterprise context
- status button row
- subtle “do not continue until regroup” message where needed

---

## Suggested module progression logic
The site should guide users through the workshop in this order:

1. Welcome / Check-in
2. Platform & Architecture (instructor-led framing)
3. Module 1 - Networking
4. Module 2 - Compute
5. Module 3 - Storage
6. Governance overlay
7. Wrap-up

This matches the intended instructional model:
- front-load enterprise context,
- run one coherent lab story,
- end with governance and operations interpretation.

---

## Content snippets to include
Use concise, reusable language.

### Example module framing snippet
**What you are about to do**  
You will complete a Microsoft Learn exercise to create a virtual network and subnet in a sandbox subscription.

**Why it matters**  
In enterprise Azure environments, network design determines workload isolation, connectivity, and the boundaries where governance and traffic controls apply.

**What the sandbox simplifies**  
This sandbox uses a flat, temporary subscription model. In a production landing zone, the workload would typically inherit networking structure and platform guardrails from the environment.

---

## Functional requirements

### Required MVP functionality
- capture participant name at the start
- create participant record
- show module pages with static content and curated links
- let participants update status per page
- display dashboard for facilitator
- persist status updates
- support browser refresh / resume without losing progress

### Nice-to-have functionality
- progress percentage
- participant search
- export CSV
- “show all who need help” panel
- auto-refresh dashboard

---

## State management behavior

### Participant-side behavior
- Once a participant enters a name, save participant ID and display name locally (for example in local storage)
- On returning to the site, restore their state
- If needed, allow a “Change participant name” link for corrections

### Instructor-side behavior
- Dashboard should refresh often or support manual refresh
- Avoid requiring login unless you already have a trivial way to add it safely
- If exposed publicly during early builds, use a hidden route or lightweight protection

---

## Edge cases to handle
- duplicate participant names
- participant refreshes browser
- participant opens the site on two tabs
- participant forgets to mark complete
- participant joins late
- participant watches only and does not do the exercise

### Recommended handling for duplicate names
Duplicate display names are harmless because the **email** is the unique key under the hood. Two people both named “Lee Robbins” are distinct rows (different emails); the dashboard can disambiguate with the email if needed:
- `Lee Robbins (lee.robbins@contoso.com)`
- `Lee Robbins (l.robbins@fabrikam.com)`
only if ambiguity actually occurs.

---

## Suggested implementation milestones

### Milestone 1 - MVP shell
- landing page
- name + email capture
- static module pages
- links only

### Milestone 2 - Status tracking
- status buttons
- backend write/update
- dashboard table

### Milestone 3 - polish
- progress indicators
- filters
- better framing content styling
- feedback collection

### Milestone 4 - optional hardening
- export
- dashboard protection
- nicer visual design

---

## Acceptance criteria
The site is ready when:

1. A participant can enter a name and proceed through all modules.
2. Each module page clearly tells the participant what to do next.
3. Each module page contains only the relevant links for that part of the workshop.
4. The participant can mark status updates and those updates persist.
5. The instructor dashboard shows participant progress in near real time.
6. The site reduces link confusion and pacing ambiguity during a live dry run.

---

## Suggested GitHub Copilot build prompt
Use this as a starting point with GitHub Copilot:

```text
Create a lightweight workshop hub website for an instructor-led Azure training session that uses Microsoft Learn sandbox exercises.

Requirements:
- participant enters **name and email** on first page
- app uses the **normalized email as the identity** and caches it locally; re-entering email + name on any device resumes the same session
- module pages contain static framing text, curated links, and status buttons
- status buttons update backend data for that participant
- build an admin dashboard that shows participant name, current module, current status, per-module completion, and last updated time
- keep the design simple, clean, and low-friction
- do not add authentication unless explicitly requested
- do not duplicate full Microsoft Learn instructions; only summarize and link out
- optimize for reliability during a live workshop
```

---

## Final recommendation
Build the smallest useful version first:
- name capture
- module pages
- status updates
- facilitator dashboard

If that works in a dry run, polish the visuals and interstitial framing next.

The success condition is not “it feels like Skillable.”
The success condition is:
> participants know where to go, you know where they are, and the live workshop stays organized.
