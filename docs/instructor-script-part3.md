# Instructor Script — Part 3: AI Agent

**Duration:** ~75 minutes (3 challenges + debrief)  
**Participant action:** Active — creating a Foundry agent, writing system prompts, running the agent against the planted incident.  
**Purpose:** Participants build a Foundry agent that uses their Fabric Data Agent to reason across both data planes, identify the planted root cause, and explain the customer impact.

---

## Before you open Part 3

- Confirm the chaos incident (T+20 min LatencySpike) has long since fired and resolved — Eventhouse should show clear anomaly windows.
- The second event (T+50 min BlindSpot) may or may not have fired depending on timing — that's fine.
- Have the Azure AI Foundry project URL ready to share: `https://ai.azure.com/build/<FOUNDRY_PROJECT_ID>`.
- Confirm the Fabric workspace connection is added to the Foundry hub (Settings → Connected resources). This is a blocker if missing — fix it now.
- Know the `incidentGroundTruth` values from `src/config.js` — you'll reveal these during the self-validation debrief.

---

## Opening framing (3 min)

> "You have a VM generating signals. You have a semantic data layer that connects those signals. Now we build the thing that makes sense of all of it."

> "Part 3 is about a specific kind of AI: not a search tool, not a chatbot — an **analytical agent**. One that can look at objective telemetry and subjective customer complaints and answer the question: 'what happened, who was affected, and what should I do?'"

> "This is the thing that application owners actually need. Not another dashboard. An AI system that explains how system behaviour is driving customer experience."

> "You're building it in three challenges. First: scaffold the agent and connect it to your data. Second: run it through five real-world use cases. Third: compare what it found to what actually happened."

---

## Challenge 1 — Agent Scaffold (15 min)

> "Open Part 3 — Agent Scaffold. Your first task is to create a Foundry agent and wire it to your Fabric Data Agent from Part 2."

> "Two things to get right here:"
> "One: make sure you add the Microsoft Fabric tool and point it at your Data Agent — `workshop-agent-userXX`, not the reference one."
> "Two: paste the starter system prompt and read it carefully. That prompt is what shapes every answer your agent gives."

Walk the room. Watch for:

- **"I can't find the Fabric tool"**: Foundry → Tools → + Add tool → Microsoft Fabric → select workspace → select Data Agent. If the workspace doesn't appear, the Fabric connection is missing from the Foundry hub — fix it now (Settings → Connected resources → + New connection → Microsoft Fabric).
- **"The test question returns no data"**: Agent is not calling the Fabric tool. Add "Always call your Fabric data tool before answering any question about system behaviour" to the system prompt.
- **"Agent says my Data Agent doesn't have data"**: The Data Agent's grounding may be stale. Have the participant go to Fabric → their Data Agent → refresh the schema.

**What good looks like for the test question** ("What was the average latency in the last 2 hours?"):
- Agent returns a specific number in milliseconds
- Mentions OrderService or another service by name
- Does NOT say "I don't have access to data"

---

## Challenge 2 — Agent Prompts (40 min)

> "Challenge 2 is the core of Part 3. You're going to run your agent through five use cases that represent the five things an application owner actually needs to know when something goes wrong."

Present the five use cases (they're on the page, but say them out loud):

> "Use case 1: Root cause. *What system event caused the ticket spike?* The agent needs to correlate two separate data streams and name a specific event."

> "Use case 2: Noise vs signal. *Are these tickets all describing the same problem?* Can the agent distinguish a cluster of related tickets from random noise?"

> "Use case 3: Customer impact. *Who was affected?* Map the incident to specific customer tenants."

> "Use case 4: Change impact. *Was there a deployment or config change involved?* This is the key use case — it's where the agent needs to find the planted root cause."

> "Use case 5: Blind spots. *Were there ticket bursts with no telemetry anomaly?* The inverse: finding what monitoring missed."

Give participants ~35 minutes for all five. Check in at the ~20-minute mark:

> "Quick check — who has a working answer for use case 4 — change impact? What did your agent say was the cause? What service?"

If most agents are identifying OrderService and the latency spike but not naming the IncidentId:

> "If your agent is describing the spike but not naming the incident ID, look at your system prompt. Does it mention what the `IncidentId` field means? Try adding: 'When you identify an anomaly, always look for and report the IncidentId field — it is the planted root cause identifier.'"

**What good looks like for use case 4:**
- Names `OrderService`
- Identifies a timestamp around T+20 min from app start
- Mentions `INC-BADDEPLOYMENT-01` (or the configured IncidentId)
- Notes that customer tickets followed the anomaly by ~3 minutes

---

## Challenge 3 — Self-Validation (15 min)

> "Open Part 3 — Self-Validation."

> "This page reveals the ground truth of what the chaos engine actually injected. Not to score you — there's no grade here. But to help you understand the gap between what your agent found and what actually happened."

Give participants 5 minutes to compare their answers to the revealed ground truth.

Then run a room-wide debrief:

### Debrief discussion

> "Let's go around. For use case 4 — the key one — how many of you got the root cause exactly right? Service name, timestamp, IncidentId?"

> "For those who got it: what made the difference? Was it the system prompt? Was it a specific question that unlocked it?"

> "For those who didn't: what did your agent say instead? What was it missing?"

Common gaps to address:

| What agents missed | Why | How to fix |
|---|---|---|
| Named the service but not the IncidentId | System prompt didn't explain what IncidentId means | Add field explanation to instructions |
| Described the spike but said "no change detected" | Agent conflated "deployment" with a code deploy; chaos engine doesn't deploy code | Better prompt: "a change could be a config update, parameter change, or dependency failure" |
| Identified use case 5 blind spot partially | BlindSpot event may not have fired yet (T+50 min) | Show the expected result from your own test run |

> "The stretch on this challenge is recommending remediation. If you want to try it: ask your agent 'given everything you've found, what are your top 3 recommendations?' The agent can't execute anything — it's read-only — but its recommendations should be specific and grounded in the data."

---

## End-of-day debrief (10 min)

> "Let's zoom out. What did you actually build today?"

> "In Part 1: a VM-based legacy system that accepts requests, experiences failures, and generates two separate streams of signals — one objective, one subjective."

> "In Part 2: a semantic data layer that connects those signals. Two data planes that can be queried together. A Data Agent grounded on your data."

> "In Part 3: an AI system that answers questions no dashboard can answer — not 'is the latency high?' but 'what caused the ticket spike, which customers were affected, and what's the early-warning sign we should have caught?'"

> "The key insight I want you to leave with: the agent isn't the magic. The data architecture is the magic. The agent is only as good as the data it can reach, the correlation logic you built in Part 2, and the instructions you wrote in the system prompt. Garbage in, garbage out — but the inverse is also true: a well-grounded agent with a thoughtful system prompt can genuinely explain system behaviour in a way that a human analyst would take an hour to do."

> "This pattern — two data planes, a semantic layer, an agent that reasons across both — is real. It's the pattern teams at Microsoft are deploying for production AIOps. You just built a working prototype of it."

---

## Facilitator timing guide

| Time from Part 3 start | Milestone |
|---|---|
| T+0 min | Opening framing |
| T+3 min | Participants start Challenge 1 (scaffold) |
| T+18 min | Challenge 1 check-in, start Challenge 2 |
| T+20 min | Use case 1–3 active |
| T+38 min | Mid-challenge check-in (use case 4 check) |
| T+58 min | Challenge 2 wrap, start Challenge 3 |
| T+65 min | Self-validation room debrief |
| T+75 min | End-of-day closing talk |
