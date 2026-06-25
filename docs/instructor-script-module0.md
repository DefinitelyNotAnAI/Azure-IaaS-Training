# Instructor Script — Module 0: Azure Landing Zones

**Duration:** ~25 minutes (lecture + demo, no participant action)  
**Participant action:** None — listen, ask questions.  
**Purpose:** Establish the *why* behind the hub-spoke topology participants will build in Modules 1–3. Connect enterprise patterns to the hands-on lab design.

---

## Before you open this module

- No participant prerequisites — this runs first.
- Open the [Azure Landing Zones conceptual architecture diagram](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/) in your browser for reference.
- Optionally, open the Azure portal and navigate to the **hub-rg** resource group so you can show the pre-deployed hub infrastructure.

---

## Opening talk (3 min)

> "Before we touch the portal, I want to spend 20 minutes giving you the mental model that makes everything else click. If you've ever asked yourself 'why does our Azure environment look like *this*?' — this is the answer."

> "Azure Landing Zones are Microsoft's opinionated answer to the question: *how do you set up Azure the right way for an enterprise?* Not just for one team, one project, or one workload — but in a way that scales to hundreds of teams and stays governable."

> "What we're building in this workshop is a simplified version of exactly that pattern. By the end of today, you won't just have deployed some Azure resources — you'll understand the architecture that underpins every serious production deployment on Azure."

---

## Section 1: The problem Landing Zones solve (5 min)

> "Let's start with the problem. Imagine you work at a company that just got Azure access. An enthusiastic developer creates a VM with a public IP and no NSG rules. The security team doesn't find out for three weeks. Sound familiar?"

> "At scale this is unmanageable. You have:
> - Hundreds of subscriptions, thousands of resources
> - No consistent naming, no consistent network design
> - Security controls that vary team-by-team
> - No central visibility into what's running or what it costs"

> "Azure Landing Zones give you a **pre-built, pre-governed foundation** that every workload team inherits. It's 'paved road' infrastructure — teams get what they need to deploy, but they can't veer off into the weeds."

### The three guarantees a Landing Zone makes

> "A Landing Zone gives every workload three things out of the box:

> 1. **Identity & Access** — Teams get their own subscription with RBAC scoped to them. They can't see or touch each other's resources by default.
> 2. **Security guardrails** — Azure Policy is applied at the management group level, above the subscription. Policies might say: 'No public IPs on VMs', 'All storage must have secure transfer enabled', 'All VMs must have Defender for Cloud enabled'. These aren't recommendations — they're *enforced*.
> 3. **Connectivity** — Teams get a spoke VNet that's already peered to a central hub. Internet egress, DNS, and management access all flow through the hub. The team doesn't configure any of that — it just works."

---

## Section 2: Management Groups and the ALZ hierarchy (5 min)

> "The foundation of the governance model is **Management Groups** — containers above subscriptions that let you apply policies and RBAC at scale."

Draw or show the ALZ management group hierarchy:

```
Tenant Root Group
└── Contoso (intermediate root)
    ├── Platform
    │   ├── Identity        ← Azure AD DS, on-prem sync
    │   ├── Connectivity    ← hub VNet, Firewall, Bastion, DNS
    │   └── Management      ← Log Analytics, Defender for Cloud, Automation
    └── Landing Zones
        ├── Corp            ← internal workloads, connected to hub
        └── Online          ← internet-facing, no corp connectivity
```

> "The **Platform** management group contains subscriptions that belong to the cloud platform team — the people who own the network, identity, and security tooling.
>
> The **Landing Zones** management group contains workload subscriptions — the application teams. **Corp** workloads are connected to the hub and can reach on-prem. **Online** workloads are internet-facing and deliberately isolated."

> "Azure Policy is applied at each management group level. Any subscription you drop into a management group automatically inherits all the policies above it. This is how you govern at scale without manually configuring every subscription."

---

## Section 3: Hub-spoke connectivity (5 min)

> "Let's zoom into the connectivity piece, because that's exactly what you're going to build today."

### The hub

