# Instructor Script — Part 2: Data Layer

**Duration:** ~60 minutes (4 guided challenges + regroup)  
**Participant action:** Active — writing KQL queries, creating named functions, building a Fabric Data Agent.  
**Purpose:** Help participants discover the relationship between system telemetry and customer support signals. By the end, each participant has a personal Fabric Data Agent they can query in natural language.

---

## Before you open Part 2

- Confirm the chaos incident at T+20 min has fired (OrderService latency spike). Check Fabric:

  ```kql
  Telemetry | where Timestamp > ago(1h) and IsAnomaly == true | take 5
  ```

  At least a few rows should appear. If not, wait — or adjust `scenario.json` for a shorter offset in a future delivery.

- Have the Fabric workspace open in your browser, on the Eventhouse → workshop-db tab.
- Know the `incidentGroundTruth` values from `src/config.js` — you'll reference them in the debrief.

---

## Opening framing (3 min)

> "Part 1 gave you a VM running a system that's accepting requests, experiencing failures, and reporting customer complaints. Part 2 is about understanding what the data is telling us."

> "Before we can build an AI agent that answers questions about system behaviour, we need a solid data foundation. You're going to build that now — and I promise it's more interesting than it sounds."

> "You're working with two fundamentally different kinds of data. The first is **objective** — your VM is emitting precise metrics: latency in milliseconds, error counts, throughput. The second is **subjective** — simulated customers are raising support tickets: 'the system is slow', 'my order timed out'. Both are real signals. They just measure different things."

> "Your job in Part 2 is to connect them."

---

## Challenge 1 — Confirm your signals (10 min)

> "Open your Part 2 — Confirm Signals page. Your first task is simply to prove that your VM's signals are landing in the shared data layer."

Walk the room while participants run their first KQL query. Watch for:

- Anyone whose `SlotTelemetry_userXX()` returns empty — check the VM extension status and ingestion API logs.
- Anyone confused by the Fabric KQL interface — walk them to the Eventhouse → workshop-db → "Explore your data" button.

**Regroup signal (admin dashboard):** When 80% of Part 2 participants show `part2_signals = Started`, do a 1-minute regroup.

> "Quick check — everyone seeing rows in their telemetry query? Good. Notice the `IsAnomaly` column. Most rows should be `false` right now — normal operation. But if the incident has fired for you, you'll start seeing `true`. That's the planted problem your agent will need to find."

---

## Challenge 2 — KQL correlation (15 min)

> "Now for the interesting part. Your VM generates two streams of signals that don't know about each other — telemetry and tickets. Your job is to write a KQL query that joins them."

> "The key insight is **time windows**. Group both streams into 5-minute buckets. Find buckets where both a latency spike AND a ticket burst happened. That's your correlation."

Give them 10 minutes to work through the starter query on their page. Then regroup:

> "Let's see what the correlation query found. Who found a correlated window? What time was it? What was the average latency?"

> "Now look at the `IncidentId` column on the anomalous telemetry rows. That's the tag the chaos engine stamped — it links the spike to the tickets it caused. Keep a note of that value — your agent is going to need to name it."

**What good looks like:**
- At least one row in the spike/ticket join with a non-empty `IncidentId`
- The correlated window is around T+20 minutes from when the app started

---

## Challenge 3 — Correlation view (10 min)

> "You've found the correlation manually. Now save it as a **named KQL function**. This is important for two reasons."

> "First: your Data Agent in Challenge 4 can be grounded on named functions — it's how the agent knows what to query. Second: it makes the query reusable. Future engineers on this system can just call `SlotCorrelation_userXX()` and get a consistent, pre-validated view."

> "While you're at it, the stretch challenge builds a **blind-spot detector** — queries that find tickets without matching anomalies. That's a real pattern: sometimes customers notice problems before your monitoring does."

Give 8 minutes. The function creation command is on the page.

---

## Challenge 4 — Build your Data Agent (20 min)

> "This is the last Part 2 challenge, and it's the one that directly enables your Foundry agent in Part 3."

> "A Fabric Data Agent is a natural-language interface grounded on your Eventhouse data. When your Foundry agent asks 'what caused the ticket spike?', it's actually calling your Data Agent — which translates that question into KQL and returns the answer."

> "Open the Fabric workspace. Create a new Data Agent, ground it on your slot's functions, paste the starter instructions, and test it with the four questions on the page."

Walk the room during this challenge. Common issues:

- **"The data agent can't find my functions"**: In the Data Agent editor → Add data source → Eventhouse → workshop-db → check that the slot functions appear in the schema list. If not, click **Refresh schema**.
- **"The agent answers but doesn't cite data"**: Instructions need the phrase "Always call your Fabric data tool before answering." Help them add it.
- **"Agent answers with wrong slot data"**: Instructions don't specify the SlotId filter. Help them add "Always filter by SlotId == 'userXX'" to the instructions.

**Hold for regroup (admin dashboard):** When 75% show `part2_dataagent = Started`, call a regroup.

---

## Part 2 debrief (5 min)

> "Let's recap what you built. You have two KQL functions — `SlotTelemetry_userXX` and `SlotTickets_userXX` — that give you filtered views of both data planes. You have a `SlotCorrelation_userXX` function that joins them. And you have a Data Agent that can answer natural-language questions about your system."

> "Here's the thing though — your Data Agent knows the data, but it doesn't know what to *do* with it. It can tell you 'there was a spike at 10:47 affecting OrderService with an average latency of 720ms and 12 matching tickets.' But it can't tell you *why* that matters, what other systems might be affected, or what you should do about it."

> "That's what Part 3 is for."

> "One more thing before we break. I want to show you something." [Show the blind-spot query results from your own test run.] "These are tickets that arrived with no matching telemetry anomaly. Customers were reporting problems that your monitoring didn't catch. That gap — between what the system reports and what customers experience — is one of the most dangerous failure modes in operations. Your agent needs to detect it."

---

## Transition to Part 3

> "Part 3 opens in about 10 minutes. Use the break to make sure your Data Agent answers all four test questions correctly — that's your prerequisite for Part 3. If you're stuck, the reference Data Agent in the workspace (`workshop-agent-reference`) has the same setup — copy its instructions as a starting point."

> "See you back here in 10."

---

## Facilitator timing guide

| Time from Part 2 start | Milestone |
|---|---|
| T+0 min | Open Part 2, framing talk |
| T+3 min | Participants start Challenge 1 |
| T+13 min | Challenge 1 regroup, start Challenge 2 |
| T+28 min | Challenge 2 debrief, start Challenge 3 |
| T+38 min | Challenge 3 wrap, start Challenge 4 |
| T+55 min | Challenge 4 regroup + Part 2 debrief |
| T+60 min | 10-minute break before Part 3 |