> "The **hub VNet** is the central network. The cloud platform team owns it. It contains:
> - **Azure Firewall** — all internet egress from spoke VNets is routed through here, where it's inspected and logged
> - **Azure Bastion** — browser-based RDP/SSH to any VM in any spoke, with no public IPs on the VMs
> - **VPN/ExpressRoute Gateway** — connectivity back to on-premises (not in today's lab)
> - **Centralized DNS** — a DNS Private Resolver that gives workloads name resolution for private endpoints"

> "The hub VNet in this workshop is **10.0.0.0/16**. I deployed it before the workshop. Go ahead and take a look at it."

*(Optional: Open portal → hub-rg, show the hub VNet, Bastion, and the peerings that will exist once participants complete Module 2.)*

### The spokes

> "Each **spoke VNet** belongs to a workload team — in our case, each of you. Key properties:
> - Isolated by default — spoke-to-spoke traffic doesn't flow without explicit routing through the hub
> - Peered to the hub — so the hub's Bastion and Firewall can serve all spokes
> - Non-overlapping CIDR — you each have a unique /24 from the 10.10.0.0/16 range, so there are no routing conflicts when they all peer to the hub"

> "The CIDR assignments aren't random — in a real ALZ deployment, this would be governed by Azure Policy: a policy that requires any spoke VNet CIDR to fall within an approved IP address range. We're simulating that governance manually."

### Non-transitive routing

> "One important concept: VNet peering is **non-transitive**. If Spoke A and Spoke B are both peered to the hub, they *cannot* talk to each other directly — traffic between them must go through the hub (through the Firewall, where it gets logged and can be permitted or denied by rules). This is intentional — you don't want every workload team to be able to reach every other team's resources by default."

---

## Section 4: Today's workshop = a simplified Landing Zone (3 min)

> "Let me map everything I just described onto what you're doing today."

| ALZ concept | Workshop equivalent |
|---|---|
| Corp Landing Zone subscription | Your assigned Resource Group (RBAC-isolated to you) |
| Spoke VNet | `vnet-userXX` that you'll create in Module 1 |
| Hub VNet | Hub at 10.0.0.0/16, pre-deployed in `hub-rg` |
| VNet Peering | What you'll configure in Module 2 |
| Azure Bastion (centralized) | Hub Bastion — you'll use it in Module 3 |
| Policy: no public IP on VMs | We'll follow this voluntarily in Module 3 |
| Non-overlapping CIDRs | Your unique /24 assignment in the banner |

> "We're not running at enterprise scale with management groups and full Azure Policy here — that would take a full day by itself. But every design choice in this workshop traces back to the Landing Zone pattern. Nothing is arbitrary."

---

## Section 5: Optional demo — the ALZ accelerator (3 min)

*Skip this section if running short on time.*

> "If you want to stand up a full Landing Zone in production, you don't build it by hand. Microsoft publishes the **Azure Landing Zones Bicep modules** — open-source, maintained reference implementations that deploy the entire management group hierarchy, policies, hub network, and platform subscriptions in about 45 minutes."

*(Open https://aka.ms/alz/bicep or https://aka.ms/alz/tf in the browser)*

> "There's also a **portal accelerator** — a guided wizard in the Azure portal that walks you through the design decisions and generates the deployment for you. The URL is https://aka.ms/caf/ready. This is how most organizations bootstrap their Azure foundation."

> "The key point: the Landing Zone is not something you build from scratch every time. It's infrastructure-as-code that you deploy once, then govern through policy. Today's lab is giving you the intuition for what the IaC is creating under the hood."

---

## Regroup discussion (2 min)

Ask the group:

- "In your environment at work — do you recognize any of these patterns? Hub-spoke? Management groups? Centralized Bastion?"
- "What governance gaps have you seen that Azure Policy could have prevented?"
- "Who in your organization would own the Platform management group? Is it the same team that owns workload deployments?"

---

## Transition to Module 1

> "Alright — you now have the context for why we're doing what we're doing. In Module 1, you're going to create your spoke VNet. You'll see your assigned CIDR in the banner at the top of the page — that's your address space. The hub already exists. Let's go build the spoke."

> "Mark this module complete on your screen and move to Module 1."

---

## Reference links

| Resource | URL |
|---|---|
| CAF Landing Zones conceptual architecture | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/ |
| ALZ Bicep modules | https://aka.ms/alz/bicep |
| ALZ Terraform modules | https://aka.ms/alz/tf |
| Azure Landing Zones portal accelerator | https://aka.ms/caf/ready |
| Hub-spoke topology | https://learn.microsoft.com/en-us/azure/architecture/networking/architecture/hub-spoke |
